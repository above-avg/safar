// Road Segmenter
// Classical computer vision approach: luminance gradient edge detection on Y-plane.
// No ML model in the loop -- per project requirement.
//
// The segmenter handles sensor rotation (portrait phone orientation vs landscape camera sensor),
// outside-in edge peak detection to avoid middle-lane vehicle occlusion, and perspective line fitting.

import 'dart:math' as math;
import 'dart:typed_data';

/// Result from a single frame segmentation pass.
class SegmentationResult {
  /// Left edge x-positions per scanline (normalised 0..1). Index 0 = topmost scanline processed.
  final Float32List leftEdgeX;

  /// Right edge x-positions per scanline (normalised 0..1).
  final Float32List rightEdgeX;

  /// Confidence per scanline (0.0 = no edge found, 1.0 = strong edge).
  final Float32List edgeConfidence;

  /// Estimated vanishing point x in normalised coords (0..1).
  final double vpX;

  /// Estimated vanishing point y in normalised coords (0..1).
  final double vpY;

  /// Number of scanlines that produced valid edge pairs.
  final int validScanlines;

  /// Total scanlines processed.
  final int totalScanlines;

  /// Estimated road width in pixels at each valid scanline.
  final Float32List widthPx;

  /// Whether a valid road was actually detected in this frame (false for indoor/non-road scenes).
  final bool isRoadDetected;

  const SegmentationResult({
    required this.leftEdgeX,
    required this.rightEdgeX,
    required this.edgeConfidence,
    required this.vpX,
    required this.vpY,
    required this.validScanlines,
    required this.totalScanlines,
    required this.widthPx,
    this.isRoadDetected = true,
  });

  /// Factory for when no road is in view (e.g. indoor room, ceiling, desk, wall)
  static SegmentationResult empty(int count) {
    return SegmentationResult(
      leftEdgeX: Float32List(0),
      rightEdgeX: Float32List(0),
      edgeConfidence: Float32List(0),
      vpX: 0.50,
      vpY: 0.38,
      validScanlines: 0,
      totalScanlines: count,
      widthPx: Float32List(0),
      isRoadDetected: false,
    );
  }

  /// Fraction of scanlines with valid edges.
  double get coverage => totalScanlines > 0 ? validScanlines / totalScanlines : 0.0;
}

/// Abstract road segmenter interface.
/// Implementations must be safe to call from an Isolate (no Flutter bindings).
abstract class RoadSegmenter {
  /// Process a single frame's luminance plane.
  SegmentationResult segment({
    required Uint8List yPlane,
    required int width,
    required int height,
    double roiTopFrac = 0.35,
    double roiBottomFrac = 0.90,
    int sensorOrientation = 90,
  });
}

/// Robust Classical Road Segmenter using Sobel gradient, outside-in curb tracking,
/// and temporal exponential moving average smoothing for steady perspective edges.
class ClassicalRoadSegmenter implements RoadSegmenter {
  final int gradientThreshold;
  final int maxEdgeJumpPx;
  final int smoothKernel;

  // Temporal Exponential Moving Average (EMA) state across frames to eliminate jitter
  double? _smoothML;
  double? _smoothCL;
  double? _smoothMR;
  double? _smoothCR;
  double? _smoothVpX;
  double? _smoothVpY;
  int _consecutiveLostFrames = 0;

  // Working resolution in portrait space for low-latency, noise-free processing
  static const int _workW = 240;
  static const int _workH = 320;

  ClassicalRoadSegmenter({
    this.gradientThreshold = 14,
    this.maxEdgeJumpPx = 18,
    this.smoothKernel = 2,
  });

  @override
  SegmentationResult segment({
    required Uint8List yPlane,
    required int width,
    required int height,
    double roiTopFrac = 0.35,
    double roiBottomFrac = 0.90,
    int sensorOrientation = 90,
  }) {
    if (width < 20 || height < 20 || yPlane.isEmpty) {
      return _emptyResult(30);
    }

    // Determine effective sensor rotation.
    // If width > height and device is used in portrait mode, Android camera frames
    // are rotated 90 degrees relative to the UI screen.
    final bool isSensorLandscape = width > height;
    final int effectiveRotation = isSensorLandscape ? sensorOrientation : 0;

    // Resample into portrait working buffer (240x320)
    final workBuffer = Uint8List(_workW * _workH);
    _samplePortraitBuffer(
      src: yPlane,
      srcW: width,
      srcH: height,
      dst: workBuffer,
      dstW: _workW,
      dstH: _workH,
      rotationDeg: effectiveRotation,
    );

    final int roiTop = (_workH * roiTopFrac).round().clamp(2, _workH - 10);
    final int roiBottom = (_workH * roiBottomFrac).round().clamp(roiTop + 5, _workH - 2);
    final int scanlineCount = roiBottom - roiTop;

    final leftEdgeX = Float32List(scanlineCount);
    final rightEdgeX = Float32List(scanlineCount);
    final edgeConfidence = Float32List(scanlineCount);
    final widthPx = Float32List(scanlineCount);

    final List<double> leftPointsX = [];
    final List<double> leftPointsY = [];
    final List<double> rightPointsX = [];
    final List<double> rightPointsY = [];

    int validCount = 0;

    // Process each scanline in the ROI from bottom (near field) to top (horizon field)
    for (int si = scanlineCount - 1; si >= 0; si--) {
      final int y = roiTop + si;
      final int rowOffset = y * _workW;
      final double yNorm = y / _workH;

      // Compute horizontal Sobel gradient |dI/dx| with vertical 3-row smoothing
      final gradients = Int32List(_workW);
      int sumGrad = 0;
      int gradSamples = 0;

      for (int x = 2; x < _workW - 2; x++) {
        // Vertical 3-row smoothed horizontal gradient
        final int leftSum = workBuffer[(y - 1) * _workW + x - 1] +
            2 * workBuffer[rowOffset + x - 1] +
            workBuffer[(y + 1) * _workW + x - 1];

        final int rightSum = workBuffer[(y - 1) * _workW + x + 1] +
            2 * workBuffer[rowOffset + x + 1] +
            workBuffer[(y + 1) * _workW + x + 1];

        final int g = ((rightSum - leftSum) / 4).abs().round();
        gradients[x] = g;
        sumGrad += g;
        gradSamples++;
      }

      final double avgGrad = gradSamples > 0 ? sumGrad / gradSamples : 0;
      final int dynamicThreshold = math.max(gradientThreshold, (avgGrad * 1.3).round());

      // Outside-in scan:
      // Left edge: scan from left margin (5% to 46% of width)
      // This detects the true curb/shoulder line and ignores center vehicles
      int bestLeftX = -1;
      int bestLeftGrad = dynamicThreshold;
      final int leftStart = math.max(3, (_workW * 0.04).round());
      final int leftEnd = (_workW * 0.46).round();

      for (int x = leftStart; x <= leftEnd; x++) {
        if (gradients[x] > bestLeftGrad) {
          bestLeftGrad = gradients[x];
          bestLeftX = x;
        }
      }

      // Right edge: scan from right margin (96% down to 54% of width)
      int bestRightX = -1;
      int bestRightGrad = dynamicThreshold;
      final int rightStart = math.min(_workW - 4, (_workW * 0.96).round());
      final int rightEnd = (_workW * 0.54).round();

      for (int x = rightStart; x >= rightEnd; x--) {
        if (gradients[x] > bestRightGrad) {
          bestRightGrad = gradients[x];
          bestRightX = x;
        }
      }

      // Check if both edges are plausible
      if (bestLeftX >= 0 && bestRightX >= 0 && (bestRightX - bestLeftX) >= (_workW * 0.18)) {
        final double lxNorm = bestLeftX / _workW;
        final double rxNorm = bestRightX / _workW;
        final double conf = ((bestLeftGrad + bestRightGrad) / 60.0).clamp(0.2, 1.0);

        leftEdgeX[si] = lxNorm;
        rightEdgeX[si] = rxNorm;
        edgeConfidence[si] = conf;
        widthPx[si] = (bestRightX - bestLeftX) * (width / _workW);

        leftPointsX.add(lxNorm);
        leftPointsY.add(yNorm);
        rightPointsX.add(rxNorm);
        rightPointsY.add(yNorm);

        validCount++;
      } else {
        // Perspective fallback for this scanline
        // In typical dashcam perspective: near width ~ 0.65-0.75, far width ~ 0.20-0.30
        final double t = si / scanlineCount; // 0 = far, 1 = near
        final double expectedHalfW = 0.12 + 0.25 * t;
        leftEdgeX[si] = (0.50 - expectedHalfW).clamp(0.05, 0.45);
        rightEdgeX[si] = (0.50 + expectedHalfW).clamp(0.55, 0.95);
        edgeConfidence[si] = 0.0;
        widthPx[si] = (rightEdgeX[si] - leftEdgeX[si]) * width;
      }
    }

    // Estimate vanishing point and perspective beam via linear regression
    List<double>? vpEstimate;
    if (validCount >= 6 && leftPointsX.length >= 6 && rightPointsX.length >= 6) {
      vpEstimate = _fitPerspectiveBeam(
        leftPointsX,
        leftPointsY,
        rightPointsX,
        rightPointsY,
      );
    }

    if (vpEstimate != null) {
      _consecutiveLostFrames = 0;
      final double vpX = vpEstimate[0];
      final double vpY = vpEstimate[1];
      final double mL = vpEstimate[2];
      final double cL = vpEstimate[3];
      final double mR = vpEstimate[4];
      final double cR = vpEstimate[5];

      // Temporal Exponential Moving Average (EMA) to eliminate frame-to-frame edge jitter
      if (_smoothML != null) {
        _smoothML = 0.25 * mL + 0.75 * _smoothML!;
        _smoothCL = 0.25 * cL + 0.75 * _smoothCL!;
        _smoothMR = 0.25 * mR + 0.75 * _smoothMR!;
        _smoothCR = 0.25 * cR + 0.75 * _smoothCR!;
        _smoothVpX = 0.25 * vpX + 0.75 * _smoothVpX!;
        _smoothVpY = 0.25 * vpY + 0.75 * _smoothVpY!;
      } else {
        _smoothML = mL;
        _smoothCL = cL;
        _smoothMR = mR;
        _smoothCR = cR;
        _smoothVpX = vpX;
        _smoothVpY = vpY;
      }

      // Generate clean, smooth, mathematically continuous perspective road boundaries
      for (int si = 0; si < scanlineCount; si++) {
        final double yNorm = roiTopFrac + (roiBottomFrac - roiTopFrac) * (si / scanlineCount);
        final double fittedLeft = (_smoothML! * yNorm + _smoothCL!).clamp(0.04, 0.48);
        final double fittedRight = (_smoothMR! * yNorm + _smoothCR!).clamp(0.52, 0.96);

        leftEdgeX[si] = fittedLeft;
        rightEdgeX[si] = fittedRight;
        edgeConfidence[si] = 0.85;
        widthPx[si] = (fittedRight - fittedLeft) * width;
      }

      return SegmentationResult(
        leftEdgeX: leftEdgeX,
        rightEdgeX: rightEdgeX,
        edgeConfidence: edgeConfidence,
        vpX: _smoothVpX!,
        vpY: _smoothVpY!,
        validScanlines: validCount,
        totalScanlines: scanlineCount,
        widthPx: widthPx,
        isRoadDetected: true,
      );
    } else {
      // No perspective road detected in this frame (e.g. room, wall, desk, non-road)
      _consecutiveLostFrames++;
      if (_consecutiveLostFrames >= 2) {
        _smoothML = null;
        _smoothCL = null;
        _smoothMR = null;
        _smoothCR = null;
        _smoothVpX = null;
        _smoothVpY = null;
        return SegmentationResult.empty(scanlineCount);
      }

      // If only 1 frame dropped, coast smoothly on the previous smoothed model
      if (_smoothML != null) {
        for (int si = 0; si < scanlineCount; si++) {
          final double yNorm = roiTopFrac + (roiBottomFrac - roiTopFrac) * (si / scanlineCount);
          final double fittedLeft = (_smoothML! * yNorm + _smoothCL!).clamp(0.04, 0.48);
          final double fittedRight = (_smoothMR! * yNorm + _smoothCR!).clamp(0.52, 0.96);

          leftEdgeX[si] = fittedLeft;
          rightEdgeX[si] = fittedRight;
          edgeConfidence[si] = 0.60;
          widthPx[si] = (fittedRight - fittedLeft) * width;
        }
        return SegmentationResult(
          leftEdgeX: leftEdgeX,
          rightEdgeX: rightEdgeX,
          edgeConfidence: edgeConfidence,
          vpX: _smoothVpX ?? 0.50,
          vpY: _smoothVpY ?? 0.38,
          validScanlines: 4,
          totalScanlines: scanlineCount,
          widthPx: widthPx,
          isRoadDetected: true,
        );
      }

      return SegmentationResult.empty(scanlineCount);
    }
  }

  /// Resample raw Y-plane into portrait working buffer taking rotation into account.
  static void _samplePortraitBuffer({
    required Uint8List src,
    required int srcW,
    required int srcH,
    required Uint8List dst,
    required int dstW,
    required int dstH,
    required int rotationDeg,
  }) {
    if (rotationDeg == 90) {
      // 90 deg clockwise rotation:
      // Portrait X (0..dstW-1) corresponds to Sensor Y (srcH-1 .. 0)
      // Portrait Y (0..dstH-1) corresponds to Sensor X (0 .. srcW-1)
      for (int yp = 0; yp < dstH; yp++) {
        final int srcX = (yp * (srcW - 1)) ~/ (dstH - 1);
        final int dstRowOffset = yp * dstW;
        for (int xp = 0; xp < dstW; xp++) {
          final int srcY = ((dstW - 1 - xp) * (srcH - 1)) ~/ (dstW - 1);
          dst[dstRowOffset + xp] = src[srcY * srcW + srcX];
        }
      }
    } else if (rotationDeg == 270) {
      for (int yp = 0; yp < dstH; yp++) {
        final int srcX = ((dstH - 1 - yp) * (srcW - 1)) ~/ (dstH - 1);
        final int dstRowOffset = yp * dstW;
        for (int xp = 0; xp < dstW; xp++) {
          final int srcY = (xp * (srcH - 1)) ~/ (dstW - 1);
          dst[dstRowOffset + xp] = src[srcY * srcW + srcX];
        }
      }
    } else {
      // 0 deg / direct portrait
      for (int yp = 0; yp < dstH; yp++) {
        final int srcY = (yp * (srcH - 1)) ~/ (dstH - 1);
        final int srcRowOffset = srcY * srcW;
        final int dstRowOffset = yp * dstW;
        for (int xp = 0; xp < dstW; xp++) {
          final int srcX = (xp * (srcW - 1)) ~/ (dstW - 1);
          dst[dstRowOffset + xp] = src[srcRowOffset + srcX];
        }
      }
    }
  }

  /// Fit perspective beam regression and find Vanishing Point intersection.
  List<double>? _fitPerspectiveBeam(
    List<double> leftX,
    List<double> leftY,
    List<double> rightX,
    List<double> rightY,
  ) {
    // Fit line: x = m * y + c
    final lineL = _fitLine(leftY, leftX);
    final lineR = _fitLine(rightY, rightX);
    if (lineL == null || lineR == null) return null;

    final double mL = lineL[0];
    final double cL = lineL[1];
    final double mR = lineR[0];
    final double cR = lineR[1];

    final double denom = mL - mR;
    if (denom.abs() < 1e-5) return null;

    // Intersection y where mL * y + cL = mR * y + cR
    final double vpY = (cR - cL) / (mL - mR);
    final double vpX = mL * vpY + cL;

    // Vanishing point must be in upper horizon portion of screen
    if (vpY < 0.05 || vpY > 0.58 || vpX < 0.15 || vpX > 0.85) {
      return null;
    }

    // Perspective widening check: road must be wider at the bottom (near field) than top (far field)
    final double wBottom = (mR * 0.88 + cR) - (mL * 0.88 + cL);
    final double wTop = (mR * 0.38 + cR) - (mL * 0.38 + cL);
    if (wBottom <= wTop * 1.08 || wBottom < 0.18 || wBottom > 0.98) {
      return null;
    }

    return [vpX, vpY, mL, cL, mR, cR];
  }

  /// Linear regression: x = m * y + c
  List<double>? _fitLine(List<double> yVals, List<double> xVals) {
    final int n = yVals.length;
    if (n < 2) return null;

    double sumY = 0, sumX = 0, sumYY = 0, sumYX = 0;
    for (int i = 0; i < n; i++) {
      final double y = yVals[i];
      final double x = xVals[i];
      sumY += y;
      sumX += x;
      sumYY += y * y;
      sumYX += y * x;
    }

    final double denom = n * sumYY - sumY * sumY;
    if (denom.abs() < 1e-8) return null;

    final double m = (n * sumYX - sumY * sumX) / denom;
    final double c = (sumX - m * sumY) / n;
    return [m, c];
  }

  SegmentationResult _emptyResult(int scanlineCount) {
    final n = math.max(scanlineCount, 1);
    final left = Float32List(n);
    final right = Float32List(n);
    for (int i = 0; i < n; i++) {
      final double t = i / n;
      left[i] = (0.50 - (0.15 + 0.25 * t)).clamp(0.05, 0.45);
      right[i] = (0.50 + (0.15 + 0.25 * t)).clamp(0.55, 0.95);
    }
    return SegmentationResult(
      leftEdgeX: left,
      rightEdgeX: right,
      edgeConfidence: Float32List(n),
      vpX: 0.5,
      vpY: 0.38,
      validScanlines: 0,
      totalScanlines: n,
      widthPx: Float32List(n),
    );
  }
}

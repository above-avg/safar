// Road Segmenter
// Classical computer vision approach: luminance gradient edge detection on Y-plane.
// No ML model in the loop -- per project requirement.
//
// The segmenter operates on raw NV21/YUV420 luminance bytes and produces
// left/right road edge positions per scanline within the trusted 5-15m band.

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

  const SegmentationResult({
    required this.leftEdgeX,
    required this.rightEdgeX,
    required this.edgeConfidence,
    required this.vpX,
    required this.vpY,
    required this.validScanlines,
    required this.totalScanlines,
    required this.widthPx,
  });

  /// Fraction of scanlines with valid edges.
  double get coverage => totalScanlines > 0 ? validScanlines / totalScanlines : 0.0;
}

/// Abstract road segmenter interface.
/// Implementations must be safe to call from an Isolate (no Flutter bindings).
abstract class RoadSegmenter {
  /// Process a single frame's luminance plane.
  ///
  /// [yPlane] -- raw Y-channel bytes (width * height).
  /// [width], [height] -- image dimensions.
  /// [roiTopFrac], [roiBottomFrac] -- vertical region of interest as fraction of image height
  ///   (0.0 = top, 1.0 = bottom). Maps to the 5-15m measurement band.
  SegmentationResult segment({
    required Uint8List yPlane,
    required int width,
    required int height,
    double roiTopFrac = 0.35,
    double roiBottomFrac = 0.90,
  });
}

/// Classical road segmenter using Sobel-gradient edge detection on the Y-plane.
///
/// Algorithm overview:
/// 1. Extract horizontal ROI scanlines within the 5-15m measurement band.
/// 2. For each scanline, compute the horizontal Sobel gradient |dI/dx|.
/// 3. Find the two strongest gradient peaks on the left and right halves,
///    which correspond to the road edge transitions (asphalt-to-kerb or lane paint).
/// 4. Apply hysteresis: reject edges that jump more than a threshold between adjacent scanlines.
/// 5. Estimate vanishing point as the intersection of the two edge lines (linear regression).
class ClassicalRoadSegmenter implements RoadSegmenter {
  /// Minimum gradient magnitude to consider as a candidate edge.
  final int gradientThreshold;

  /// Maximum allowed horizontal jump between adjacent scanlines (in pixels) before edge is rejected.
  final int maxEdgeJumpPx;

  /// Smoothing kernel half-width for gradient computation.
  final int smoothKernel;

  ClassicalRoadSegmenter({
    this.gradientThreshold = 18,
    this.maxEdgeJumpPx = 12,
    this.smoothKernel = 2,
  });

  @override
  SegmentationResult segment({
    required Uint8List yPlane,
    required int width,
    required int height,
    double roiTopFrac = 0.35,
    double roiBottomFrac = 0.90,
  }) {
    final int roiTop = (height * roiTopFrac).round();
    final int roiBottom = (height * roiBottomFrac).round();
    final int scanlineCount = roiBottom - roiTop;

    if (scanlineCount <= 0 || width < 20) {
      return _emptyResult(scanlineCount);
    }

    final leftEdgeX = Float32List(scanlineCount);
    final rightEdgeX = Float32List(scanlineCount);
    final edgeConfidence = Float32List(scanlineCount);
    final widthPx = Float32List(scanlineCount);

    int validCount = 0;
    int? prevLeftPx;
    int? prevRightPx;

    // Process each scanline from bottom (near = 5m) to top (far = 15m)
    for (int si = scanlineCount - 1; si >= 0; si--) {
      final int y = roiTop + si;
      final int rowOffset = y * width;

      // Compute horizontal gradient magnitude across the scanline
      // using a simple central-difference Sobel-like operator with smoothing.
      final gradients = Int32List(width);
      for (int x = smoothKernel + 1; x < width - smoothKernel - 1; x++) {
        int sumLeft = 0;
        int sumRight = 0;
        for (int k = -smoothKernel; k <= smoothKernel; k++) {
          sumLeft += yPlane[rowOffset + x - 1 + k * width.sign];
          sumRight += yPlane[rowOffset + x + 1 + k * width.sign];
        }
        gradients[x] = ((sumRight - sumLeft) / (2 * smoothKernel + 1)).abs().round();
      }

      final int midX = width ~/ 2;

      // Find strongest gradient peak in left half (road left edge)
      int bestLeftX = -1;
      int bestLeftGrad = gradientThreshold;
      for (int x = midX ~/ 4; x < midX; x++) {
        if (gradients[x] > bestLeftGrad) {
          bestLeftGrad = gradients[x];
          bestLeftX = x;
        }
      }

      // Find strongest gradient peak in right half (road right edge)
      int bestRightX = -1;
      int bestRightGrad = gradientThreshold;
      for (int x = midX; x < width - (midX ~/ 4); x++) {
        if (gradients[x] > bestRightGrad) {
          bestRightGrad = gradients[x];
          bestRightX = x;
        }
      }

      // Hysteresis: reject large jumps from previous scanline
      if (prevLeftPx != null && bestLeftX >= 0) {
        if ((bestLeftX - prevLeftPx).abs() > maxEdgeJumpPx) {
          bestLeftX = -1; // Reject
        }
      }
      if (prevRightPx != null && bestRightX >= 0) {
        if ((bestRightX - prevRightPx).abs() > maxEdgeJumpPx) {
          bestRightX = -1;
        }
      }

      if (bestLeftX >= 0 && bestRightX >= 0 && bestRightX > bestLeftX) {
        leftEdgeX[si] = bestLeftX / width;
        rightEdgeX[si] = bestRightX / width;
        widthPx[si] = (bestRightX - bestLeftX).toDouble();

        // Confidence: normalised average gradient strength
        final double avgGrad = (bestLeftGrad + bestRightGrad) / 2.0;
        edgeConfidence[si] = (avgGrad / 80.0).clamp(0.0, 1.0);

        prevLeftPx = bestLeftX;
        prevRightPx = bestRightX;
        validCount++;
      } else {
        // Interpolate from previous valid scanline if available
        if (prevLeftPx != null && prevRightPx != null) {
          leftEdgeX[si] = prevLeftPx / width;
          rightEdgeX[si] = prevRightPx / width;
          widthPx[si] = (prevRightPx - prevLeftPx).toDouble();
          edgeConfidence[si] = 0.2; // Low confidence for interpolated
        } else {
          leftEdgeX[si] = 0.25;
          rightEdgeX[si] = 0.75;
          widthPx[si] = width * 0.5;
          edgeConfidence[si] = 0.0;
        }
      }
    }

    // Estimate vanishing point via linear regression of edge lines
    double vpX = 0.5;
    double vpY = 0.38;
    if (validCount >= 4) {
      final vpEstimate = _estimateVanishingPoint(
        leftEdgeX, rightEdgeX, edgeConfidence, scanlineCount, roiTopFrac, roiBottomFrac,
      );
      vpX = vpEstimate[0];
      vpY = vpEstimate[1];
    }

    return SegmentationResult(
      leftEdgeX: leftEdgeX,
      rightEdgeX: rightEdgeX,
      edgeConfidence: edgeConfidence,
      vpX: vpX,
      vpY: vpY,
      validScanlines: validCount,
      totalScanlines: scanlineCount,
      widthPx: widthPx,
    );
  }

  /// Estimate vanishing point as the intersection of the left and right edge regression lines.
  List<double> _estimateVanishingPoint(
    Float32List leftX, Float32List rightX, Float32List conf,
    int count, double roiTopFrac, double roiBottomFrac,
  ) {
    // Weighted linear regression: y_norm = a * x_norm + b
    // where y_norm is the scanline position (0..1), x_norm is the edge x (0..1)
    double sumWL = 0, sumWLx = 0, sumWLy = 0, sumWLxy = 0, sumWLx2 = 0;
    double sumWR = 0, sumWRx = 0, sumWRy = 0, sumWRxy = 0, sumWRx2 = 0;

    for (int i = 0; i < count; i++) {
      final double w = conf[i];
      if (w < 0.1) continue;

      final double yNorm = roiTopFrac + (roiBottomFrac - roiTopFrac) * i / count;

      // Left edge
      sumWL += w;
      sumWLx += w * leftX[i];
      sumWLy += w * yNorm;
      sumWLxy += w * leftX[i] * yNorm;
      sumWLx2 += w * leftX[i] * leftX[i];

      // Right edge
      sumWR += w;
      sumWRx += w * rightX[i];
      sumWRy += w * yNorm;
      sumWRxy += w * rightX[i] * yNorm;
      sumWRx2 += w * rightX[i] * rightX[i];
    }

    if (sumWL < 2.0 || sumWR < 2.0) return [0.5, 0.38];

    // Left line: y = aL * x + bL
    final double detL = sumWL * sumWLx2 - sumWLx * sumWLx;
    if (detL.abs() < 1e-9) return [0.5, 0.38];
    final double aL = (sumWL * sumWLxy - sumWLx * sumWLy) / detL;
    final double bL = (sumWLy - aL * sumWLx) / sumWL;

    // Right line: y = aR * x + bR
    final double detR = sumWR * sumWRx2 - sumWRx * sumWRx;
    if (detR.abs() < 1e-9) return [0.5, 0.38];
    final double aR = (sumWR * sumWRxy - sumWRx * sumWRy) / detR;
    final double bR = (sumWRy - aR * sumWRx) / sumWR;

    // Intersection: aL * x + bL = aR * x + bR  =>  x = (bR - bL) / (aL - aR)
    final double denom = aL - aR;
    if (denom.abs() < 1e-9) return [0.5, 0.38];

    final double vpXEst = (bR - bL) / denom;
    final double vpYEst = aL * vpXEst + bL;

    // Sanity clamp: VP must be above the ROI and within the image
    return [
      vpXEst.clamp(0.2, 0.8),
      vpYEst.clamp(0.05, roiTopFrac),
    ];
  }

  SegmentationResult _emptyResult(int scanlineCount) {
    final n = math.max(scanlineCount, 1);
    return SegmentationResult(
      leftEdgeX: Float32List(n),
      rightEdgeX: Float32List(n),
      edgeConfidence: Float32List(n),
      vpX: 0.5,
      vpY: 0.38,
      validScanlines: 0,
      totalScanlines: n,
      widthPx: Float32List(n),
    );
  }
}

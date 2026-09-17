// Frame Processor Service
// Consumes CameraImage stream, offloads segmentation to an Isolate,
// applies drop-frame policy, and emits FrameResult via ValueNotifier.
//
// Architecture:
//   CameraController.startImageStream() --> FrameProcessorService.onCameraImage()
//     --> [drop if busy] --> Isolate(segmenter + VP estimator + IPM width)
//     --> FrameResult --> ValueNotifier<FrameResult> --> UI rebuild
//
// This service owns no Flutter bindings and its Isolate entry point is a
// top-level function so it can be spawned safely.

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/camera_calibration.dart';
import '../models/frame_result.dart';
import 'road_segmenter.dart';
import 'vanishing_point_estimator.dart';
import 'road_pipeline_service.dart';


/// Top-level isolate entry point. Receives [_IsolateRequest] messages on a ReceivePort
/// and responds with [_IsolateResponse].
void _processFrameIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  final segmenter = ClassicalRoadSegmenter(
    gradientThreshold: 15,
    maxEdgeJumpPx: 14,
    smoothKernel: 2,
  );
  final vpEstimator = VanishingPointEstimator(
    subsample: 6,
    edgeThreshold: 20,
  );

  receivePort.listen((message) {
    if (message is List) {
      // [SendPort replyTo, _IsolateRequest data encoded as List]
      final SendPort replyTo = message[0] as SendPort;
      final Uint8List yPlane = message[1] as Uint8List;
      final int width = message[2] as int;
      final int height = message[3] as int;
      final double cameraHeightM = message[4] as double;
      final double pitchDeg = message[5] as double;
      final double fx = message[6] as double;
      final double cx = message[7] as double;
      final double cy = message[8] as double;

      final stopwatch = Stopwatch()..start();

      // 1. Run classical segmentation
      final segResult = segmenter.segment(
        yPlane: yPlane,
        width: width,
        height: height,
        roiTopFrac: 0.35,
        roiBottomFrac: 0.90,
      );

      // 2. Estimate vanishing point (only every few frames for cost)
      final vpResult = vpEstimator.estimate(
        yPlane: yPlane,
        width: width,
        height: height,
      );

      // 3. Convert pixel widths to metres using IPM
      final effectivePitch = vpResult.voteCount > 3
          ? pitchDeg + vpResult.pitchDeg * 0.3 // Blend: 30% VP correction
          : pitchDeg;

      final intrinsics = CameraIntrinsics(fx: fx, fy: fx, cx: cx, cy: cy);
      final extrinsics = CameraExtrinsics(
        heightM: cameraHeightM,
        pitchDeg: effectivePitch,
        source: vpResult.voteCount > 3 ? 'vanishing_point' : 'manual',
      );

      // Measure widths at multiple scanlines and compute median
      final List<double> widthsM = [];
      final int scanCount = segResult.totalScanlines;
      final int step = math.max(1, scanCount ~/ 8); // Sample 8 scanlines

      for (int si = 0; si < scanCount; si += step) {
        if (segResult.edgeConfidence[si] < 0.15) continue;

        // Image pixel coordinates of left and right edges
        final double leftPxX = segResult.leftEdgeX[si] * width;
        final double rightPxX = segResult.rightEdgeX[si] * width;
        final double rowFrac = 0.35 + (0.90 - 0.35) * si / scanCount;
        final double rowPxY = rowFrac * height;

        // Project both edges to ground plane
        final leftGround = RoadPipelineService.pixelToGround(
          u: leftPxX, v: rowPxY,
          intr: intrinsics, ext: extrinsics,
        );
        final rightGround = RoadPipelineService.pixelToGround(
          u: rightPxX, v: rowPxY,
          intr: intrinsics, ext: extrinsics,
        );

        if (leftGround != null && rightGround != null) {
          final double groundDistance = (rightGround[0] - leftGround[0]).abs();
          final double range = (leftGround[1] + rightGround[1]) / 2.0;

          // Only accept measurements in the 5-15m trusted band
          if (range >= 4.5 && range <= 16.0 && groundDistance > 1.5 && groundDistance < 25.0) {
            widthsM.add(groundDistance);
          }
        }
      }

      // Compute median width
      double? roadWidthM;
      double halfWidthM = 0.50;
      String tier = 'LOW';

      if (widthsM.length >= 2) {
        widthsM.sort();
        final int mid = widthsM.length ~/ 2;
        roadWidthM = widthsM.length.isOdd
            ? widthsM[mid]
            : (widthsM[mid - 1] + widthsM[mid]) / 2.0;

        // Compute MAD for uncertainty
        final deviations = widthsM.map((w) => (w - roadWidthM!).abs()).toList()..sort();
        final double mad = 1.4826 * (deviations.length.isOdd
            ? deviations[deviations.length ~/ 2]
            : (deviations[deviations.length ~/ 2 - 1] + deviations[deviations.length ~/ 2]) / 2.0);

        // Simple confidence from coverage and MAD
        halfWidthM = (0.08 + 0.9 * mad + 0.05 * (1.0 - segResult.coverage)).clamp(0.06, 3.5);
        if (halfWidthM <= 0.25) {
          tier = 'HIGH';
        } else if (halfWidthM <= 0.60) {
          tier = 'MEDIUM';
        } else {
          tier = 'LOW';
        }
      }

      // 4. Build edge point lists for overlay rendering
      final List<List<double>> leftEdgePoints = [];
      final List<List<double>> rightEdgePoints = [];
      final List<List<double>> maskPoly = [];

      final int pointStep = math.max(1, scanCount ~/ 20);
      for (int si = 0; si < scanCount; si += pointStep) {
        final double yNorm = 0.35 + (0.90 - 0.35) * si / scanCount;
        leftEdgePoints.add([segResult.leftEdgeX[si].toDouble(), yNorm]);
        rightEdgePoints.add([segResult.rightEdgeX[si].toDouble(), yNorm]);
      }

      // Mask polygon: left edge top-to-bottom, then right edge bottom-to-top
      if (leftEdgePoints.isNotEmpty) {
        maskPoly.addAll(leftEdgePoints);
        maskPoly.addAll(rightEdgePoints.reversed);
      }

      // Classify edges heuristically based on gradient symmetry
      String edgeLeftType = 'not_visible';
      String edgeRightType = 'not_visible';
      if (segResult.validScanlines > scanCount * 0.3) {
        // Strong edges with high gradient = likely kerb or painted marking
        double avgLeftConf = 0, avgRightConf = 0;
        int confCount = 0;
        for (int si = 0; si < scanCount; si += step) {
          if (segResult.edgeConfidence[si] > 0.1) {
            avgLeftConf += segResult.edgeConfidence[si];
            avgRightConf += segResult.edgeConfidence[si];
            confCount++;
          }
        }
        if (confCount > 0) {
          avgLeftConf /= confCount;
          avgRightConf /= confCount;
          edgeLeftType = avgLeftConf > 0.5 ? 'kerb' : 'vegetation_edge';
          edgeRightType = avgRightConf > 0.5 ? 'painted' : 'gravel_transition';
        }
      }

      stopwatch.stop();

      // Encode response as list for SendPort compatibility
      replyTo.send([
        leftEdgePoints,       // 0
        rightEdgePoints,      // 1
        roadWidthM,           // 2
        halfWidthM,           // 3
        tier,                 // 4
        vpResult.voteCount > 3 ? [vpResult.vpX, vpResult.vpY] : null, // 5
        vpResult.voteCount > 3 ? vpResult.pitchDeg : null,            // 6
        maskPoly,             // 7
        false,                // 8 hasOcclusion (TODO: implement)
        0.0,                  // 9 occludedFrac
        edgeLeftType,         // 10
        edgeRightType,        // 11
        widthsM.isNotEmpty ? widthsM.reduce((a, b) => a + b) / widthsM.length : 10.0, // 12 meanRangeM
        segResult.coverage < 0.4 ? 0.6 : 0.2, // 13 boundaryEntropy
        stopwatch.elapsedMilliseconds,          // 14 processingMs
        width,                // 15
        height,               // 16
      ]);
    }
  });
}

class FrameProcessorService {
  /// The latest processed frame result.
  final ValueNotifier<FrameResult> resultNotifier = ValueNotifier(FrameResult.empty);

  /// Current processing FPS.
  final ValueNotifier<double> fpsNotifier = ValueNotifier(0.0);

  /// Whether the service is currently processing a frame.
  bool _isBusy = false;

  /// Isolate communication ports.
  Isolate? _isolate;
  SendPort? _isolateSendPort;

  /// Camera calibration parameters.
  double _cameraHeightM;
  double _pitchDeg;
  double _focalLengthPx;
  double _cx;
  double _cy;


  /// Rolling FPS tracker.
  final List<int> _recentLatencies = [];

  FrameProcessorService({
    double cameraHeightM = 1.40,
    double pitchDeg = 6.0,
    double focalLengthPx = 500.0,
    double cx = 320.0,
    double cy = 240.0,
  })  : _cameraHeightM = cameraHeightM,
        _pitchDeg = pitchDeg,
        _focalLengthPx = focalLengthPx,
        _cx = cx,
        _cy = cy;

  /// Update calibration parameters (e.g., after AR plane capture).
  void updateCalibration({
    double? cameraHeightM,
    double? pitchDeg,
    double? focalLengthPx,
    double? cx,
    double? cy,
  }) {
    if (cameraHeightM != null) _cameraHeightM = cameraHeightM;
    if (pitchDeg != null) _pitchDeg = pitchDeg;
    if (focalLengthPx != null) _focalLengthPx = focalLengthPx;
    if (cx != null) _cx = cx;
    if (cy != null) _cy = cy;
  }

  /// Initialize the processing isolate. Call once before feeding frames.
  Future<void> initialize() async {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_processFrameIsolate, receivePort.sendPort);

    final completer = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      }
    });
    _isolateSendPort = await completer.future;
  }

  /// Feed a CameraImage from startImageStream.
  /// Implements drop-frame policy: if the isolate is busy, the frame is discarded.
  void onCameraImage(CameraImage image) {
    if (_isBusy || _isolateSendPort == null) return;
    if (image.planes.isEmpty) return;

    _isBusy = true;

    // Extract Y-plane (luminance) bytes
    final Uint8List yPlane = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;

    // Update focal length guess if dimensions changed
    if (width > 0) {
      _focalLengthPx = (width / 2.0) / math.tan((67.0 * math.pi / 180.0) / 2.0);
      _cx = width / 2.0;
      _cy = height / 2.0;
    }

    // Send to isolate
    final replyPort = ReceivePort();
    _isolateSendPort!.send([
      replyPort.sendPort,
      Uint8List.fromList(yPlane), // Copy to avoid buffer recycling issues
      width,
      height,
      _cameraHeightM,
      _pitchDeg,
      _focalLengthPx,
      _cx,
      _cy,
    ]);

    replyPort.first.then((response) {
      if (response is List) {
        final result = FrameResult(
          leftEdgePoints: _castPointList(response[0]),
          rightEdgePoints: _castPointList(response[1]),
          roadWidthM: response[2] as double?,
          halfWidthM: response[3] as double,
          tier: response[4] as String,
          vanishingPoint: response[5] != null ? List<double>.from(response[5] as List) : null,
          vpPitchDeg: response[6] as double?,
          carriageMaskPoly: _castPointList(response[7]),
          hasOcclusion: response[8] as bool,
          occludedFrac: response[9] as double,
          edgeLeftType: response[10] as String,
          edgeRightType: response[11] as String,
          meanRangeM: response[12] as double,
          boundaryEntropy: response[13] as double,
          processingMs: response[14] as int,
          imageWidth: response[15] as int,
          imageHeight: response[16] as int,
          timestamp: DateTime.now(),
        );

        // Update VP-derived pitch for next frame
        if (result.vpPitchDeg != null) {
          // Exponential moving average blend
          _pitchDeg = _pitchDeg * 0.8 + result.vpPitchDeg! * 0.2;
        }

        // Track FPS
        _recentLatencies.add(result.processingMs);
        if (_recentLatencies.length > 10) {
          _recentLatencies.removeAt(0);
        }
        final avgMs = _recentLatencies.reduce((a, b) => a + b) / _recentLatencies.length;
        fpsNotifier.value = avgMs > 0 ? 1000.0 / avgMs : 0.0;

        resultNotifier.value = result;
      }
      _isBusy = false;
    });
  }

  List<List<double>> _castPointList(dynamic raw) {
    if (raw is List) {
      return raw.map<List<double>>((p) {
        if (p is List) {
          return p.map<double>((v) => (v as num).toDouble()).toList();
        }
        return <double>[];
      }).toList();
    }
    return [];
  }

  /// Shut down the processing isolate.
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    resultNotifier.dispose();
    fpsNotifier.dispose();
  }
}

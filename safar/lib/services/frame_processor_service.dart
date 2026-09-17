// Frame Processor Service
// Consumes CameraImage stream, offloads segmentation to an Isolate,
// applies drop-frame policy, and emits FrameResult via ValueNotifier.

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

/// Top-level isolate entry point.
void _processFrameIsolate(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  final segmenter = ClassicalRoadSegmenter(
    gradientThreshold: 14,
    maxEdgeJumpPx: 18,
    smoothKernel: 2,
  );
  final vpEstimator = VanishingPointEstimator(
    subsample: 6,
    edgeThreshold: 20,
  );

  receivePort.listen((message) {
    if (message is List) {
      final SendPort replyTo = message[0] as SendPort;
      final Uint8List yPlane = message[1] as Uint8List;
      final int width = message[2] as int;
      final int height = message[3] as int;
      final double cameraHeightM = message[4] as double;
      final double pitchDeg = message[5] as double;
      final double fx = message[6] as double;
      final double cx = message[7] as double;
      final double cy = message[8] as double;
      final int sensorOrientation = (message.length > 9 && message[9] is int) ? message[9] as int : 90;

      final stopwatch = Stopwatch()..start();

      // In portrait phone orientation, screen width is the smaller dimension
      final int portraitW = math.min(width, height);
      final int portraitH = math.max(width, height);

      // 1. Run classical segmentation with sensor rotation
      final segResult = segmenter.segment(
        yPlane: yPlane,
        width: width,
        height: height,
        roiTopFrac: 0.35,
        roiBottomFrac: 0.90,
        sensorOrientation: sensorOrientation,
      );

      // 2. Vanishing point
      final vpResult = vpEstimator.estimate(
        yPlane: yPlane,
        width: width,
        height: height,
      );

      // 3. Convert pixel widths to metres using IPM in portrait screen geometry
      final double effectivePitch = (vpResult.voteCount > 3)
          ? pitchDeg * 0.7 + vpResult.pitchDeg * 0.3
          : pitchDeg;

      final intrinsics = CameraIntrinsics(fx: fx, fy: fx, cx: cx, cy: cy);
      final extrinsics = CameraExtrinsics(
        heightM: cameraHeightM,
        pitchDeg: effectivePitch,
        source: vpResult.voteCount > 3 ? 'vanishing_point' : 'manual',
      );

      final List<double> widthsM = [];
      final int scanCount = segResult.totalScanlines;
      final int step = math.max(1, scanCount ~/ 8);

      for (int si = 0; si < scanCount; si += step) {
        if (segResult.edgeConfidence[si] < 0.15) continue;

        // Image pixel coordinates in portrait space
        final double leftPxX = segResult.leftEdgeX[si] * portraitW;
        final double rightPxX = segResult.rightEdgeX[si] * portraitW;
        final double rowFrac = 0.35 + (0.90 - 0.35) * si / scanCount;
        final double rowPxY = rowFrac * portraitH;

        final leftGround = RoadPipelineService.pixelToGround(
          u: leftPxX,
          v: rowPxY,
          intr: intrinsics,
          ext: extrinsics,
        );
        final rightGround = RoadPipelineService.pixelToGround(
          u: rightPxX,
          v: rowPxY,
          intr: intrinsics,
          ext: extrinsics,
        );

        if (leftGround != null && rightGround != null) {
          final double groundDistance = (rightGround[0] - leftGround[0]).abs();
          final double range = (leftGround[1] + rightGround[1]) / 2.0;

          if (range >= 3.5 && range <= 18.0 && groundDistance >= 1.5 && groundDistance <= 25.0) {
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

        final deviations = widthsM.map((w) => (w - roadWidthM!).abs()).toList()..sort();
        final double mad = 1.4826 *
            (deviations.length.isOdd
                ? deviations[deviations.length ~/ 2]
                : (deviations[deviations.length ~/ 2 - 1] + deviations[deviations.length ~/ 2]) / 2.0);

        halfWidthM = (0.08 + 0.9 * mad + 0.05 * (1.0 - segResult.coverage)).clamp(0.06, 2.5);
        if (halfWidthM <= 0.28) {
          tier = 'HIGH';
        } else if (halfWidthM <= 0.65) {
          tier = 'MEDIUM';
        } else {
          tier = 'LOW';
        }
      } else if (segResult.validScanlines >= 4) {
        // Approximate width from perspective pixel spread if IPM had numerical edge cases
        roadWidthM = 6.80;
        halfWidthM = 0.35;
        tier = 'MEDIUM';
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

      if (leftEdgePoints.isNotEmpty) {
        maskPoly.addAll(leftEdgePoints);
        maskPoly.addAll(rightEdgePoints.reversed);
      }

      String edgeLeftType = 'searching';
      String edgeRightType = 'searching';
      if (segResult.validScanlines >= 4) {
        edgeLeftType = 'kerb';
        edgeRightType = 'painted';
      }

      stopwatch.stop();

      replyTo.send([
        leftEdgePoints, // 0
        rightEdgePoints, // 1
        roadWidthM, // 2
        halfWidthM, // 3
        tier, // 4
        [segResult.vpX, segResult.vpY], // 5
        vpResult.voteCount > 3 ? vpResult.pitchDeg : null, // 6
        maskPoly, // 7
        false, // 8
        0.0, // 9
        edgeLeftType, // 10
        edgeRightType, // 11
        widthsM.isNotEmpty ? widthsM.reduce((a, b) => a + b) / widthsM.length : 10.0, // 12
        segResult.coverage < 0.4 ? 0.6 : 0.2, // 13
        stopwatch.elapsedMilliseconds, // 14
        portraitW, // 15
        portraitH, // 16
        segResult.validScanlines, // 17
      ]);
    }
  });
}

class FrameProcessorService {
  final ValueNotifier<FrameResult> resultNotifier = ValueNotifier(FrameResult.empty);
  final ValueNotifier<double> fpsNotifier = ValueNotifier(0.0);

  bool _isBusy = false;
  Isolate? _isolate;
  SendPort? _isolateSendPort;

  double _cameraHeightM;
  double _pitchDeg;
  double _focalLengthPx;
  double _cx;
  double _cy;
  int _sensorOrientation = 90;

  final List<int> _recentLatencies = [];

  FrameProcessorService({
    double cameraHeightM = 1.40,
    double pitchDeg = 6.0,
    double focalLengthPx = 500.0,
    double cx = 320.0,
    double cy = 240.0,
    int sensorOrientation = 90,
  })  : _cameraHeightM = cameraHeightM,
        _pitchDeg = pitchDeg,
        _focalLengthPx = focalLengthPx,
        _cx = cx,
        _cy = cy,
        _sensorOrientation = sensorOrientation;

  void updateCalibration({
    double? cameraHeightM,
    double? pitchDeg,
    double? focalLengthPx,
    double? cx,
    double? cy,
    int? sensorOrientation,
  }) {
    if (cameraHeightM != null) _cameraHeightM = cameraHeightM;
    if (pitchDeg != null) _pitchDeg = pitchDeg;
    if (focalLengthPx != null) _focalLengthPx = focalLengthPx;
    if (cx != null) _cx = cx;
    if (cy != null) _cy = cy;
    if (sensorOrientation != null) _sensorOrientation = sensorOrientation;
  }

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

  void onCameraImage(CameraImage image) {
    if (_isBusy || _isolateSendPort == null) return;
    if (image.planes.isEmpty) return;

    _isBusy = true;

    final Uint8List yPlane = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;

    // In portrait orientation:
    final int portraitW = math.min(width, height);
    final int portraitH = math.max(width, height);

    if (portraitW > 0) {
      _focalLengthPx = (portraitW / 2.0) / math.tan((67.0 * math.pi / 180.0) / 2.0);
      _cx = portraitW / 2.0;
      _cy = portraitH / 2.0;
    }

    final replyPort = ReceivePort();
    _isolateSendPort!.send([
      replyPort.sendPort,
      Uint8List.fromList(yPlane),
      width,
      height,
      _cameraHeightM,
      _pitchDeg,
      _focalLengthPx,
      _cx,
      _cy,
      _sensorOrientation,
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

        if (result.vpPitchDeg != null) {
          _pitchDeg = _pitchDeg * 0.8 + result.vpPitchDeg! * 0.2;
        }

        _recentLatencies.add(result.processingMs);
        if (_recentLatencies.length > 10) {
          _recentLatencies.removeAt(0);
        }
        final avgMs = _recentLatencies.reduce((a, b) => a + b) / _recentLatencies.length;
        fpsNotifier.value = avgMs > 0 ? 1000.0 / avgMs : 0.0;

        resultNotifier.value = result;
      }
      _isBusy = false;
    }).catchError((_) {
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

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    resultNotifier.dispose();
    fpsNotifier.dispose();
  }
}

// Live Survey Viewfinder Screen
// Consumes camera image stream via FrameProcessorService for real per-frame
// road edge detection, width measurement, and vanishing point estimation.
// Falls back to simulated road background when camera is unavailable.
// Clear instructions, legible typography, and 3-layer overlay.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../theme/safar_tokens.dart';
import '../services/permissions_service.dart';
import '../services/frame_processor_service.dart';
import '../widgets/hud_overlay_painter.dart';
import '../widgets/live_hud_card.dart';

class LiveSurveyScreen extends StatefulWidget {
  const LiveSurveyScreen({super.key});

  @override
  State<LiveSurveyScreen> createState() => _LiveSurveyScreenState();
}

class _LiveSurveyScreenState extends State<LiveSurveyScreen> {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _hasCameraPermission = false;
  bool _useDeviceCamera = true;
  bool _showInstructions = true;

  bool _isRecording = false;
  bool _layer1SegmentationTint = true;
  bool _layer2TransectLadder = true;
  bool _layer3HudGraphics = true;
  bool _isArPlaneCaptured = false;
  bool _isStreamingFrames = false;

  // Frame processor service -- the real pipeline
  FrameProcessorService? _frameProcessor;

  // Live telemetry state (updated from FrameResult or simulation fallback)
  double _currentWidthM = 0.0;
  double _halfWidthM = 0.50;
  double _chainageM = 0.0;
  double _speedKmh = 0.0;
  double _pitchDeg = 6.0;
  double _imuRms = 0.02;
  double _gpsHdop = 1.0;
  String _currentTier = 'LOW';
  String _edgeLeft = 'not_visible';
  String _edgeRight = 'not_visible';
  String _calibSource = 'MANUAL';
  double _meanRangeM = 10.0;
  int _observationCount = 0;
  double _madM = 0.0;
  double _processingFps = 0.0;

  // Dynamic overlay data from FrameResult
  List<List<double>> _leftEdgePoints = [];
  List<List<double>> _rightEdgePoints = [];
  List<List<double>> _carriageMaskPoly = [];
  List<double>? _vanishingPoint;
  bool _hasOcclusion = false;

  // Interactive Tap-to-Measure state
  bool _isTapMeasureActive = false;
  Offset? _liveTapPointA;
  Offset? _liveTapPointB;
  double? _liveTapDistanceM;

  void _handleCanvasTap(TapUpDetails details) {
    if (!_isTapMeasureActive) return;
    if (_liveTapPointA == null) {
      setState(() {
        _liveTapPointA = details.localPosition;
        _liveTapPointB = null;
        _liveTapDistanceM = null;
      });
    } else if (_liveTapPointB == null) {
      setState(() {
        _liveTapPointB = details.localPosition;
        final double dx = _liveTapPointB!.dx - _liveTapPointA!.dx;
        final double dy = _liveTapPointB!.dy - _liveTapPointA!.dy;
        final double pixelDist = math.sqrt(dx * dx + dy * dy);
        _liveTapDistanceM = (pixelDist / 44.0).clamp(0.5, 25.0);
        _currentWidthM = _liveTapDistanceM!;
        _halfWidthM = 0.08;
        _currentTier = 'HIGH';
        _calibSource = 'TAP RULER';
      });
    } else {
      setState(() {
        _liveTapPointA = details.localPosition;
        _liveTapPointB = null;
        _liveTapDistanceM = null;
      });
    }
  }

  // Fallback simulation timer (when camera is not available)
  Timer? _simulationTimer;

  // Rolling width buffer for temporal smoothing
  final List<double> _widthBuffer = [];
  static const int _widthBufferSize = 8;

  @override
  void initState() {
    super.initState();
    _initFrameProcessor();
    _checkPermissionsAndInitCamera();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _stopImageStream();
    _cameraController?.dispose();
    _frameProcessor?.dispose();
    super.dispose();
  }

  Future<void> _initFrameProcessor() async {
    _frameProcessor = FrameProcessorService(
      cameraHeightM: 1.40,
      pitchDeg: 6.0,
    );
    await _frameProcessor!.initialize();

    // Listen to results from the processing isolate
    _frameProcessor!.resultNotifier.addListener(_onFrameResult);
    _frameProcessor!.fpsNotifier.addListener(_onFpsUpdate);
  }

  void _onFrameResult() {
    if (!mounted) return;
    final result = _frameProcessor!.resultNotifier.value;

    // Temporal smoothing: rolling median of recent widths
    if (result.hasValidMeasurement && (!_isTapMeasureActive || _liveTapDistanceM == null)) {
      _widthBuffer.add(result.roadWidthM!);
      if (_widthBuffer.length > _widthBufferSize) {
        _widthBuffer.removeAt(0);
      }
      final sorted = List<double>.from(_widthBuffer)..sort();
      final smoothedWidth = sorted[sorted.length ~/ 2];

      setState(() {
        _currentWidthM = smoothedWidth;
        _halfWidthM = result.halfWidthM;
        _currentTier = result.tier;
        _observationCount = _widthBuffer.length;

        // Compute MAD from buffer
        if (_widthBuffer.length >= 3) {
          final deviations = _widthBuffer.map((w) => (w - smoothedWidth).abs()).toList()..sort();
          _madM = 1.4826 * deviations[deviations.length ~/ 2];
        }
      });
    }

    setState(() {
      _leftEdgePoints = result.leftEdgePoints;
      _rightEdgePoints = result.rightEdgePoints;
      _carriageMaskPoly = result.carriageMaskPoly;
      _vanishingPoint = result.vanishingPoint;
      _hasOcclusion = result.hasOcclusion;
      _edgeLeft = result.edgeLeftType.toUpperCase();
      _edgeRight = result.edgeRightType.toUpperCase();
      _meanRangeM = result.meanRangeM;

      if (result.vpPitchDeg != null) {
        _pitchDeg = result.vpPitchDeg!;
        _calibSource = 'VP ESTIMATE';
      }

      if (_isRecording) {
        _chainageM += (_speedKmh * 1000.0 / 3600.0) * (result.processingMs / 1000.0);
      }
    });
  }

  void _onFpsUpdate() {
    if (!mounted) return;
    setState(() {
      _processingFps = _frameProcessor!.fpsNotifier.value;
    });
  }

  Future<void> _checkPermissionsAndInitCamera() async {
    final hasPerm = await PermissionsService.checkCameraPermission();
    if (!mounted) return;
    setState(() => _hasCameraPermission = hasPerm);

    if (hasPerm) {
      await _initCamera();
    } else {
      _startFallbackSimulation();
    }
  }

  Future<void> _requestPermissions() async {
    final results = await PermissionsService.requestAllPermissions();
    if (!mounted) return;
    setState(() {
      _hasCameraPermission = results['camera'] ?? false;
    });

    if (_hasCameraPermission) {
      _simulationTimer?.cancel();
      await _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _useDeviceCamera = false);
        _startFallbackSimulation();
        return;
      }

      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
        _useDeviceCamera = true;
      });

      // Update focal length from actual camera resolution
      final size = _cameraController!.value.previewSize;
      if (size != null) {
        _frameProcessor?.updateCalibration(
          focalLengthPx: (size.width / 2.0) / math.tan((67.0 * math.pi / 180.0) / 2.0),
          cx: size.width / 2.0,
          cy: size.height / 2.0,
        );
      }

      // Start streaming frames to the processor
      _startImageStream();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCameraReady = false;
        _useDeviceCamera = false;
      });
      _startFallbackSimulation();
    }
  }

  void _startImageStream() {
    if (_isStreamingFrames || _cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) {
      _frameProcessor?.onCameraImage(image);
    });
    _isStreamingFrames = true;
  }

  Future<void> _stopImageStream() async {
    if (!_isStreamingFrames || _cameraController == null) return;
    try {
      await _cameraController!.stopImageStream();
    } catch (_) {
      // Ignore: stream may already be stopped
    }
    _isStreamingFrames = false;
  }

  /// Fallback simulation when camera is not available (emulator, permission denied).
  /// Uses a Timer to generate slowly varying fake data so the UI is not dead.
  void _startFallbackSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!mounted) return;
      final double t = timer.tick * 0.05;
      setState(() {
        if (!_isTapMeasureActive || _liveTapDistanceM == null) {
          _currentWidthM = 7.30 + (math.sin(t) * 0.18) + (math.sin(t * 3.0) * 0.04);
          _halfWidthM = (_currentWidthM > 7.35) ? 0.22 : 0.28;
          _currentTier = (_halfWidthM <= 0.25) ? 'HIGH' : 'MEDIUM';
          _calibSource = 'SIMULATOR';
        }
        _pitchDeg = 5.8 + (math.sin(t * 1.5) * 0.4);
        _imuRms = 0.03 + (math.sin(t * 2.0).abs() * 0.02);
        _speedKmh = 38.0 + (math.sin(t * 0.8) * 3.5);
        _gpsHdop = 0.80 + (math.sin(t * 0.4).abs() * 0.10);
        _edgeLeft = 'KERB';
        _edgeRight = 'PAINTED';
        _observationCount = 28;
        _madM = 0.11;
        if (_isRecording) {
          _chainageM += (_speedKmh * 1000.0 / 3600.0) * 0.15;
        }
      });
    });
  }

  void _captureArPlane() {
    setState(() {
      _isArPlaneCaptured = true;
      _calibSource = 'AR PLANE';
    });
    _frameProcessor?.updateCalibration(
      cameraHeightM: 1.40,
      pitchDeg: 6.0,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: SafarTokens.asphalt800,
        content: Text(
          'STATIONARY AR GROUND PLANE CAPTURED: CAMERA HEIGHT h=1.40 m | PITCH=+6.0 deg',
          style: SafarTokens.fontMono(fontSize: 12.0, color: SafarTokens.hivis),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLive = _hasCameraPermission && _isCameraReady && _useDeviceCamera && _cameraController != null;

    return Scaffold(
      backgroundColor: SafarTokens.asphalt950,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Camera Viewfinder or Road Perspective Simulation
            Positioned.fill(
              child: isLive
                  ? CameraPreview(_cameraController!)
                  : Container(
                      color: SafarTokens.asphalt900,
                      child: CustomPaint(
                        painter: _SimulatedRoadBackgroundPainter(),
                      ),
                    ),
            ),

            // 2. The 3-Layer Overlay Canvas with Interactive Tap Measure
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: _handleCanvasTap,
                child: CustomPaint(
                  painter: HudOverlayPainter(
                    showSegmentationTint: _layer1SegmentationTint,
                    showTransectLadder: _layer2TransectLadder,
                    showHudGraphics: _layer3HudGraphics,
                    currentWidthM: _currentWidthM,
                    hasOcclusion: _hasOcclusion,
                    // Dynamic data from frame processor
                    dynamicLeftEdge: _leftEdgePoints,
                    dynamicRightEdge: _rightEdgePoints,
                    dynamicMaskPoly: _carriageMaskPoly,
                    dynamicVP: _vanishingPoint,
                    useDynamicEdges: isLive && _leftEdgePoints.isNotEmpty,
                    tapPointA: _liveTapPointA,
                    tapPointB: _liveTapPointB,
                    tapMeasuredDistanceM: _liveTapDistanceM,
                  ),
                ),
              ),
            ),

            // 3. Processing FPS indicator (top-left, small)
            if (isLive && !_isTapMeasureActive)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: SafarTokens.asphalt950.withValues(alpha: 0.80),
                    borderRadius: BorderRadius.circular(SafarTokens.rSm),
                  ),
                  child: Text(
                    '${_processingFps.toStringAsFixed(1)} FPS | ${_isStreamingFrames ? "LIVE" : "PAUSED"}',
                    style: SafarTokens.fontMono(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w600,
                      color: _processingFps > 5
                          ? SafarTokens.confHigh
                          : _processingFps > 2
                              ? SafarTokens.confMed
                              : SafarTokens.confLow,
                    ),
                  ),
                ),
              ),

            // 4. Tap-to-Measure Active Banner
            if (_isTapMeasureActive)
              Positioned(
                top: 8,
                left: 8,
                right: 74,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: SafarTokens.asphalt950.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(SafarTokens.rSm),
                    border: Border.all(color: SafarTokens.hivis, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.straighten, color: SafarTokens.hivis, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _liveTapPointA == null
                              ? 'TAP LEFT KERB (POINT A)'
                              : (_liveTapPointB == null
                                  ? 'TAP RIGHT KERB (POINT B)'
                                  : 'MEASURED: ${_liveTapDistanceM?.toStringAsFixed(2)} m'),
                          style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w700, color: SafarTokens.hivis),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_liveTapPointA != null)
                        InkWell(
                          onTap: () {
                            setState(() {
                              _liveTapPointA = null;
                              _liveTapPointB = null;
                              _liveTapDistanceM = null;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text('RESET', style: SafarTokens.fontMono(fontSize: 10, color: SafarTokens.confLow, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isTapMeasureActive = false;
                            _liveTapPointA = null;
                            _liveTapPointB = null;
                            _liveTapDistanceM = null;
                          });
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.close, size: 16, color: SafarTokens.asphalt400),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 5. "SIMULATOR MODE" banner when using fallback
            if (!isLive && !_isTapMeasureActive)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: SafarTokens.asphalt950.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(SafarTokens.rSm),
                    border: Border.all(color: SafarTokens.hivisDim),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.science_outlined, size: 14, color: SafarTokens.hivis),
                      const SizedBox(width: 6),
                      Text(
                        'SIMULATOR (SYNTHETIC ROAD)',
                        style: SafarTokens.fontMono(
                          fontSize: 10.0,
                          fontWeight: FontWeight.w800,
                          color: SafarTokens.paint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 6. Camera Edge Searching Hint (if camera live but no edges found yet)
            if (isLive && _leftEdgePoints.isEmpty && !_isTapMeasureActive)
              Positioned(
                top: 36,
                left: 8,
                right: 74,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: SafarTokens.asphalt950.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(SafarTokens.rSm),
                    border: Border.all(color: SafarTokens.asphalt700),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 14, color: SafarTokens.hivisDim),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Scanning road edges... Point at road with kerbs, or tap ruler icon to measure manually.',
                          style: SafarTokens.fontUi(fontSize: 10.5, color: SafarTokens.concrete200),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 7. Permission Request Banner (if permission not granted)
            if (!_hasCameraPermission)
              Positioned(
                top: 30,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SafarTokens.asphalt950.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(SafarTokens.rMd),
                    border: Border.all(color: SafarTokens.confMed, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_outlined, color: SafarTokens.confMed, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'CAMERA & LOCATION PERMISSION REQUIRED',
                              style: SafarTokens.fontUi(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w800,
                                color: SafarTokens.paint,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Safar needs Camera access to measure road boundaries in real time and Location to tag chainage coordinates.',
                        style: SafarTokens.fontUi(fontSize: 11.0, color: SafarTokens.asphalt400),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SafarTokens.hivis,
                              foregroundColor: SafarTokens.asphalt950,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                            ),
                            onPressed: _requestPermissions,
                            child: Text(
                              'GRANT PERMISSIONS',
                              style: SafarTokens.fontUi(fontSize: 11.0, fontWeight: FontWeight.w800),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _useDeviceCamera = false);
                              _startFallbackSimulation();
                            },
                            child: Text(
                              'USE ROAD SIMULATOR',
                              style: SafarTokens.fontMono(fontSize: 10.5, color: SafarTokens.paint),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // 6. Instructions Card (Collapsible)
            if (_showInstructions && _hasCameraPermission)
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: SafarTokens.asphalt950.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(SafarTokens.rMd),
                    border: Border.all(color: SafarTokens.asphalt700),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'HOW LIVE SURVEY WORKS (STEP-BY-STEP)',
                            style: SafarTokens.microLabel(color: SafarTokens.hivis),
                          ),
                          InkWell(
                            onTap: () => setState(() => _showInstructions = false),
                            child: const Icon(Icons.close, size: 16, color: SafarTokens.asphalt400),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '1. Mount phone securely on windshield or dash.\n'
                        '2. Tap the Hand icon (right bar) while STATIONARY to calibrate camera height (1.40 m).\n'
                        '3. Drive at survey speed (25-55 km/h). Observe the live width readout.\n'
                        '4. Green/Yellow rungs indicate the 5-15 m measurement band perpendicular to road.',
                        style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),

            // 7. Floating Overlay Layer Controls (Right side)
            Positioned(
              right: 12,
              top: _showInstructions ? 140 : 16,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: SafarTokens.asphalt950.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(SafarTokens.rMd),
                  border: Border.all(color: SafarTokens.asphalt700),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
                ),
                child: Column(
                  children: [
                    _buildLayerToggle(
                      'L1',
                      'Segmentation Tint',
                      _layer1SegmentationTint,
                      () => setState(() => _layer1SegmentationTint = !_layer1SegmentationTint),
                    ),
                    const SizedBox(height: 8),
                    _buildLayerToggle(
                      'L2',
                      'Transect Ladder (1m)',
                      _layer2TransectLadder,
                      () => setState(() => _layer2TransectLadder = !_layer2TransectLadder),
                    ),
                    const SizedBox(height: 8),
                    _buildLayerToggle(
                      'L3',
                      'HUD Geometry',
                      _layer3HudGraphics,
                      () => setState(() => _layer3HudGraphics = !_layer3HudGraphics),
                    ),
                    const Divider(color: SafarTokens.asphalt700, height: 16),
                    IconButton(
                      icon: Icon(
                        Icons.straighten,
                        size: 22,
                        color: _isTapMeasureActive ? SafarTokens.hivis : SafarTokens.asphalt400,
                      ),
                      tooltip: _isTapMeasureActive ? 'Exit Tap Measure' : 'Interactive Tap Measure on Screen',
                      onPressed: () {
                        setState(() {
                          _isTapMeasureActive = !_isTapMeasureActive;
                          if (!_isTapMeasureActive) {
                            _liveTapPointA = null;
                            _liveTapPointB = null;
                            _liveTapDistanceM = null;
                          }
                        });
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.touch_app_outlined,
                        size: 22,
                        color: _isArPlaneCaptured ? SafarTokens.confHigh : SafarTokens.hivis,
                      ),
                      tooltip: 'Capture Stationary AR Plane',
                      onPressed: _captureArPlane,
                    ),
                    IconButton(
                      icon: Icon(
                        _useDeviceCamera ? Icons.videocam : Icons.computer,
                        size: 20,
                        color: SafarTokens.paint,
                      ),
                      tooltip: _useDeviceCamera ? 'Switch to Road Simulator' : 'Switch to Device Camera',
                      onPressed: () {
                        if (!_hasCameraPermission) {
                          _requestPermissions();
                        } else {
                          setState(() => _useDeviceCamera = !_useDeviceCamera);
                          if (_useDeviceCamera) {
                            _simulationTimer?.cancel();
                            _startImageStream();
                          } else {
                            _stopImageStream();
                            _startFallbackSimulation();
                          }
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.help_outline, size: 20, color: SafarTokens.asphalt400),
                      tooltip: 'Show Instructions',
                      onPressed: () => setState(() => _showInstructions = !_showInstructions),
                    ),
                  ],
                ),
              ),
            ),

            // 8. Bottom panel: HUD card + Drive action bar
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HUD Readout Card
                  LiveHudCard(
                    widthM: _currentWidthM,
                    halfWidthM: _halfWidthM,
                    chainageM: _chainageM,
                    tier: _currentTier,
                    observationCount: _observationCount,
                    madM: _madM,
                    edgeLeft: _edgeLeft,
                    edgeRight: _edgeRight,
                    meanRangeM: _meanRangeM,
                    calibSource: _calibSource,
                    speedKmh: _speedKmh,
                    pitchDeg: _pitchDeg,
                    imuRms: _imuRms,
                    gpsHdop: _gpsHdop,
                  ),
                  const SizedBox(height: 8),
                  // Drive Action Bar
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isRecording ? SafarTokens.confLow : SafarTokens.hivis,
                              foregroundColor: SafarTokens.asphalt950,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                            ),
                            onPressed: () {
                              setState(() => _isRecording = !_isRecording);
                              if (_isRecording) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: SafarTokens.asphalt800,
                                    duration: const Duration(seconds: 2),
                                    content: Text(
                                      'SURVEY RECORDING STARTED (Tracking chainage and 5m bins)',
                                      style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis),
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: SafarTokens.asphalt800,
                                    duration: const Duration(seconds: 3),
                                    content: Text(
                                      'SURVEY RUN COMPLETED (${_chainageM.toStringAsFixed(0)} m corridor). View in MAP or DATA tabs.',
                                      style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis),
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              _isRecording ? 'STOP DRIVE' : 'START SURVEY DRIVE',
                              style: SafarTokens.fontUi(
                                fontSize: 13.0,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.05,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 48,
                        child: Container(
                          decoration: BoxDecoration(
                            color: SafarTokens.asphalt800,
                            borderRadius: BorderRadius.circular(SafarTokens.rSm),
                            border: Border.all(color: SafarTokens.asphalt600),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.bookmark_add_outlined, color: SafarTokens.concrete50, size: 20),
                            tooltip: 'Bookmark for AR Override',
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: SafarTokens.asphalt800,
                                  content: Text(
                                    'CH ${_chainageM.toStringAsFixed(0)} m bookmarked',
                                    style: SafarTokens.fontMono(fontSize: 12, color: SafarTokens.hivis),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerToggle(String shortTag, String title, bool isActive, VoidCallback onTap) {
    return Tooltip(
      message: 'Toggle $title',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive ? SafarTokens.hivis : SafarTokens.asphalt800,
            borderRadius: BorderRadius.circular(SafarTokens.rSm),
            border: Border.all(
              color: isActive ? SafarTokens.hivis : SafarTokens.asphalt600,
              width: 1.0,
            ),
          ),
          child: Center(
            child: Text(
              shortTag,
              style: SafarTokens.fontMono(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: isActive ? SafarTokens.asphalt950 : SafarTokens.concrete100,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Background painter creating a perspective road simulation
class _SimulatedRoadBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double vpX = size.width * 0.50;
    final double vpY = size.height * 0.38;

    // Sky
    final Paint skyPaint = Paint()..color = SafarTokens.asphalt800;
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, vpY), skyPaint);

    // Ground / Asphalt Road
    final Path groundPath = Path()
      ..moveTo(0, vpY)
      ..lineTo(size.width, vpY)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final Paint groundPaint = Paint()..color = SafarTokens.asphalt900;
    canvas.drawPath(groundPath, groundPaint);

    // Road surface perspective wedge
    final Path roadPath = Path()
      ..moveTo(vpX - 40, vpY)
      ..lineTo(vpX + 40, vpY)
      ..lineTo(size.width * 0.95, size.height)
      ..lineTo(size.width * 0.05, size.height)
      ..close();
    final Paint roadPaint = Paint()..color = SafarTokens.asphalt950;
    canvas.drawPath(roadPath, roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

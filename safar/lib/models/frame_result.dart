// Per-frame pipeline output model.
// Produced by FrameProcessorService, consumed by LiveSurveyScreen and HudOverlayPainter.

class FrameResult {
  /// Detected left road edge points in normalised image coordinates (0..1).
  /// Each entry is [x, y] from top-left.
  final List<List<double>> leftEdgePoints;

  /// Detected right road edge points in normalised image coordinates.
  final List<List<double>> rightEdgePoints;

  /// Measured road width in metres (null if measurement failed).
  final double? roadWidthM;

  /// Estimated half-width uncertainty in metres.
  final double halfWidthM;

  /// Confidence tier derived from live observation quality.
  final String tier; // HIGH | MEDIUM | LOW

  /// Vanishing point in normalised image coordinates [x, y].
  final List<double>? vanishingPoint;

  /// Estimated pitch from vanishing point in degrees.
  final double? vpPitchDeg;

  /// Road centreline in normalised coordinates (list of [x, y]).
  final List<List<double>> centrelinePoints;

  /// Normalised polygon vertices for the detected carriageway mask.
  /// Used by HudOverlayPainter to draw the segmentation tint.
  final List<List<double>> carriageMaskPoly;

  /// Whether an occlusion (vehicle/obstacle) was detected in the measurement band.
  final bool hasOcclusion;

  /// Fraction of the measurement band that is occluded (0.0 to 1.0).
  final double occludedFrac;

  /// Edge classification for the left boundary.
  final String edgeLeftType; // kerb | painted | gravel_transition | vegetation_edge | occluded | not_visible

  /// Edge classification for the right boundary.
  final String edgeRightType;

  /// Mean range (distance ahead) of the measurement in metres.
  final double meanRangeM;

  /// Boundary entropy: a measure of edge detection confidence.
  final double boundaryEntropy;

  /// Frame processing latency in milliseconds.
  final int processingMs;

  /// Source image dimensions.
  final int imageWidth;
  final int imageHeight;

  /// Timestamp of the processed frame.
  final DateTime timestamp;

  const FrameResult({
    this.leftEdgePoints = const [],
    this.rightEdgePoints = const [],
    this.roadWidthM,
    this.halfWidthM = 0.50,
    this.tier = 'LOW',
    this.vanishingPoint,
    this.vpPitchDeg,
    this.centrelinePoints = const [],
    this.carriageMaskPoly = const [],
    this.hasOcclusion = false,
    this.occludedFrac = 0.0,
    this.edgeLeftType = 'not_visible',
    this.edgeRightType = 'not_visible',
    this.meanRangeM = 10.0,
    this.boundaryEntropy = 0.5,
    this.processingMs = 0,
    this.imageWidth = 0,
    this.imageHeight = 0,
    required this.timestamp,
  });

  /// Whether this result contains a valid width measurement.
  bool get hasValidMeasurement => roadWidthM != null && roadWidthM! > 0.0;

  /// Formatted width string for display.
  String get widthDisplay => hasValidMeasurement
      ? roadWidthM!.toStringAsFixed(2)
      : '--';

  /// FPS implied by processing latency.
  double get impliedFps => processingMs > 0 ? 1000.0 / processingMs : 0.0;

  static final FrameResult empty = FrameResult(
    timestamp: DateTime(2000, 1, 1),
  );
}

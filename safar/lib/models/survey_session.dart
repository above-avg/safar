// Survey Session Model
// Corresponding to files/pipeline.py and files/README.md

import 'transect.dart';
import 'prediction.dart';
import 'map_marker_data.dart';

enum SurveyMode {
  upload,
  live,
  frames,
  manualAr,
}

extension SurveyModeExtension on SurveyMode {
  String get displayName {
    switch (this) {
      case SurveyMode.upload:
        return 'Upload Video + Sensor Log (Cloud GPU)';
      case SurveyMode.live:
        return 'Live Camera Viewfinder (On-Device INT8)';
      case SurveyMode.frames:
        return 'Frame Folder / Dashcam Archive';
      case SurveyMode.manualAr:
        return 'Manual AR Ruler (Ground Truth)';
    }
  }

  String get shortName {
    switch (this) {
      case SurveyMode.upload:
        return 'UPLOAD';
      case SurveyMode.live:
        return 'LIVE';
      case SurveyMode.frames:
        return 'FRAMES';
      case SurveyMode.manualAr:
        return 'AR RULER';
    }
  }
}

class SurveySession {
  final String id;
  final String title;
  final SurveyMode mode;
  final DateTime createdAt;
  final Duration duration;
  final double distanceM;
  final double meanWidthM;
  final double highConfidencePct;
  final List<ChainageBin> bins;
  final List<Prediction> predictions;
  final List<MapSegmentData> mapSegments;
  final String status; // completed | processing | pending_review

  const SurveySession({
    required this.id,
    required this.title,
    required this.mode,
    required this.createdAt,
    required this.duration,
    required this.distanceM,
    required this.meanWidthM,
    required this.highConfidencePct,
    required this.bins,
    required this.predictions,
    required this.mapSegments,
    this.status = 'completed',
  });
}

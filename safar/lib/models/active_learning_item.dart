// Active Learning Review Queue Item Model
// Corresponding to Section 10 of System Plan (P02)

class ActiveLearningItem {
  final String id;
  final String sessionId;
  final double chainageM;
  final double provisionalWidthM;
  final double halfWidthM;
  final String reason; // e.g. "Low observation count", "Parked vehicle occlusion", "Gravel transition blur"
  final String edgeLeft;
  final String edgeRight;
  double? correctedLeftM;
  double? correctedRightM;
  bool isReviewed;
  String status; // pending | corrected | promoted

  ActiveLearningItem({
    required this.id,
    required this.sessionId,
    required this.chainageM,
    required this.provisionalWidthM,
    required this.halfWidthM,
    required this.reason,
    required this.edgeLeft,
    required this.edgeRight,
    this.correctedLeftM,
    this.correctedRightM,
    this.isReviewed = false,
    this.status = 'pending',
  });

  double get correctedWidthM {
    if (correctedLeftM != null && correctedRightM != null) {
      return correctedLeftM! + correctedRightM!;
    }
    return provisionalWidthM;
  }
}

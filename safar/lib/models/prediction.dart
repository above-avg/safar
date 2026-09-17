// Conformal Prediction Model
// Corresponding to files/confidence.py

enum ConfidenceTier {
  high,
  medium,
  low,
}

extension ConfidenceTierExtension on ConfidenceTier {
  String get name {
    switch (this) {
      case ConfidenceTier.high:
        return 'HIGH';
      case ConfidenceTier.medium:
        return 'MEDIUM';
      case ConfidenceTier.low:
        return 'LOW';
    }
  }

  String get description {
    switch (this) {
      case ConfidenceTier.high:
        return '<= 0.25 m interval - Auto-accepted';
      case ConfidenceTier.medium:
        return '<= 0.60 m interval - Accept with flag';
      case ConfidenceTier.low:
        return '> 0.60 m interval - Route to review queue';
    }
  }
}

class Prediction {
  final double widthM;
  final double halfWidthM;
  final ConfidenceTier tier;
  final double coverageTarget;
  final Map<String, dynamic> features;

  const Prediction({
    required this.widthM,
    required this.halfWidthM,
    required this.tier,
    this.coverageTarget = 0.90,
    this.features = const {},
  });

  double get loM => widthM - halfWidthM;
  double get hiM => widthM + halfWidthM;

  Map<String, dynamic> toJson() => {
    'width_m': widthM,
    'half_width_m': halfWidthM,
    'tier': tier.name,
    'lo_m': loM,
    'hi_m': hiM,
    'coverage_target': coverageTarget,
    'features': features,
  };
}

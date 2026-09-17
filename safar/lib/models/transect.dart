// Transect and ChainageBin Models
// Corresponding to files/measure.py

class Transect {
  final double chainageM;
  final double centreX;
  final double centreY;
  final double? widthM;
  final double? leftOffsetM;
  final double? rightOffsetM;
  final String edgeLeft; // kerb | painted | gravel_transition | vegetation_edge | occluded | not_visible
  final String edgeRight;
  final double meanRangeM;
  final double occludedFrac;
  final double boundaryEntropy;
  final double imuRms;

  const Transect({
    required this.chainageM,
    required this.centreX,
    required this.centreY,
    this.widthM,
    this.leftOffsetM,
    this.rightOffsetM,
    this.edgeLeft = 'not_visible',
    this.edgeRight = 'not_visible',
    this.meanRangeM = 10.0,
    this.occludedFrac = 0.0,
    this.boundaryEntropy = 0.2,
    this.imuRms = 0.02,
  });
}

class ChainageBin {
  final double chainageM;
  final double widthM;
  final double madM; // Median Absolute Deviation
  final int n; // Number of observations
  final String edgeLeft;
  final String edgeRight;
  final double meanRangeM;
  final double occludedFrac;
  final double boundaryEntropy;
  final double latitude;
  final double longitude;
  final List<Transect> members;

  const ChainageBin({
    required this.chainageM,
    required this.widthM,
    required this.madM,
    required this.n,
    required this.edgeLeft,
    required this.edgeRight,
    required this.meanRangeM,
    required this.occludedFrac,
    required this.boundaryEntropy,
    required this.latitude,
    required this.longitude,
    this.members = const [],
  });

  Map<String, dynamic> toJson() => {
    'chainage_m': chainageM,
    'width_m': widthM,
    'mad_m': madM,
    'n': n,
    'edge_left': edgeLeft,
    'edge_right': edgeRight,
    'mean_range_m': meanRangeM,
    'occluded_frac': occludedFrac,
    'boundary_entropy': boundaryEntropy,
    'lat': latitude,
    'lon': longitude,
  };
}

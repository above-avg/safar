// Road Pipeline Service
// Implementing the mathematical pipeline from files/ipm.py, files/measure.py,
// files/calibration.py, and files/confidence.py

import 'dart:convert';
import 'dart:math' as math;
import '../models/camera_calibration.dart';
import '../models/transect.dart';
import '../models/prediction.dart';

class RoadPipelineService {
  static const double defaultResolutionMPerPx = 0.02; // 2 cm/pixel BEV raster
  static const double defaultMeasureRangeNearM = 5.0; // 5m - 15m trusted band
  static const double defaultMeasureRangeFarM = 15.0;

  // Rank maps corresponding to files/confidence.py
  static const Map<String, int> edgeRank = {
    'kerb': 0,
    'painted': 1,
    'gravel_transition': 2,
    'vegetation_edge': 3,
    'occluded': 4,
    'not_visible': 5,
  };

  static const Map<String, int> calibRank = {
    'ar_plane': 0,
    'vanishing_point': 1,
    'marking_prior': 2,
    'manual': 1,
    'unknown': 3,
  };

  // Convert (u, v) image pixel coordinates to ground plane coordinates (X right, Y forward in metres)
  // Inverse Perspective Mapping (IPM) as in files/ipm.py and files/calibration.py
  static List<double>? pixelToGround({
    required double u,
    required double v,
    required CameraIntrinsics intr,
    required CameraExtrinsics ext,
  }) {
    // Normalised ray in camera frame
    final double rayX = (u - intr.cx) / intr.fx;
    final double rayY = (v - intr.cy) / intr.fy;
    const double rayZ = 1.0;

    final double cosP = math.cos(ext.pitchRad);
    final double sinP = math.sin(ext.pitchRad);

    // Direction vector in ground coordinates (X right, Y forward, Z up)
    final double dX = rayX;
    final double dY = cosP * rayZ - sinP * rayY;
    final double dZ = -sinP * rayZ - cosP * rayY;

    // Ray must descend to road plane (dZ < 0)
    if (dZ >= -1e-5) {
      return null; // Horizon or above
    }

    final double t = -ext.heightM / dZ;
    if (t <= 0) return null;

    final double groundX = t * dX;
    final double groundY = t * dY;
    return [groundX, groundY];
  }

  // Inverse: Ground point (X right, Y forward in metres) back to image pixels (u, v)
  static List<double>? groundToPixel({
    required double groundX,
    required double groundY,
    required CameraIntrinsics intr,
    required CameraExtrinsics ext,
  }) {
    final double cosP = math.cos(ext.pitchRad);
    final double sinP = math.sin(ext.pitchRad);

    // Camera frame coordinates
    final double camX = groundX;
    final double camY = ext.heightM * cosP - groundY * sinP;
    final double camZ = groundY * cosP + ext.heightM * sinP;

    if (camZ <= 0.1) return null; // Behind camera

    final double u = intr.fx * (camX / camZ) + intr.cx;
    final double v = intr.fy * (camY / camZ) + intr.cy;
    return [u, v];
  }

  // Heuristic Split-Conformal Half-Width Estimator
  // Directly porting the formula from files/confidence.py
  static Prediction predictConfidence({
    required double widthM,
    required double madM,
    required int observationCount,
    required double meanRangeM,
    required String edgeLeft,
    required String edgeRight,
    required double occludedFrac,
    required double boundaryEntropy,
    required String calibSource,
    double crossMethodDisagreement = 0.04, // Typical 4% agreement between IPM and Depth
    double imuRms = 0.02,
    double gpsHdop = 0.8,
  }) {
    final double eLeftRank = (edgeRank[edgeLeft] ?? 5).toDouble();
    final double eRightRank = (edgeRank[edgeRight] ?? 5).toDouble();
    final double cRank = (calibRank[calibSource] ?? 3).toDouble();

    // Baseline uncertainty budget
    double hw = 0.08;
    hw += 0.55 * crossMethodDisagreement * math.max(widthM, 1.0);
    hw += 0.90 * madM;
    hw += 0.006 * math.max(meanRangeM - 8.0, 0.0) * widthM / 1.4;
    hw += 0.10 * (eLeftRank + eRightRank);
    hw += 0.70 * occludedFrac;
    hw += 0.25 * boundaryEntropy;
    hw += 0.18 * cRank;
    hw *= math.pow(6.0 / math.max(observationCount.toDouble(), 2.0), 0.35);

    // Clamp between 0.06m and 3.50m
    hw = hw.clamp(0.06, 3.50);

    ConfidenceTier tier;
    if (hw <= 0.25) {
      tier = ConfidenceTier.high;
    } else if (hw <= 0.60) {
      tier = ConfidenceTier.medium;
    } else {
      tier = ConfidenceTier.low;
    }

    final Map<String, dynamic> features = {
      'cross_method_disagreement': crossMethodDisagreement,
      'observation_mad': madM,
      'observation_count': observationCount,
      'mean_range_m': meanRangeM,
      'edge_left_rank': eLeftRank,
      'edge_right_rank': eRightRank,
      'occlusion_fraction': occludedFrac,
      'seg_boundary_entropy': boundaryEntropy,
      'imu_vibration_rms': imuRms,
      'gps_hdop': gpsHdop,
      'calibration_rank': cRank,
      'width_m': widthM,
    };

    return Prediction(
      widthM: widthM,
      halfWidthM: hw,
      tier: tier,
      coverageTarget: 0.90,
      features: features,
    );
  }

  // Robust Aggregation into 5m Chainage Bins (Median + MAD)
  // Corresponding to files/measure.py
  static ChainageBin aggregateTransects({
    required double chainageM,
    required List<Transect> transects,
    required double latitude,
    required double longitude,
  }) {
    if (transects.isEmpty) {
      return ChainageBin(
        chainageM: chainageM,
        widthM: 0.0,
        madM: 0.0,
        n: 0,
        edgeLeft: 'not_visible',
        edgeRight: 'not_visible',
        meanRangeM: 10.0,
        occludedFrac: 0.0,
        boundaryEntropy: 0.5,
        latitude: latitude,
        longitude: longitude,
      );
    }

    final validWidths = transects
        .map((t) => t.widthM)
        .where((w) => w != null && w > 0.0)
        .cast<double>()
        .toList();

    if (validWidths.isEmpty) {
      return ChainageBin(
        chainageM: chainageM,
        widthM: 0.0,
        madM: 0.0,
        n: 0,
        edgeLeft: 'not_visible',
        edgeRight: 'not_visible',
        meanRangeM: 10.0,
        occludedFrac: 0.0,
        boundaryEntropy: 0.5,
        latitude: latitude,
        longitude: longitude,
        members: transects,
      );
    }

    validWidths.sort();
    final double medianWidth = _median(validWidths);

    final deviations = validWidths.map((w) => (w - medianWidth).abs()).toList();
    deviations.sort();
    final double mad = 1.4826 * _median(deviations);

    // Modal edge classifications
    final edgeLefts = transects.map((t) => t.edgeLeft).toList();
    final edgeRights = transects.map((t) => t.edgeRight).toList();

    final meanRange = transects.map((t) => t.meanRangeM).reduce((a, b) => a + b) / transects.length;
    final meanOccluded = transects.map((t) => t.occludedFrac).reduce((a, b) => a + b) / transects.length;
    final meanEntropy = transects.map((t) => t.boundaryEntropy).reduce((a, b) => a + b) / transects.length;

    return ChainageBin(
      chainageM: chainageM,
      widthM: medianWidth,
      madM: mad,
      n: transects.length,
      edgeLeft: _mode(edgeLefts),
      edgeRight: _mode(edgeRights),
      meanRangeM: meanRange,
      occludedFrac: meanOccluded,
      boundaryEntropy: meanEntropy,
      latitude: latitude,
      longitude: longitude,
      members: transects,
    );
  }

  static double _median(List<double> sortedList) {
    if (sortedList.isEmpty) return 0.0;
    final int middle = sortedList.length ~/ 2;
    if (sortedList.length % 2 == 1) {
      return sortedList[middle];
    } else {
      return (sortedList[middle - 1] + sortedList[middle]) / 2.0;
    }
  }

  static String _mode(List<String> list) {
    if (list.isEmpty) return 'not_visible';
    final Map<String, int> counts = {};
    for (final item in list) {
      counts[item] = (counts[item] ?? 0) + 1;
    }
    String best = list.first;
    int maxCount = 0;
    counts.forEach((k, v) {
      if (v > maxCount) {
        maxCount = v;
        best = k;
      }
    });
    return best;
  }

  // Export GeoJSON (EPSG:4326) format
  static String exportGeoJson(List<ChainageBin> bins, List<Prediction> predictions) {
    final List<Map<String, dynamic>> features = [];

    for (int i = 0; i < bins.length; i++) {
      final bin = bins[i];
      final pred = i < predictions.length ? predictions[i] : null;

      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [bin.longitude, bin.latitude],
        },
        'properties': {
          'chainage_m': bin.chainageM,
          'width_m': bin.widthM,
          'interval_half_m': pred?.halfWidthM ?? 0.30,
          'width_lo_m': pred?.loM ?? (bin.widthM - 0.30),
          'width_hi_m': pred?.hiM ?? (bin.widthM + 0.30),
          'tier': pred?.tier.name ?? 'medium',
          'edge_left': bin.edgeLeft,
          'edge_right': bin.edgeRight,
          'observation_count': bin.n,
          'mad_m': bin.madM,
          'fire_tender_passable': bin.widthM >= 3.5,
          'ambulance_passable': bin.widthM >= 3.0,
        },
      });
    }

    final Map<String, dynamic> geoJson = {
      'type': 'FeatureCollection',
      'crs': {
        'type': 'name',
        'properties': {'name': 'urn:ogc:def:crs:OGC:1.3:CRS84'}
      },
      'features': features,
    };

    return const JsonEncoder.withIndent('  ').convert(geoJson);
  }

  // Export CSV format
  static String exportCsv(List<ChainageBin> bins, List<Prediction> predictions) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('chainage_m,latitude,longitude,width_m,half_width_m,lo_m,hi_m,tier,edge_left,edge_right,obs_count,mad_m,fire_tender_passable,ambulance_passable');

    for (int i = 0; i < bins.length; i++) {
      final bin = bins[i];
      final pred = i < predictions.length ? predictions[i] : null;
      final double hw = pred?.halfWidthM ?? 0.30;
      final double lo = pred?.loM ?? (bin.widthM - hw);
      final double hi = pred?.hiM ?? (bin.widthM + hw);
      final String tier = pred?.tier.name ?? 'MEDIUM';
      final bool firePassable = bin.widthM >= 3.5;
      final bool ambPassable = bin.widthM >= 3.0;

      buffer.writeln(
        '${bin.chainageM.toStringAsFixed(1)},'
        '${bin.latitude.toStringAsFixed(6)},'
        '${bin.longitude.toStringAsFixed(6)},'
        '${bin.widthM.toStringAsFixed(2)},'
        '${hw.toStringAsFixed(2)},'
        '${lo.toStringAsFixed(2)},'
        '${hi.toStringAsFixed(2)},'
        '$tier,'
        '${bin.edgeLeft},'
        '${bin.edgeRight},'
        '${bin.n},'
        '${bin.madM.toStringAsFixed(3)},'
        '$firePassable,'
        '$ambPassable'
      );
    }
    return buffer.toString();
  }
}

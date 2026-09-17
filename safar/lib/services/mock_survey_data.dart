// Mock Survey Datasets
// Generating realistic road survey corridors with GPS tracks,
// varying widths, edge types, pinch points, and low-confidence items.

import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../models/transect.dart';
import '../models/prediction.dart';
import '../models/map_marker_data.dart';
import '../models/active_learning_item.dart';
import '../models/survey_session.dart';
import 'road_pipeline_service.dart';

class MockSurveyData {
  MockSurveyData._();

  // Dataset 1: NH-48 National Highway Corridor (Dual Carriageway, Kerbed, High Confidence)
  static SurveySession createHighwaySession() {
    const double startLat = 12.8390;
    const double startLon = 77.6770;
    const int count = 80; // 80 bins * 5m = 400m sample slice
    const double baseWidth = 9.20;

    final List<ChainageBin> bins = [];
    final List<Prediction> predictions = [];
    final List<MapSegmentData> segments = [];

    for (int i = 0; i < count; i++) {
      final double chainage = i * 5.0;
      final double lat = startLat + (i * 0.000042) + (math.sin(i * 0.1) * 0.000005);
      final double lon = startLon + (i * 0.000038) + (math.cos(i * 0.08) * 0.000004);

      // Width varies smoothly around 9.2m
      final double width = baseWidth + math.sin(i * 0.15) * 0.45;
      final double mad = 0.08 + (math.sin(i * 0.3).abs() * 0.04);
      const int obs = 28;

      final bin = ChainageBin(
        chainageM: chainage,
        widthM: width,
        madM: mad,
        n: obs,
        edgeLeft: 'kerb',
        edgeRight: 'painted',
        meanRangeM: 9.4,
        occludedFrac: 0.0,
        boundaryEntropy: 0.12,
        latitude: lat,
        longitude: lon,
      );
      bins.add(bin);

      final pred = RoadPipelineService.predictConfidence(
        widthM: width,
        madM: mad,
        observationCount: obs,
        meanRangeM: 9.4,
        edgeLeft: 'kerb',
        edgeRight: 'painted',
        occludedFrac: 0.0,
        boundaryEntropy: 0.12,
        calibSource: 'ar_plane',
        crossMethodDisagreement: 0.025,
      );
      predictions.add(pred);

      segments.add(MapSegmentData(
        id: 'NH48-BIN-$i',
        position: LatLng(lat, lon),
        chainageM: chainage,
        widthM: width,
        halfWidthM: pred.halfWidthM,
        tier: pred.tier.name,
        edgeLeft: 'KERB',
        edgeRight: 'PAINTED',
        observationCount: obs,
        madM: mad,
        calibSource: 'AR PLANE',
        utmEast: 682140.0 + (i * 4.2),
        utmNorth: 1420100.0 + (i * 3.8),
      ));
    }

    return SurveySession(
      id: 'SESSION-NH48-001',
      title: 'NH-48 Corridor Survey (Asphalt/Kerbed)',
      mode: SurveyMode.upload,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      duration: const Duration(minutes: 18, seconds: 40),
      distanceM: count * 5.0,
      meanWidthM: baseWidth,
      highConfidencePct: 94.2,
      bins: bins,
      predictions: predictions,
      mapSegments: segments,
      status: 'completed',
    );
  }

  // Dataset 2: Rural Ridge Road (Gravel Shoulder, Curves, Containing Pinch Points < 3.5m)
  static SurveySession createRuralSession() {
    const double startLat = 13.0450;
    const double startLon = 77.4820;
    const int count = 90; // 450m

    final List<ChainageBin> bins = [];
    final List<Prediction> predictions = [];
    final List<MapSegmentData> segments = [];

    for (int i = 0; i < count; i++) {
      final double chainage = i * 5.0;
      final double lat = startLat + (i * 0.000035) + (math.sin(i * 0.18) * 0.000012);
      final double lon = startLon + (i * 0.000045) + (math.cos(i * 0.15) * 0.000010);

      // Natural pinch point between bin 35 and 45 (width dips under 3.5m)
      double width = 5.20 + math.sin(i * 0.12) * 0.8;
      if (i >= 35 && i <= 45) {
        width = 3.20 + (math.sin((i - 35) / 10.0 * math.pi) * -0.30); // 2.90m - 3.20m (Pinch point)
      }

      final String edgeL = (i >= 35 && i <= 45) ? 'gravel_transition' : 'vegetation_edge';
      final String edgeR = 'gravel_transition';
      final double mad = (i >= 35 && i <= 45) ? 0.32 : 0.16;
      final int obs = (i >= 35 && i <= 45) ? 6 : 18;

      final bin = ChainageBin(
        chainageM: chainage,
        widthM: width,
        madM: mad,
        n: obs,
        edgeLeft: edgeL,
        edgeRight: edgeR,
        meanRangeM: 10.2,
        occludedFrac: 0.05,
        boundaryEntropy: (i >= 35 && i <= 45) ? 0.58 : 0.28,
        latitude: lat,
        longitude: lon,
      );
      bins.add(bin);

      final pred = RoadPipelineService.predictConfidence(
        widthM: width,
        madM: mad,
        observationCount: obs,
        meanRangeM: 10.2,
        edgeLeft: edgeL,
        edgeRight: edgeR,
        occludedFrac: 0.05,
        boundaryEntropy: (i >= 35 && i <= 45) ? 0.58 : 0.28,
        calibSource: 'vanishing_point',
        crossMethodDisagreement: (i >= 35 && i <= 45) ? 0.14 : 0.06,
      );
      predictions.add(pred);

      segments.add(MapSegmentData(
        id: 'RURAL-BIN-$i',
        position: LatLng(lat, lon),
        chainageM: chainage,
        widthM: width,
        halfWidthM: pred.halfWidthM,
        tier: pred.tier.name,
        edgeLeft: edgeL.toUpperCase(),
        edgeRight: edgeR.toUpperCase(),
        observationCount: obs,
        madM: mad,
        calibSource: 'VANISHING POINT',
        utmEast: 661200.0 + (i * 3.5),
        utmNorth: 1442900.0 + (i * 4.5),
      ));
    }

    return SurveySession(
      id: 'SESSION-RURAL-002',
      title: 'Rural Ridge Link Road (Pinch Points & Curves)',
      mode: SurveyMode.live,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      duration: const Duration(minutes: 14, seconds: 20),
      distanceM: count * 5.0,
      meanWidthM: 4.85,
      highConfidencePct: 68.4,
      bins: bins,
      predictions: predictions,
      mapSegments: segments,
      status: 'completed',
    );
  }

  // Dataset 3: Urban Arterial Corridor (Parked Vehicles, Occlusion Hatching)
  static SurveySession createUrbanSession() {
    const double startLat = 12.9716;
    const double startLon = 77.5946;
    const int count = 75; // 375m

    final List<ChainageBin> bins = [];
    final List<Prediction> predictions = [];
    final List<MapSegmentData> segments = [];

    for (int i = 0; i < count; i++) {
      final double chainage = i * 5.0;
      final double lat = startLat + (i * 0.000030);
      final double lon = startLon + (i * 0.000040);

      // Occlusions between bin 20 and 28 due to parked trucks
      final bool hasOcclusion = (i >= 20 && i <= 28);
      final double width = hasOcclusion ? 6.40 : 7.60 + (math.sin(i * 0.2) * 0.3);
      final double occludedFrac = hasOcclusion ? 0.45 : 0.0;
      final String edgeR = hasOcclusion ? 'occluded' : 'kerb';
      final double mad = hasOcclusion ? 0.40 : 0.10;
      final int obs = hasOcclusion ? 8 : 24;

      final bin = ChainageBin(
        chainageM: chainage,
        widthM: width,
        madM: mad,
        n: obs,
        edgeLeft: 'kerb',
        edgeRight: edgeR,
        meanRangeM: 8.8,
        occludedFrac: occludedFrac,
        boundaryEntropy: hasOcclusion ? 0.72 : 0.15,
        latitude: lat,
        longitude: lon,
      );
      bins.add(bin);

      final pred = RoadPipelineService.predictConfidence(
        widthM: width,
        madM: mad,
        observationCount: obs,
        meanRangeM: 8.8,
        edgeLeft: 'kerb',
        edgeRight: edgeR,
        occludedFrac: occludedFrac,
        boundaryEntropy: hasOcclusion ? 0.72 : 0.15,
        calibSource: 'ar_plane',
        crossMethodDisagreement: hasOcclusion ? 0.18 : 0.03,
      );
      predictions.add(pred);

      segments.add(MapSegmentData(
        id: 'URBAN-BIN-$i',
        position: LatLng(lat, lon),
        chainageM: chainage,
        widthM: width,
        halfWidthM: pred.halfWidthM,
        tier: pred.tier.name,
        edgeLeft: 'KERB',
        edgeRight: edgeR.toUpperCase(),
        observationCount: obs,
        madM: mad,
        calibSource: 'AR PLANE',
        utmEast: 673400.0 + (i * 3.0),
        utmNorth: 1434800.0 + (i * 4.0),
      ));
    }

    return SurveySession(
      id: 'SESSION-URBAN-003',
      title: 'Urban Arterial Drive (Vehicle Occlusions)',
      mode: SurveyMode.upload,
      createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      duration: const Duration(minutes: 11, seconds: 15),
      distanceM: count * 5.0,
      meanWidthM: 7.35,
      highConfidencePct: 82.6,
      bins: bins,
      predictions: predictions,
      mapSegments: segments,
      status: 'pending_review',
    );
  }

  // Active Learning Low-Confidence Review Items
  static List<ActiveLearningItem> createActiveLearningQueue() {
    return [
      ActiveLearningItem(
        id: 'REV-001',
        sessionId: 'SESSION-RURAL-002',
        chainageM: 195.0,
        provisionalWidthM: 3.12,
        halfWidthM: 0.78,
        reason: 'Low edge gradient on gravel transition; sharp road curvature',
        edgeLeft: 'gravel_transition',
        edgeRight: 'vegetation_edge',
      ),
      ActiveLearningItem(
        id: 'REV-002',
        sessionId: 'SESSION-URBAN-003',
        chainageM: 115.0,
        provisionalWidthM: 6.38,
        halfWidthM: 0.84,
        reason: 'Parked delivery truck occluding right kerb (> 45% occlusion)',
        edgeLeft: 'kerb',
        edgeRight: 'occluded',
      ),
      ActiveLearningItem(
        id: 'REV-003',
        sessionId: 'SESSION-RURAL-002',
        chainageM: 210.0,
        provisionalWidthM: 3.05,
        halfWidthM: 0.69,
        reason: 'Pinch point bottleneck: shoulder washed out by monsoon run-off',
        edgeLeft: 'gravel_transition',
        edgeRight: 'gravel_transition',
      ),
      ActiveLearningItem(
        id: 'REV-004',
        sessionId: 'SESSION-URBAN-003',
        chainageM: 130.0,
        provisionalWidthM: 6.42,
        halfWidthM: 0.72,
        reason: 'High boundary entropy (0.74); tree shadow glare over pavement',
        edgeLeft: 'kerb',
        edgeRight: 'occluded',
      ),
    ];
  }
}

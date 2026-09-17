// Safar Unit and Widget Test Suite
// Verifying mathematical IPM projection, Conformal Prediction,
// 5m Chainage Binning, GeoJSON generation, and Application Shell.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/main.dart';
import 'package:safar/models/camera_calibration.dart';
import 'package:safar/models/transect.dart';
import 'package:safar/models/prediction.dart';
import 'package:safar/services/road_pipeline_service.dart';

void main() {
  group('Mathematical Road Pipeline Tests', () {
    const intr = CameraIntrinsics(
      fx: 800.0,
      fy: 800.0,
      cx: 400.0,
      cy: 300.0,
    );

    const ext = CameraExtrinsics(
      heightM: 1.40,
      pitchDeg: 6.0,
      rollDeg: 0.0,
      yawDeg: 0.0,
      source: 'manual',
    );

    test('IPM ground point to pixel and pixel to ground consistency', () {
      // 10 metres forward, road centre
      final pixel = RoadPipelineService.groundToPixel(
        groundX: 0.0,
        groundY: 10.0,
        intr: intr,
        ext: ext,
      );

      expect(pixel, isNotNull);
      final double u = pixel![0];
      final double v = pixel[1];

      // u should be close to cx because X=0
      expect((u - intr.cx).abs(), lessThan(1.0));

      // Inverse projection back to ground
      final ground = RoadPipelineService.pixelToGround(
        u: u,
        v: v,
        intr: intr,
        ext: ext,
      );

      expect(ground, isNotNull);
      expect((ground![0] - 0.0).abs(), lessThan(0.1));
      expect((ground[1] - 10.0).abs(), lessThan(0.1));
    });

    test('IPM horizon check: ray at or above horizon returns null', () {
      // Very top pixel (sky)
      final skyGround = RoadPipelineService.pixelToGround(
        u: 400.0,
        v: 10.0,
        intr: intr,
        ext: ext,
      );

      expect(skyGround, isNull);
    });

    test('Split Conformal Prediction produces calibrated adaptive intervals', () {
      // Clear urban road with high observation count and kerb
      final predHigh = RoadPipelineService.predictConfidence(
        widthM: 7.20,
        madM: 0.08,
        observationCount: 30,
        meanRangeM: 8.5,
        edgeLeft: 'kerb',
        edgeRight: 'kerb',
        occludedFrac: 0.0,
        boundaryEntropy: 0.10,
        calibSource: 'ar_plane',
        crossMethodDisagreement: 0.02,
      );

      expect(predHigh.tier, equals(ConfidenceTier.high));
      expect(predHigh.halfWidthM, lessThanOrEqualTo(0.25));

      // Ambiguous rural edge with gravel transition and low observations
      final predLow = RoadPipelineService.predictConfidence(
        widthM: 3.80,
        madM: 0.45,
        observationCount: 3,
        meanRangeM: 14.5,
        edgeLeft: 'gravel_transition',
        edgeRight: 'vegetation_edge',
        occludedFrac: 0.40,
        boundaryEntropy: 0.75,
        calibSource: 'unknown',
        crossMethodDisagreement: 0.22,
      );

      expect(predLow.tier, equals(ConfidenceTier.low));
      expect(predLow.halfWidthM, greaterThan(0.60));
    });

    test('Robust 5m Chainage Binning uses Median + MAD, not Mean', () {
      // Simulate 5 transects with one extreme parked truck outlier (e.g. 15.0m)
      final transects = [
        const Transect(chainageM: 10.0, centreX: 0, centreY: 10, widthM: 7.20, edgeLeft: 'kerb', edgeRight: 'painted'),
        const Transect(chainageM: 11.0, centreX: 0, centreY: 11, widthM: 7.25, edgeLeft: 'kerb', edgeRight: 'painted'),
        const Transect(chainageM: 12.0, centreX: 0, centreY: 12, widthM: 7.18, edgeLeft: 'kerb', edgeRight: 'painted'),
        const Transect(chainageM: 13.0, centreX: 0, centreY: 13, widthM: 7.22, edgeLeft: 'kerb', edgeRight: 'painted'),
        const Transect(chainageM: 14.0, centreX: 0, centreY: 14, widthM: 15.0, edgeLeft: 'occluded', edgeRight: 'kerb'), // Outlier
      ];

      final bin = RoadPipelineService.aggregateTransects(
        chainageM: 10.0,
        transects: transects,
        latitude: 12.9716,
        longitude: 77.5946,
      );

      // Median should remain around 7.21m, completely rejecting the 15.0m outlier
      expect((bin.widthM - 7.21).abs(), lessThan(0.05));
      expect(bin.edgeLeft, equals('kerb'));
    });

    test('GeoJSON Exporter generates valid EPSG:4326 GeoJSON structure', () {
      final bin = ChainageBin(
        chainageM: 50.0,
        widthM: 7.24,
        madM: 0.11,
        n: 28,
        edgeLeft: 'kerb',
        edgeRight: 'painted',
        meanRangeM: 9.4,
        occludedFrac: 0.0,
        boundaryEntropy: 0.12,
        latitude: 12.9716,
        longitude: 77.5946,
      );

      final pred = RoadPipelineService.predictConfidence(
        widthM: 7.24,
        madM: 0.11,
        observationCount: 28,
        meanRangeM: 9.4,
        edgeLeft: 'kerb',
        edgeRight: 'painted',
        occludedFrac: 0.0,
        boundaryEntropy: 0.12,
        calibSource: 'ar_plane',
      );

      final geoJsonStr = RoadPipelineService.exportGeoJson([bin], [pred]);
      final parsed = jsonDecode(geoJsonStr) as Map<String, dynamic>;

      expect(parsed['type'], equals('FeatureCollection'));
      expect(parsed['features'], hasLength(1));
      final feature = (parsed['features'] as List).first as Map<String, dynamic>;
      expect(feature['properties']['width_m'], equals(7.24));
      expect(feature['properties']['fire_tender_passable'], isTrue);
    });
  });

  group('Safar UI Widget Smoke Tests', () {
    testWidgets('SafarApp mounts and renders bottom navigation with destinations', (WidgetTester tester) async {
      await tester.pumpWidget(const SafarApp());
      await tester.pumpAndSettle();

      // Verify navigation labels are rendered
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('MEASURE'), findsOneWidget);
      expect(find.text('MAP'), findsOneWidget);
      expect(find.text('CLOUD'), findsOneWidget);
      expect(find.text('DATA'), findsOneWidget);
    });
  });
}

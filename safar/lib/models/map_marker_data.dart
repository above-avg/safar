// Map Segment and Accessibility Data Models
// Corresponding to Section 15 of System Plan (P02)
// Emergency Vehicle Accessibility Index & Zoomable GPS Map Points

import 'package:latlong2/latlong.dart';

enum AccessibilityStatus {
  passable,
  caution,
  pinchPointImpassable,
}

class MapSegmentData {
  final String id;
  final LatLng position;
  final double chainageM;
  final double widthM;
  final double halfWidthM;
  final String tier; // HIGH | MEDIUM | LOW
  final String edgeLeft;
  final String edgeRight;
  final int observationCount;
  final double madM;
  final String calibSource;
  final double utmEast;
  final double utmNorth;

  const MapSegmentData({
    required this.id,
    required this.position,
    required this.chainageM,
    required this.widthM,
    required this.halfWidthM,
    required this.tier,
    required this.edgeLeft,
    required this.edgeRight,
    required this.observationCount,
    required this.madM,
    required this.calibSource,
    required this.utmEast,
    required this.utmNorth,
  });

  // Emergency Vehicle Accessibility (Fire tender needs ~3.5m - 4.0m, Ambulance ~3.0m)
  AccessibilityStatus get fireTenderStatus {
    if (widthM < 3.5) return AccessibilityStatus.pinchPointImpassable;
    if (widthM < 4.0) return AccessibilityStatus.caution;
    return AccessibilityStatus.passable;
  }

  AccessibilityStatus get ambulanceStatus {
    if (widthM < 3.0) return AccessibilityStatus.pinchPointImpassable;
    if (widthM < 3.5) return AccessibilityStatus.caution;
    return AccessibilityStatus.passable;
  }

  String get fireTenderStatusLabel {
    switch (fireTenderStatus) {
      case AccessibilityStatus.pinchPointImpassable:
        return 'BLOCKED (< 3.5 m)';
      case AccessibilityStatus.caution:
        return 'TIGHT (3.5 - 4.0 m)';
      case AccessibilityStatus.passable:
        return 'CLEAR (> 4.0 m)';
    }
  }

  String get ambulanceStatusLabel {
    switch (ambulanceStatus) {
      case AccessibilityStatus.pinchPointImpassable:
        return 'BLOCKED (< 3.0 m)';
      case AccessibilityStatus.caution:
        return 'TIGHT (3.0 - 3.5 m)';
      case AccessibilityStatus.passable:
        return 'CLEAR (> 3.5 m)';
    }
  }
}

// Interactive GPS Map Screen
// Visualises surveyed corridors, road width heatmaps, pinch points,
// and measurement data on a zoomable, pannable map.

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../theme/safar_tokens.dart';
import '../models/survey_session.dart';
import '../models/map_marker_data.dart';
import '../services/mock_survey_data.dart';
import '../widgets/interactive_road_map.dart';

class InteractiveMapScreen extends StatefulWidget {
  const InteractiveMapScreen({super.key});

  @override
  State<InteractiveMapScreen> createState() => _InteractiveMapScreenState();
}

class _InteractiveMapScreenState extends State<InteractiveMapScreen> {
  late final List<SurveySession> _sessions;
  int _selectedSessionIndex = 1; // Default to Rural Ridge to demonstrate pinch points
  MapSegmentData? _activeSegment;

  @override
  void initState() {
    super.initState();
    _sessions = [
      MockSurveyData.createHighwaySession(),
      MockSurveyData.createRuralSession(),
      MockSurveyData.createUrbanSession(),
    ];
    if (_sessions[_selectedSessionIndex].mapSegments.isNotEmpty) {
      _activeSegment = _sessions[_selectedSessionIndex].mapSegments.first;
    }
  }

  void _showMapGuideDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SafarTokens.asphalt950,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SafarTokens.rMd),
            side: const BorderSide(color: SafarTokens.asphalt700, width: 1.0),
          ),
          title: Text(
            'GPS CORRIDOR MAP GUIDE',
            style: SafarTokens.fontUi(
              fontSize: 14.0,
              fontWeight: FontWeight.w800,
              color: SafarTokens.hivis,
              letterSpacing: 0.08,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ABOUT THIS MAP',
                  style: SafarTokens.microLabel(color: SafarTokens.hivis),
                ),
                const SizedBox(height: 6),
                Text(
                  'Visualizes surveyed road corridors on 100% free OpenStreetMap vector/raster tiles. Shows road width variations, confidence intervals, and critical accessibility pinch points.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'GESTURES & CONTROLS:',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 6),
                Text(
                  '- Pinch to zoom in/out anywhere on the map.\n'
                  '- Drag with one finger to pan along the road.\n'
                  '- Tap any path segment or red "!" pin to view width, confidence interval, and clearance.\n'
                  '- Tap the crosshair button (right side) to locate your physical GPS position.\n'
                  '- Tap the fit button (crop icon) to zoom out to the entire corridor.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'PINCH POINTS (< 3.5 m):',
                  style: SafarTokens.microLabel(color: SafarTokens.confLow),
                ),
                const SizedBox(height: 6),
                Text(
                  'Red segments and "!" pins flag locations where traversable width is under 3.5 metres, which blocks standard fire engines and emergency response vehicles.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.4),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'GOT IT',
                style: SafarTokens.fontMono(
                  fontSize: 12.0,
                  fontWeight: FontWeight.w700,
                  color: SafarTokens.hivis,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = _sessions[_selectedSessionIndex];
    final int pinchPointCount = currentSession.mapSegments.where((s) => s.widthM < 3.5).length;
    final double passPct = ((currentSession.mapSegments.length - pinchPointCount) /
            (currentSession.mapSegments.isEmpty ? 1 : currentSession.mapSegments.length) *
            100.0);

    return Scaffold(
      backgroundColor: SafarTokens.asphalt900,
      appBar: AppBar(
        title: Text(
          'GPS CORRIDOR MAP',
          style: SafarTokens.fontUi(
            fontSize: 14.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.08,
            color: SafarTokens.concrete50,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: SafarTokens.concrete100),
            tooltip: 'GPS Map Guide',
            onPressed: _showMapGuideDialog,
          ),
          // Compact Corridor selector
          PopupMenuButton<int>(
            tooltip: 'Select Corridor',
            color: SafarTokens.asphalt800,
            onSelected: (val) {
              setState(() {
                _selectedSessionIndex = val;
                _activeSegment = _sessions[val].mapSegments.isNotEmpty
                    ? _sessions[val].mapSegments.first
                    : null;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 0,
                child: Text('NH-48 HIGHWAY', style: SafarTokens.fontMono(fontSize: 11.5, color: SafarTokens.paint)),
              ),
              PopupMenuItem(
                value: 1,
                child: Text('RURAL RIDGE (PINCH POINTS)', style: SafarTokens.fontMono(fontSize: 11.5, color: SafarTokens.paint)),
              ),
              PopupMenuItem(
                value: 2,
                child: Text('URBAN ARTERIAL', style: SafarTokens.fontMono(fontSize: 11.5, color: SafarTokens.paint)),
              ),
            ],
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: SafarTokens.asphalt800,
                borderRadius: BorderRadius.circular(SafarTokens.rSm),
                border: Border.all(color: SafarTokens.asphalt700, width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.alt_route, color: SafarTokens.hivis, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    _selectedSessionIndex == 0
                        ? 'NH-48'
                        : (_selectedSessionIndex == 1 ? 'RURAL' : 'URBAN'),
                    style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis, fontWeight: FontWeight.w700),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: SafarTokens.hivis, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Regional Mapping Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            color: SafarTokens.asphalt950,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildMetricSnippet('MAPPED EXTENT', '${(currentSession.distanceM / 1000.0).toStringAsFixed(2)} km'),
                  const SizedBox(width: 20),
                  _buildMetricSnippet('MEAN WIDTH', '${currentSession.meanWidthM.toStringAsFixed(2)} m'),
                  const SizedBox(width: 20),
                  _buildMetricSnippet(
                    'FIRE ACCESS',
                    '${passPct.toStringAsFixed(1)}%',
                    valueColor: passPct > 85.0 ? SafarTokens.confHigh : SafarTokens.confLow,
                  ),
                  const SizedBox(width: 20),
                  _buildMetricSnippet(
                    'PINCH POINTS',
                    '$pinchPointCount CRITICAL',
                    valueColor: pinchPointCount > 0 ? SafarTokens.confLow : SafarTokens.confHigh,
                  ),
                  const SizedBox(width: 20),
                  _buildMetricSnippet(
                    'ACTIVE PIN',
                    _activeSegment != null
                        ? 'CH ${_activeSegment!.chainageM.toStringAsFixed(0)} m (${_activeSegment!.widthM.toStringAsFixed(2)} m)'
                        : 'NONE',
                    valueColor: SafarTokens.paint,
                  ),
                  const SizedBox(width: 20),
                  _buildMetricSnippet('WORKING CRS', 'AUTO-UTM (43N)'),
                ],
              ),
            ),
          ),

          // Zoomable & Pannable Road Map
          Expanded(
            child: InteractiveRoadMap(
              segments: currentSession.mapSegments,
              initialCenter: currentSession.mapSegments.isNotEmpty
                  ? currentSession.mapSegments.first.position
                  : const LatLng(13.0450, 77.4820),
              initialZoom: 15.8,
              onSegmentSelected: (seg) {
                setState(() => _activeSegment = seg);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricSnippet(String title, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
        const SizedBox(height: 2),
        Text(
          value,
          style: SafarTokens.fontMono(
            fontSize: 12.0,
            fontWeight: FontWeight.w700,
            color: valueColor ?? SafarTokens.hivis,
          ),
        ),
      ],
    );
  }
}

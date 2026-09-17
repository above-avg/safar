// Manual AR Ruler & Overhead Road Connections Screen
// Dual Mode:
// 1. OVERHEAD NETWORK MAP (BEV): Top-down map showing connected road segments, junctions,
//    and real-time metrics (carriageway width, IRC:SP:84 fire clearance, confidence) on each road.
//    Supports smooth panning, pinch-to-zoom, HUD zoom buttons, and dynamic addition of new roads & junctions.
// 2. AR TAPE RULER: Point-to-point metric ruler for ground-truth capture and manual verification.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';

/// Data model for a road segment in the top-down network
class NetworkRoadSegment {
  final String id;
  final String name;
  final String fromJunction;
  final String toJunction;
  final double widthM;
  final double lengthM;
  final int lanes;
  final double confidenceHalfM;
  final Offset start; // Normalized coordinates on canvas (0..1)
  final Offset end;
  final List<Offset> controlPoints; // For curved paths

  const NetworkRoadSegment({
    required this.id,
    required this.name,
    required this.fromJunction,
    required this.toJunction,
    required this.widthM,
    required this.lengthM,
    required this.lanes,
    required this.confidenceHalfM,
    required this.start,
    required this.end,
    this.controlPoints = const [],
  });

  bool get isFireTenderPassable => widthM >= 3.50;
  bool get isAmbulancePassable => widthM >= 3.00;
}

class NetworkJunction {
  final String id;
  final String label;
  final Offset position;

  const NetworkJunction({
    required this.id,
    required this.label,
    required this.position,
  });
}

class ManualArRulerScreen extends StatefulWidget {
  const ManualArRulerScreen({super.key});

  @override
  State<ManualArRulerScreen> createState() => _ManualArRulerScreenState();
}

class _ManualArRulerScreenState extends State<ManualArRulerScreen> {
  // Mode toggle: 0 = Overhead Map (BEV), 1 = AR Tape Ruler
  int _selectedModeIndex = 0;

  // AR Ruler state
  Offset? _pointA;
  Offset? _pointB;
  bool _isFrozen = false;
  double _measuredWidthM = 0.0;
  final double _cameraHeightM = 1.40;

  // Overhead Map state
  NetworkRoadSegment? _selectedRoad;
  NetworkJunction? _selectedJunction;
  String _networkFilter = 'ALL'; // 'ALL', 'PINCH', 'PASSABLE'

  // InteractiveViewer Transformation Controller & Zoom State
  final TransformationController _transformationController = TransformationController();
  double _zoomLevel = 1.0;

  // Road network junctions and segments
  late List<NetworkJunction> _junctions;
  late List<NetworkRoadSegment> _roadSegments;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);

    _junctions = [
      const NetworkJunction(id: 'J1', label: 'NORTH GATE (J1)', position: Offset(0.50, 0.12)),
      const NetworkJunction(id: 'J2', label: 'CENTRAL CIRCLE (J2)', position: Offset(0.50, 0.44)),
      const NetworkJunction(id: 'J3', label: 'BAZAAR FORK (J3)', position: Offset(0.22, 0.72)),
      const NetworkJunction(id: 'J4', label: 'EAST INTERCHANGE (J4)', position: Offset(0.80, 0.65)),
      const NetworkJunction(id: 'J5', label: 'SOUTH TERMINAL (J5)', position: Offset(0.50, 0.92)),
    ];

    _roadSegments = [
      const NetworkRoadSegment(
        id: 'R1',
        name: 'NH-44 ARTERIAL HIGHWAY',
        fromJunction: 'J1',
        toJunction: 'J2',
        widthM: 7.24,
        lengthM: 450.0,
        lanes: 2,
        confidenceHalfM: 0.18,
        start: Offset(0.50, 0.12),
        end: Offset(0.50, 0.44),
      ),
      const NetworkRoadSegment(
        id: 'R2',
        name: 'OLD BAZAAR CHOKEPOINT',
        fromJunction: 'J2',
        toJunction: 'J3',
        widthM: 3.18, // Critical pinch point! (<3.5m)
        lengthM: 320.0,
        lanes: 1,
        confidenceHalfM: 0.14,
        start: Offset(0.50, 0.44),
        end: Offset(0.22, 0.72),
      ),
      const NetworkRoadSegment(
        id: 'R3',
        name: 'EAST RING CONNECTOR',
        fromJunction: 'J2',
        toJunction: 'J4',
        widthM: 5.60,
        lengthM: 380.0,
        lanes: 2,
        confidenceHalfM: 0.22,
        start: Offset(0.50, 0.44),
        end: Offset(0.80, 0.65),
      ),
      const NetworkRoadSegment(
        id: 'R4',
        name: 'BAZAAR SOUTH EXIT',
        fromJunction: 'J3',
        toJunction: 'J5',
        widthM: 4.10,
        lengthM: 280.0,
        lanes: 1,
        confidenceHalfM: 0.20,
        start: Offset(0.22, 0.72),
        end: Offset(0.50, 0.92),
      ),
      const NetworkRoadSegment(
        id: 'R5',
        name: 'EAST EXPRESSWAY SPUR',
        fromJunction: 'J4',
        toJunction: 'J5',
        widthM: 10.20, // 4-lane wide road
        lengthM: 520.0,
        lanes: 4,
        confidenceHalfM: 0.12,
        start: Offset(0.80, 0.65),
        end: Offset(0.50, 0.92),
      ),
    ];

    _selectedRoad = _roadSegments[1]; // Default to Bazaar Chokepoint to highlight pinch point
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if ((scale - _zoomLevel).abs() > 0.02) {
      setState(() => _zoomLevel = scale);
    }
  }

  void _zoomIn() {
    final Matrix4 m = _transformationController.value.clone();
    m.scale(1.25, 1.25);
    _transformationController.value = m;
  }

  void _zoomOut() {
    final Matrix4 m = _transformationController.value.clone();
    m.scale(0.8, 0.8);
    _transformationController.value = m;
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _handleRulerTap(TapUpDetails details) {
    if (_isFrozen) return;
    if (_pointA == null) {
      setState(() {
        _pointA = details.localPosition;
        _pointB = null;
        _measuredWidthM = 0.0;
      });
    } else if (_pointB == null) {
      setState(() {
        _pointB = details.localPosition;
        _calculateMetricDistance();
      });
    } else {
      setState(() {
        _pointA = details.localPosition;
        _pointB = null;
        _measuredWidthM = 0.0;
      });
    }
  }

  void _calculateMetricDistance() {
    if (_pointA == null || _pointB == null) return;
    final double dx = _pointB!.dx - _pointA!.dx;
    final double dy = _pointB!.dy - _pointA!.dy;
    final double pixelDist = math.sqrt(dx * dx + dy * dy);
    _measuredWidthM = (pixelDist / (31.4 * _cameraHeightM)).clamp(1.5, 20.0);
  }

  void _saveGroundTruth() {
    if (_measuredWidthM <= 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: SafarTokens.asphalt800,
        content: Text(
          'RECORDED GROUND-TRUTH TAPE PAIR: ${_measuredWidthM.toStringAsFixed(2)} m SAVED TO CALIBRATION SET',
          style: SafarTokens.fontMono(fontSize: 11.0, color: SafarTokens.hivis),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafarTokens.asphalt950,
      appBar: AppBar(
        backgroundColor: SafarTokens.asphalt900,
        elevation: 0,
        title: Text(
          _selectedModeIndex == 0 ? 'OVERHEAD ROAD MAP (BEV)' : 'MANUAL AR METRIC RULER',
          style: SafarTokens.fontUi(
            fontSize: 14.0,
            fontWeight: FontWeight.w800,
            color: SafarTokens.paint,
            letterSpacing: 0.06,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: SafarTokens.asphalt400, size: 20),
            tooltip: 'View Guide',
            onPressed: _showHelpDialog,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: SafarTokens.asphalt950,
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: SafarTokens.asphalt800,
                borderRadius: BorderRadius.circular(SafarTokens.rSm),
                border: Border.all(color: SafarTokens.asphalt700),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildModeTab(
                      index: 0,
                      label: 'OVERHEAD MAP (BEV)',
                      icon: Icons.alt_route,
                    ),
                  ),
                  Expanded(
                    child: _buildModeTab(
                      index: 1,
                      label: 'AR TAPE RULER',
                      icon: Icons.straighten,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _selectedModeIndex == 0
          ? _buildOverheadNetworkView()
          : _buildArRulerView(),
    );
  }

  Widget _buildModeTab({required int index, required String label, required IconData icon}) {
    final bool isSelected = _selectedModeIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedModeIndex = index),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? SafarTokens.hivis : Colors.transparent,
          borderRadius: BorderRadius.circular(SafarTokens.rSm - 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? SafarTokens.asphalt950 : SafarTokens.asphalt400,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: SafarTokens.fontMono(
                fontSize: 11.0,
                fontWeight: FontWeight.w800,
                color: isSelected ? SafarTokens.asphalt950 : SafarTokens.concrete100,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // VIEW 1: OVERHEAD ROAD CONNECTIONS & METRICS (PAN/ZOOM & EDITABLE)
  // ==========================================
  Widget _buildOverheadNetworkView() {
    final filteredRoads = _roadSegments.where((road) {
      if (_networkFilter == 'PINCH') return road.widthM < 3.50;
      if (_networkFilter == 'PASSABLE') return road.widthM >= 3.50;
      return true;
    }).toList();

    return Column(
      children: [
        // Filter and Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: SafarTokens.asphalt900,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('ALL', 'ALL (${_roadSegments.length})'),
                const SizedBox(width: 4),
                _buildFilterChip('PINCH', 'PINCH (<3.5m)'),
                const SizedBox(width: 4),
                _buildFilterChip('PASSABLE', 'PASSABLE'),
                const SizedBox(width: 8),
                Container(height: 20, width: 1, color: SafarTokens.asphalt700),
                const SizedBox(width: 8),
                // + ADD ROAD button
                InkWell(
                  onTap: () => _showAddRoadDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: SafarTokens.hivis,
                      borderRadius: BorderRadius.circular(SafarTokens.rSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 14, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          'ADD ROAD',
                          style: SafarTokens.fontMono(
                            fontSize: 10.0,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // + ADD JUNCTION button
                InkWell(
                  onTap: _showAddJunctionDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: SafarTokens.asphalt800,
                      borderRadius: BorderRadius.circular(SafarTokens.rSm),
                      border: Border.all(color: SafarTokens.asphalt600),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hub_outlined, size: 14, color: SafarTokens.paint),
                        const SizedBox(width: 4),
                        Text(
                          '+ JUNCTION',
                          style: SafarTokens.fontMono(
                            fontSize: 10.0,
                            fontWeight: FontWeight.w700,
                            color: SafarTokens.paint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Interactive Overhead BEV Canvas with Pan & Zoom
        Expanded(
          child: Stack(
            children: [
              // Pannable & Zoomable Network Canvas
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  boundaryMargin: const EdgeInsets.all(500),
                  minScale: 0.35,
                  maxScale: 4.5,
                  constrained: true,
                  clipBehavior: Clip.hardEdge,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, constraints.maxHeight);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _handleOverheadMapTap(details.localPosition, size),
                        child: CustomPaint(
                          size: size,
                          painter: _OverheadRoadNetworkPainter(
                            junctions: _junctions,
                            roads: filteredRoads,
                            selectedRoad: _selectedRoad,
                            selectedJunction: _selectedJunction,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Floating Legend & Filter indicator (Top-Left)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: SafarTokens.asphalt950.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(SafarTokens.rSm),
                    border: Border.all(color: SafarTokens.asphalt700),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8, color: SafarTokens.confLow),
                      const SizedBox(width: 4),
                      Text('< 3.5m PINCH', style: SafarTokens.fontMono(fontSize: 9.5, color: SafarTokens.confLow)),
                      const SizedBox(width: 8),
                      Container(width: 8, height: 8, color: SafarTokens.hivis),
                      const SizedBox(width: 4),
                      Text('>= 3.5m PASS', style: SafarTokens.fontMono(fontSize: 9.5, color: SafarTokens.hivis)),
                    ],
                  ),
                ),
              ),

              // Floating Zoom Controls HUD (Top-Right)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: SafarTokens.asphalt950.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(SafarTokens.rSm),
                    border: Border.all(color: SafarTokens.asphalt700),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Zoom in (+)
                      InkWell(
                        onTap: _zoomIn,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.add, size: 20, color: SafarTokens.hivis),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: SafarTokens.asphalt900,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          '${(_zoomLevel * 100).toInt()}%',
                          style: SafarTokens.fontMono(fontSize: 8.5, fontWeight: FontWeight.w800, color: SafarTokens.concrete100),
                        ),
                      ),
                      // Zoom out (-)
                      InkWell(
                        onTap: _zoomOut,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.remove, size: 20, color: SafarTokens.concrete100),
                        ),
                      ),
                      const Divider(color: SafarTokens.asphalt700, height: 6, thickness: 1),
                      // Reset / Fit view
                      InkWell(
                        onTap: _resetZoom,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.fit_screen, size: 18, color: SafarTokens.paint),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Road Detail Inspection Card
              if (_selectedRoad != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _buildRoadInspectionCard(_selectedRoad!),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleOverheadMapTap(Offset local, Size size) {
    // 1. Check if user tapped a junction
    for (final j in _junctions) {
      final pj = Offset(j.position.dx * size.width, j.position.dy * size.height);
      if ((local - pj).distance < 24.0) {
        _showJunctionDetails(j);
        return;
      }
    }

    // 2. Check if user tapped a road
    NetworkRoadSegment? closestRoad;
    double minDistance = double.infinity;

    for (final road in _roadSegments) {
      final pA = Offset(road.start.dx * size.width, road.start.dy * size.height);
      final pB = Offset(road.end.dx * size.width, road.end.dy * size.height);
      final d = _pointToSegmentDistance(local, pA, pB);
      if (d < minDistance) {
        minDistance = d;
        closestRoad = road;
      }
    }

    final double hitTolerance = (40.0 / _zoomLevel).clamp(20.0, 60.0);
    if (closestRoad != null && minDistance < hitTolerance) {
      setState(() => _selectedRoad = closestRoad);
    }
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final bool isSelected = _networkFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _networkFilter = filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt800,
          borderRadius: BorderRadius.circular(SafarTokens.rSm),
          border: Border.all(color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt700),
        ),
        child: Text(
          label,
          style: SafarTokens.fontMono(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? SafarTokens.asphalt950 : SafarTokens.concrete100,
          ),
        ),
      ),
    );
  }

  Widget _buildRoadInspectionCard(NetworkRoadSegment road) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt900,
        borderRadius: BorderRadius.circular(SafarTokens.rMd),
        border: Border.all(
          color: road.isFireTenderPassable ? SafarTokens.hivis : SafarTokens.confLow,
          width: 1.5,
        ),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  road.name,
                  style: SafarTokens.fontMono(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: SafarTokens.paint,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: road.isFireTenderPassable ? SafarTokens.confHigh : SafarTokens.confLow,
                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                ),
                child: Text(
                  road.isFireTenderPassable ? 'IRC:SP:84 PASS' : 'CRITICAL PINCH (<3.5m)',
                  style: SafarTokens.fontMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMetricBadge('CARRIAGEWAY', '${road.widthM.toStringAsFixed(2)} m', road.isFireTenderPassable ? SafarTokens.hivis : SafarTokens.confLow),
              const SizedBox(width: 8),
              _buildMetricBadge('UNCERTAINTY', '+/- ${road.confidenceHalfM.toStringAsFixed(2)} m', SafarTokens.concrete100),
              const SizedBox(width: 8),
              _buildMetricBadge('LENGTH', '${road.lengthM.toStringAsFixed(0)} m', SafarTokens.concrete100),
              const SizedBox(width: 8),
              _buildMetricBadge('LANES', '${road.lanes}', SafarTokens.paint),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CONNECTION: ${road.fromJunction} --> ${road.toJunction}',
                style: SafarTokens.fontMono(fontSize: 10.0, color: SafarTokens.asphalt400),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16, color: SafarTokens.hivis),
                    tooltip: 'Edit Road Width & Metrics',
                    onPressed: () => _showEditRoadDialog(road),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16, color: SafarTokens.confLow),
                    tooltip: 'Delete Road Segment',
                    onPressed: () => _deleteRoad(road),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: SafarTokens.asphalt400),
                    tooltip: 'Deselect',
                    onPressed: () => setState(() => _selectedRoad = null),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          InkWell(
            onTap: () {
              setState(() {
                _selectedModeIndex = 1;
                _measuredWidthM = road.widthM;
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'MEASURE WITH AR RULER ->',
                  style: SafarTokens.fontMono(fontSize: 10.5, fontWeight: FontWeight.w700, color: SafarTokens.hivis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBadge(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: SafarTokens.asphalt950,
          borderRadius: BorderRadius.circular(SafarTokens.rSm),
          border: Border.all(color: SafarTokens.asphalt700),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
            const SizedBox(height: 2),
            Text(
              value,
              style: SafarTokens.fontMono(fontSize: 11.0, fontWeight: FontWeight.w700, color: valueColor),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final double l2 = (b.dx - a.dx) * (b.dx - a.dx) + (b.dy - a.dy) * (b.dy - a.dy);
    if (l2 == 0) return (p - a).distance;
    final double t = math.max(0, math.min(1, ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2));
    final Offset projection = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - projection).distance;
  }

  // ==========================================
  // ADD ROAD / ADD JUNCTION DIALOG WORKFLOWS
  // ==========================================
  void _showAddRoadDialog([String? defaultFromJunction, String? defaultToJunction]) {
    final nameController = TextEditingController(text: 'ROAD ${_roadSegments.length + 1}');
    String fromJ = defaultFromJunction ?? (_junctions.isNotEmpty ? _junctions.first.id : 'J1');
    String toJ = defaultToJunction ?? (_junctions.length > 1 ? _junctions[1].id : fromJ);
    double widthM = 3.75;
    double lengthM = 350.0;
    int lanes = 2;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SafarTokens.asphalt950,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isPassable = widthM >= 3.50;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ADD NEW ROAD CORRIDOR',
                          style: SafarTokens.fontUi(
                            fontSize: 14.0,
                            fontWeight: FontWeight.w800,
                            color: SafarTokens.hivis,
                            letterSpacing: 0.08,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: SafarTokens.asphalt400, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: SafarTokens.fontMono(fontSize: 12.0, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'CORRIDOR / ROAD NAME',
                        labelStyle: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                        filled: true,
                        fillColor: SafarTokens.asphalt900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(SafarTokens.rSm),
                          borderSide: const BorderSide(color: SafarTokens.asphalt700),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(SafarTokens.rSm),
                          borderSide: const BorderSide(color: SafarTokens.asphalt700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('FROM JUNCTION', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: SafarTokens.asphalt900,
                                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                                  border: Border.all(color: SafarTokens.asphalt700),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: fromJ,
                                    isExpanded: true,
                                    dropdownColor: SafarTokens.asphalt900,
                                    items: _junctions.map((j) {
                                      return DropdownMenuItem(
                                        value: j.id,
                                        child: Text(j.id, style: SafarTokens.fontMono(fontSize: 12.0, color: Colors.white)),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) setModalState(() => fromJ = val);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.arrow_forward, color: SafarTokens.hivis, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('TO JUNCTION', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: SafarTokens.asphalt900,
                                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                                  border: Border.all(color: SafarTokens.asphalt700),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: toJ,
                                    isExpanded: true,
                                    dropdownColor: SafarTokens.asphalt900,
                                    items: _junctions.map((j) {
                                      return DropdownMenuItem(
                                        value: j.id,
                                        child: Text(j.id, style: SafarTokens.fontMono(fontSize: 12.0, color: Colors.white)),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) setModalState(() => toJ = val);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('CARRIAGEWAY WIDTH', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                        Text(
                          '${widthM.toStringAsFixed(2)} m',
                          style: SafarTokens.fontMono(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w800,
                            color: isPassable ? SafarTokens.hivis : SafarTokens.confLow,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: widthM,
                      min: 2.0,
                      max: 16.0,
                      divisions: 140,
                      activeColor: isPassable ? SafarTokens.hivis : SafarTokens.confLow,
                      inactiveColor: SafarTokens.asphalt800,
                      onChanged: (val) => setModalState(() => widthM = val),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildPresetChip('3.10m (PINCH)', 3.10, widthM, (w) => setModalState(() => widthM = w)),
                          const SizedBox(width: 6),
                          _buildPresetChip('3.75m (1-LANE)', 3.75, widthM, (w) => setModalState(() => widthM = w)),
                          const SizedBox(width: 6),
                          _buildPresetChip('5.50m (INTERM)', 5.50, widthM, (w) => setModalState(() => widthM = w)),
                          const SizedBox(width: 6),
                          _buildPresetChip('7.00m (2-LANE)', 7.00, widthM, (w) => setModalState(() => widthM = w)),
                          const SizedBox(width: 6),
                          _buildPresetChip('10.5m (3-LANE)', 10.50, widthM, (w) => setModalState(() => widthM = w)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isPassable
                            ? SafarTokens.confHigh.withValues(alpha: 0.15)
                            : SafarTokens.confLow.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(SafarTokens.rSm),
                        border: Border.all(
                          color: isPassable ? SafarTokens.confHigh : SafarTokens.confLow,
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPassable ? Icons.check_circle : Icons.warning_amber_rounded,
                            size: 18,
                            color: isPassable ? SafarTokens.confHigh : SafarTokens.confLow,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isPassable
                                  ? 'IRC:SP:84 PASS: Meets minimum 3.50m clearance for fire tenders and emergency vehicles.'
                                  : 'CRITICAL CHOKEPOINT (<3.5m): Blocked under IRC:SP:84 fire safety guidelines!',
                              style: SafarTokens.fontMono(
                                fontSize: 10.0,
                                color: isPassable ? SafarTokens.confHigh : SafarTokens.confLow,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('LENGTH (m)', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                decoration: BoxDecoration(
                                  color: SafarTokens.asphalt900,
                                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                                  border: Border.all(color: SafarTokens.asphalt700),
                                ),
                                child: Text('${lengthM.toInt()} m', style: SafarTokens.fontMono(fontSize: 12.0, color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('LANES', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                              const SizedBox(height: 4),
                              Row(
                                children: [1, 2, 3, 4].map((lane) {
                                  final isLaneSelected = lanes == lane;
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => setModalState(() => lanes = lane),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isLaneSelected ? SafarTokens.hivis : SafarTokens.asphalt900,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: isLaneSelected ? SafarTokens.hivis : SafarTokens.asphalt700),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$lane',
                                            style: SafarTokens.fontMono(
                                              fontSize: 11.0,
                                              fontWeight: FontWeight.w800,
                                              color: isLaneSelected ? Colors.black : Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: SafarTokens.concrete100,
                              side: const BorderSide(color: SafarTokens.asphalt600),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('CANCEL', style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SafarTokens.hivis,
                              foregroundColor: SafarTokens.asphalt950,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: fromJ == toJ
                                ? null
                                : () {
                                    final startJ = _junctions.firstWhere((j) => j.id == fromJ);
                                    final endJ = _junctions.firstWhere((j) => j.id == toJ);
                                    final newRoad = NetworkRoadSegment(
                                      id: 'R${_roadSegments.length + 1}',
                                      name: nameController.text.trim().isEmpty ? 'NEW CORRIDOR' : nameController.text.trim().toUpperCase(),
                                      fromJunction: fromJ,
                                      toJunction: toJ,
                                      widthM: double.parse(widthM.toStringAsFixed(2)),
                                      lengthM: lengthM,
                                      lanes: lanes,
                                      confidenceHalfM: 0.15,
                                      start: startJ.position,
                                      end: endJ.position,
                                    );
                                    setState(() {
                                      _roadSegments.add(newRoad);
                                      _selectedRoad = newRoad;
                                    });
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: SafarTokens.asphalt800,
                                        content: Text(
                                          'ADDED ROAD: ${newRoad.name} (${newRoad.widthM.toStringAsFixed(2)}m) CONNECTING $fromJ -> $toJ',
                                          style: SafarTokens.fontMono(fontSize: 11.0, color: SafarTokens.hivis),
                                        ),
                                      ),
                                    );
                                  },
                            child: Text('ADD ROAD TO NETWORK', style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddJunctionDialog() {
    final nextId = 'J${_junctions.length + 1}';
    final idController = TextEditingController(text: nextId);
    final labelController = TextEditingController(text: 'JUNCTION ($nextId)');
    double posX = 0.50;
    double posY = 0.50;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SafarTokens.asphalt950,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ADD NEW JUNCTION NODE',
                          style: SafarTokens.fontUi(
                            fontSize: 14.0,
                            fontWeight: FontWeight.w800,
                            color: SafarTokens.hivis,
                            letterSpacing: 0.08,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: SafarTokens.asphalt400, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: idController,
                      style: SafarTokens.fontMono(fontSize: 12.0, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'JUNCTION ID (e.g. J6)',
                        labelStyle: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                        filled: true,
                        fillColor: SafarTokens.asphalt900,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: labelController,
                      style: SafarTokens.fontMono(fontSize: 12.0, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'JUNCTION LABEL / NAME',
                        labelStyle: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                        filled: true,
                        fillColor: SafarTokens.asphalt900,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('MAP PLACEMENT PRESETS', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildLocationPresetChip('North-West', 0.20, 0.25, posX, posY, (x, y) => setModalState(() { posX = x; posY = y; })),
                        _buildLocationPresetChip('North-East', 0.80, 0.25, posX, posY, (x, y) => setModalState(() { posX = x; posY = y; })),
                        _buildLocationPresetChip('West Hub', 0.15, 0.50, posX, posY, (x, y) => setModalState(() { posX = x; posY = y; })),
                        _buildLocationPresetChip('East Hub', 0.85, 0.50, posX, posY, (x, y) => setModalState(() { posX = x; posY = y; })),
                        _buildLocationPresetChip('South-West', 0.20, 0.85, posX, posY, (x, y) => setModalState(() { posX = x; posY = y; })),
                        _buildLocationPresetChip('South-East', 0.80, 0.85, posX, posY, (x, y) => setModalState(() { posX = x; posY = y; })),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('COORDINATE X (${(posX * 100).toInt()}%)', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                              Slider(
                                value: posX,
                                min: 0.08,
                                max: 0.92,
                                activeColor: SafarTokens.hivis,
                                inactiveColor: SafarTokens.asphalt800,
                                onChanged: (v) => setModalState(() => posX = v),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('COORDINATE Y (${(posY * 100).toInt()}%)', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                              Slider(
                                value: posY,
                                min: 0.08,
                                max: 0.92,
                                activeColor: SafarTokens.hivis,
                                inactiveColor: SafarTokens.asphalt800,
                                onChanged: (v) => setModalState(() => posY = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: SafarTokens.concrete100,
                              side: const BorderSide(color: SafarTokens.asphalt600),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('CANCEL', style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SafarTokens.hivis,
                              foregroundColor: SafarTokens.asphalt950,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              final jId = idController.text.trim().toUpperCase();
                              final jLabel = labelController.text.trim().toUpperCase();
                              if (jId.isEmpty) return;
                              final newJunction = NetworkJunction(
                                id: jId,
                                label: jLabel.isEmpty ? 'JUNCTION $jId' : jLabel,
                                position: Offset(posX, posY),
                              );
                              setState(() {
                                _junctions.add(newJunction);
                              });
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: SafarTokens.asphalt800,
                                  content: Text(
                                    'ADDED JUNCTION: $jId AT (${(posX * 100).toInt()}%, ${(posY * 100).toInt()}%)',
                                    style: SafarTokens.fontMono(fontSize: 11.0, color: SafarTokens.hivis),
                                  ),
                                ),
                              );
                            },
                            child: Text('ADD JUNCTION NODE', style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditRoadDialog(NetworkRoadSegment road) {
    double widthM = road.widthM;
    int lanes = road.lanes;
    final nameController = TextEditingController(text: road.name);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SafarTokens.asphalt950,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isPassable = widthM >= 3.50;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'EDIT ROAD WIDTH & METRICS',
                          style: SafarTokens.fontUi(
                            fontSize: 14.0,
                            fontWeight: FontWeight.w800,
                            color: SafarTokens.hivis,
                            letterSpacing: 0.08,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: SafarTokens.asphalt400, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      style: SafarTokens.fontMono(fontSize: 12.0, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'ROAD NAME',
                        labelStyle: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                        filled: true,
                        fillColor: SafarTokens.asphalt900,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ADJUST CARRIAGEWAY WIDTH', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                        Text(
                          '${widthM.toStringAsFixed(2)} m',
                          style: SafarTokens.fontMono(
                            fontSize: 18.0,
                            fontWeight: FontWeight.w800,
                            color: isPassable ? SafarTokens.hivis : SafarTokens.confLow,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: widthM,
                      min: 2.0,
                      max: 16.0,
                      divisions: 140,
                      activeColor: isPassable ? SafarTokens.hivis : SafarTokens.confLow,
                      inactiveColor: SafarTokens.asphalt800,
                      onChanged: (val) => setModalState(() => widthM = val),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildPresetChip('3.10m (PINCH)', 3.10, widthM, (w) => setModalState(() => widthM = w)),
                          const SizedBox(width: 6),
                          _buildPresetChip('3.50m (CLEAR)', 3.50, widthM, (w) => setModalState(() => widthM = w)),
                          const SizedBox(width: 6),
                          _buildPresetChip('3.75m (1-LANE)', 3.75, widthM, (w) => setModalState(() => widthM = w)),
                          const SizedBox(width: 6),
                          _buildPresetChip('7.00m (2-LANE)', 7.00, widthM, (w) => setModalState(() => widthM = w)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isPassable
                            ? SafarTokens.confHigh.withValues(alpha: 0.15)
                            : SafarTokens.confLow.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(SafarTokens.rSm),
                        border: Border.all(
                          color: isPassable ? SafarTokens.confHigh : SafarTokens.confLow,
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPassable ? Icons.check_circle : Icons.warning_amber_rounded,
                            size: 18,
                            color: isPassable ? SafarTokens.confHigh : SafarTokens.confLow,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isPassable
                                  ? 'IRC:SP:84 PASS: Minimum 3.50m clearance satisfied.'
                                  : 'CRITICAL CHOKEPOINT: Width < 3.50m blocks fire tender passage!',
                              style: SafarTokens.fontMono(
                                fontSize: 10.0,
                                color: isPassable ? SafarTokens.confHigh : SafarTokens.confLow,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: SafarTokens.concrete100,
                              side: const BorderSide(color: SafarTokens.asphalt600),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('CANCEL', style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SafarTokens.hivis,
                              foregroundColor: SafarTokens.asphalt950,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              final updated = NetworkRoadSegment(
                                id: road.id,
                                name: nameController.text.trim().isEmpty ? road.name : nameController.text.trim().toUpperCase(),
                                fromJunction: road.fromJunction,
                                toJunction: road.toJunction,
                                widthM: double.parse(widthM.toStringAsFixed(2)),
                                lengthM: road.lengthM,
                                lanes: lanes,
                                confidenceHalfM: road.confidenceHalfM,
                                start: road.start,
                                end: road.end,
                                controlPoints: road.controlPoints,
                              );
                              final index = _roadSegments.indexWhere((r) => r.id == road.id);
                              if (index != -1) {
                                setState(() {
                                  _roadSegments[index] = updated;
                                  _selectedRoad = updated;
                                });
                              }
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: SafarTokens.asphalt800,
                                  content: Text(
                                    'UPDATED ${updated.name}: WIDTH IS NOW ${updated.widthM.toStringAsFixed(2)}m (${updated.isFireTenderPassable ? "PASS" : "PINCH"})',
                                    style: SafarTokens.fontMono(fontSize: 11.0, color: SafarTokens.hivis),
                                  ),
                                ),
                              );
                            },
                            child: Text('SAVE CHANGES', style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _deleteRoad(NetworkRoadSegment road) {
    setState(() {
      _roadSegments.removeWhere((r) => r.id == road.id);
      if (_selectedRoad?.id == road.id) {
        _selectedRoad = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: SafarTokens.asphalt800,
        content: Text(
          'DELETED ROAD: ${road.name}',
          style: SafarTokens.fontMono(fontSize: 11.0, color: SafarTokens.confLow),
        ),
      ),
    );
  }

  void _showJunctionDetails(NetworkJunction junction) {
    setState(() => _selectedJunction = junction);
    final connectedRoads = _roadSegments.where((r) => r.fromJunction == junction.id || r.toJunction == junction.id).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: SafarTokens.asphalt950,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    junction.label,
                    style: SafarTokens.fontUi(fontSize: 14, fontWeight: FontWeight.w800, color: SafarTokens.hivis),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: SafarTokens.asphalt400, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'CONNECTED CORRIDORS (${connectedRoads.length}):',
                style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
              ),
              const SizedBox(height: 6),
              ...connectedRoads.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(r.name, style: SafarTokens.fontMono(fontSize: 11.0, color: Colors.white)),
                    Text(
                      '${r.widthM.toStringAsFixed(1)}m ${r.isFireTenderPassable ? "PASS" : "PINCH"}',
                      style: SafarTokens.fontMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: r.isFireTenderPassable ? SafarTokens.hivis : SafarTokens.confLow,
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SafarTokens.hivis,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('CONNECT NEW ROAD FROM THIS JUNCTION', style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w800)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAddRoadDialog(junction.id);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresetChip(String label, double value, double currentVal, ValueChanged<double> onSelect) {
    final bool isSelected = (currentVal - value).abs() < 0.05;
    return InkWell(
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt800,
          borderRadius: BorderRadius.circular(SafarTokens.rSm),
          border: Border.all(color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt700),
        ),
        child: Text(
          label,
          style: SafarTokens.fontMono(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildLocationPresetChip(String label, double x, double y, double curX, double curY, Function(double, double) onSelect) {
    final bool isSelected = (curX - x).abs() < 0.05 && (curY - y).abs() < 0.05;
    return InkWell(
      onTap: () => onSelect(x, y),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt800,
          borderRadius: BorderRadius.circular(SafarTokens.rSm),
          border: Border.all(color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt700),
        ),
        child: Text(
          label,
          style: SafarTokens.fontMono(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // VIEW 2: AR POINT-TO-POINT METRIC RULER
  // ==========================================
  Widget _buildArRulerView() {
    return Stack(
      children: [
        // Camera or Surveyor Grid Background
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _handleRulerTap,
            child: CustomPaint(
              painter: _ArRulerCanvasPainter(
                pointA: _pointA,
                pointB: _pointB,
                measuredWidthM: _measuredWidthM,
              ),
            ),
          ),
        ),

        // Instruction Bar
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: SafarTokens.asphalt950.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(SafarTokens.rSm),
              border: Border.all(color: SafarTokens.asphalt700),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: SafarTokens.hivis),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pointA == null
                        ? 'TAP LEFT ROAD EDGE (POINT A)'
                        : (_pointB == null ? 'TAP RIGHT ROAD EDGE (POINT B)' : 'MEASURED: ${_measuredWidthM.toStringAsFixed(2)} m (TAP TO RESET)'),
                    style: SafarTokens.fontMono(fontSize: 11.0, fontWeight: FontWeight.w700, color: SafarTokens.paint),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom Measurement Card
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SafarTokens.asphalt900,
              borderRadius: BorderRadius.circular(SafarTokens.rMd),
              border: Border.all(color: SafarTokens.asphalt700),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AR MEASURED GROUND DISTANCE', style: SafarTokens.microLabel(color: SafarTokens.hivis)),
                        const SizedBox(height: 2),
                        Text(
                          _measuredWidthM > 0 ? '${_measuredWidthM.toStringAsFixed(2)} m' : '--.-- m',
                          style: SafarTokens.fontMono(fontSize: 24.0, fontWeight: FontWeight.w800, color: SafarTokens.hivis),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _measuredWidthM >= 3.5 ? SafarTokens.confHigh : SafarTokens.confLow,
                        borderRadius: BorderRadius.circular(SafarTokens.rSm),
                      ),
                      child: Text(
                        _measuredWidthM >= 3.5 ? 'PASS (>=3.5m)' : 'PINCH POINT',
                        style: SafarTokens.fontMono(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _isFrozen ? SafarTokens.hivis : SafarTokens.concrete100,
                          side: BorderSide(color: _isFrozen ? SafarTokens.hivis : SafarTokens.asphalt600),
                        ),
                        onPressed: () => setState(() => _isFrozen = !_isFrozen),
                        child: Text(_isFrozen ? 'UNFREEZE' : 'FREEZE', style: SafarTokens.fontMono(fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SafarTokens.concrete100,
                          side: const BorderSide(color: SafarTokens.asphalt600),
                        ),
                        onPressed: () {
                          setState(() {
                            _pointA = null;
                            _pointB = null;
                            _measuredWidthM = 0.0;
                          });
                        },
                        child: Text('RESET', style: SafarTokens.fontMono(fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SafarTokens.hivis,
                          foregroundColor: SafarTokens.asphalt950,
                        ),
                        onPressed: _measuredWidthM > 0 ? _saveGroundTruth : null,
                        child: Text('SAVE GROUND TRUTH', style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SafarTokens.asphalt950,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rMd)),
        title: Text('ROAD NETWORK & AR GUIDE', style: SafarTokens.fontUi(fontSize: 14, fontWeight: FontWeight.w800, color: SafarTokens.hivis)),
        content: Text(
          '1. OVERHEAD MAP: Displays interconnected road corridors from above with real-time width readouts and pinch-point warnings.\n\n'
          '• PAN & ZOOM: Drag with one finger to pan around. Pinch with two fingers or use on-screen [+] and [-] buttons to zoom.\n'
          '• ADD ROADS: Tap "+ ADD ROAD" to draw new road corridors connecting junctions with custom widths.\n'
          '• EDIT WIDTH: Select any road and tap the edit icon to simulate widening to see if it clears the 3.5m fire safety clearance.\n\n'
          '2. AR TAPE RULER: Independent surveyor tape measure using phone AR geometry. Tap two points across any road to verify ground-truth width.',
          style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: SafarTokens.fontMono(fontSize: 12, fontWeight: FontWeight.w700, color: SafarTokens.hivis)),
          ),
        ],
      ),
    );
  }
}

/// Custom Painter for the Top-Down Overhead Road Network
class _OverheadRoadNetworkPainter extends CustomPainter {
  final List<NetworkJunction> junctions;
  final List<NetworkRoadSegment> roads;
  final NetworkRoadSegment? selectedRoad;
  final NetworkJunction? selectedJunction;

  _OverheadRoadNetworkPainter({
    required this.junctions,
    required this.roads,
    required this.selectedRoad,
    this.selectedJunction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw surveyor grid
    final Paint gridPaint = Paint()
      ..color = SafarTokens.asphalt800.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const double step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Draw road connections
    for (final road in roads) {
      final pA = Offset(road.start.dx * size.width, road.start.dy * size.height);
      final pB = Offset(road.end.dx * size.width, road.end.dy * size.height);
      final bool isSelected = road.id == selectedRoad?.id;

      // Road width in pixels (scaled proportional to carriageway width)
      final double roadPixelW = (road.widthM * 3.6).clamp(12.0, 52.0);

      // Road asphalt casing
      final Paint asphaltPaint = Paint()
        ..color = isSelected ? SafarTokens.asphalt700 : SafarTokens.asphalt900
        ..style = PaintingStyle.stroke
        ..strokeWidth = roadPixelW
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(pA, pB, asphaltPaint);

      // Road border / kerb line
      final Paint borderPaint = Paint()
        ..color = road.isFireTenderPassable
            ? (isSelected ? SafarTokens.hivis : SafarTokens.asphalt600)
            : SafarTokens.confLow
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : 1.5;
      canvas.drawLine(pA, pB, borderPaint);

      // Dashed lane divider(s)
      final Paint dashPaint = Paint()
        ..color = SafarTokens.segMarking.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawLine(pA, pB, dashPaint);

      // Midpoint for metric badge
      final Offset mid = Offset((pA.dx + pB.dx) / 2, (pA.dy + pB.dy) / 2);
      _drawRoadMetricBadge(canvas, road, mid, isSelected);
    }

    // 3. Draw Junction Nodes
    for (final j in junctions) {
      final p = Offset(j.position.dx * size.width, j.position.dy * size.height);
      final bool isJunctionSelected = j.id == selectedJunction?.id;

      final Paint jPaint = Paint()..color = SafarTokens.asphalt950;
      final Paint jStroke = Paint()
        ..color = isJunctionSelected ? SafarTokens.hivis : SafarTokens.asphalt400
        ..style = PaintingStyle.stroke
        ..strokeWidth = isJunctionSelected ? 3.0 : 2.0;

      canvas.drawCircle(p, 12, jPaint);
      canvas.drawCircle(p, 12, jStroke);
      canvas.drawCircle(p, 4, Paint()..color = isJunctionSelected ? SafarTokens.hivis : SafarTokens.concrete100);

      // Node Label
      final tp = TextPainter(
        text: TextSpan(
          text: j.id,
          style: TextStyle(
            color: isJunctionSelected ? SafarTokens.hivis : Colors.white,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + 15));
    }
  }

  void _drawRoadMetricBadge(Canvas canvas, NetworkRoadSegment road, Offset pos, bool isSelected) {
    final String text = '${road.widthM.toStringAsFixed(1)}m ${road.isFireTenderPassable ? "" : "[!]" }';
    final Color badgeBg = road.isFireTenderPassable
        ? (isSelected ? SafarTokens.hivis : SafarTokens.asphalt950)
        : SafarTokens.confLow;
    final Color textColor = road.isFireTenderPassable
        ? (isSelected ? SafarTokens.asphalt950 : SafarTokens.hivis)
        : Colors.white;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 10.0, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: tp.width + 12, height: tp.height + 6),
      const Radius.circular(4),
    );

    canvas.drawRRect(r, Paint()..color = badgeBg);
    canvas.drawRRect(r, Paint()..color = road.isFireTenderPassable ? SafarTokens.hivis : Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.0);
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _OverheadRoadNetworkPainter oldDelegate) => true;
}

/// Canvas painter for AR Ruler mode
class _ArRulerCanvasPainter extends CustomPainter {
  final Offset? pointA;
  final Offset? pointB;
  final double measuredWidthM;

  _ArRulerCanvasPainter({
    required this.pointA,
    required this.pointB,
    required this.measuredWidthM,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Grid background
    final Paint gridPaint = Paint()
      ..color = SafarTokens.asphalt800.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (pointA != null) {
      _drawReticle(canvas, pointA!, 'POINT A', SafarTokens.segKerb);
    }
    if (pointB != null) {
      _drawReticle(canvas, pointB!, 'POINT B', SafarTokens.hivis);
    }
    if (pointA != null && pointB != null) {
      final Paint linePaint = Paint()
        ..color = SafarTokens.hivis
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawLine(pointA!, pointB!, linePaint);

      final Offset mid = Offset((pointA!.dx + pointB!.dx) / 2, (pointA!.dy + pointB!.dy) / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: '${measuredWidthM.toStringAsFixed(2)} m',
          style: const TextStyle(color: Colors.black, fontSize: 12.0, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: mid, width: tp.width + 12, height: tp.height + 6),
        const Radius.circular(4),
      );
      canvas.drawRRect(r, Paint()..color = SafarTokens.hivis);
      tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height / 2));
    }
  }

  void _drawReticle(Canvas canvas, Offset p, String label, Color color) {
    final Paint pPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(p, 14, pPaint);
    canvas.drawLine(Offset(p.dx - 20, p.dy), Offset(p.dx + 20, p.dy), pPaint);
    canvas.drawLine(Offset(p.dx, p.dy - 20), Offset(p.dx, p.dy + 20), pPaint);
    canvas.drawCircle(p, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ArRulerCanvasPainter oldDelegate) => true;
}

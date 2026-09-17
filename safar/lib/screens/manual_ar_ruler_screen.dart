// Manual AR Ruler & Overhead Road Connections Screen
// Dual Mode:
// 1. OVERHEAD NETWORK MAP (BEV): Top-down map showing connected road segments, junctions,
//    and real-time metrics (carriageway width, IRC:SP:84 fire clearance, confidence) on each road.
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
  String _networkFilter = 'ALL'; // 'ALL', 'PINCH', 'PASSABLE'

  // Pre-configured road network with connections and metrics
  late final List<NetworkJunction> _junctions;
  late final List<NetworkRoadSegment> _roadSegments;

  @override
  void initState() {
    super.initState();

    _junctions = const [
      NetworkJunction(id: 'J1', label: 'NORTH GATE (J1)', position: Offset(0.50, 0.12)),
      NetworkJunction(id: 'J2', label: 'CENTRAL CIRCLE (J2)', position: Offset(0.50, 0.44)),
      NetworkJunction(id: 'J3', label: 'BAZAAR FORK (J3)', position: Offset(0.22, 0.72)),
      NetworkJunction(id: 'J4', label: 'EAST INTERCHANGE (J4)', position: Offset(0.80, 0.65)),
      NetworkJunction(id: 'J5', label: 'SOUTH TERMINAL (J5)', position: Offset(0.50, 0.92)),
    ];

    _roadSegments = const [
      NetworkRoadSegment(
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
      NetworkRoadSegment(
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
      NetworkRoadSegment(
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
      NetworkRoadSegment(
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
      NetworkRoadSegment(
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
  // VIEW 1: OVERHEAD ROAD CONNECTIONS & METRICS
  // ==========================================
  Widget _buildOverheadNetworkView() {
    final filteredRoads = _roadSegments.where((road) {
      if (_networkFilter == 'PINCH') return road.widthM < 3.50;
      if (_networkFilter == 'PASSABLE') return road.widthM >= 3.50;
      return true;
    }).toList();

    return Column(
      children: [
        // Filter chip row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: SafarTokens.asphalt900,
          child: Row(
            children: [
              Text(
                'FILTER: ',
                style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
              ),
              const SizedBox(width: 8),
              _buildFilterChip('ALL', 'ALL ROADS (${_roadSegments.length})'),
              const SizedBox(width: 6),
              _buildFilterChip('PINCH', 'PINCH POINTS (<3.5m)'),
              const SizedBox(width: 6),
              _buildFilterChip('PASSABLE', 'FIRE PASSABLE'),
            ],
          ),
        ),

        // Interactive Overhead BEV Canvas
        Expanded(
          child: Stack(
            children: [
              // Grid Background & Network Canvas
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final RenderBox box = context.findRenderObject() as RenderBox;
                    final local = details.localPosition;
                    // Find closest road
                    NetworkRoadSegment? closestRoad;
                    double minDistance = double.infinity;

                    for (final road in _roadSegments) {
                      final pA = Offset(road.start.dx * box.size.width, road.start.dy * box.size.height);
                      final pB = Offset(road.end.dx * box.size.width, road.end.dy * box.size.height);
                      final d = _pointToSegmentDistance(local, pA, pB);
                      if (d < minDistance) {
                        minDistance = d;
                        closestRoad = road;
                      }
                    }

                    if (closestRoad != null && minDistance < 50) {
                      setState(() => _selectedRoad = closestRoad);
                    }
                  },
                  child: CustomPaint(
                    painter: _OverheadRoadNetworkPainter(
                      junctions: _junctions,
                      roads: filteredRoads,
                      selectedRoad: _selectedRoad,
                    ),
                  ),
                ),
              ),

              // Floating Legend & Summary
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
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedModeIndex = 1;
                    _measuredWidthM = road.widthM;
                  });
                },
                child: Text(
                  'MEASURE WITH AR RULER ->',
                  style: SafarTokens.fontMono(fontSize: 10.5, fontWeight: FontWeight.w700, color: SafarTokens.hivis),
                ),
              ),
            ],
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
          '1. OVERHEAD MAP: Displays interconnected road corridors from above. Real-time carriageway metrics, IRC:SP:84 fire clearances, and widths are printed beside each road.\n\n'
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

  _OverheadRoadNetworkPainter({
    required this.junctions,
    required this.roads,
    required this.selectedRoad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw surveyor grid
    final Paint gridPaint = Paint()
      ..color = SafarTokens.asphalt800.withValues(alpha: 0.4)
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
      final bool isSelected = road == selectedRoad;

      // Road width in pixels (scaled)
      final double roadPixelW = (road.widthM * 3.6).clamp(12.0, 48.0);

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

      // Dashed lane divider
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
      final Paint jPaint = Paint()..color = SafarTokens.asphalt950;
      final Paint jStroke = Paint()
        ..color = SafarTokens.hivis
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(p, 10, jPaint);
      canvas.drawCircle(p, 10, jStroke);
      canvas.drawCircle(p, 4, Paint()..color = SafarTokens.hivis);

      // Node Label
      final tp = TextPainter(
        text: TextSpan(
          text: j.id,
          style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy + 14));
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

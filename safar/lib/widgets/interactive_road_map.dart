// Interactive Road Map Widget
// Free OpenStreetMap vector/raster tiles (no API key required, 100% free).
// Displays mapped areas, road width heatmaps, pinch points, and measurement data callouts.
// Avoids emojis.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/safar_tokens.dart';
import '../models/map_marker_data.dart';
import '../services/permissions_service.dart';
import 'confidence_badge.dart';

enum MapFilterMode {
  allWidths,
  fireTender,
  ambulance,
}

class InteractiveRoadMap extends StatefulWidget {
  final List<MapSegmentData> segments;
  final LatLng initialCenter;
  final double initialZoom;
  final ValueChanged<MapSegmentData>? onSegmentSelected;

  const InteractiveRoadMap({
    super.key,
    required this.segments,
    required this.initialCenter,
    this.initialZoom = 15.5,
    this.onSegmentSelected,
  });

  @override
  State<InteractiveRoadMap> createState() => _InteractiveRoadMapState();
}

class _InteractiveRoadMapState extends State<InteractiveRoadMap> {
  late final MapController _mapController;
  MapSegmentData? _selectedSegment;
  MapFilterMode _filterMode = MapFilterMode.allWidths;
  bool _showCallout = true;
  LatLng? _userLiveLocation;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    if (widget.segments.isNotEmpty) {
      _selectedSegment = widget.segments.first;
    }
  }

  Future<void> _locateUserGps() async {
    setState(() => _isLocating = true);
    try {
      final loc = await PermissionsService.getCurrentGpsLocation();
      if (!mounted) return;
      setState(() {
        _isLocating = false;
        if (loc != null) {
          _userLiveLocation = loc;
          _mapController.move(loc, 16.5);
        }
      });
      if (loc == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SafarTokens.asphalt800,
            content: Text(
              'LOCATION PERMISSION REQUIRED OR GPS NOT AVAILABLE. CENTERING ON ROUTE.',
              style: SafarTokens.fontMono(fontSize: 11.5, color: SafarTokens.hivis),
            ),
          ),
        );
        if (widget.segments.isNotEmpty) {
          _mapController.move(widget.segments.first.position, 16.0);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _zoomIn() {
    final double currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1.0);
  }

  void _zoomOut() {
    final double currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1.0);
  }

  void _fitBounds() {
    if (widget.segments.isEmpty) return;
    final List<LatLng> points = widget.segments.map((s) => s.position).toList();
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(40.0),
      ),
    );
  }

  Color _colorForSegment(MapSegmentData seg) {
    if (_filterMode == MapFilterMode.fireTender) {
      if (seg.widthM < 3.5) return SafarTokens.confLow; // Blocked
      if (seg.widthM < 4.0) return SafarTokens.confMed; // Caution
      return SafarTokens.confHigh; // Passable
    } else if (_filterMode == MapFilterMode.ambulance) {
      if (seg.widthM < 3.0) return SafarTokens.confLow;
      if (seg.widthM < 3.5) return SafarTokens.confMed;
      return SafarTokens.confHigh;
    }
    return SafarTokens.colorForWidth(seg.widthM);
  }

  @override
  Widget build(BuildContext context) {
    // Generate polyline segments along the surveyed track
    final List<Polyline> polylines = [];
    for (int i = 0; i < widget.segments.length - 1; i++) {
      final segA = widget.segments[i];
      final segB = widget.segments[i + 1];
      final Color color = _colorForSegment(segA);

      polylines.add(
        Polyline(
          points: [segA.position, segB.position],
          color: color,
          strokeWidth: segA == _selectedSegment ? 9.0 : 6.0,
        ),
      );
    }

    // Generate markers for pinch points (< 3.5m), start/end, and live GPS location
    final List<Marker> markers = [];

    // Live GPS Marker if active
    if (_userLiveLocation != null) {
      markers.add(
        Marker(
          point: _userLiveLocation!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.25),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blueAccent, width: 2.0),
            ),
            child: const Center(
              child: Icon(Icons.my_location, color: Colors.blueAccent, size: 20),
            ),
          ),
        ),
      );
    }

    if (widget.segments.isNotEmpty) {
      markers.add(
        Marker(
          point: widget.segments.first.position,
          width: 34,
          height: 34,
          child: _buildStartEndPin('START', SafarTokens.hivis),
        ),
      );
      markers.add(
        Marker(
          point: widget.segments.last.position,
          width: 34,
          height: 34,
          child: _buildStartEndPin('END', SafarTokens.paint),
        ),
      );
    }

    // Critical pinch points (< 3.5m)
    for (final seg in widget.segments) {
      if (seg.widthM < 3.5) {
        markers.add(
          Marker(
            point: seg.position,
            width: 30,
            height: 30,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedSegment = seg;
                  _showCallout = true;
                });
                widget.onSegmentSelected?.call(seg);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: SafarTokens.confLow,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.0),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: const Center(
                  child: Text(
                    '!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return Stack(
      children: [
        // Free OpenStreetMap Standard Tiles (100% Free, Public, No API Key Required)
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.initialCenter,
            initialZoom: widget.initialZoom,
            minZoom: 3.0,
            maxZoom: 19.0,
            onTap: (tapPosition, point) {
              if (widget.segments.isEmpty) return;
              MapSegmentData? closest;
              double minDistance = double.infinity;
              const Distance distance = Distance();

              for (final seg in widget.segments) {
                final double d = distance.as(LengthUnit.Meter, point, seg.position);
                if (d < minDistance) {
                  minDistance = d;
                  closest = seg;
                }
              }

              if (closest != null && minDistance < 60.0) {
                setState(() {
                  _selectedSegment = closest;
                  _showCallout = true;
                });
                widget.onSegmentSelected?.call(closest);
              }
            },
          ),
          children: [
            // 100% Free OpenStreetMap tile server
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.safar.app',
              maxZoom: 19,
            ),

            // Road Width Heatmap Polylines
            PolylineLayer(polylines: polylines),

            // Markers
            MarkerLayer(markers: markers),
          ],
        ),

        // Top Filter Bar: Accessibility Filters
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: _buildFilterBar(),
        ),

        // Floating Zoom and Navigation Controls (+, -, Fit, Live GPS, Legend)
        Positioned(
          right: 12,
          top: 75,
          child: Column(
            children: [
              _buildMapButton(
                icon: Icons.add,
                tooltip: 'Zoom In',
                onTap: _zoomIn,
              ),
              const SizedBox(height: 8),
              _buildMapButton(
                icon: Icons.remove,
                tooltip: 'Zoom Out',
                onTap: _zoomOut,
              ),
              const SizedBox(height: 8),
              _buildMapButton(
                icon: Icons.crop_free,
                tooltip: 'Fit Survey Route to Screen',
                onTap: _fitBounds,
              ),
              const SizedBox(height: 8),
              _buildMapButton(
                icon: _isLocating ? Icons.hourglass_top : Icons.my_location,
                tooltip: 'Locate My Position (GPS)',
                onTap: _locateUserGps,
              ),
              const SizedBox(height: 8),
              _buildMapButton(
                icon: Icons.help_outline,
                tooltip: 'Map Legend & Gestures',
                onTap: _showLegendDialog,
              ),
            ],
          ),
        ),

        // Bottom HUD Callout: Measurement Data
        if (_selectedSegment != null && _showCallout)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: _buildMeasurementCallout(_selectedSegment!),
          ),

        // Re-open Callout button if closed
        if (_selectedSegment != null && !_showCallout)
          Positioned(
            left: 10,
            bottom: 10,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: SafarTokens.asphalt950,
                foregroundColor: SafarTokens.hivis,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              icon: const Icon(Icons.info_outline, size: 16),
              label: Text(
                'SHOW MEASUREMENT DETAILS (CH ${_selectedSegment!.chainageM.toStringAsFixed(0)} m)',
                style: SafarTokens.fontMono(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              onPressed: () => setState(() => _showCallout = true),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt950.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(SafarTokens.rMd),
        border: Border.all(color: SafarTokens.asphalt700, width: 1.0),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              'HEATMAP VIEW: ',
              style: SafarTokens.fontUi(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: SafarTokens.asphalt400,
                letterSpacing: 0.08,
              ),
            ),
            const SizedBox(width: 8),
            _buildFilterChip('ALL ROAD WIDTHS', MapFilterMode.allWidths),
            const SizedBox(width: 6),
            _buildFilterChip('FIRE TENDER (< 3.5m PINCH)', MapFilterMode.fireTender),
            const SizedBox(width: 6),
            _buildFilterChip('AMBULANCE (< 3.0m PINCH)', MapFilterMode.ambulance),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, MapFilterMode mode) {
    final bool isSelected = _filterMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _filterMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt800,
          borderRadius: BorderRadius.circular(SafarTokens.rSm),
          border: Border.all(
            color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt600,
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: SafarTokens.fontMono(
            fontSize: 11.0,
            fontWeight: FontWeight.w700,
            color: isSelected ? SafarTokens.asphalt950 : SafarTokens.concrete100,
          ),
        ),
      ),
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: SafarTokens.asphalt950.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(SafarTokens.rSm),
        elevation: 4,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SafarTokens.rSm),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              border: Border.all(color: SafarTokens.asphalt600, width: 1.2),
              borderRadius: BorderRadius.circular(SafarTokens.rSm),
            ),
            child: Icon(icon, color: SafarTokens.concrete50, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildStartEndPin(String text, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: SafarTokens.asphalt950, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: SafarTokens.asphalt950,
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void _showLegendDialog() {
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
            'GPS MAP LEGEND & GUIDE',
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
                  'INTERACTION GESTURES',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 6),
                _buildLegendRow(
                  icon: Icons.pinch_outlined,
                  iconColor: SafarTokens.paint,
                  title: 'Two-Finger Pinch',
                  desc: 'Zoom in and out continuously across the road corridor.',
                ),
                const SizedBox(height: 6),
                _buildLegendRow(
                  icon: Icons.pan_tool_outlined,
                  iconColor: SafarTokens.paint,
                  title: 'One-Finger Drag',
                  desc: 'Pan along the surveyed highway or rural alignment.',
                ),
                const SizedBox(height: 6),
                _buildLegendRow(
                  icon: Icons.touch_app_outlined,
                  iconColor: SafarTokens.hivis,
                  title: 'Tap on Path / Pin',
                  desc: 'Inspect exact chainage, metric road width, and 90% confidence.',
                ),
                const Divider(color: SafarTokens.asphalt700, height: 20),

                Text(
                  'ROAD WIDTH HEATMAP COLORS',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 6),
                _buildColorRampRow(
                  color: SafarTokens.confHigh,
                  title: '>= 7.0 m (Wide 2-Lane)',
                  desc: 'Full clearance for high-speed two-way traffic and heavy vehicles.',
                ),
                const SizedBox(height: 6),
                _buildColorRampRow(
                  color: SafarTokens.hivis,
                  title: '5.0 - 7.0 m (1.5 - 2 Lane)',
                  desc: 'Standard carriageway width for urban collectors and rural links.',
                ),
                const SizedBox(height: 6),
                _buildColorRampRow(
                  color: SafarTokens.confMed,
                  title: '3.5 - 5.0 m (Single Lane)',
                  desc: 'Single lane with passing requirement. Standard vehicles pass.',
                ),
                const SizedBox(height: 6),
                _buildColorRampRow(
                  color: SafarTokens.confLow,
                  title: '< 3.5 m (Critical Pinch Point)',
                  desc: 'Blocks emergency fire tenders (3.5m requirement). Marked with !',
                ),
                const Divider(color: SafarTokens.asphalt700, height: 20),

                Text(
                  'FREE MAP TILES',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 4),
                Text(
                  'Safar uses 100% free OpenStreetMap raster tiles. No paid APIs or tokens are required.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete300),
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

  Widget _buildLegendRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SafarTokens.fontMono(fontSize: 11.5, fontWeight: FontWeight.w700, color: SafarTokens.paint)),
              const SizedBox(height: 1),
              Text(desc, style: SafarTokens.fontUi(fontSize: 11.0, color: SafarTokens.asphalt400)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColorRampRow({
    required Color color,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: SafarTokens.asphalt600, width: 1.0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SafarTokens.fontMono(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 1),
              Text(desc, style: SafarTokens.fontUi(fontSize: 11.0, color: SafarTokens.asphalt400)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMeasurementCallout(MapSegmentData seg) {
    final bool isPinch = seg.widthM < 3.5;
    final Color widthColor = SafarTokens.colorForWidth(seg.widthM);

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt950.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(SafarTokens.rMd),
        border: Border.all(
          color: isPinch ? SafarTokens.confLow : SafarTokens.asphalt700,
          width: isPinch ? 2.0 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 18.0, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row: Chainage + GPS Lat/Lon + Close button (Wrap-enabled)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: SafarTokens.asphalt800,
                        borderRadius: BorderRadius.circular(SafarTokens.rSm),
                      ),
                      child: Text(
                        'CHAINAGE ${seg.chainageM.toStringAsFixed(0)} m',
                        style: SafarTokens.fontMono(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: SafarTokens.hivis,
                        ),
                      ),
                    ),
                    Text(
                      '${seg.position.latitude.toStringAsFixed(5)} N, ${seg.position.longitude.toStringAsFixed(5)} E',
                      style: SafarTokens.fontMono(
                        fontSize: 11.0,
                        color: SafarTokens.paint,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConfidenceBadge(tier: seg.tier, halfWidthM: seg.halfWidthM),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => setState(() => _showCallout = false),
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(Icons.close, size: 18, color: SafarTokens.asphalt400),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Primary Measurement Readout
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${seg.widthM.toStringAsFixed(2)} m',
                style: SafarTokens.fontMono(
                  fontSize: 26.0,
                  fontWeight: FontWeight.w800,
                  color: widthColor,
                  letterSpacing: -0.02,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '+/- ${seg.halfWidthM.toStringAsFixed(2)} m (90% interval)',
                  style: SafarTokens.fontMono(
                    fontSize: 11.5,
                    color: SafarTokens.asphalt400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Details Layout using Wrap to prevent any screen overflow on small mobile screens
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: SafarTokens.asphalt900,
              borderRadius: BorderRadius.circular(SafarTokens.rSm),
              border: Border.all(color: SafarTokens.asphalt700),
            ),
            child: Wrap(
              spacing: 16.0,
              runSpacing: 8.0,
              children: [
                _buildCalloutItem(
                  'FIRE TENDER CLEARANCE (3.5 m REQUIRED)',
                  seg.fireTenderStatus == AccessibilityStatus.pinchPointImpassable
                      ? 'BLOCKED (< 3.5 m PINCH)'
                      : 'PASSIBLE (CLEAR)',
                  seg.fireTenderStatus == AccessibilityStatus.pinchPointImpassable
                      ? SafarTokens.confLow
                      : SafarTokens.confHigh,
                ),
                _buildCalloutItem(
                  'ROAD BOUNDARIES',
                  'L: ${seg.edgeLeft}  |  R: ${seg.edgeRight}',
                  SafarTokens.paint,
                ),
                _buildCalloutItem(
                  'AGGREGATED FRAMES',
                  '${seg.observationCount} frames (MAD: ${seg.madM.toStringAsFixed(2)} m)',
                  SafarTokens.concrete300,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalloutItem(String title, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
        const SizedBox(height: 2),
        Text(
          value,
          style: SafarTokens.fontMono(
            fontSize: 11.0,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

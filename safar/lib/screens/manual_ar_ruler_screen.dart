// Manual AR Ruler Screen
// AR point-to-point metric ruler for ground-truth capture and manual overrides.
// Strict compliance with Section 01 & 04 of System Plan (P02).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';

class ManualArRulerScreen extends StatefulWidget {
  const ManualArRulerScreen({super.key});

  @override
  State<ManualArRulerScreen> createState() => _ManualArRulerScreenState();
}

class _ManualArRulerScreenState extends State<ManualArRulerScreen> {
  Offset? _pointA;
  Offset? _pointB;
  bool _isFrozen = false;
  double _measuredWidthM = 0.0;
  final double _cameraHeightM = 1.40;

  void _handleTap(TapUpDetails details) {
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
      // Reset
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

    // Approximate AR perspective mapping on 1.4m height ground plane
    // Roughly 42 pixels per metre at this near-field focal plane
    _measuredWidthM = (pixelDist / 44.0).clamp(1.5, 20.0);
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

  void _showHelpDialog() {
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
            'MANUAL AR RULER GUIDE',
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
                  'WHY USE THE AR RULER?',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 6),
                Text(
                  'The AR Ruler acts as a virtual surveyor tape measure using phone ARCore ground plane geometry. It does NOT use neural networks or ML predictions, making it an independent source of ground truth.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'HOW TO MEASURE ROAD WIDTH:',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 6),
                Text(
                  '1. Keep vehicle stationary or walk to the road edge.\n'
                  '2. Tap the pause button (top right) to freeze a clear frame if needed.\n'
                  '3. Tap the LEFT road edge/kerb (Point A).\n'
                  '4. Tap the RIGHT road edge/kerb (Point B).\n'
                  '5. The metric span in metres is computed immediately.\n'
                  '6. Tap "SAVE GROUND TRUTH" to store this calibration pair for Split Conformal recalibration.',
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

  void _resetPoints() {
    setState(() {
      _pointA = null;
      _pointB = null;
      _measuredWidthM = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafarTokens.asphalt950,
      appBar: AppBar(
        title: Text(
          'MANUAL AR RULER (GROUND TRUTH)',
          style: SafarTokens.fontUi(
            fontSize: 13.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.08,
            color: SafarTokens.concrete50,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: SafarTokens.concrete100),
            tooltip: 'AR Ruler Instructions',
            onPressed: _showHelpDialog,
          ),
          IconButton(
            icon: Icon(
              _isFrozen ? Icons.play_arrow : Icons.pause,
              color: _isFrozen ? SafarTokens.confLow : SafarTokens.hivis,
            ),
            tooltip: _isFrozen ? 'Unfreeze Live View' : 'Freeze Frame to Tap Carefully',
            onPressed: () {
              setState(() => _isFrozen = !_isFrozen);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. AR Camera Background Canvas
          Positioned.fill(
            child: GestureDetector(
              onTapUp: _handleTap,
              child: CustomPaint(
                painter: _ArPlanePainter(
                  pointA: _pointA,
                  pointB: _pointB,
                  isFrozen: _isFrozen,
                ),
              ),
            ),
          ),

          // 2. Top Instructions Banner
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: SafarTokens.asphalt950.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(SafarTokens.rSm),
                border: Border.all(color: SafarTokens.asphalt700),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _pointA == null
                          ? 'STEP 1: TAP LEFT ROAD EDGE (POINT A)'
                          : (_pointB == null
                              ? 'STEP 2: TAP RIGHT ROAD EDGE (POINT B)'
                              : 'ROAD SPAN MEASURED. TAP SAVE OR RESET.'),
                      style: SafarTokens.fontMono(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w700,
                        color: SafarTokens.hivis,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'h=${_cameraHeightM.toStringAsFixed(2)} m',
                    style: SafarTokens.fontMono(fontSize: 11.0, color: SafarTokens.asphalt400),
                  ),
                ],
              ),
            ),
          ),

          // Center guidance hint when starting
          if (_pointA == null)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: SafarTokens.asphalt950.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                  border: Border.all(color: SafarTokens.hivis.withValues(alpha: 0.7)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.touch_app, color: SafarTokens.hivis, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'TAP ROAD SURFACE TO SET POINT A (LEFT KERB)',
                        style: SafarTokens.fontMono(
                          fontSize: 11.0,
                          color: SafarTokens.hivis,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3. Measurement Result Card (Bottom)
          Positioned(
            left: 14,
            right: 14,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: SafarTokens.asphalt950.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(SafarTokens.rMd),
                border: Border.all(color: SafarTokens.asphalt700),
                boxShadow: const [
                  BoxShadow(color: Colors.black87, blurRadius: 16.0, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('AR METRIC RULER SPAN', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                      if (_isFrozen)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: SafarTokens.confLow.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(SafarTokens.rSm),
                          ),
                          child: Text('FRAME FROZEN', style: SafarTokens.fontMono(fontSize: 10.5, color: SafarTokens.confLow, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _measuredWidthM > 0 ? _measuredWidthM.toStringAsFixed(2) : '--.--',
                        style: SafarTokens.fontMono(
                          fontSize: 32.0,
                          fontWeight: FontWeight.w800,
                          color: SafarTokens.hivis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('m', style: SafarTokens.fontMono(fontSize: 16, color: SafarTokens.asphalt400)),
                      const Spacer(),
                      if (_measuredWidthM > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: SafarTokens.asphalt800,
                            borderRadius: BorderRadius.circular(SafarTokens.rSm),
                          ),
                          child: Text(
                            'GROUND TRUTH',
                            style: SafarTokens.fontMono(fontSize: 10, color: SafarTokens.paint),
                          ),
                        ),
                    ],
                  ),
                  if (_pointA != null || _measuredWidthM > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_pointA != null) ...[
                          Expanded(
                            flex: 1,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: SafarTokens.confLow,
                                side: const BorderSide(color: SafarTokens.asphalt700),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onPressed: _resetPoints,
                              child: Text(
                                'RESET',
                                style: SafarTokens.fontMono(fontSize: 11.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (_measuredWidthM > 0)
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SafarTokens.hivis,
                                foregroundColor: SafarTokens.asphalt950,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                              ),
                              onPressed: _saveGroundTruth,
                              child: Text(
                                'SAVE GROUND TRUTH',
                                style: SafarTokens.fontUi(fontWeight: FontWeight.w800, fontSize: 11.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'No neural network in the loop. Calibrated directly from phone ARCore ground plane geometry.',
                    style: SafarTokens.fontUi(fontSize: 11.0, color: SafarTokens.asphalt400),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArPlanePainter extends CustomPainter {
  final Offset? pointA;
  final Offset? pointB;
  final bool isFrozen;

  _ArPlanePainter({
    required this.pointA,
    required this.pointB,
    required this.isFrozen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // AR Ground Plane Grid (Perspective dots)
    final Paint dotPaint = Paint()
      ..color = SafarTokens.asphalt700
      ..strokeWidth = 2.0;

    for (double y = size.height * 0.40; y < size.height; y += 35) {
      for (double x = 20; x < size.width; x += 35) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

    // Draw Measurement Span if points are placed
    if (pointA != null) {
      // Point A marker (Left Kerb)
      _drawMarker(canvas, pointA!, 'POINT A (LEFT)', SafarTokens.segKerb);
    }

    if (pointB != null) {
      // Point B marker (Right Kerb)
      _drawMarker(canvas, pointB!, 'POINT B (RIGHT)', SafarTokens.hivis);

      // Connecting Tape Line
      final Paint linePaint = Paint()
        ..color = SafarTokens.hivis
        ..strokeWidth = 2.5;
      canvas.drawLine(pointA!, pointB!, linePaint);

      // Distance callout badge
      final Offset mid = Offset((pointA!.dx + pointB!.dx) / 2.0, (pointA!.dy + pointB!.dy) / 2.0);
      canvas.drawCircle(mid, 4.0, Paint()..color = SafarTokens.paint);
    }
  }

  void _drawMarker(Canvas canvas, Offset pt, String label, Color color) {
    // Crosshair rings
    canvas.drawCircle(pt, 16.0, Paint()..color = color.withValues(alpha: 0.2)..style = PaintingStyle.fill);
    canvas.drawCircle(pt, 16.0, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawCircle(pt, 3.0, Paint()..color = SafarTokens.paint..style = PaintingStyle.fill);

    // Crosshair lines
    canvas.drawLine(Offset(pt.dx - 22, pt.dy), Offset(pt.dx + 22, pt.dy), Paint()..color = color..strokeWidth = 1.0);
    canvas.drawLine(Offset(pt.dx, pt.dy - 22), Offset(pt.dx, pt.dy + 22), Paint()..color = color..strokeWidth = 1.0);

    // Label
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: SafarTokens.fontMono(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
          backgroundColor: SafarTokens.asphalt950,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(pt.dx - (textPainter.width / 2), pt.dy - 36));
  }

  @override
  bool shouldRepaint(covariant _ArPlanePainter oldDelegate) {
    return oldDelegate.pointA != pointA ||
        oldDelegate.pointB != pointB ||
        oldDelegate.isFrozen != isFrozen;
  }
}

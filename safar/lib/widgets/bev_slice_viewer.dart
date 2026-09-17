// Bird's-Eye View (BEV) Slice Viewer Widget
// Displays top-down metric road probability raster & sub-pixel edge crossings
// Corresponding to files/ipm.py and files/measure.py

import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';
import '../models/transect.dart';

class BevSliceViewer extends StatelessWidget {
  final ChainageBin bin;
  final double halfWidthM;

  const BevSliceViewer({
    super.key,
    required this.bin,
    required this.halfWidthM,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt950,
        borderRadius: BorderRadius.circular(SafarTokens.rMd),
        border: Border.all(color: SafarTokens.asphalt700, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BEV RASTER SLICE (2 cm/px METRIC RASTER)',
                style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SafarTokens.asphalt800,
                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                ),
                child: Text(
                  'CH ${bin.chainageM.toStringAsFixed(1)} m',
                  style: SafarTokens.fontMono(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w600,
                    color: SafarTokens.hivis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12.0),

          // Visual BEV Canvas
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: _BevSlicePainter(
                widthM: bin.widthM,
                halfWidthM: halfWidthM,
                edgeLeft: bin.edgeLeft,
                edgeRight: bin.edgeRight,
                occludedFrac: bin.occludedFrac,
              ),
            ),
          ),
          const SizedBox(height: 12.0),

          // Telemetry details beneath BEV
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildDataCol('LEFT EDGE', bin.edgeLeft.toUpperCase(), SafarTokens.paint),
              _buildDataCol('WIDTH', '${bin.widthM.toStringAsFixed(2)} m', SafarTokens.hivis),
              _buildDataCol('RIGHT EDGE', bin.edgeRight.toUpperCase(), SafarTokens.paint),
              _buildDataCol('MAD', '${bin.madM.toStringAsFixed(3)} m', SafarTokens.asphalt400),
              _buildDataCol('FRAMES (n)', '${bin.n}', SafarTokens.asphalt400),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataCol(String title, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SafarTokens.microLabel()),
        const SizedBox(height: 2),
        Text(
          value,
          style: SafarTokens.fontMono(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _BevSlicePainter extends CustomPainter {
  final double widthM;
  final double halfWidthM;
  final String edgeLeft;
  final String edgeRight;
  final double occludedFrac;

  _BevSlicePainter({
    required this.widthM,
    required this.halfWidthM,
    required this.edgeLeft,
    required this.edgeRight,
    required this.occludedFrac,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double midX = size.width * 0.50;
    final double midY = size.height * 0.50;

    // Scale: 16m lateral extent total
    const double lateralExtentM = 14.0;
    final double pxPerM = size.width / lateralExtentM;

    final double roadHalfPx = (widthM / 2.0) * pxPerM;
    final double leftPx = midX - roadHalfPx;
    final double rightPx = midX + roadHalfPx;

    // Ground Grid Lines (1m grid)
    final Paint gridPaint = Paint()
      ..color = SafarTokens.asphalt800
      ..strokeWidth = 1.0;

    for (double m = -6.0; m <= 6.0; m += 1.0) {
      final double gx = midX + (m * pxPerM);
      canvas.drawLine(Offset(gx, 0), Offset(gx, size.height), gridPaint);
    }

    // Road Surface Raster Area
    final Rect roadRect = Rect.fromLTRB(leftPx, 18, rightPx, size.height - 18);
    final Paint roadFill = Paint()
      ..color = SafarTokens.segCarriageway.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    canvas.drawRect(roadRect, roadFill);

    // Left Edge Marker (Sub-pixel contour crossing)
    final Paint leftEdgePaint = Paint()
      ..color = edgeLeft == 'kerb' ? SafarTokens.segKerb : SafarTokens.segShoulder
      ..strokeWidth = 2.5;
    canvas.drawLine(Offset(leftPx, 10), Offset(leftPx, size.height - 10), leftEdgePaint);

    // Right Edge Marker
    final Paint rightEdgePaint = Paint()
      ..color = edgeRight == 'kerb'
          ? SafarTokens.segKerb
          : (edgeRight == 'occluded' ? SafarTokens.segOcclusion : SafarTokens.segMarking)
      ..strokeWidth = 2.5;
    canvas.drawLine(Offset(rightPx, 10), Offset(rightPx, size.height - 10), rightEdgePaint);

    // Centreline Spline
    final Paint centrePaint = Paint()
      ..color = SafarTokens.segMarking.withValues(alpha: 0.8)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(midX, 5), Offset(midX, size.height - 5), centrePaint);

    // Dimension Arrow and Width Callout
    final Paint arrowPaint = Paint()
      ..color = SafarTokens.hivis
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(leftPx, midY), Offset(rightPx, midY), arrowPaint);

    // Arrow tick marks at edges
    canvas.drawLine(Offset(leftPx, midY - 6), Offset(leftPx, midY + 6), arrowPaint);
    canvas.drawLine(Offset(rightPx, midY - 6), Offset(rightPx, midY + 6), arrowPaint);

    // Dimension Text: "7.24 m"
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${widthM.toStringAsFixed(2)} m',
        style: SafarTokens.fontMono(
          fontSize: 12.0,
          fontWeight: FontWeight.w700,
          color: SafarTokens.asphalt950,
          backgroundColor: SafarTokens.hivis,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(midX - (textPainter.width / 2.0), midY - (textPainter.height / 2.0)),
    );
  }

  @override
  bool shouldRepaint(covariant _BevSlicePainter oldDelegate) {
    return oldDelegate.widthM != widthM ||
        oldDelegate.halfWidthM != halfWidthM ||
        oldDelegate.edgeLeft != edgeLeft ||
        oldDelegate.edgeRight != edgeRight;
  }
}

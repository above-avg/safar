// Chainage Profile Chart Widget
// Width vs Chainage plot showing 90% confidence interval band,
// median width curve, and fire tender accessibility threshold.

import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';
import '../models/transect.dart';
import '../models/prediction.dart';

class ChainageProfileChart extends StatelessWidget {
  final List<ChainageBin> bins;
  final List<Prediction> predictions;
  final int? selectedIndex;
  final ValueChanged<int>? onSelectBin;

  const ChainageProfileChart({
    super.key,
    required this.bins,
    required this.predictions,
    this.selectedIndex,
    this.onSelectBin,
  });

  @override
  Widget build(BuildContext context) {
    if (bins.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('No chainage data available')),
      );
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt800,
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
                'WIDTH PROFILE (5 m CHAINAGE BINS)',
                style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
              ),
              Row(
                children: [
                  _buildLegendDot(SafarTokens.hivis, 'MEDIAN WIDTH'),
                  const SizedBox(width: 10),
                  _buildLegendDot(SafarTokens.hivis.withValues(alpha: 0.25), '90% INTERVAL'),
                  const SizedBox(width: 10),
                  _buildLegendDot(SafarTokens.confLow, '< 3.5 m PINCH'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) {
                    final double x = details.localPosition.dx;
                    final int tappedIdx = (x / constraints.maxWidth * bins.length).clamp(0, bins.length - 1).toInt();
                    onSelectBin?.call(tappedIdx);
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _ProfileChartPainter(
                      bins: bins,
                      predictions: predictions,
                      selectedIndex: selectedIndex,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: SafarTokens.fontMono(
            fontSize: 9.0,
            color: SafarTokens.asphalt400,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProfileChartPainter extends CustomPainter {
  final List<ChainageBin> bins;
  final List<Prediction> predictions;
  final int? selectedIndex;

  _ProfileChartPainter({
    required this.bins,
    required this.predictions,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty) return;

    // Determine Y range (road width from 0m to ~12m)
    const double minY = 1.0;
    const double maxY = 12.0;

    double toScreenY(double width) {
      final double normalized = (width - minY) / (maxY - minY);
      return size.height - (normalized * size.height).clamp(0.0, size.height);
    }

    double toScreenX(int index) {
      return (index / (bins.length - 1).clamp(1, 9999)) * size.width;
    }

    // Grid lines (3.5m emergency threshold, 7.0m standard two-lane, 10.0m highway)
    final Paint gridPaint = Paint()
      ..color = SafarTokens.asphalt700
      ..strokeWidth = 1.0;

    final Paint thresholdPaint = Paint()
      ..color = SafarTokens.confLow.withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 3.5m Fire tender threshold line (dashed)
    final double y35 = toScreenY(3.5);
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, y35), Offset(x + 5, y35), thresholdPaint);
    }

    // 7.0m standard grid line
    final double y70 = toScreenY(7.0);
    canvas.drawLine(Offset(0, y70), Offset(size.width, y70), gridPaint);

    // 90% Confidence Interval Shaded Envelope (Lo to Hi)
    final Path intervalPath = Path();
    final List<Offset> hiPoints = [];
    final List<Offset> loPoints = [];

    for (int i = 0; i < bins.length; i++) {
      final bin = bins[i];
      final pred = i < predictions.length ? predictions[i] : null;
      final double hw = pred?.halfWidthM ?? 0.30;
      final double lo = bin.widthM - hw;
      final double hi = bin.widthM + hw;

      final double x = toScreenX(i);
      hiPoints.add(Offset(x, toScreenY(hi)));
      loPoints.add(Offset(x, toScreenY(lo)));
    }

    intervalPath.moveTo(hiPoints.first.dx, hiPoints.first.dy);
    for (final pt in hiPoints) {
      intervalPath.lineTo(pt.dx, pt.dy);
    }
    for (int i = loPoints.length - 1; i >= 0; i--) {
      intervalPath.lineTo(loPoints[i].dx, loPoints[i].dy);
    }
    intervalPath.close();

    final Paint intervalFill = Paint()
      ..color = SafarTokens.hivis.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawPath(intervalPath, intervalFill);

    // Median Width Line
    final Path widthPath = Path();
    final Paint widthPaint = Paint()
      ..color = SafarTokens.hivis
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < bins.length; i++) {
      final double x = toScreenX(i);
      final double y = toScreenY(bins[i].widthM);
      if (i == 0) {
        widthPath.moveTo(x, y);
      } else {
        widthPath.lineTo(x, y);
      }
    }
    canvas.drawPath(widthPath, widthPaint);

    // Data points & selection highlight
    final Paint pointPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < bins.length; i++) {
      final double x = toScreenX(i);
      final double y = toScreenY(bins[i].widthM);
      final pred = i < predictions.length ? predictions[i] : null;

      final Color pointColor = pred?.tier == ConfidenceTier.low
          ? SafarTokens.confLow
          : (bins[i].widthM < 3.5 ? SafarTokens.confLow : SafarTokens.hivis);

      pointPaint.color = pointColor;

      if (i == selectedIndex) {
        // Highlight vertical guide
        final Paint guidePaint = Paint()
          ..color = SafarTokens.paint.withValues(alpha: 0.5)
          ..strokeWidth = 1.0;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), guidePaint);

        // Highlight ring
        canvas.drawCircle(Offset(x, y), 6.0, Paint()..color = SafarTokens.paint);
        canvas.drawCircle(Offset(x, y), 4.0, pointPaint);
      } else if (bins.length < 50 || i % 3 == 0) {
        canvas.drawCircle(Offset(x, y), 2.2, pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProfileChartPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex || oldDelegate.bins != bins;
  }
}

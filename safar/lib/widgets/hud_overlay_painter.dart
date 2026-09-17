// HUD Overlay Custom Painter
// Rendering the 3 toggleable layers over the road viewfinder.
// Strict compliance with Section 04 of System Plan (P02).
//
// When useDynamicEdges is true, the painter draws detected road edges
// from the frame processor instead of static hardcoded geometry.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';

class HudOverlayPainter extends CustomPainter {
  final bool showSegmentationTint; // Layer 1
  final bool showTransectLadder;   // Layer 2
  final bool showHudGraphics;      // Layer 3
  final double vanishingPointY;
  final double currentWidthM;
  final bool hasOcclusion;

  // Dynamic edge data from FrameProcessorService
  final List<List<double>> dynamicLeftEdge;   // Normalised [x, y] points
  final List<List<double>> dynamicRightEdge;
  final List<List<double>> dynamicMaskPoly;
  final List<double>? dynamicVP;              // Normalised [x, y]
  final bool useDynamicEdges;

  // Interactive Tap-to-Measure points
  final Offset? tapPointA;
  final Offset? tapPointB;
  final double? tapMeasuredDistanceM;

  HudOverlayPainter({
    required this.showSegmentationTint,
    required this.showTransectLadder,
    required this.showHudGraphics,
    this.vanishingPointY = 0.38,
    this.currentWidthM = 7.24,
    this.hasOcclusion = false,
    this.dynamicLeftEdge = const [],
    this.dynamicRightEdge = const [],
    this.dynamicMaskPoly = const [],
    this.dynamicVP,
    this.useDynamicEdges = false,
    this.tapPointA,
    this.tapPointB,
    this.tapMeasuredDistanceM,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double vpY = dynamicVP != null
        ? size.height * dynamicVP![1]
        : size.height * vanishingPointY;
    final double vpX = dynamicVP != null
        ? size.width * dynamicVP![0]
        : size.width * 0.50;

    // Measurement band Y positions (near = 5m, far = 15m)
    final double nearY = size.height * 0.88;
    final double farY = size.height * 0.52;

    // Static road boundaries at far edge of trusted band (fallback)
    final double farRoadHalfW = size.width * 0.16;
    final double farRoadL = vpX - farRoadHalfW;
    final double farRoadR = vpX + farRoadHalfW;

    // Interactive tap measurement overlay
    if (tapPointA != null) {
      _drawTapReticle(canvas, tapPointA!, 'POINT A', SafarTokens.segKerb);
    }
    if (tapPointB != null) {
      _drawTapReticle(canvas, tapPointB!, 'POINT B', SafarTokens.hivis);
    }
    if (tapPointA != null && tapPointB != null && tapMeasuredDistanceM != null) {
      _drawTapMeasureLine(canvas, tapPointA!, tapPointB!, tapMeasuredDistanceM!);
    }

    // LAYER 1: Semantic Segmentation Tint
    if (showSegmentationTint) {
      if (useDynamicEdges && dynamicMaskPoly.length >= 3) {
        // Dynamic carriageway mask from frame processor
        _drawDynamicCarriagewayMask(canvas, size);
      } else {
        // Static fallback
        _drawStaticCarriagewayMask(canvas, size, vpX, vpY, nearY, farY, farRoadL, farRoadR);
      }

      // Occlusion Hatch (if vehicle present)
      if (hasOcclusion) {
        _drawOcclusionHatch(canvas, size, vpX, nearY);
      }
    }

    // LAYER 2: Transect Ladder (Hi-Vis rungs every 1 m in the 5-15 m band)
    if (showTransectLadder) {
      if (useDynamicEdges && dynamicLeftEdge.length >= 2 && dynamicRightEdge.length >= 2) {
        _drawDynamicTransectLadder(canvas, size);
      } else {
        _drawStaticTransectLadder(canvas, size, vpX, nearY, farY, farRoadL, farRoadR);
      }

      // Band boundary labels
      _drawBandLabel(canvas, '15 m FAR LIMIT', Offset(farRoadL - 10, farY - 14));
      _drawBandLabel(canvas, '5 m NEAR LIMIT', Offset(vpX - size.width * 0.38, nearY + 6));
    }

    // LAYER 3: HUD Readout & Geometry Graphics
    if (showHudGraphics) {
      // Horizon Line
      final Paint horizonPaint = Paint()
        ..color = SafarTokens.asphalt500.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, vpY), Offset(size.width, vpY), horizonPaint);

      // Vanishing Point Crosshair
      final Paint vpPaint = Paint()
        ..color = SafarTokens.hivis
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(vpX - 12, vpY), Offset(vpX + 12, vpY), vpPaint);
      canvas.drawLine(Offset(vpX, vpY - 12), Offset(vpX, vpY + 12), vpPaint);
      canvas.drawCircle(Offset(vpX, vpY), 3.0, vpPaint);

      // VP indicator label
      if (dynamicVP != null) {
        _drawBandLabel(canvas, 'VP (LIVE)', Offset(vpX + 8, vpY - 14));
      }

      // Centreline Tangent Guide
      final Paint centreGuide = Paint()
        ..color = SafarTokens.hivis.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(vpX, size.height), Offset(vpX, vpY), centreGuide);

      // Dynamic edge lines (if available)
      if (useDynamicEdges) {
        _drawEdgeLines(canvas, size);
      }
    }
  }

  /// Draw the carriageway mask from dynamically detected edges.
  void _drawDynamicCarriagewayMask(Canvas canvas, Size size) {
    if (dynamicMaskPoly.length < 3) return;

    final Path maskPath = Path();
    maskPath.moveTo(
      dynamicMaskPoly[0][0] * size.width,
      dynamicMaskPoly[0][1] * size.height,
    );
    for (int i = 1; i < dynamicMaskPoly.length; i++) {
      maskPath.lineTo(
        dynamicMaskPoly[i][0] * size.width,
        dynamicMaskPoly[i][1] * size.height,
      );
    }
    maskPath.close();

    // Fill
    final Paint roadFill = Paint()
      ..color = SafarTokens.segCarriageway.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    canvas.drawPath(maskPath, roadFill);

    // Stroke
    final Paint roadStroke = Paint()
      ..color = SafarTokens.segCarriageway
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(maskPath, roadStroke);
  }

  /// Draw the static fallback carriageway mask.
  void _drawStaticCarriagewayMask(
    Canvas canvas, Size size,
    double vpX, double vpY, double nearY, double farY,
    double farRoadL, double farRoadR,
  ) {
    final Path roadBandPath = Path()
      ..moveTo(vpX - size.width * 0.38, nearY)
      ..lineTo(farRoadL, farY)
      ..lineTo(farRoadR, farY)
      ..lineTo(vpX + size.width * 0.38, nearY)
      ..close();

    final Paint roadFill = Paint()
      ..color = SafarTokens.segCarriageway.withValues(alpha: 0.30)
      ..style = PaintingStyle.fill;
    canvas.drawPath(roadBandPath, roadFill);

    final Paint roadStroke = Paint()
      ..color = SafarTokens.segCarriageway
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(roadBandPath, roadStroke);

    // Left Kerb
    final Paint kerbPaint = Paint()
      ..color = SafarTokens.segKerb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawLine(
      Offset(vpX - size.width * 0.40, size.height),
      Offset(vpX - size.width * 0.10, vpY),
      kerbPaint,
    );

    // Right Shoulder
    final Path shoulderPath = Path()
      ..moveTo(vpX + size.width * 0.38, nearY)
      ..lineTo(farRoadR, farY)
      ..lineTo(farRoadR + 25.0, farY)
      ..lineTo(vpX + size.width * 0.48, nearY)
      ..close();
    final Paint shoulderFill = Paint()
      ..color = SafarTokens.segShoulder.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    canvas.drawPath(shoulderPath, shoulderFill);

    // Dashed lane marking
    final Paint markingPaint = Paint()
      ..color = SafarTokens.segMarking
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (double t = 0.1; t < 0.9; t += 0.14) {
      final double y1 = farY + (nearY - farY) * t;
      final double y2 = farY + (nearY - farY) * (t + 0.08);
      canvas.drawLine(Offset(vpX, y1), Offset(vpX, y2), markingPaint);
    }
  }

  /// Draw the transect ladder using dynamically detected edge positions.
  void _drawDynamicTransectLadder(Canvas canvas, Size size) {
    final Paint ladderPaint = Paint()
      ..color = SafarTokens.hivis
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final Paint ladderCap = Paint()
      ..color = SafarTokens.paint
      ..style = PaintingStyle.fill;

    // Draw rungs at evenly spaced dynamic edge positions
    final int rungCount = math.min(dynamicLeftEdge.length, dynamicRightEdge.length);
    final int step = math.max(1, rungCount ~/ 10); // Show ~10 rungs

    for (int i = 0; i < rungCount; i += step) {
      final double leftX = dynamicLeftEdge[i][0] * size.width;
      final double leftY = dynamicLeftEdge[i][1] * size.height;
      final double rightX = dynamicRightEdge[i][0] * size.width;
      final double rightY = dynamicRightEdge[i][1] * size.height;

      // Average Y for the rung (should be very close)
      final double rungY = (leftY + rightY) / 2.0;

      canvas.drawLine(Offset(leftX, rungY), Offset(rightX, rungY), ladderPaint);
      canvas.drawCircle(Offset(leftX, rungY), 2.5, ladderCap);
      canvas.drawCircle(Offset(rightX, rungY), 2.5, ladderCap);
    }

    // Band boundary lines
    final Paint bandBoundaryPaint = Paint()
      ..color = SafarTokens.hivisDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    if (dynamicLeftEdge.isNotEmpty && dynamicRightEdge.isNotEmpty) {
      // Near limit (bottom)
      final nearLeft = dynamicLeftEdge.last;
      final nearRight = dynamicRightEdge.last;
      canvas.drawLine(
        Offset(nearLeft[0] * size.width - 20, nearLeft[1] * size.height),
        Offset(nearRight[0] * size.width + 20, nearRight[1] * size.height),
        bandBoundaryPaint,
      );

      // Far limit (top)
      final farLeft = dynamicLeftEdge.first;
      final farRight = dynamicRightEdge.first;
      canvas.drawLine(
        Offset(farLeft[0] * size.width - 20, farLeft[1] * size.height),
        Offset(farRight[0] * size.width + 20, farRight[1] * size.height),
        bandBoundaryPaint,
      );
    }
  }

  /// Draw the static fallback transect ladder.
  void _drawStaticTransectLadder(
    Canvas canvas, Size size,
    double vpX, double nearY, double farY,
    double farRoadL, double farRoadR,
  ) {
    final Paint ladderPaint = Paint()
      ..color = SafarTokens.hivis
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final Paint ladderCap = Paint()
      ..color = SafarTokens.paint
      ..style = PaintingStyle.fill;

    const int rungCount = 10;
    for (int i = 0; i <= rungCount; i++) {
      final double frac = i / rungCount.toDouble();
      final double pFrac = math.pow(frac, 1.4).toDouble();
      final double rungY = nearY - (nearY - farY) * pFrac;

      final double leftX = (vpX - size.width * 0.38) +
          (farRoadL - (vpX - size.width * 0.38)) * pFrac;
      final double rightX = (vpX + size.width * 0.38) +
          (farRoadR - (vpX + size.width * 0.38)) * pFrac;

      canvas.drawLine(Offset(leftX, rungY), Offset(rightX, rungY), ladderPaint);
      canvas.drawCircle(Offset(leftX, rungY), 2.5, ladderCap);
      canvas.drawCircle(Offset(rightX, rungY), 2.5, ladderCap);
    }

    // Band boundary lines
    final Paint bandBoundaryPaint = Paint()
      ..color = SafarTokens.hivisDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(farRoadL - 20, farY), Offset(farRoadR + 20, farY), bandBoundaryPaint);
    canvas.drawLine(Offset(vpX - size.width * 0.40, nearY), Offset(vpX + size.width * 0.40, nearY), bandBoundaryPaint);
  }

  /// Draw detected edge lines as continuous polylines.
  void _drawEdgeLines(Canvas canvas, Size size) {
    if (dynamicLeftEdge.length < 2 || dynamicRightEdge.length < 2) return;

    final Paint leftEdgePaint = Paint()
      ..color = SafarTokens.segKerb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final Paint rightEdgePaint = Paint()
      ..color = SafarTokens.segShoulder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Left edge polyline
    final Path leftPath = Path();
    leftPath.moveTo(
      dynamicLeftEdge[0][0] * size.width,
      dynamicLeftEdge[0][1] * size.height,
    );
    for (int i = 1; i < dynamicLeftEdge.length; i++) {
      leftPath.lineTo(
        dynamicLeftEdge[i][0] * size.width,
        dynamicLeftEdge[i][1] * size.height,
      );
    }
    canvas.drawPath(leftPath, leftEdgePaint);

    // Right edge polyline
    final Path rightPath = Path();
    rightPath.moveTo(
      dynamicRightEdge[0][0] * size.width,
      dynamicRightEdge[0][1] * size.height,
    );
    for (int i = 1; i < dynamicRightEdge.length; i++) {
      rightPath.lineTo(
        dynamicRightEdge[i][0] * size.width,
        dynamicRightEdge[i][1] * size.height,
      );
    }
    canvas.drawPath(rightPath, rightEdgePaint);
  }

  /// Draw occlusion hatch overlay.
  void _drawOcclusionHatch(Canvas canvas, Size size, double vpX, double nearY) {
    final Rect occRect = Rect.fromCenter(
      center: Offset(vpX + size.width * 0.24, nearY - 60),
      width: 70,
      height: 60,
    );
    final Paint occFill = Paint()
      ..color = SafarTokens.segOcclusion.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawRect(occRect, occFill);

    final Paint occStroke = Paint()
      ..color = SafarTokens.segOcclusion
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(occRect, occStroke);

    final Paint hatchPaint = Paint()
      ..color = SafarTokens.segOcclusion
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.save();
    canvas.clipRect(occRect);
    for (double d = -60; d < 120; d += 10) {
      canvas.drawLine(
        Offset(occRect.left + d, occRect.top),
        Offset(occRect.left + d + 30, occRect.bottom),
        hatchPaint,
      );
    }
    canvas.restore();
  }

  void _drawBandLabel(Canvas canvas, String text, Offset offset) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: SafarTokens.fontMono(
          fontSize: 9.0,
          fontWeight: FontWeight.w600,
          color: SafarTokens.hivisDim,
          letterSpacing: 0.08,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, offset);
  }

  void _drawTapReticle(Canvas canvas, Offset point, String label, Color color) {
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(point, 16.0, ringPaint);
    canvas.drawCircle(point, 3.0, dotPaint);

    // Crosshairs
    canvas.drawLine(Offset(point.dx - 22, point.dy), Offset(point.dx + 22, point.dy), ringPaint);
    canvas.drawLine(Offset(point.dx, point.dy - 22), Offset(point.dx, point.dy + 22), ringPaint);

    // Label badge above point
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: SafarTokens.fontMono(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromCenter(
      center: Offset(point.dx, point.dy - 28),
      width: textPainter.width + 10,
      height: textPainter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()..color = SafarTokens.asphalt950.withValues(alpha: 0.90),
    );
    textPainter.paint(canvas, Offset(point.dx - (textPainter.width / 2), point.dy - 28 - (textPainter.height / 2)));
  }

  void _drawTapMeasureLine(Canvas canvas, Offset a, Offset b, double distanceM) {
    final linePaint = Paint()
      ..color = SafarTokens.hivis
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(a, b, linePaint);

    // Center badge with distance
    final mid = Offset((a.dx + b.dx) / 2.0, (a.dy + b.dy) / 2.0);
    final badgeText = '${distanceM.toStringAsFixed(2)} m';
    final textPainter = TextPainter(
      text: TextSpan(
        text: badgeText,
        style: SafarTokens.fontMono(
          fontSize: 13.0,
          fontWeight: FontWeight.w900,
          color: SafarTokens.asphalt950,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromCenter(
      center: mid,
      width: textPainter.width + 14,
      height: textPainter.height + 6,
    );
    final bgPaint = Paint()..color = SafarTokens.hivis;
    canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(4)), bgPaint);
    textPainter.paint(canvas, Offset(mid.dx - textPainter.width / 2, mid.dy - textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant HudOverlayPainter oldDelegate) {
    return oldDelegate.showSegmentationTint != showSegmentationTint ||
        oldDelegate.showTransectLadder != showTransectLadder ||
        oldDelegate.showHudGraphics != showHudGraphics ||
        oldDelegate.currentWidthM != currentWidthM ||
        oldDelegate.hasOcclusion != hasOcclusion ||
        oldDelegate.useDynamicEdges != useDynamicEdges ||
        oldDelegate.dynamicLeftEdge != dynamicLeftEdge ||
        oldDelegate.dynamicRightEdge != dynamicRightEdge ||
        oldDelegate.dynamicVP != dynamicVP ||
        oldDelegate.tapPointA != tapPointA ||
        oldDelegate.tapPointB != tapPointB ||
        oldDelegate.tapMeasuredDistanceM != tapMeasuredDistanceM;
  }
}

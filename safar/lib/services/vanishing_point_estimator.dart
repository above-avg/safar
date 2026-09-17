// Vanishing Point Estimator
// Estimates camera pitch from the vanishing point location in the image.
// Uses a simplified Hough-line approach on the luminance gradient.
// Operates purely on Y-plane bytes, safe to call from Isolate.

import 'dart:math' as math;
import 'dart:typed_data';

class VanishingPointEstimate {
  /// Vanishing point X in normalised image coordinates (0..1).
  final double vpX;

  /// Vanishing point Y in normalised image coordinates (0..1).
  final double vpY;

  /// Estimated pitch in degrees (positive = camera nose-down).
  final double pitchDeg;

  /// Confidence: number of line intersections that voted for this VP.
  final int voteCount;

  const VanishingPointEstimate({
    required this.vpX,
    required this.vpY,
    required this.pitchDeg,
    required this.voteCount,
  });

  static const VanishingPointEstimate fallback = VanishingPointEstimate(
    vpX: 0.5,
    vpY: 0.38,
    pitchDeg: 6.0,
    voteCount: 0,
  );
}

class VanishingPointEstimator {
  /// Number of angular bins for simplified Hough accumulation.
  final int angleBins;

  /// Gradient magnitude threshold for edge pixel detection.
  final int edgeThreshold;

  /// Subsample factor: process every Nth row/column for speed.
  final int subsample;

  VanishingPointEstimator({
    this.angleBins = 180,
    this.edgeThreshold = 25,
    this.subsample = 4,
  });

  /// Estimate the vanishing point from Y-plane luminance.
  ///
  /// Returns a [VanishingPointEstimate] with normalised coordinates and pitch.
  /// The pitch is computed from VP position relative to the optical centre,
  /// using the FOV-based focal length guess.
  VanishingPointEstimate estimate({
    required Uint8List yPlane,
    required int width,
    required int height,
    double hfovDeg = 67.0,
  }) {
    // Compute gradient magnitudes and directions at subsampled points
    final List<double> edgeX = [];
    final List<double> edgeY = [];
    final List<double> edgeAngle = [];

    // Only process the top 60% of the image (VP is above horizon area)
    final int yLimit = (height * 0.6).round();

    for (int y = 1; y < yLimit - 1; y += subsample) {
      final int rowOffset = y * width;
      for (int x = 1; x < width - 1; x += subsample) {
        // Sobel gradient
        final int gx = -yPlane[rowOffset - width + x - 1]
            + yPlane[rowOffset - width + x + 1]
            - 2 * yPlane[rowOffset + x - 1]
            + 2 * yPlane[rowOffset + x + 1]
            - yPlane[rowOffset + width + x - 1]
            + yPlane[rowOffset + width + x + 1];

        final int gy = -yPlane[rowOffset - width + x - 1]
            - 2 * yPlane[rowOffset - width + x]
            - yPlane[rowOffset - width + x + 1]
            + yPlane[rowOffset + width + x - 1]
            + 2 * yPlane[rowOffset + width + x]
            + yPlane[rowOffset + width + x + 1];

        final double mag = math.sqrt(gx * gx + gy * gy.toDouble());
        if (mag > edgeThreshold) {
          edgeX.add(x.toDouble());
          edgeY.add(y.toDouble());
          // Gradient direction perpendicular to edge = the direction the edge runs
          edgeAngle.add(math.atan2(gy.toDouble(), gx.toDouble()));
        }
      }
    }

    if (edgeX.length < 10) {
      return VanishingPointEstimate.fallback;
    }

    // Use RANSAC-lite: pick pairs of edge points and find VP candidates.
    // For speed, we only try a limited number of random pairs.
    final rng = math.Random(42); // Deterministic for reproducibility
    final int maxPairs = math.min(200, edgeX.length * (edgeX.length - 1) ~/ 2);

    // Accumulator grid for VP voting (coarse grid)
    final int gridW = 20;
    final int gridH = 15;
    final voteCounts = Int32List(gridW * gridH);

    for (int iter = 0; iter < maxPairs; iter++) {
      final int i = rng.nextInt(edgeX.length);
      int j = rng.nextInt(edgeX.length);
      if (i == j) continue;

      // Two edge points with their perpendicular-to-edge directions
      // form two lines through the VP.
      final double x1 = edgeX[i], y1 = edgeY[i], a1 = edgeAngle[i];
      final double x2 = edgeX[j], y2 = edgeY[j], a2 = edgeAngle[j];

      // Filter: only consider near-vertical edges (road edges converging to VP)
      final double absA1 = a1.abs();
      final double absA2 = a2.abs();
      if (absA1 < 0.3 || absA1 > math.pi - 0.3) continue; // Skip near-horizontal
      if (absA2 < 0.3 || absA2 > math.pi - 0.3) continue;

      // Lines: point + direction perpendicular to gradient
      // Direction perpendicular to gradient: (-sin(a), cos(a))
      final double dx1 = -math.sin(a1), dy1 = math.cos(a1);
      final double dx2 = -math.sin(a2), dy2 = math.cos(a2);

      // Intersection via parametric: P1 + t*D1 = P2 + s*D2
      final double denom = dx1 * dy2 - dy1 * dx2;
      if (denom.abs() < 1e-6) continue;

      final double t = ((x2 - x1) * dy2 - (y2 - y1) * dx2) / denom;
      final double vpXPx = x1 + t * dx1;
      final double vpYPx = y1 + t * dy1;

      // Must be within reasonable image bounds
      if (vpXPx < 0 || vpXPx >= width || vpYPx < 0 || vpYPx >= height * 0.5) continue;

      // Vote in grid
      final int gx = (vpXPx / width * gridW).floor().clamp(0, gridW - 1);
      final int gy = (vpYPx / (height * 0.5) * gridH).floor().clamp(0, gridH - 1);
      voteCounts[gy * gridW + gx]++;
    }

    // Find grid cell with most votes
    int bestIdx = 0;
    int bestVotes = 0;
    for (int i = 0; i < voteCounts.length; i++) {
      if (voteCounts[i] > bestVotes) {
        bestVotes = voteCounts[i];
        bestIdx = i;
      }
    }

    if (bestVotes < 3) {
      return VanishingPointEstimate.fallback;
    }

    final int bestGY = bestIdx ~/ gridW;
    final int bestGX = bestIdx % gridW;
    final double vpXNorm = (bestGX + 0.5) / gridW;
    final double vpYNorm = (bestGY + 0.5) / gridH * 0.5; // Scale back from half-image

    // Compute pitch from VP position
    // VP at optical centre = 0 pitch. VP below centre = positive pitch (nose down).
    final double fPx = (width / 2.0) / math.tan((hfovDeg * math.pi / 180.0) / 2.0);
    final double cy = height / 2.0;
    final double vpYPx = vpYNorm * height;
    final double pitchRad = math.atan2(vpYPx - cy, fPx);
    final double pitchDeg = pitchRad * 180.0 / math.pi;

    return VanishingPointEstimate(
      vpX: vpXNorm,
      vpY: vpYNorm,
      pitchDeg: pitchDeg,
      voteCount: bestVotes,
    );
  }
}

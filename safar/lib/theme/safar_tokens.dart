// Safar Design Tokens
// Palette: "Asphalt & Hi-Vis"
// Reference points: worn asphalt, retroreflective lane paint,
// surveyor's marking spray, hi-vis safety vests, total-station LCDs.
// Deliberately NOT: purple/blue gradients, glassmorphism, neon cyan.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SafarTokens {
  SafarTokens._();

  // Neutrals: Asphalt (Dark - Field / HUD Context)
  static const Color asphalt950 = Color(0xFF0B0D0E);
  static const Color asphalt900 = Color(0xFF121517); // App background
  static const Color asphalt800 = Color(0xFF191D20); // Card / Surface
  static const Color asphalt700 = Color(0xFF22272B); // Raised elements
  static const Color asphalt600 = Color(0xFF2E353A); // Rules / Dividers
  static const Color asphalt500 = Color(0xFF434B52); // Subtle borders
  static const Color asphalt400 = Color(0xFF6B757D); // Muted text / Labels

  // Neutrals: Concrete (Light - Desk / Dashboard Context)
  static const Color concrete50 = Color(0xFFFAF8F3); // Warm light background
  static const Color concrete100 = Color(0xFFF1EDE4); // Raised
  static const Color concrete200 = Color(0xFFE2DCCE); // Rule
  static const Color concrete300 = Color(0xFFCBC3B1); // Border
  static const Color ink = Color(0xFF14171A); // Dark text
  static const Color fgMute = Color(0xFF6A6558); // Muted light text

  // Brand Accent: Hi-Vis
  // Fill/highlight only. Never body text on light backgrounds.
  static const Color hivis = Color(0xFFD9F24B);
  static const Color hivisDim = Color(0xFFB4CC2E);
  static const Color hivisDeep = Color(0xFF5F6D0C); // Accent text on light surfaces
  static const Color paint = Color(0xFFF5F2E9); // Retroreflective lane marking off-white

  // Confidence Tiers
  // Never the only channel - always pair with a label and icon.
  static const Color confHigh = Color(0xFF3FB68B); // <= 0.25 m half-width
  static const Color confMed = Color(0xFFE8A33D); // <= 0.60 m half-width
  static const Color confLow = Color(0xFFE0574B); // > 0.60 m half-width -> review queue
  static const Color confNone = Color(0xFF6B757D); // Uncalibrated / Unknown

  // Semantic Overlay (Camera & BEV)
  // Fills at 28-35% alpha, 2px stroke at 100%. Occlusion uses diagonal hatch + red.
  static const Color segCarriageway = Color(0xFF2FB6E8); // Cyan
  static const Color segMarking = Color(0xFFFFFFFF); // White
  static const Color segKerb = Color(0xFFD9F24B); // Hi-vis
  static const Color segShoulder = Color(0xFFF2A32C); // Amber
  static const Color segFootpath = Color(0xFFA87BE8); // Violet
  static const Color segMedian = Color(0xFFFF71B8); // Pink
  static const Color segOcclusion = Color(0xFFE0574B); // Red + hatch
  static const Color segVegetation = Color(0xFF56A96B); // Green
  static const Color segUnknown = Color(0xFF8A949C); // Grey

  // Width Heatmap (Sequential Map View)
  static const Color wRamp1 = Color(0xFF5C1F14); // < 3.0 m (Critical pinch point)
  static const Color wRamp2 = Color(0xFFA33B1E); // 3.0 - 5.5 m
  static const Color wRamp3 = Color(0xFFE0873A); // 5.5 - 7.0 m
  static const Color wRamp4 = Color(0xFFE8D06A); // 7.0 - 9.0 m
  static const Color wRamp5 = Color(0xFFA9CC4E); // 9.0 - 12.0 m
  static const Color wRamp6 = Color(0xFF4E9E6B); // > 12.0 m

  // Measurement HUD
  static const Color hudLine = hivis;
  static const Color hudCap = paint;
  static const Color hudBg = Color(0xDC0B0D0E); // rgba(11,13,14, 0.86)

  // Typography helpers
  // Archivo: UI, headings. Engineered feel.
  static TextStyle fontUi({
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    Color? backgroundColor,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.archivo(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      backgroundColor: backgroundColor,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  // IBM Plex Mono: Every number, coordinate, ID, unit, interval.
  // Tabular numbers rule is non-negotiable.
  static TextStyle fontMono({
    double fontSize = 14.0,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    Color? backgroundColor,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.ibmPlexMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      backgroundColor: backgroundColor,
      letterSpacing: letterSpacing ?? -0.01,
      height: height,
      fontFeatures: const [
        FontFeature.tabularFigures(),
        FontFeature.slashedZero(),
      ],
    );
  }

  // Surveyor Uppercase Micro-Label
  static TextStyle microLabel({Color color = asphalt400}) {
    return GoogleFonts.archivo(
      fontSize: 10.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.11,
      color: color,
    );
  }

  // Radii
  static const double rSm = 4.0;
  static const double rMd = 8.0;
  static const double rLg = 14.0;
  static const double rPill = 999.0;

  // Helper to get color for a measured road width
  static Color colorForWidth(double widthM) {
    if (widthM < 3.0) return wRamp1;
    if (widthM < 5.5) return wRamp2;
    if (widthM < 7.0) return wRamp3;
    if (widthM < 9.0) return wRamp4;
    if (widthM < 12.0) return wRamp5;
    return wRamp6;
  }

  // Helper to get confidence tier color
  static Color colorForConfidence(String tier) {
    switch (tier.toLowerCase()) {
      case 'high':
        return confHigh;
      case 'medium':
      case 'med':
        return confMed;
      case 'low':
        return confLow;
      default:
        return confNone;
    }
  }
}

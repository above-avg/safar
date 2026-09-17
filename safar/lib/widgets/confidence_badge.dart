// Confidence Badge Widget
// Always pairing color with explicit textual label and icon.
// Survives greyscale and colour-blindness as per tokens.css.

import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';

class ConfidenceBadge extends StatelessWidget {
  final String tier; // HIGH | MEDIUM | LOW
  final double? halfWidthM;
  final bool compact;

  const ConfidenceBadge({
    super.key,
    required this.tier,
    this.halfWidthM,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final String cleanTier = tier.toUpperCase();
    final Color badgeColor = SafarTokens.colorForConfidence(cleanTier);

    IconData iconData;
    String labelText;

    switch (cleanTier) {
      case 'HIGH':
        iconData = Icons.verified_outlined;
        labelText = 'HIGH';
        break;
      case 'MEDIUM':
      case 'MED':
        iconData = Icons.info_outline;
        labelText = 'MED';
        break;
      case 'LOW':
        iconData = Icons.warning_amber_outlined;
        labelText = 'LOW';
        break;
      default:
        iconData = Icons.help_outline;
        labelText = cleanTier;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6.0 : 8.0,
        vertical: compact ? 2.0 : 4.0,
      ),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(SafarTokens.rPill),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.7),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            iconData,
            size: compact ? 11.0 : 13.0,
            color: badgeColor,
          ),
          const SizedBox(width: 4.0),
          Text(
            labelText,
            style: SafarTokens.fontMono(
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w700,
              color: badgeColor,
              letterSpacing: 0.08,
            ),
          ),
          if (halfWidthM != null && !compact) ...[
            const SizedBox(width: 4.0),
            Text(
              '+/- ${halfWidthM!.toStringAsFixed(2)} m',
              style: SafarTokens.fontMono(
                fontSize: 10.0,
                fontWeight: FontWeight.w500,
                color: SafarTokens.asphalt400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Live Surveyor HUD Readout Card
// Strict compliance with Section 04 of System Plan (P02)
// Every number in mono, tabular figures. Digits never shift horizontally.

import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';
import 'confidence_badge.dart';

class LiveHudCard extends StatelessWidget {
  final double widthM;
  final double halfWidthM;
  final double chainageM;
  final String tier; // HIGH | MEDIUM | LOW
  final int observationCount;
  final double madM;
  final String edgeLeft;
  final String edgeRight;
  final double meanRangeM;
  final String calibSource;
  final double speedKmh; // Survey speed band: 25 - 55 km/h
  final double pitchDeg; // Per-frame VP pitch
  final double imuRms;
  final double gpsHdop;

  const LiveHudCard({
    super.key,
    required this.widthM,
    required this.halfWidthM,
    required this.chainageM,
    required this.tier,
    this.observationCount = 28,
    this.madM = 0.11,
    this.edgeLeft = 'KERB',
    this.edgeRight = 'PAINTED',
    this.meanRangeM = 9.4,
    this.calibSource = 'AR PLANE',
    this.speedKmh = 38.5,
    this.pitchDeg = 5.8,
    this.imuRms = 0.03,
    this.gpsHdop = 0.82,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSpeedValid = speedKmh >= 25.0 && speedKmh <= 55.0;
    final bool hasData = widthM > 0.01;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: SafarTokens.hudBg,
        borderRadius: BorderRadius.circular(SafarTokens.rLg),
        border: Border.all(
          color: SafarTokens.asphalt700,
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16.0,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Row: Carriageway + Chainage + Calibration
          Row(
            children: [
              Text(
                'CARRIAGEWAY',
                style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: SafarTokens.asphalt700,
                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                ),
                child: Text(
                  'CH ${chainageM.toStringAsFixed(0)} m',
                  style: SafarTokens.fontMono(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w600,
                    color: SafarTokens.paint,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: SafarTokens.asphalt700,
                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                ),
                child: Text(
                  calibSource,
                  style: SafarTokens.fontMono(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w600,
                    color: SafarTokens.hivisDim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4.0),

          // Primary Readout: Live Width
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hasData ? widthM.toStringAsFixed(2) : '--',
                style: SafarTokens.fontMono(
                  fontSize: 34.0,
                  fontWeight: FontWeight.w700,
                  color: hasData ? SafarTokens.hivis : SafarTokens.asphalt500,
                  letterSpacing: -0.03,
                ),
              ),
              const SizedBox(width: 4.0),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'm',
                  style: SafarTokens.fontMono(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w500,
                    color: SafarTokens.asphalt400,
                  ),
                ),
              ),
              const Spacer(),
              ConfidenceBadge(
                tier: tier,
                halfWidthM: halfWidthM,
              ),
            ],
          ),

          // Interval row -- wrapped to prevent overflow
          if (hasData)
            Text(
              '+/- ${halfWidthM.toStringAsFixed(2)} m | 90% | n=$observationCount',
              style: SafarTokens.fontMono(
                fontSize: 10.0,
                fontWeight: FontWeight.w500,
                color: SafarTokens.asphalt400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          if (!hasData)
            Text(
              'Waiting for measurement data...',
              style: SafarTokens.fontUi(
                fontSize: 11.0,
                color: SafarTokens.asphalt400,
              ),
            ),
          const SizedBox(height: 8.0),

          const Divider(color: SafarTokens.asphalt700, height: 1.0),
          const SizedBox(height: 8.0),

          // Surveyor Tags Row -- using Wrap for safe layout
          Wrap(
            spacing: 6.0,
            runSpacing: 5.0,
            children: [
              _buildTag('L: $edgeLeft', SafarTokens.paint),
              _buildTag('R: $edgeRight', SafarTokens.paint),
              _buildTag(
                '${speedKmh.toStringAsFixed(0)} km/h',
                isSpeedValid ? SafarTokens.paint : SafarTokens.confLow,
              ),
              _buildTag(
                '${pitchDeg >= 0 ? '+' : ''}${pitchDeg.toStringAsFixed(1)} deg',
                SafarTokens.paint,
              ),
              _buildTag('HDOP ${gpsHdop.toStringAsFixed(1)}', SafarTokens.asphalt400),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String label, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt700,
        borderRadius: BorderRadius.circular(SafarTokens.rPill),
        border: Border.all(color: SafarTokens.asphalt600, width: 0.6),
      ),
      child: Text(
        label,
        style: SafarTokens.fontMono(
          fontSize: 10.0,
          fontWeight: FontWeight.w600,
          color: textColor,
          letterSpacing: 0.04,
        ),
      ),
    );
  }
}

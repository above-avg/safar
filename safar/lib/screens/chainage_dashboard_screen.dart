// Chainage Dashboard Screen
// Route survey analysis, 5m chainage bins table, BEV slice inspector,
// and GeoJSON / CSV exports.

import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';
import '../models/survey_session.dart';
import '../models/transect.dart';
import '../models/prediction.dart';
import '../services/road_pipeline_service.dart';
import '../services/mock_survey_data.dart';
import '../widgets/chainage_profile_chart.dart';
import '../widgets/bev_slice_viewer.dart';
import '../widgets/confidence_badge.dart';

class ChainageDashboardScreen extends StatefulWidget {
  final SurveySession? session;

  const ChainageDashboardScreen({super.key, this.session});

  @override
  State<ChainageDashboardScreen> createState() => _ChainageDashboardScreenState();
}

class _ChainageDashboardScreenState extends State<ChainageDashboardScreen> {
  late SurveySession _session;
  int _selectedBinIndex = 0;
  String _filterTier = 'ALL';

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? MockSurveyData.createRuralSession();
    if (_session.bins.isNotEmpty) {
      _selectedBinIndex = 0;
    }
  }

  void _showExportDialog() {
    final String geoJsonData = RoadPipelineService.exportGeoJson(_session.bins, _session.predictions);
    final String csvData = RoadPipelineService.exportCsv(_session.bins, _session.predictions);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SafarTokens.asphalt800,
          title: Text(
            'EXPORT GEOSPATIAL DATA',
            style: SafarTokens.fontUi(
              fontSize: 14.0,
              fontWeight: FontWeight.w700,
              color: SafarTokens.hivis,
              letterSpacing: 0.08,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exports include metric road widths, 90% confidence intervals, modal edge types, and emergency vehicle passability flags.',
                style: SafarTokens.fontUi(fontSize: 12.0, color: SafarTokens.concrete100),
              ),
              const SizedBox(height: 16.0),
              _buildExportOption(
                title: 'GEOJSON (EPSG:4326 / WGS84)',
                subtitle: 'Vector point features for GIS and Web Dashboards',
                bytes: geoJsonData.length,
                onTap: () {
                  Navigator.pop(context);
                  _showRawPreviewDialog('GEOJSON OUTPUT', geoJsonData);
                },
              ),
              const SizedBox(height: 10.0),
              _buildExportOption(
                title: 'CSV RECORD TABLE',
                subtitle: 'Tabular chainage bins, coordinates, and MAD stats',
                bytes: csvData.length,
                onTap: () {
                  Navigator.pop(context);
                  _showRawPreviewDialog('CSV RECORD OUTPUT', csvData);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CLOSE', style: SafarTokens.fontMono(color: SafarTokens.asphalt400)),
            ),
          ],
        );
      },
    );
  }

  void _showRawPreviewDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SafarTokens.asphalt950,
          title: Text(
            title,
            style: SafarTokens.fontMono(fontSize: 13, color: SafarTokens.hivis, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: SafarTokens.fontMono(fontSize: 10.0, color: SafarTokens.concrete100),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('DONE', style: SafarTokens.fontMono(color: SafarTokens.hivis, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExportOption({
    required String title,
    required String subtitle,
    required int bytes,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SafarTokens.rSm),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: SafarTokens.asphalt900,
          borderRadius: BorderRadius.circular(SafarTokens.rSm),
          border: Border.all(color: SafarTokens.asphalt700),
        ),
        child: Row(
          children: [
            const Icon(Icons.file_download_outlined, color: SafarTokens.hivis, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SafarTokens.fontMono(fontSize: 11.5, fontWeight: FontWeight.w700, color: SafarTokens.paint)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: SafarTokens.fontUi(fontSize: 10.5, color: SafarTokens.asphalt400)),
                ],
              ),
            ),
            Text(
              '${(bytes / 1024).toStringAsFixed(1)} KB',
              style: SafarTokens.fontMono(fontSize: 10, color: SafarTokens.hivisDim),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ChainageBin? activeBin = _selectedBinIndex < _session.bins.length
        ? _session.bins[_selectedBinIndex]
        : null;

    final Prediction? activePred = _selectedBinIndex < _session.predictions.length
        ? _session.predictions[_selectedBinIndex]
        : null;

    // Filter bins
    final List<int> filteredIndices = [];
    for (int i = 0; i < _session.bins.length; i++) {
      final pred = i < _session.predictions.length ? _session.predictions[i] : null;
      if (_filterTier == 'ALL') {
        filteredIndices.add(i);
      } else if (_filterTier == 'HIGH' && pred?.tier == ConfidenceTier.high) {
        filteredIndices.add(i);
      } else if (_filterTier == 'LOW' && pred?.tier == ConfidenceTier.low) {
        filteredIndices.add(i);
      } else if (_filterTier == 'PINCH' && _session.bins[i].widthM < 3.5) {
        filteredIndices.add(i);
      }
    }

    return Scaffold(
      backgroundColor: SafarTokens.asphalt900,
      appBar: AppBar(
        title: Text(
          _session.title.toUpperCase(),
          style: SafarTokens.fontUi(
            fontSize: 13.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.08,
            color: SafarTokens.concrete50,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: SafarTokens.hivis),
            tooltip: 'Export GeoJSON and CSV',
            onPressed: _showExportDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1. Session Metrics Summary Cards (2 rows of 2 for ample space and no cramped text)
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'SURVEY DISTANCE',
                  '${(_session.distanceM).toStringAsFixed(0)} m',
                  'Continuous corridor',
                  SafarTokens.paint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricCard(
                  'MEAN ROAD WIDTH',
                  '${_session.meanWidthM.toStringAsFixed(2)} m',
                  'Clear traversable width',
                  SafarTokens.hivis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'HIGH CONFIDENCE',
                  '${_session.highConfidencePct.toStringAsFixed(1)}%',
                  'Calibrated <=0.25m interval',
                  SafarTokens.confHigh,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricCard(
                  'CHAINAGE BINS',
                  '${_session.bins.length} BINS',
                  '5m Median + MAD bins',
                  SafarTokens.paint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16.0),

          // 2. Instructions Guide Card
          _buildInstructionsGuide(),
          const SizedBox(height: 16.0),

          // 3. Width vs Chainage Profile Chart
          ChainageProfileChart(
            bins: _session.bins,
            predictions: _session.predictions,
            selectedIndex: _selectedBinIndex,
            onSelectBin: (idx) {
              setState(() => _selectedBinIndex = idx);
            },
          ),
          const SizedBox(height: 16.0),

          // 4. Active Selected Bin BEV Raster Slice
          if (activeBin != null) ...[
            BevSliceViewer(
              bin: activeBin,
              halfWidthM: activePred?.halfWidthM ?? 0.30,
            ),
            const SizedBox(height: 16.0),
          ],

          // 5. Chainage Bins Table Header & Filter Chips
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text('CHAINAGE RECORD (5 m BINS)', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildTableFilterChip('ALL'),
                  _buildTableFilterChip('HIGH'),
                  _buildTableFilterChip('LOW'),
                  _buildTableFilterChip('PINCH'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8.0),

          // 6. Chainage Bins List View
          Container(
            decoration: BoxDecoration(
              color: SafarTokens.asphalt800,
              borderRadius: BorderRadius.circular(SafarTokens.rMd),
              border: Border.all(color: SafarTokens.asphalt700),
            ),
            child: Column(
              children: [
                // Table header row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(
                    color: SafarTokens.asphalt950,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(SafarTokens.rMd)),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('CHAINAGE', style: SafarTokens.microLabel())),
                      Expanded(flex: 2, child: Text('WIDTH', style: SafarTokens.microLabel())),
                      Expanded(flex: 3, child: Text('90% INTERVAL', style: SafarTokens.microLabel())),
                      Expanded(flex: 2, child: Text('EDGES', style: SafarTokens.microLabel())),
                      Expanded(flex: 2, child: Text('TIER', style: SafarTokens.microLabel())),
                    ],
                  ),
                ),

                // Table data rows
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredIndices.length,
                  separatorBuilder: (context, idx) => const Divider(color: SafarTokens.asphalt700, height: 1),
                  itemBuilder: (context, listIdx) {
                    final int i = filteredIndices[listIdx];
                    final bin = _session.bins[i];
                    final pred = i < _session.predictions.length ? _session.predictions[i] : null;
                    final bool isSelected = i == _selectedBinIndex;
                    final bool isPinch = bin.widthM < 3.5;

                    return InkWell(
                      onTap: () => setState(() => _selectedBinIndex = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        color: isSelected ? SafarTokens.hivis.withValues(alpha: 0.14) : null,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${bin.chainageM.toStringAsFixed(0)} m',
                                style: SafarTokens.fontMono(
                                  fontSize: 12.0,
                                  color: isSelected ? SafarTokens.hivis : SafarTokens.paint,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${bin.widthM.toStringAsFixed(2)} m',
                                style: SafarTokens.fontMono(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: isPinch ? SafarTokens.confLow : SafarTokens.paint,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '+/- ${(pred?.halfWidthM ?? 0.30).toStringAsFixed(2)} m',
                                style: SafarTokens.fontMono(
                                  fontSize: 11.0,
                                  color: SafarTokens.asphalt400,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${bin.edgeLeft.substring(0, 1).toUpperCase()}/${bin.edgeRight.substring(0, 1).toUpperCase()}',
                                style: SafarTokens.fontMono(fontSize: 11.5, color: SafarTokens.concrete300),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: ConfidenceBadge(
                                tier: pred?.tier.name ?? 'MEDIUM',
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsGuide() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt800,
        borderRadius: BorderRadius.circular(SafarTokens.rMd),
        border: const Border(
          left: BorderSide(color: SafarTokens.hivis, width: 3.5),
          top: BorderSide(color: SafarTokens.asphalt700),
          right: BorderSide(color: SafarTokens.asphalt700),
          bottom: BorderSide(color: SafarTokens.asphalt700),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: SafarTokens.hivis, size: 16),
              const SizedBox(width: 6),
              Text(
                'HOW TO READ THE CHAINAGE PROFILE',
                style: SafarTokens.fontMono(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: SafarTokens.hivis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '- Chainage: Distance measured along the road alignment starting at 0.0 m.\n'
            '- 5m Bins: Median road width computed every 5 meters to eliminate parked vehicles and transient occlusions.\n'
            '- 3.5m Red Line: Critical threshold for emergency fire tender clearance. Anything below this line is an impassable pinch point.\n'
            '- Blue Shaded Envelope: 90% Split Conformal confidence interval. A narrower envelope indicates higher measurement certainty.\n'
            '- Tap any point on the chart or row in the table to inspect its 2cm/px top-down BEV slice.',
            style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete200, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, String subtitle, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt800,
        borderRadius: BorderRadius.circular(SafarTokens.rSm),
        border: Border.all(color: SafarTokens.asphalt700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
          const SizedBox(height: 4),
          Text(
            value,
            style: SafarTokens.fontMono(
              fontSize: 18.0,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: SafarTokens.fontUi(
              fontSize: 10.5,
              color: SafarTokens.concrete300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableFilterChip(String label) {
    final bool isSelected = _filterTier == label;
    return GestureDetector(
      onTap: () => setState(() => _filterTier = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
        decoration: BoxDecoration(
          color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt800,
          borderRadius: BorderRadius.circular(SafarTokens.rSm),
          border: Border.all(
            color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt700,
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
}

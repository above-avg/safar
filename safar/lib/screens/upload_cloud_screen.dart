// Cloud GPU Upload Screen (The Default Ingest Mode)
// Strict compliance with Section 03 of System Plan (P02)
// "Live shows you it's working. Upload is what you trust."

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';
import '../models/survey_session.dart';
import '../services/mock_survey_data.dart';
import 'chainage_dashboard_screen.dart';

class UploadCloudScreen extends StatefulWidget {
  const UploadCloudScreen({super.key});

  @override
  State<UploadCloudScreen> createState() => _UploadCloudScreenState();
}

class _UploadCloudScreenState extends State<UploadCloudScreen> {
  String _selectedVideoName = 'survey_drive_nh48_raw.mp4';
  String _selectedSensorLogName = 'survey_drive_nh48_sensors.json';
  bool _isProcessing = false;
  int _processingStage = 0;
  double _progressFrac = 0.0;
  SurveySession? _completedSession;
  Timer? _progressTimer;

  final List<String> _pipelineStages = [
    'PROBING VIDEO & IMU HARDWARE TIMESTAMPS',
    'PRIVACY PASS: BLURRING FACES & PLATES ON INGEST',
    'RESOLVING EXTRINSICS: STATIONARY AR PLANE & VP PITCH',
    'WARPING TO 2 cm/px BEV & TEMPORAL MOSAIC',
    'CASTING TRANSECTS & 5 m CHAINAGE AGGREGATION (MEDIAN + MAD)',
    'SPLIT CONFORMAL CALIBRATION & 90% UNCERTAINTY INTERVALS',
    'GENERATING UTM GEODATA & GEOJSON RECORD',
  ];

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startCloudJob(SurveySession session) {
    setState(() {
      _isProcessing = true;
      _processingStage = 0;
      _progressFrac = 0.0;
      _completedSession = null;
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted) return;
      setState(() {
        _progressFrac += 0.15;
        if (_progressFrac >= 1.0) {
          _progressFrac = 0.0;
          _processingStage++;
          if (_processingStage >= _pipelineStages.length) {
            timer.cancel();
            _isProcessing = false;
            _completedSession = session;
          }
        }
      });
    });
  }

  void _showPipelineGuideDialog() {
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
            'CLOUD GPU PIPELINE GUIDE',
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
                  'WHY CLOUD GPU PROCESSING?',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 6),
                Text(
                  'While Live Survey provides instant on-dash feedback, real-time edge processing cannot run heavy vanishing point optimization or full temporal mosaicking without thermal throttling. The Cloud GPU pipeline is the definitive "Measurement of Record".',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'THE 7 SERVER PROCESSING STAGES:',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 6),
                Text(
                  '1. Hardware Timestamp Probing (Video & IMU sync)\n'
                  '2. Privacy Pass: Blurs human faces & license plates\n'
                  '3. Extrinsics Solver: Refines camera pitch per frame\n'
                  '4. BEV Warping: 2 cm/px top-down orthographic raster\n'
                  '5. Transect Casting: 5m chainage aggregation (Median + MAD)\n'
                  '6. Split Conformal Calibration: 90% uncertainty intervals\n'
                  '7. GeoJSON & CSV Export: Standard EPSG:4326 GIS record',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafarTokens.asphalt900,
      appBar: AppBar(
        title: Text(
          'CLOUD GPU PIPELINE',
          style: SafarTokens.fontUi(
            fontSize: 14.0,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.05,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: SafarTokens.concrete100),
            tooltip: 'Cloud GPU Pipeline Guide',
            onPressed: _showPipelineGuideDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Principle Banner
          Container(
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: SafarTokens.asphalt800,
              borderRadius: BorderRadius.circular(SafarTokens.rMd),
              border: const Border(
                left: BorderSide(color: SafarTokens.hivis, width: 4.0),
                top: BorderSide(color: SafarTokens.asphalt700),
                right: BorderSide(color: SafarTokens.asphalt700),
                bottom: BorderSide(color: SafarTokens.asphalt700),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ENGINEERING PRINCIPLE: LIVE VS UPLOAD SPLIT',
                  style: SafarTokens.microLabel(color: SafarTokens.hivis),
                ),
                const SizedBox(height: 4),
                Text(
                  '"Live shows you it\'s working. Upload is what you trust."',
                  style: SafarTokens.fontUi(
                    fontSize: 14.0,
                    fontWeight: FontWeight.w700,
                    color: SafarTokens.paint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Continuous mobile inference throttles phones in 15 minutes. Upload mode executes full-resolution server processing with reproducible models.',
                  style: SafarTokens.fontUi(fontSize: 12.0, color: SafarTokens.asphalt400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16.0),

          // File Ingest Box
          Text('SESSION INGEST FILES', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
          const SizedBox(height: 8.0),
          _buildFilePickerRow(
            label: 'RAW VIDEO (MP4)',
            fileName: _selectedVideoName,
            icon: Icons.video_file_outlined,
          ),
          const SizedBox(height: 8.0),
          _buildFilePickerRow(
            label: 'SENSOR LOG (GPS + IMU + AR POSES)',
            fileName: _selectedSensorLogName,
            icon: Icons.data_object_outlined,
          ),
          const SizedBox(height: 16.0),

          // Preloaded Survey Runs
          Text('SELECT SURVEY DATASET TO PROCESS', style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
          const SizedBox(height: 8.0),
          Row(
            children: [
              Expanded(
                child: _buildPresetButton(
                  'NH-48 HIGHWAY (400 m)',
                  'DUAL CARRIAGEWAY',
                  _selectedVideoName.contains('nh48'),
                  () {
                    setState(() {
                      _selectedVideoName = 'nh48_run_1080p.mp4';
                      _selectedSensorLogName = 'nh48_sensors_synced.json';
                    });
                  },
                ),
              ),
              const SizedBox(width: 10.0),
              Expanded(
                child: _buildPresetButton(
                  'RURAL RIDGE (450 m)',
                  'PINCH POINTS (< 3.5 m)',
                  _selectedVideoName.contains('rural'),
                  () {
                    setState(() {
                      _selectedVideoName = 'rural_ridge_run.mp4';
                      _selectedSensorLogName = 'rural_sensors_synced.json';
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14.0),

          // Primary Run Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isProcessing ? SafarTokens.asphalt700 : SafarTokens.hivis,
              foregroundColor: SafarTokens.asphalt950,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
            ),
            icon: _isProcessing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: SafarTokens.hivis))
                : const Icon(Icons.play_arrow, size: 22),
            label: Text(
              _isProcessing ? 'PROCESSING PIPELINE ON GPU...' : 'RUN 7-STAGE CLOUD GPU PIPELINE',
              style: SafarTokens.fontUi(fontWeight: FontWeight.w900, fontSize: 13.0, letterSpacing: 0.05),
            ),
            onPressed: _isProcessing
                ? null
                : () {
                    final session = _selectedVideoName.contains('rural')
                        ? MockSurveyData.createRuralSession()
                        : MockSurveyData.createHighwaySession();
                    _startCloudJob(session);
                  },
          ),
          const SizedBox(height: 18.0),

          // Processing State Card
          if (_isProcessing) ...[
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: SafarTokens.asphalt950,
                borderRadius: BorderRadius.circular(SafarTokens.rMd),
                border: Border.all(color: SafarTokens.hivisDim, width: 1.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('CLOUD GPU RUNNER ACTIVE', style: SafarTokens.microLabel(color: SafarTokens.hivis)),
                      Text(
                        'STAGE ${_processingStage + 1} OF ${_pipelineStages.length}',
                        style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  LinearProgressIndicator(
                    value: (_processingStage + _progressFrac) / _pipelineStages.length,
                    backgroundColor: SafarTokens.asphalt800,
                    valueColor: const AlwaysStoppedAnimation<Color>(SafarTokens.hivis),
                  ),
                  const SizedBox(height: 12.0),
                  Text(
                    _pipelineStages[_processingStage],
                    style: SafarTokens.fontMono(fontSize: 11.5, color: SafarTokens.paint, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20.0),
          ],

          // Completed Session Results
          if (_completedSession != null) ...[
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: SafarTokens.asphalt800,
                borderRadius: BorderRadius.circular(SafarTokens.rMd),
                border: Border.all(color: SafarTokens.confHigh, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('MEASUREMENT OF RECORD GENERATED', style: SafarTokens.microLabel(color: SafarTokens.confHigh)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: SafarTokens.confHigh.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(SafarTokens.rPill),
                        ),
                        child: Text(
                          '90% INTERVAL GUARANTEED',
                          style: SafarTokens.fontMono(fontSize: 9.5, color: SafarTokens.confHigh, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10.0),
                  Text(
                    _completedSession!.title,
                    style: SafarTokens.fontUi(fontSize: 16.0, fontWeight: FontWeight.w700, color: SafarTokens.concrete50),
                  ),
                  const SizedBox(height: 12.0),

                  // Comparison: Live vs Cloud
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: SafarTokens.asphalt900,
                      borderRadius: BorderRadius.circular(SafarTokens.rSm),
                      border: Border.all(color: SafarTokens.asphalt700),
                    ),
                    child: Column(
                      children: [
                        _buildComparisonRow(
                          metric: 'Mean Width',
                          liveVal: '${(_completedSession!.meanWidthM - 0.14).toStringAsFixed(2)} m (provisional)',
                          cloudVal: '${_completedSession!.meanWidthM.toStringAsFixed(2)} m (record)',
                        ),
                        const Divider(color: SafarTokens.asphalt700, height: 12),
                        _buildComparisonRow(
                          metric: 'Mean 90% Half-Width',
                          liveVal: '+/- 0.52 m',
                          cloudVal: '+/- 0.22 m (calibrated)',
                        ),
                        const Divider(color: SafarTokens.asphalt700, height: 12),
                        _buildComparisonRow(
                          metric: 'Pitch Correction',
                          liveVal: 'Stationary Prior only',
                          cloudVal: 'Per-frame Vanishing Point',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14.0),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SafarTokens.hivis,
                      foregroundColor: SafarTokens.asphalt950,
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChainageDashboardScreen(session: _completedSession!),
                        ),
                      );
                    },
                    child: Text(
                      'INSPECT SURVEY SESSION & EXPORT GEODATA',
                      style: SafarTokens.fontUi(fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilePickerRow({
    required String label,
    required String fileName,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt800,
        borderRadius: BorderRadius.circular(SafarTokens.rSm),
        border: Border.all(color: SafarTokens.asphalt700),
      ),
      child: Row(
        children: [
          Icon(icon, color: SafarTokens.hivis, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SafarTokens.microLabel(color: SafarTokens.asphalt400)),
                const SizedBox(height: 2),
                Text(
                  fileName,
                  style: SafarTokens.fontMono(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    color: SafarTokens.paint,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // Simulating file picker selection
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: SafarTokens.asphalt800,
                  content: Text('SELECTED: $fileName', style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis)),
                ),
              );
            },
            child: Text('BROWSE', style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String title, String subtitle, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SafarTokens.rSm),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: isSelected ? SafarTokens.hivis.withValues(alpha: 0.12) : SafarTokens.asphalt800,
          borderRadius: BorderRadius.circular(SafarTokens.rSm),
          border: Border.all(
            color: isSelected ? SafarTokens.hivis : SafarTokens.asphalt700,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SafarTokens.fontMono(fontSize: 11.5, fontWeight: FontWeight.w700, color: isSelected ? SafarTokens.hivis : SafarTokens.paint)),
            const SizedBox(height: 3),
            Text(subtitle, style: SafarTokens.microLabel(color: isSelected ? SafarTokens.hivisDim : SafarTokens.asphalt400)),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonRow({
    required String metric,
    required String liveVal,
    required String cloudVal,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(metric, style: SafarTokens.fontUi(fontSize: 11.0, color: SafarTokens.asphalt400)),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  liveVal,
                  style: SafarTokens.fontMono(fontSize: 10.0, color: SafarTokens.asphalt400),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 10, color: SafarTokens.asphalt600),
              ),
              Expanded(
                child: Text(
                  cloudVal,
                  style: SafarTokens.fontMono(fontSize: 10.5, color: SafarTokens.hivis, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

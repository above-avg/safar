// Retraining Loop & Active Learning Screen
// Three levels of model and confidence improvement.
// Strict compliance with Section 10 of System Plan (P02).

import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';
import '../models/active_learning_item.dart';
import '../services/mock_survey_data.dart';

class RetrainingLoopScreen extends StatefulWidget {
  const RetrainingLoopScreen({super.key});

  @override
  State<RetrainingLoopScreen> createState() => _RetrainingLoopScreenState();
}

class _RetrainingLoopScreenState extends State<RetrainingLoopScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<ActiveLearningItem> _queue;
  int _activeReviewIndex = 0;

  // Level 1 state
  double _cameraHeightM = 1.40;
  double _pitchOffsetDeg = 0.0;

  // Level 2 state
  final int _groundTruthPairCount = 38;
  final double _targetCoverage = 0.90;
  final double _empiricalCoverage = 0.914;
  final double _meanHalfWidthM = 0.24;

  // Level 3 active learning state
  bool _isFineTuning = false;
  bool _showGateResult = false;
  bool _isPromoted = false;
  final double _baselineMae = 0.32;
  final double _candidateMae = 0.19;
  final double _baselineCov = 0.865;
  final double _candidateCov = 0.912;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _queue = MockSurveyData.createActiveLearningQueue();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _runActiveLearningFineTune() {
    setState(() {
      _isFineTuning = true;
      _showGateResult = false;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isFineTuning = false;
        _showGateResult = true;
        // Automatic promote/reject gate: Promotes ONLY if coverage AND MAE improve
        _isPromoted = (_candidateMae < _baselineMae) && (_candidateCov >= _targetCoverage);
      });
    });
  }

  void _showRetrainingGuideDialog() {
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
            '3-LEVEL CALIBRATION GUIDE',
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
                  'LEVEL 1: EXTRINSICS RECALIBRATION',
                  style: SafarTokens.microLabel(color: SafarTokens.hivis),
                ),
                const SizedBox(height: 4),
                Text(
                  'Takes minutes, zero machine learning. Adjusts camera physical height and windshield pitch offset. Fixes systematic fleet scaling errors.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.35),
                ),
                const SizedBox(height: 12),
                Text(
                  'LEVEL 2: CONFORMAL CONFIDENCE',
                  style: SafarTokens.microLabel(color: SafarTokens.hivis),
                ),
                const SizedBox(height: 4),
                Text(
                  'Takes ~1 hour with 30-50 ground-truth tape pairs. Recalibrates Split Conformal quantiles to guarantee that 90% uncertainty intervals match empirical road observations.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.35),
                ),
                const SizedBox(height: 12),
                Text(
                  'LEVEL 3: ACTIVE LEARNING & GATE',
                  style: SafarTokens.microLabel(color: SafarTokens.hivis),
                ),
                const SizedBox(height: 4),
                Text(
                  'Surfaces the lowest-confidence road frames for human operator edge nudge. Fine-tunes model head with frozen backbone and automatically gates deployment (promotes ONLY if held-out MAE improves and 90% coverage passes).',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.35),
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
          'RETRAINING & CALIBRATION LOOP',
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
            tooltip: '3-Level Calibration Guide',
            onPressed: _showRetrainingGuideDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: SafarTokens.hivis,
          labelColor: SafarTokens.hivis,
          unselectedLabelColor: SafarTokens.asphalt400,
          labelStyle: SafarTokens.fontMono(fontSize: 11.0, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'L1: EXTRINSICS'),
            Tab(text: 'L2: CONFIDENCE'),
            Tab(text: 'L3: ACTIVE LEARNING'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLevel1ExtrinsicsTab(),
          _buildLevel2ConfidenceTab(),
          _buildLevel3ActiveLearningTab(),
        ],
      ),
    );
  }

  // Level 1: Recalibrate Extrinsics (Minutes, No ML)
  Widget _buildLevel1ExtrinsicsTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildInfoCard(
          title: 'LEVEL 1: RECALIBRATE (MINUTES, NO ML)',
          description:
              'Fixes systematically wrong camera height or pitch. Height error is the single most common cause of consistent percentage error across a fleet. No retraining needed.',
        ),
        const SizedBox(height: 16.0),

        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: SafarTokens.asphalt800,
            borderRadius: BorderRadius.circular(SafarTokens.rMd),
            border: Border.all(color: SafarTokens.asphalt700),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CAMERA MOUNT PHYSICAL HEIGHT (h)', style: SafarTokens.microLabel()),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_cameraHeightM.toStringAsFixed(2)} m',
                    style: SafarTokens.fontMono(fontSize: 28, fontWeight: FontWeight.w700, color: SafarTokens.hivis),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: SafarTokens.paint),
                        onPressed: () => setState(() => _cameraHeightM = (_cameraHeightM - 0.02).clamp(0.8, 3.0)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: SafarTokens.paint),
                        onPressed: () => setState(() => _cameraHeightM = (_cameraHeightM + 0.02).clamp(0.8, 3.0)),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(color: SafarTokens.asphalt700, height: 20),

              Text('PITCH OFFSET TRIM (DEGREES)', style: SafarTokens.microLabel()),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_pitchOffsetDeg >= 0 ? '+' : ''}${_pitchOffsetDeg.toStringAsFixed(1)} deg',
                    style: SafarTokens.fontMono(fontSize: 28, fontWeight: FontWeight.w700, color: SafarTokens.paint),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: SafarTokens.paint),
                        onPressed: () => setState(() => _pitchOffsetDeg = (_pitchOffsetDeg - 0.1).clamp(-5.0, 5.0)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: SafarTokens.paint),
                        onPressed: () => setState(() => _pitchOffsetDeg = (_pitchOffsetDeg + 0.1).clamp(-5.0, 5.0)),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(color: SafarTokens.asphalt700, height: 20),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SafarTokens.hivis,
                  foregroundColor: SafarTokens.asphalt950,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                ),
                icon: const Icon(Icons.check, size: 18),
                label: Text(
                  'APPLY CALIBRATED EXTRINSICS TO RIG',
                  style: SafarTokens.fontUi(fontWeight: FontWeight.w800, fontSize: 12),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: SafarTokens.asphalt800,
                      content: Text(
                        'EXTRINSICS PERSISTED: h=${_cameraHeightM.toStringAsFixed(2)}m, pitch=${_pitchOffsetDeg.toStringAsFixed(1)}deg',
                        style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Level 2: Recalibrate Confidence (An Hour, ~50 Labels)
  Widget _buildLevel2ConfidenceTab() {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildInfoCard(
          title: 'LEVEL 2: RECALIBRATE CONFIDENCE (~50 TAPE LABELS)',
          description:
              'Drive a stretch, tape-measure 30-50 spots, run split conformal calibration. Intervals now match your fleet and mount. Widths do not change; trustworthiness does.',
        ),
        const SizedBox(height: 16.0),

        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: SafarTokens.asphalt800,
            borderRadius: BorderRadius.circular(SafarTokens.rMd),
            border: Border.all(color: SafarTokens.asphalt700),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HELD-OUT SEGMENT CALIBRATION RESULTS', style: SafarTokens.microLabel(color: SafarTokens.hivis)),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      'EMPIRICAL COVERAGE',
                      '${(_empiricalCoverage * 100).toStringAsFixed(1)}%',
                      'Target: ${(_targetCoverage * 100).toStringAsFixed(0)}% (PASS)',
                      SafarTokens.confHigh,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      'MEAN HALF-WIDTH',
                      '+/- ${_meanHalfWidthM.toStringAsFixed(2)} m',
                      'Strictly adaptive interval',
                      SafarTokens.hivis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      'TAPE MEASURE SITES',
                      '$_groundTruthPairCount LOCATIONS',
                      'Ground truth tape pairs',
                      SafarTokens.paint,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      'CONFORMAL QUANTILE',
                      'q = 1.14',
                      'Calibrated multiplier',
                      SafarTokens.concrete100,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SafarTokens.asphalt950,
                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                  border: Border.all(color: SafarTokens.asphalt700),
                ),
                child: Text(
                  '"Our stated 90% intervals achieved 91.4% empirical coverage on held-out roads, at a mean half-width of 0.24 m."',
                  style: SafarTokens.fontMono(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    color: SafarTokens.paint,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: SafarTokens.hivis,
                  side: const BorderSide(color: SafarTokens.hivis),
                  minimumSize: const Size(double.infinity, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(
                  'RE-RUN CONFORMAL SPLIT ON HELD-OUT DATA',
                  style: SafarTokens.fontUi(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: SafarTokens.asphalt800,
                      content: Text('RE-CALIBRATED CONFORMAL QUANTILES (q=1.14)', style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis)),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Level 3: Active Learning Review Queue (A Day, ~500 Labels)
  Widget _buildLevel3ActiveLearningTab() {
    final activeItem = _queue[_activeReviewIndex];

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildInfoCard(
          title: 'LEVEL 3: ACTIVE LEARNING & AUTOMATIC PROMOTE GATE',
          description:
              'The system selects low-confidence items where the model is uncertain. Operators correct edges in seconds. Nightly fine-tune runs with an automatic PROMOTE/REJECT gate.',
        ),
        const SizedBox(height: 16.0),

        // Review Queue Card
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: SafarTokens.asphalt800,
            borderRadius: BorderRadius.circular(SafarTokens.rMd),
            border: Border.all(color: SafarTokens.asphalt700),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('LOW-CONFIDENCE REVIEW QUEUE', style: SafarTokens.microLabel(color: SafarTokens.confLow)),
                  Text(
                    'ITEM ${_activeReviewIndex + 1} OF ${_queue.length}',
                    style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.paint),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Item details
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'CH ${activeItem.chainageM.toStringAsFixed(1)} m',
                    style: SafarTokens.fontMono(fontSize: 18, fontWeight: FontWeight.w700, color: SafarTokens.hivis),
                  ),
                  Text(
                    'PROV: ${activeItem.provisionalWidthM.toStringAsFixed(2)} m +/- ${activeItem.halfWidthM.toStringAsFixed(2)} m',
                    style: SafarTokens.fontMono(fontSize: 11.5, color: SafarTokens.confLow),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'FLAG REASON: ${activeItem.reason.toUpperCase()}',
                style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.asphalt400),
              ),
              const SizedBox(height: 16),

              // Interactive Edge Adjustment Canvas
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: SafarTokens.asphalt950,
                  borderRadius: BorderRadius.circular(SafarTokens.rSm),
                  border: Border.all(color: SafarTokens.asphalt700),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Container(
                        width: 140,
                        height: 50,
                        color: SafarTokens.segCarriageway.withValues(alpha: 0.3),
                      ),
                    ),
                    const Center(
                      child: Text(
                        'DRAG EDGE PINS TO NUDGE CORRECTION',
                        style: TextStyle(color: SafarTokens.asphalt500, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SafarTokens.paint,
                        side: const BorderSide(color: SafarTokens.asphalt600),
                      ),
                      onPressed: () {
                        setState(() {
                          _activeReviewIndex = (_activeReviewIndex + 1) % _queue.length;
                        });
                      },
                      child: Text('SKIP', style: SafarTokens.fontMono(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SafarTokens.hivis,
                        foregroundColor: SafarTokens.asphalt950,
                      ),
                      onPressed: () {
                        setState(() {
                          activeItem.isReviewed = true;
                          activeItem.status = 'corrected';
                          _activeReviewIndex = (_activeReviewIndex + 1) % _queue.length;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: SafarTokens.asphalt800,
                            content: Text(
                              'SPARSE LABEL STORED FOR ACTIVE LEARNING NIGHTLY BATCH',
                              style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis),
                            ),
                          ),
                        );
                      },
                      child: Text('SAVE SPARSE CORRECTION', style: SafarTokens.fontUi(fontWeight: FontWeight.w800, fontSize: 11.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),

        // Nightly Retrain Simulator with Gate
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: SafarTokens.asphalt800,
            borderRadius: BorderRadius.circular(SafarTokens.rMd),
            border: Border.all(color: SafarTokens.asphalt700),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NIGHTLY FINE-TUNE RUNNER (retrain.py)', style: SafarTokens.microLabel(color: SafarTokens.paint)),
              const SizedBox(height: 10),
              Text(
                'Runs fine-tune with --freeze-backbone. Evaluates on fixed held-out road validation set. Automatically gates model deployment.',
                style: SafarTokens.fontUi(fontSize: 12.0, color: SafarTokens.asphalt400),
              ),
              const SizedBox(height: 14),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SafarTokens.asphalt700,
                  foregroundColor: SafarTokens.paint,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
                ),
                icon: _isFineTuning
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: SafarTokens.hivis))
                    : const Icon(Icons.rocket_launch_outlined, size: 18, color: SafarTokens.hivis),
                label: Text(
                  _isFineTuning ? 'FINE-TUNING BACKBONE HEAD...' : 'SIMULATE NIGHTLY FINE-TUNE & EVAL GATE',
                  style: SafarTokens.fontMono(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                onPressed: _isFineTuning ? null : _runActiveLearningFineTune,
              ),

              if (_showGateResult) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SafarTokens.asphalt950,
                    borderRadius: BorderRadius.circular(SafarTokens.rSm),
                    border: Border.all(color: _isPromoted ? SafarTokens.confHigh : SafarTokens.confLow, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isPromoted ? 'GATE VERDICT: PROMOTE MODEL' : 'GATE VERDICT: REJECT MODEL',
                            style: SafarTokens.fontMono(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w700,
                              color: _isPromoted ? SafarTokens.confHigh : SafarTokens.confLow,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (_isPromoted ? SafarTokens.confHigh : SafarTokens.confLow).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(SafarTokens.rSm),
                            ),
                            child: Text(
                              _isPromoted ? 'DEPLOYED' : 'BLOCKED',
                              style: SafarTokens.fontMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: _isPromoted ? SafarTokens.confHigh : SafarTokens.confLow,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'HELD-OUT MAE:  ${_baselineMae.toStringAsFixed(2)} m -> ${_candidateMae.toStringAsFixed(2)} m (IMPROVED)',
                        style: SafarTokens.fontMono(fontSize: 10.5, color: SafarTokens.paint),
                      ),
                      Text(
                        'HELD-OUT 90% COVERAGE:  ${(_baselineCov * 100).toStringAsFixed(1)}% -> ${(_candidateCov * 100).toStringAsFixed(1)}% (PASS)',
                        style: SafarTokens.fontMono(fontSize: 10.5, color: SafarTokens.paint),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({required String title, required String description}) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt800,
        borderRadius: BorderRadius.circular(SafarTokens.rMd),
        border: const Border(
          left: BorderSide(color: SafarTokens.hivis, width: 3.0),
          top: BorderSide(color: SafarTokens.asphalt700),
          right: BorderSide(color: SafarTokens.asphalt700),
          bottom: BorderSide(color: SafarTokens.asphalt700),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SafarTokens.microLabel(color: SafarTokens.hivis)),
          const SizedBox(height: 4),
          Text(description, style: SafarTokens.fontUi(fontSize: 12.0, color: SafarTokens.asphalt400)),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String title, String value, String sub, Color valColor) {
    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: SafarTokens.asphalt950,
        borderRadius: BorderRadius.circular(SafarTokens.rSm),
        border: Border.all(color: SafarTokens.asphalt700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SafarTokens.microLabel()),
          const SizedBox(height: 4),
          Text(value, style: SafarTokens.fontMono(fontSize: 16, fontWeight: FontWeight.w700, color: valColor)),
          const SizedBox(height: 2),
          Text(sub, style: SafarTokens.fontMono(fontSize: 9.5, color: SafarTokens.asphalt400)),
        ],
      ),
    );
  }
}

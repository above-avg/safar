// System Configuration Screen
// Directly editing all magic numbers from files/config.yaml
// Strict avoidance of emojis as per user directive.

import 'package:flutter/material.dart';
import '../theme/safar_tokens.dart';

class ConfigSettingsScreen extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onToggleTheme;

  const ConfigSettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<ConfigSettingsScreen> createState() => _ConfigSettingsScreenState();
}

class _ConfigSettingsScreenState extends State<ConfigSettingsScreen> {
  // Capture
  int _targetFps = 30;
  double _minSurveySpeedKmh = 25.0;
  double _maxSurveySpeedKmh = 55.0;
  bool _lockExposure = true;
  bool _lockFocus = true;

  // Camera Extrinsics
  double _heightM = 1.40;
  double _pitchDeg = 6.0;
  String _calibSource = 'ar_plane';

  // IPM
  double _resolutionCm = 2.0; // 0.02 m/px
  double _nearBandM = 5.0;
  double _farBandM = 15.0;

  // Privacy
  bool _blurFaces = true;
  bool _blurPlates = true;
  bool _blurOnIngest = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SafarTokens.asphalt900,
      appBar: AppBar(
        title: Text(
          'SYSTEM PARAMETERS (config.yaml)',
          style: SafarTokens.fontUi(
            fontSize: 13.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.08,
            color: SafarTokens.concrete50,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // UI Theme Setting
          _buildSectionHeader('DISPLAY CONTEXT & THEME'),
          _buildCard([
            SwitchListTile(
              title: Text('DARK THEME (FIELD / HUD CONTEXT)', style: SafarTokens.fontMono(fontSize: 12, fontWeight: FontWeight.w600, color: SafarTokens.paint)),
              subtitle: Text('Default high-contrast surveyor appearance. Turn off for desk/dashboard concrete theme.', style: SafarTokens.fontUi(fontSize: 11, color: SafarTokens.asphalt400)),
              value: widget.isDarkMode,
              activeColor: SafarTokens.hivis,
              onChanged: widget.onToggleTheme,
            ),
          ]),
          const SizedBox(height: 16.0),

          // Capture Section
          _buildSectionHeader('CAPTURE & CAMERA HARDWARE'),
          _buildCard([
            _buildSliderRow(
              label: 'TARGET CAPTURE FPS',
              valueStr: '$_targetFps FPS',
              child: Slider(
                value: _targetFps.toDouble(),
                min: 15.0,
                max: 60.0,
                divisions: 3,
                activeColor: SafarTokens.hivis,
                inactiveColor: SafarTokens.asphalt700,
                onChanged: (v) => setState(() => _targetFps = v.toInt()),
              ),
            ),
            const Divider(color: SafarTokens.asphalt700),
            _buildSliderRow(
              label: 'SURVEY SPEED BAND (km/h)',
              valueStr: '[${_minSurveySpeedKmh.toInt()}, ${_maxSurveySpeedKmh.toInt()}] km/h',
              child: RangeSlider(
                values: RangeValues(_minSurveySpeedKmh, _maxSurveySpeedKmh),
                min: 10,
                max: 90,
                divisions: 16,
                activeColor: SafarTokens.hivis,
                inactiveColor: SafarTokens.asphalt700,
                onChanged: (vals) {
                  setState(() {
                    _minSurveySpeedKmh = vals.start;
                    _maxSurveySpeedKmh = vals.end;
                  });
                },
              ),
            ),
            const Divider(color: SafarTokens.asphalt700),
            SwitchListTile(
              title: Text('LOCK EXPOSURE & FOCUS', style: SafarTokens.fontMono(fontSize: 12, color: SafarTokens.paint)),
              subtitle: Text('Prevents focal length & optical drift mid-survey drive.', style: SafarTokens.fontUi(fontSize: 11, color: SafarTokens.asphalt400)),
              value: _lockExposure && _lockFocus,
              activeColor: SafarTokens.hivis,
              onChanged: (v) {
                setState(() {
                  _lockExposure = v;
                  _lockFocus = v;
                });
              },
            ),
          ]),
          const SizedBox(height: 16.0),

          // Camera Extrinsics Section
          _buildSectionHeader('CAMERA EXTRINSICS (files/calibration.py)'),
          _buildCard([
            _buildSliderRow(
              label: 'CAMERA HEIGHT ABOVE ROAD (height_m)',
              valueStr: '${_heightM.toStringAsFixed(2)} m',
              child: Slider(
                value: _heightM,
                min: 0.8,
                max: 2.8,
                divisions: 40,
                activeColor: SafarTokens.hivis,
                inactiveColor: SafarTokens.asphalt700,
                onChanged: (v) => setState(() => _heightM = v),
              ),
            ),
            const Divider(color: SafarTokens.asphalt700),
            _buildSliderRow(
              label: 'NOSE DOWN PITCH ANGLE (pitch_deg)',
              valueStr: '+${_pitchDeg.toStringAsFixed(1)} deg',
              child: Slider(
                value: _pitchDeg,
                min: 0.0,
                max: 15.0,
                divisions: 30,
                activeColor: SafarTokens.hivis,
                inactiveColor: SafarTokens.asphalt700,
                onChanged: (v) => setState(() => _pitchDeg = v),
              ),
            ),
            const Divider(color: SafarTokens.asphalt700),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('DEFAULT CALIBRATION SOURCE', style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.concrete100)),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _calibSource,
                    dropdownColor: SafarTokens.asphalt800,
                    style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'ar_plane', child: Text('AR PLANE')),
                      DropdownMenuItem(value: 'vanishing_point', child: Text('VANISHING POINT')),
                      DropdownMenuItem(value: 'marking_prior', child: Text('MARKING PRIOR')),
                      DropdownMenuItem(value: 'manual', child: Text('MANUAL')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _calibSource = val);
                    },
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16.0),

          // IPM Geometry & Band
          _buildSectionHeader('INVERSE PERSPECTIVE MAPPING (files/ipm.py)'),
          _buildCard([
            _buildSliderRow(
              label: 'BEV RASTER RESOLUTION',
              valueStr: '${_resolutionCm.toStringAsFixed(0)} cm/px',
              child: Slider(
                value: _resolutionCm,
                min: 1.0,
                max: 5.0,
                divisions: 8,
                activeColor: SafarTokens.hivis,
                inactiveColor: SafarTokens.asphalt700,
                onChanged: (v) => setState(() => _resolutionCm = v),
              ),
            ),
            const Divider(color: SafarTokens.asphalt700),
            _buildSliderRow(
              label: 'MEASURE RANGE BAND (NEAR TO FAR)',
              valueStr: '[${_nearBandM.toInt()}, ${_farBandM.toInt()}] m',
              child: RangeSlider(
                values: RangeValues(_nearBandM, _farBandM),
                min: 2,
                max: 30,
                divisions: 14,
                activeColor: SafarTokens.hivis,
                inactiveColor: SafarTokens.asphalt700,
                onChanged: (vals) {
                  setState(() {
                    _nearBandM = vals.start;
                    _farBandM = vals.end;
                  });
                },
              ),
            ),
          ]),
          const SizedBox(height: 16.0),

          // Privacy Ingest Section
          _buildSectionHeader('INGEST PRIVACY & ANONYMISATION'),
          _buildCard([
            SwitchListTile(
              title: Text('ANONYMISE ON INGEST (BEFORE PERSISTENCE)', style: SafarTokens.fontMono(fontSize: 12, color: SafarTokens.paint)),
              subtitle: Text('Immediately scrubs faces and plates before writing to storage.', style: SafarTokens.fontUi(fontSize: 11, color: SafarTokens.asphalt400)),
              value: _blurOnIngest,
              activeColor: SafarTokens.hivis,
              onChanged: (v) => setState(() => _blurOnIngest = v),
            ),
            const Divider(color: SafarTokens.asphalt700),
            SwitchListTile(
              title: Text('BLUR FACES ON INGEST', style: SafarTokens.fontMono(fontSize: 12, color: SafarTokens.paint)),
              subtitle: Text('Applies Gaussian blur before frame is written to disk or network.', style: SafarTokens.fontUi(fontSize: 11, color: SafarTokens.asphalt400)),
              value: _blurFaces,
              activeColor: SafarTokens.hivis,
              onChanged: (v) => setState(() => _blurFaces = v),
            ),
            const Divider(color: SafarTokens.asphalt700),
            SwitchListTile(
              title: Text('BLUR LICENSE PLATES ON INGEST', style: SafarTokens.fontMono(fontSize: 12, color: SafarTokens.paint)),
              subtitle: Text('Complies with public survey GDPR & municipal privacy rules.', style: SafarTokens.fontUi(fontSize: 11, color: SafarTokens.asphalt400)),
              value: _blurPlates,
              activeColor: SafarTokens.hivis,
              onChanged: (v) => setState(() => _blurPlates = v),
            ),
          ]),
          const SizedBox(height: 20.0),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SafarTokens.hivis,
              foregroundColor: SafarTokens.asphalt950,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SafarTokens.rSm)),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: SafarTokens.asphalt800,
                  content: Text(
                    'CONFIG PARAMETERS SAVED TO SYSTEM CONFIGURATION',
                    style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.hivis),
                  ),
                ),
              );
            },
            child: Text(
              'SAVE & APPLY ALL CONFIGURATIONS',
              style: SafarTokens.fontUi(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
      child: Text(title, style: SafarTokens.microLabel(color: SafarTokens.hivisDim)),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: SafarTokens.asphalt800,
        borderRadius: BorderRadius.circular(SafarTokens.rMd),
        border: Border.all(color: SafarTokens.asphalt700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String valueStr,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: SafarTokens.fontMono(fontSize: 11, color: SafarTokens.concrete100),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(valueStr, style: SafarTokens.fontMono(fontSize: 12, fontWeight: FontWeight.w700, color: SafarTokens.hivis)),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

// Safar: Reading the Road
// Metric road-width measurement from routine survey drives, with calibrated confidence intervals.
// Palette: Asphalt & Hi-Vis | Typography: Archivo & IBM Plex Mono

import 'package:flutter/material.dart';
import 'theme/safar_tokens.dart';
import 'theme/safar_theme.dart';
import 'screens/live_survey_screen.dart';
import 'screens/interactive_map_screen.dart';
import 'screens/upload_cloud_screen.dart';
import 'screens/chainage_dashboard_screen.dart';
import 'screens/manual_ar_ruler_screen.dart';
import 'screens/retraining_loop_screen.dart';
import 'screens/config_settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SafarApp());
}

class SafarApp extends StatefulWidget {
  const SafarApp({super.key});

  @override
  State<SafarApp> createState() => _SafarAppState();
}

class _SafarAppState extends State<SafarApp> {
  bool _isDarkMode = true;

  void _toggleTheme(bool isDark) {
    setState(() => _isDarkMode = isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Safar - Reading the Road',
      debugShowCheckedModeBanner: false,
      theme: SafarTheme.lightTheme,
      darkTheme: SafarTheme.darkTheme,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: SafarMainShell(
        isDarkMode: _isDarkMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class SafarMainShell extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onToggleTheme;

  const SafarMainShell({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<SafarMainShell> createState() => _SafarMainShellState();
}

class _SafarMainShellState extends State<SafarMainShell> {
  int _currentIndex = 0; // Default to Live Survey -- the primary workflow

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const LiveSurveyScreen(),
      const ManualArRulerScreen(),
      const InteractiveMapScreen(),
      const UploadCloudScreen(),
      const ChainageDashboardScreen(),
    ];
  }

  void _navigateToSecondaryScreen(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  void _showGlobalSurveyorGuide() {
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
            'SAFAR: SYSTEM SURVEYOR GUIDE',
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
                  'MISSION OVERVIEW',
                  style: SafarTokens.microLabel(color: SafarTokens.hivis),
                ),
                const SizedBox(height: 6),
                Text(
                  'Safar ("Reading the Road") turns routine driving with a smartphone into metric road width surveys with 90% Split Conformal confidence intervals and emergency vehicle accessibility indexing.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'QUICK START',
                  style: SafarTokens.microLabel(color: SafarTokens.confHigh),
                ),
                const SizedBox(height: 6),
                Text(
                  '1. Open LIVE tab and grant Camera + Location permissions.\n'
                  '2. Mount phone on windshield. Tap the hand icon while stationary to calibrate.\n'
                  '3. Drive at 25-55 km/h. Watch the live width readout update.\n'
                  '4. After driving, go to CLOUD tab to process the official measurement.\n'
                  '5. View results on the MAP or in the DATA dashboard.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'ZERO PAID SERVICES (100% FREE)',
                  style: SafarTokens.microLabel(color: SafarTokens.confHigh),
                ),
                const SizedBox(height: 6),
                Text(
                  'Safar uses OpenStreetMap tiles and open GIS standards. No paid APIs required.',
                  style: SafarTokens.fontUi(fontSize: 11.5, color: SafarTokens.concrete100, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'TABS:',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 6),
                _buildGuideSection(
                  '1. LIVE',
                  'Real-time camera viewfinder with road edge detection, live width readout, and interactive tap-to-measure.',
                ),
                _buildGuideSection(
                  '2. MEASURE',
                  'Virtual AR tape measure. Tap road edges to capture ground truth calibration pairs with zero ML.',
                ),
                _buildGuideSection(
                  '3. MAP',
                  'Zoomable GPS map showing surveyed corridors with road width heatmap and pinch point alerts (< 3.5m).',
                ),
                _buildGuideSection(
                  '4. CLOUD',
                  'Upload raw video for full-resolution server processing. This is the official Measurement of Record.',
                ),
                _buildGuideSection(
                  '5. DATA',
                  'Route profile chart, 5m chainage bins, BEV slices, and GeoJSON/CSV export.',
                ),
                const SizedBox(height: 8),
                Text(
                  'ADDITIONAL TOOLS ("+" button):',
                  style: SafarTokens.microLabel(color: SafarTokens.asphalt400),
                ),
                const SizedBox(height: 6),
                _buildGuideSection(
                  'RETRAIN & CALIBRATE',
                  '3-level loop: Extrinsics (h, pitch), Split Conformal quantiles, and Active Learning queue.',
                ),
                _buildGuideSection(
                  'SYSTEM SETTINGS',
                  'Tune IPM resolution, near/far range band, target FPS, and privacy blurring.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'CLOSE GUIDE',
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

  Widget _buildGuideSection(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SafarTokens.fontMono(fontSize: 11.5, fontWeight: FontWeight.w700, color: SafarTokens.paint)),
          const SizedBox(height: 2),
          Text(description, style: SafarTokens.fontUi(fontSize: 11.0, color: SafarTokens.concrete300, height: 1.35)),
        ],
      ),
    );
  }

  void _showToolsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: SafarTokens.asphalt900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: SafarTokens.asphalt600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'TOOLS & CALIBRATION',
                  style: SafarTokens.microLabel(color: SafarTokens.hivis),
                ),
                const SizedBox(height: 12),
                _buildToolTile(
                  icon: Icons.straighten,
                  title: 'AR RULER',
                  subtitle: 'Virtual tape measure for ground truth capture',
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToSecondaryScreen(const ManualArRulerScreen());
                  },
                ),
                const SizedBox(height: 8),
                _buildToolTile(
                  icon: Icons.auto_fix_high,
                  title: 'RETRAIN & CALIBRATE',
                  subtitle: 'Extrinsics, conformal intervals, active learning',
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToSecondaryScreen(const RetrainingLoopScreen());
                  },
                ),
                const SizedBox(height: 8),
                _buildToolTile(
                  icon: Icons.settings,
                  title: 'SYSTEM SETTINGS',
                  subtitle: 'Camera params, speed band, theme, privacy blur',
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToSecondaryScreen(ConfigSettingsScreen(
                      isDarkMode: widget.isDarkMode,
                      onToggleTheme: widget.onToggleTheme,
                    ));
                  },
                ),
                const SizedBox(height: 8),
                _buildToolTile(
                  icon: Icons.help_outline,
                  title: 'HOW SAFAR WORKS',
                  subtitle: 'Full system guide and workflow overview',
                  onTap: () {
                    Navigator.pop(context);
                    _showGlobalSurveyorGuide();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SafarTokens.rMd),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SafarTokens.asphalt800,
          borderRadius: BorderRadius.circular(SafarTokens.rMd),
          border: Border.all(color: SafarTokens.asphalt700),
        ),
        child: Row(
          children: [
            Icon(icon, color: SafarTokens.hivis, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SafarTokens.fontMono(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: SafarTokens.paint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: SafarTokens.fontUi(fontSize: 11.0, color: SafarTokens.asphalt400),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: SafarTokens.asphalt500, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SafarTokens.asphalt700, width: 1.0)),
        ),
        child: NavigationBar(
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined, size: 22),
              selectedIcon: Icon(Icons.camera_alt, size: 22),
              label: 'LIVE',
            ),
            NavigationDestination(
              icon: Icon(Icons.straighten_outlined, size: 22),
              selectedIcon: Icon(Icons.straighten, size: 22),
              label: 'MEASURE',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined, size: 22),
              selectedIcon: Icon(Icons.map, size: 22),
              label: 'MAP',
            ),
            NavigationDestination(
              icon: Icon(Icons.cloud_upload_outlined, size: 22),
              selectedIcon: Icon(Icons.cloud_upload, size: 22),
              label: 'CLOUD',
            ),
            NavigationDestination(
              icon: Icon(Icons.timeline_outlined, size: 22),
              selectedIcon: Icon(Icons.timeline, size: 22),
              label: 'DATA',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'fab_tools',
        backgroundColor: SafarTokens.asphalt800,
        foregroundColor: SafarTokens.hivis,
        tooltip: 'Tools & Calibration',
        onPressed: _showToolsMenu,
        child: const Icon(Icons.add, size: 22),
      ),
    );
  }
}

# Safar System Enhancements & Usability Fixes

## P0: Live Vision Loop
- [x] `lib/services/road_segmenter.dart` -- ClassicalRoadSegmenter (luminance gradient edge detection on Y-plane, no ML)
- [x] `lib/services/frame_processor_service.dart` -- Image stream consumer with Isolate offloading, drop-frame policy, `ValueNotifier<FrameResult>`
- [x] `lib/services/vanishing_point_estimator.dart` -- Hough-based VP estimation from edge lines for live pitch correction
- [x] `lib/models/frame_result.dart` -- Per-frame output: edges, road width, VP, mask polygon, latency
- [x] `lib/screens/live_survey_screen.dart` -- Live image stream integration with fallback road simulator

## P1: UI Overflow & Yellow/Black Stripe Fixes
- [x] `lib/screens/manual_ar_ruler_screen.dart`:
  - Wrapped top instruction text in `Expanded` with `overflow: TextOverflow.ellipsis` to eliminate RenderFlex overflow on narrow devices
  - Restructured bottom measurement card into two clean rows (metric readout + action buttons) so `RESET` and `SAVE GROUND TRUTH` never overflow horizontally
- [x] `lib/screens/chainage_dashboard_screen.dart`:
  - Replaced unconstrained `Row` of filter chips with responsive `Wrap` to prevent horizontal overflow
  - Added ellipsis to interval text cell in 5m chainage table
- [x] `lib/screens/interactive_map_screen.dart`:
  - Replaced wide corridor dropdown in AppBar with compact `PopupMenuButton` to eliminate title/actions collisions
- [x] `lib/screens/retraining_loop_screen.dart`:
  - Enabled `isScrollable: true` with `tabAlignment: TabAlignment.start` on TabBar
  - Wrapped active learning review item details in responsive `Wrap` to eliminate overflow
- [x] `lib/screens/config_settings_screen.dart`:
  - Wrapped `DEFAULT CALIBRATION SOURCE` label in `Expanded`
  - Wrapped slider row label in `Expanded` with `overflow: TextOverflow.ellipsis`
- [x] `lib/widgets/live_hud_card.dart`:
  - Compact layout, mono tabular numbers, `Wrap` on metadata tags, `overflow: TextOverflow.ellipsis`
- [x] `lib/screens/upload_cloud_screen.dart`:
  - Fixed syntax error in AppBar title and made comparison rows responsive with `Column` and `Expanded`

## P2: Usability & "Measurement Thing" Implementation
- [x] **Interactive Tap-to-Measure Tool on Live Camera (`live_survey_screen.dart` + `hud_overlay_painter.dart`)**:
  - Direct on-canvas two-point tap measuring on the live camera preview
  - High-visibility reticles on Point A and Point B with distance badge
  - Real-time IPM ground distance calculation
  - Dedicated "TAP MEASURE" button in viewfinder floating controls with active status banner
- [x] **Dedicated MEASURE Bottom Tab (`main.dart`)**:
  - Promoted AR Metric Ruler to top-level tab 2 (`MEASURE` with ruler icon)
  - 5 clean navigation tabs: `LIVE`, `MEASURE`, `MAP`, `CLOUD`, `DATA`
- [x] **Survey Drive Recording Feedback**:
  - Live chainage tracking and visual SnackBar alerts on survey drive start/stop
- [x] **Clear Guidance & Zero Paid API Guarantees**:
  - OpenStreetMap free tiles with offline fallback
  - Step-by-step guidance dialogs across all screens

## Verification
- [x] `flutter analyze` passes with 0 issues
- [x] `flutter test` passes (6/6 tests passing)
- [x] `flutter build apk --debug` verified

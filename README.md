<<<<<<< HEAD
# Safar: Reading the Road

Metric road-width measurement from routine survey drives, calibrated with Split Conformal confidence intervals and emergency vehicle accessibility indexing.

---

## 1. System Overview & Engineering Philosophy

Municipal road management and emergency vehicle access planning (fire tenders, ambulances) require accurate, repeatable carriageway width measurements across thousands of kilometres of road networks. Traditional approaches rely on either slow, hazardous manual tape measurements or expensive, specialized LiDAR survey vehicles.

**Safar ("Reading the Road")** transforms routine driving using an ordinary smartphone into a survey-grade road measurement instrument:
- **Zero Paid APIs / 100% Free**: Operates using public OpenStreetMap raster tiles and open GIS standards (WGS84 EPSG:4326 and UTM projections). No Google Maps API, CartoDB tokens, or paid cloud services required.
- **Dual-Scale Principle**: Monocular scale recovery combines Inverse Perspective Mapping (IPM) with stationary AR ground-plane extrinsics and per-frame vanishing point pitch correction.
- **Live vs. Upload Split**: "Live shows you it is working; Upload is what you trust." The on-dash live mode gives immediate surveyor feedback, while the Cloud GPU pipeline processes full-resolution video with temporal mosaicking for the authoritative measurement of record.
- **Calibrated Uncertainty**: Uses Split Conformal Prediction to produce guaranteed 90% confidence intervals (e.g., `7.24 m +/- 0.22 m`) rather than unquantified point estimates.
- **Emergency Vehicle Clearance**: Evaluates every 5-metre chainage interval against the Indian IRC:SP:84 minimum clearance standard (3.50 metres clear width required for fire tenders).
- **Asphalt & Hi-Vis Visual Identity**: Clean, high-contrast engineering aesthetics using dark ground tones (`#121517`), bright retroreflective accents (`#D9F24B`), and IBM Plex Mono typography with tabular figures.

---

## 2. Directory Structure & Complete File Inventory

```
Safar/
├── files/                                # Architectural specification documents
│   ├── Reading the Road — System Plan (P02).html # System blueprint
│   ├── config.yaml                       # Baseline system parameters
│   ├── tokens.css                        # Asphalt & Hi-Vis design tokens
│   ├── pipeline.py                       # Reference end-to-end Python pipeline
│   ├── calibration.py                    # Intrinsics & extrinsics calibration reference
│   ├── ipm.py                            # Inverse perspective mapping reference
│   ├── measure.py                        # Transect casting & aggregation reference
│   └── confidence.py                     # Split conformal confidence reference
│
└── safar/                                # Flutter Mobile Application
    ├── pubspec.yaml                      # Project dependencies & asset configuration
    ├── android/
    │   ├── app/src/main/AndroidManifest.xml # Permissions (Camera, Fine/Coarse GPS)
    │   ├── build.gradle.kts              # Root Android Gradle build configuration
    │   └── settings.gradle.kts           # Plugin management & AGP/Kotlin setup
    │
    ├── lib/
    │   ├── main.dart                     # App root, navigation shell & Global Surveyor Guide
    │   │
    │   ├── theme/
    │   │   ├── safar_tokens.dart         # Color palette, spacing, typography & radii
    │   │   └── safar_theme.dart          # Dark (Field/HUD) & Light (Desk) themes
    │   │
    │   ├── models/
    │   │   ├── camera_calibration.dart   # Camera intrinsics & physical mount extrinsics
    │   │   ├── transect.dart             # Per-frame transects & 5m chainage bins
    │   │   ├── prediction.dart           # Split conformal uncertainty & confidence tiers
    │   │   ├── survey_session.dart       # Corridor survey sessions & summary metrics
    │   │   ├── map_marker_data.dart      # GPS waypoints, accessibility & heatmap data
    │   │   └── active_learning_item.dart # Low-confidence frames for human review queue
    │   │
    │   ├── services/
    │   │   ├── permissions_service.dart  # Runtime Camera & GPS location permission handling
    │   │   ├── road_pipeline_service.dart# IPM geometry, 5m Median+MAD binning, GeoJSON/CSV export
    │   │   └── mock_survey_data.dart     # Highway, rural pinch-point & urban corridors
    │   │
    │   ├── widgets/
    │   │   ├── interactive_road_map.dart # OpenStreetMap widget with zoom/pan, heatmaps & GPS locate
    │   │   ├── live_hud_card.dart        # Real-time width readout in IBM Plex Mono with telemetry tags
    │   │   ├── hud_overlay_painter.dart  # 3-layer viewfinder overlay (Tint, Ladder, HUD)
    │   │   ├── chainage_profile_chart.dart # Width vs Chainage plot with 90% confidence envelope
    │   │   ├── bev_slice_viewer.dart     # 2 cm/px top-down Bird's-Eye View raster slice visualizer
    │   │   └── confidence_badge.dart     # High / Medium / Low status badge with color & text
    │   │
    │   └── screens/
    │       ├── live_survey_screen.dart   # Viewfinder with camera preview & simulator fallback
    │       ├── interactive_map_screen.dart # Full-screen GPS map with regional metrics & legend
    │       ├── upload_cloud_screen.dart  # Cloud GPU ingest hub with 7-stage processing simulator
    │       ├── chainage_dashboard_screen.dart # Chainage bin table, BEV inspector & data exporter
    │       ├── manual_ar_ruler_screen.dart # Virtual 3D surveyor tape measure for ground-truth pairs
    │       ├── retraining_loop_screen.dart # 3-level loop (Extrinsics, Confidence, Active Learning)
    │       └── config_settings_screen.dart # Hyperparameter editor for config.yaml parameters
    │
    └── test/
        └── widget_test.dart              # Automated unit tests (IPM, Conformal, 5m Binning, GeoJSON, UI)
```

---

## 3. Detailed File Descriptions & Usage

### Core Application & Navigation

#### `lib/main.dart`
* **Purpose**: Entry point for the Flutter application. Configures the Material theme (Dark/Light), initializes the global `SafarMainShell`, and hosts the bottom navigation bar connecting all 6 operational modules.
* **Key Components**:
  * `SafarApp`: Top-level widget managing dark/light theme state.
  * `SafarMainShell`: 6-destination bottom navigation bar with icons and labels.
  * `_showGlobalSurveyorGuide()`: Global modal providing comprehensive onboarding instructions, module workflows, and explanations of system principles.
  * Floating action buttons providing one-tap access to System Configuration and the Global Surveyor Guide from any screen.

---

### Design System & Theming

#### `lib/theme/safar_tokens.dart`
* **Purpose**: Defines the design tokens mirroring `tokens.css` from the system plan.
* **Key Tokens**:
  * **Ground Palette**: `asphalt950` (`#0B0D0E`), `asphalt900` (`#121517`), `asphalt800` (`#1C2024`), `asphalt700` (`#282E33`).
  * **Brand & Paint**: `hivis` (`#D9F24B`), `hivisDim` (`#A6BC2A`), `paint` (`#F5F2E9`).
  * **Confidence Ramps**: `confHigh` (`#4E9E6B`), `confMed` (`#E0873A`), `confLow` (`#D94B4B`).
  * **Road Width Heatmap**: 6-step color ramp (`<3.0m` critical bottleneck up to `>12.0m` multi-lane highway).
  * **Typography**: Archivo font family for prose and UI labels; IBM Plex Mono for all numeric measurements, coordinates, units, and intervals with tabular figures.

#### `lib/theme/safar_theme.dart`
* **Purpose**: Generates Flutter `ThemeData` instances for both dark (Field/HUD) and light (Desk/Office) modes, configuring app bars, cards, buttons, dialogs, and navigation bars according to Safar tokens.

---

### Data Models

#### `lib/models/camera_calibration.dart`
* **Purpose**: Represents camera intrinsic matrix parameters (`fx`, `fy`, `cx`, `cy`, baseline distortion) and physical rig extrinsic mount parameters (camera height `h`, pitch angle, roll, yaw).
* **Usage**: Feeds into the Inverse Perspective Mapping equations to convert screen coordinates to metric ground distances.

#### `lib/models/transect.dart`
* **Purpose**: Models instantaneous road transects cast across the road carriageway (1-metre intervals along the 5–15m trusted range band) and 5-metre aggregated chainage bins (`ChainageBin`).
* **Attributes**: `chainageM`, `widthM`, `madM` (Median Absolute Deviation), observation count `n`, `edgeLeft`, `edgeRight`, `latitude`, `longitude`.

#### `lib/models/prediction.dart`
* **Purpose**: Represents calibrated metric width predictions accompanied by Split Conformal confidence bounds.
* **Attributes**: `widthM`, `halfWidthM` (90% uncertainty bound), `tier` (`high`, `medium`, `low`), `targetCoverage` (0.90).

#### `lib/models/map_marker_data.dart`
* **Purpose**: Models geospatial survey waypoints along corridors for map rendering and GIS indexing.
* **Attributes**: LatLng position, chainage, metric width, 90% interval, edge types, observation count, and emergency accessibility status (`passable`, `caution`, `pinchPointImpassable`).

#### `lib/models/survey_session.dart`
* **Purpose**: Encapsulates a complete survey drive (e.g., NH-48 Highway, Rural Ridge). Contains chainage bins, predictions, map segments, total distance, mean width, and high-confidence percentages.

#### `lib/models/active_learning_item.dart`
* **Purpose**: Models flagged, low-confidence survey segments queued for human review in the active learning loop.

---

### Hardware Services & Geometry Pipeline

#### `lib/services/permissions_service.dart`
* **Purpose**: Encapsulates hardware device permission checks and requests using `permission_handler` and `geolocator`.
* **Methods**:
  * `checkCameraPermission()`: Returns boolean status of camera permission.
  * `checkLocationPermission()`: Returns boolean status of GPS permission.
  * `requestAllPermissions()`: Prompts user for both Camera and Location access.
  * `getCurrentGpsLocation()`: Reads live device GPS coordinates with high accuracy.

#### `lib/services/road_pipeline_service.dart`
* **Purpose**: Implements the mathematical core of the road measurement system in Dart.
* **Algorithms Implemented**:
  * **IPM Ground to Pixel & Pixel to Ground**: Full rotation and translation projection taking into account camera height $h$, pitch $p$, roll $r$, and optical center $(c_x, c_y)$.
  * **Horizon Check**: Rays pointing at or above the ground plane horizon return `null` to avoid mathematical singularities.
  * **5m Chainage Binning**: Uses **Median + MAD** (Median Absolute Deviation) across frames rather than arithmetic mean, completely rejecting transient outliers caused by passing vehicles or parked trucks.
  * **Split Conformal Predictor**: Calibrates adaptive 90% prediction intervals based on observation count, edge classification entropy, range, and cross-method depth disagreement.
  * **GeoJSON Exporter**: Generates standard WGS84 (EPSG:4326) `FeatureCollection` vector points with all road properties and emergency passability flags.
  * **CSV Exporter**: Outputs structured tabular data for spreadsheets and municipal databases.

#### `lib/services/mock_survey_data.dart`
* **Purpose**: Generates realistic survey sessions for demonstration and offline field testing:
  * **NH-48 Highway**: 400-metre dual-carriageway with wide lanes (mean width 8.2m) and high confidence.
  * **Rural Ridge**: 450-metre hilly road featuring tight curves and critical pinch points (< 3.5m) that block fire tenders.
  * **Urban Arterial**: 500-metre city corridor with parked vehicles, kerb edges, and partial occlusions.
  * **Active Learning Queue**: Ambiguous edge frames for review.

---

### UI Widgets & Visualizers

#### `lib/widgets/interactive_road_map.dart`
* **Purpose**: 100% free interactive map component using `flutter_map` with OpenStreetMap raster tiles.
* **Features**:
  * Smooth two-finger pinch-to-zoom and one-finger panning.
  * Zoom in (`+`), Zoom out (`-`), and Fit Corridor to screen bounds (`crop_free`).
  * Live GPS button (`my_location`) that queries `PermissionsService.getCurrentGpsLocation()` and centers on the surveyor with an active pulsing GPS marker.
  * Continuous road width heatmap polyline trace.
  * Critical pinch point marker pins (`!`) for locations narrower than 3.5 metres.
  * Non-overflowing, responsive measurement callout card showing chainage, width, 90% confidence interval, emergency passability status, and edge classifications.
  * Map Legend dialog explaining interaction gestures and color ramps.

#### `lib/widgets/live_hud_card.dart`
* **Purpose**: Displays the real-time surveyor HUD readout on the viewfinder.
* **Features**:
  * Live width readout in 38pt IBM Plex Mono with tabular figures.
  * 90% interval readout, sample size $n$, and MAD statistic.
  * Surveyor tag chips with explanatory tooltips: Left/Right edge classification, perspective range band, calibration source, camera pitch, survey speed band (25–55 km/h), IMU RMS vibration, and GPS HDOP.

#### `lib/widgets/hud_overlay_painter.dart`
* **Purpose**: Custom canvas painter rendering the 3-layer viewfinder overlay:
  * **Layer 1**: Segmentation tint with diagonal hatch overlay for occlusions.
  * **Layer 2**: Transect ladder drawn at 1-metre intervals across the road carriageway within the 5–15m trusted range band.
  * **Layer 3**: HUD geometry lines, horizon indicator, and optical center crosshairs.

#### `lib/widgets/chainage_profile_chart.dart`
* **Purpose**: Interactive CustomPaint chart plotting Road Width (y-axis) against Chainage Distance (x-axis).
* **Features**:
  * Shaded blue 90% Split Conformal confidence envelope.
  * Red dashed horizontal threshold line at 3.50 metres (emergency vehicle clearance limit).
  * Data points colored according to width, with pinch points highlighted in red.
  * Tappable chainage points to select and inspect specific 5-metre intervals.

#### `lib/widgets/bev_slice_viewer.dart`
* **Purpose**: Visualizes top-down 2 cm/pixel Bird's-Eye View (BEV) orthographic raster slices for the selected chainage bin, displaying the road carriageway and detected boundaries.

#### `lib/widgets/confidence_badge.dart`
* **Purpose**: Renders High, Medium, or Low confidence status chips pairing color with clear textual labels.

---

### Application Screens (Modules)

#### `lib/screens/live_survey_screen.dart` (Live Survey Module)
* **Purpose**: Real-time camera survey viewfinder.
* **Features**:
  * Prompts for and manages device camera and GPS permissions with an onboarding guidance banner.
  * Uses live device back camera preview (`camera: ^0.11.2+1`) with automatic fallback to an animated road perspective simulator for desktop/emulator environments.
  * Floating layer toggle controls (Layer 1 segmentation, Layer 2 transects, Layer 3 HUD).
  * One-tap Stationary AR Plane height calibration capture ($h=1.40$m).
  * Clap sync test for video/IMU timestamp synchronization.
  * Live HUD readout card and survey drive recording controls.

#### `lib/screens/interactive_map_screen.dart` (GPS Map Module)
* **Purpose**: Dedicated geospatial mapping dashboard.
* **Features**:
  * Corridor selector dropdown (NH-48 Highway, Rural Ridge, Urban Arterial).
  * Horizontal regional summary metrics (Mapped Extent, Mean Width, Fire Tender Access %, Critical Pinch Point Count, Working CRS).
  * Full-screen interactive OpenStreetMap with road width heatmaps and measurement inspection callouts.
  * Contextual Help button opening the GPS Corridor Map Guide.

#### `lib/screens/upload_cloud_screen.dart` (Cloud GPU Ingest Module)
* **Purpose**: Ingest hub for server-side full-resolution processing ("Measurement of Record").
* **Features**:
  * Ingest file pickers for raw survey MP4 video and synchronized IMU sensor logs.
  * Dataset selector with active highlight borders.
  * Primary action button: `RUN 7-STAGE CLOUD GPU PIPELINE`.
  * Simulated execution of the 7 pipeline stages:
    1. Probing video & IMU hardware timestamps.
    2. Privacy pass: Blurring human faces and vehicle license plates.
    3. Resolving extrinsics: Vanishing point per-frame pitch correction.
    4. Warping to 2 cm/px top-down BEV mosaic.
    5. Transect casting & 5m chainage aggregation (Median + MAD).
    6. Split Conformal calibration (90% uncertainty intervals).
    7. Generating UTM geodata and GeoJSON record.
  * Side-by-side comparison table between Live provisional metrics and Cloud calibrated record.

#### `lib/screens/chainage_dashboard_screen.dart` (Chainage Dashboard Module)
* **Purpose**: Analytical dashboard for reviewing surveyed corridors.
* **Features**:
  * $2 \times 2$ summary cards for total distance, mean width, high confidence percentage, and chainage bin count.
  * Collapsible guide card explaining how to interpret the Width vs Chainage chart and the 3.5m threshold line.
  * Interactive Width Profile chart and BEV slice inspector.
  * Chainage record table with filter chips (`ALL`, `HIGH`, `LOW`, `PINCH`).
  * Vector export modal for **GeoJSON (EPSG:4326)** and **CSV record tables**.

#### `lib/screens/manual_ar_ruler_screen.dart` (AR Ruler Module)
* **Purpose**: Point-to-point 3D AR metric ruler for ground-truth capture without machine learning.
* **Features**:
  * Perspective AR grid canvas with on-screen reticle guidance.
  * Tap Point A (left edge) and Point B (right edge) to measure span in metres.
  * Freeze-frame toggle (`pause`/`play`) to pause video while tapping kerb edges.
  * Explicit `RESET` and `SAVE GROUND TRUTH` buttons.
  * Help dialog explaining ground-truth pair calibration.

#### `lib/screens/retraining_loop_screen.dart` (Retraining Module)
* **Purpose**: Manages the 3-level model and confidence improvement loop.
* **Tabs**:
  * **Level 1: Extrinsics**: Adjust physical camera mount height ($h$) and pitch offset trim without retraining ML models.
  * **Level 2: Confidence**: Recalibrates Split Conformal quantiles using 30–50 ground-truth tape pairs to ensure stated 90% intervals match empirical coverage.
  * **Level 3: Active Learning**: Review queue for low-confidence frames, sparse edge pin adjustments, and simulated nightly fine-tune runner with an **automated deployment gate** (promotes model only if held-out MAE improves and 90% coverage passes).

#### `lib/screens/config_settings_screen.dart` (Settings Screen)
* **Purpose**: In-app configuration editor directly modifying parameters from `config.yaml`:
  * Camera mount height ($h$) and pitch prior.
  * Trusted perspective range band ($5-15$ metres).
  * 5m chainage bin interval and minimum frame requirement.
  * Conformal confidence target $\alpha = 0.10$ (90% coverage).
  * Emergency vehicle clearance threshold ($3.50$ metres).
  * Dark / Light theme toggle.

---

## 4. Mathematical & Algorithmic Summary

### Inverse Perspective Mapping (IPM)

Given a camera at height $h$ above a flat ground plane with pitch angle $p$ and camera intrinsics $(f_x, f_y, c_x, c_y)$:

1. **Pixel to Ray**: A pixel coordinate $(u, v)$ is converted to normalized camera coordinates:
   $$x_c = \frac{u - c_x}{f_x}, \quad y_c = \frac{v - c_y}{f_y}$$

2. **Horizon Check**: The pitch-rotated ray direction component $d_z = \cos(p) - y_c \sin(p)$. If $d_z \le 0.05$, the ray is pointing at or above the ground horizon and is clipped.

3. **Ground Intersection**:
   $$Y_g = \frac{h \cdot (\sin(p) + y_c \cos(p))}{d_z}$$
   $$X_g = \frac{x_c \cdot (h \cos(p) - Y_g \sin(p))}{f_x / f_y}$$

### 5-Metre Chainage Binning (Median + MAD)

For all transect width measurements $w_1, w_2, \dots, w_n$ within a 5-metre chainage interval:
$$\tilde{w} = \text{median}(w_1, \dots, w_n)$$
$$\text{MAD} = \text{median}(|w_i - \tilde{w}|)$$

Using the median and Median Absolute Deviation completely eliminates transient measurement spikes caused by parked vehicles, overhanging trees, and overtaking traffic.

### Split Conformal Calibration

To guarantee that 90% of true road widths fall within $[\hat{w} - \hat{q}, \hat{w} + \hat{q}]$, nonconformity scores $s_i = |w_i^{\text{true}} - \hat{w}_i|$ are computed on a held-out calibration dataset of $n$ ground-truth tape-measured spots. The calibrated conformal quantile is:
$$\hat{q} = \text{Quantile}\left(s_1, \dots, s_n; \frac{\lceil(n+1)(1-\alpha)\rceil}{n}\right)$$

---

## 5. Getting Started & Verification

### Prerequisites
* Flutter SDK (3.32.2 or higher)
* Dart SDK (3.8.1 or higher)
* Android SDK (API 34 / Android 14 recommended)
* Physical Android device or Android Emulator

### Installation

1. Clone the repository and navigate to the `safar` project folder:
   ```bash
   cd safar
   ```

2. Fetch pub dependencies:
   ```bash
   flutter pub get
   ```

3. Verify static analysis:
   ```bash
   flutter analyze
   # Output: No issues found!
   ```

4. Run the automated unit and widget test suite:
   ```bash
   flutter test
   # Output: All tests passed! (6/6 tests passing)
   ```

5. Run the application on an Android device or emulator:
   ```bash
   flutter run
   ```

6. Build a standalone debug APK:
   ```bash
   flutter build apk --debug
   # Output: build/app/outputs/flutter-apk/app-debug.apk
   ```

---

## 6. Regulatory & Standards Compliance

* **IRC:SP:84-2014**: Manual of Specifications & Standards for Four Laning of Highways — Carriageway clearance thresholds.
* **WGS84 / EPSG:4326**: Standard geospatial coordinate reference system used in GeoJSON vector exports.
* **Auto-UTM Projection**: Automatic UTM zone selection (e.g. Zone 43N for India) for metric chainage distance calculations.
* **Split Conformal Prediction**: Finite-sample distribution-free uncertainty guarantees (Vovk et al., 2005).
=======
# Read the Road

A working local road-video analysis prototype with a dark survey dashboard, animated synthetic preview, real SegFormer inference, conservative road-width geometry and evidence exports.

## Run

Requires Python 3.10+ and an internet connection for installation and the initial pretrained-model download. CPU is supported; a compatible CUDA PyTorch installation accelerates inference.

`requirements-lock.txt` records the exact packages verified on Windows / Python 3.10. Use `-r requirements-lock.txt` instead for that environment. The general requirements file allows other supported Python platforms to resolve compatible builds.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn backend.app:app --host 127.0.0.1 --port 8000
```

Open http://127.0.0.1:8000. Alternatively run `start.ps1` after installing dependencies. If your environment sets `PIP_NO_INDEX=1`, install from your approved package mirror or unset it for the installation process. The app works without a JavaScript build step. Web fonts are optional; system font fallbacks work offline.

1. Explore the **synthetic demo**, which uses simulated geometry and measurements. It does not run the model.
2. Select **New survey** and upload a video. The first real job downloads the pinned SegFormer B0 checkpoint into `.cache/huggingface`.
3. Leave calibration empty for your unknown-camera footage. Actual ML masks and visible image spans are displayed; metre values are withheld.
4. Inspect sampled frames, toggle road masks/boundaries, select points on the profile, and export JSON or CSV.
5. Optionally provide measured calibration for conditional metric estimates. Do not copy example parameters into an unknown camera profile.

The prototype accepts MP4/MOV/AVI/MKV/WebM if OpenCV can decode the codec, up to 500 MB and 10 minutes. It samples 0.1–2 Hz and caps work at 600 sampled frames; exports flag truncated coverage. Playback displays sampled stills, not a full-frame-rate rendered video. One local job runs at a time. Cancel stops after the current loading/inference operation. Source files are removed after processing; sampled JPEGs and result JSON remain under `data/<job-id>`. Active job state is in memory; after a server restart, use the saved JSON directly. Do not expose this unauthenticated prototype to the public internet.

## What is implemented

- Pretrained semantic segmentation using `nvidia/segformer-b2-finetuned-cityscapes-1024-1024` (pinned revision) with obstacle exclusion.
- Learned metric depth prior using `depth-anything/Depth-Anything-V2-Metric-Outdoor-Small-hf` (pinned revision) with mounting-height plane anchoring.
- Temporal optical flow tracking (`Farneback`) to propagate masks and depth continuously across full-length video between model keyframes.
- Calibrated ray/plane intersection with lens distortion and resolution scaling; perpendicular centerline cross-sections.
- Uncalibrated / rough estimation mode using outdoor depth prior and FOV/height assumptions, emitting scenario sensitivity envelopes while clearly distinguishing them from calibrated truth.
- Full H.264 video rendering with synchronized mask overlays, cross-sections, and title bars.
- 2D survey corridor mapping with depth-scaled visual odometry or optional time-aligned GPS track ingestion (CSV / GPX).
- Full-video width strip visualization covering all timestamps even across visual tracking gaps.
- Reprocessing capability (`/api/jobs/{id}/reprocess`) from retained source video or recovered sparse images.
- Diagnostics for mask confidence, boundary coverage, exposure, low texture/blur, abrupt width changes and calibration sensitivity.
- Comprehensive evidence exports: timestamped JSON, measurements CSV, annotated MP4, and spatial map JSON / PNG.
- An explicitly labeled synthetic UI demonstration, independent of inference.

## Calibration and scale modes

1. **Calibrated mode**: Supply JSON with `image_width`, `image_height`, `fx`, `fy`, `cx`, `cy`, `height_m`, `pitch_deg`; optional `roll_deg`, five OpenCV distortion coefficients `[k1,k2,p1,p2,k3]`, `height_error_m`, `angle_error_deg`, `focal_error_pct`.
   Intrinsics refer to calibration image dimensions and are scaled for resized frames. World axes are right/down/forward; road plane is `Y = height_m`.
2. **Rough learned-depth mode**: Unknown camera footage uses Depth Anything V2 outdoor depth scaled by an assumed camera mounting height prior (default 1.5 m) and diagonal FOV assumption (default 90°). Emits approximate widths and sensitivity intervals with documented assumptions.
3. **Calibrated-only mode**: Withholds all physical metric estimates when calibration is absent, displaying road masks and preview pixel spans only.

Width means visible ego-connected paved carriageway, not an individual lane or right of way. Metric output depends on calibration or depth assumptions, full edge visibility, and a locally planar road. Quality is a heuristic score, not a calibrated probability.

## Verification

```powershell
.\.venv\Scripts\python.exe -m pytest -q
node --check frontend/dashboard.js
node --check frontend/demo.js
node --check frontend/app.js
```

Geometry tests cover known ground-plane measurements, distortion/roll roundtrips, resolution changes, curved/directional centerlines, missing scale, occlusion and low-quality inputs. API tests verify decoding, job queueing, validation, reprocessing, cancellation, GPS ingestion, and exports. Unit tests cover GPS parsing/interpolation, camera matrices, depth-to-height plane anchoring, rough width calculations, survey mapping, and video encoding.

`python scripts/smoke_model.py` runs a real-model test with both SegFormer B2 and Depth Anything V2 on CPU using a public demo image and generates a repeated-still integration fixture under `data/smoke`.

Model references:
- https://huggingface.co/nvidia/segformer-b2-finetuned-cityscapes-1024-1024
- https://huggingface.co/depth-anything/Depth-Anything-V2-Metric-Outdoor-Small-hf
>>>>>>> master

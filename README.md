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

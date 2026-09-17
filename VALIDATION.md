# Prototype validation — 17 September 2026 (v0.2)

- 28 automated tests passed on Windows / Python 3.10 (`tests/test_geometry.py`, `tests/test_api.py`, `tests/test_v2_modules.py`).
- Frontend JavaScript syntax checks passed with `node --check frontend/dashboard.js`, `node --check frontend/demo.js`, and `node --check frontend/app.js`.
- Real pinned SegFormer B2 (`nvidia/segformer-b2-finetuned-cityscapes-1024-1024`) and Depth Anything V2 (`depth-anything/Depth-Anything-V2-Metric-Outdoor-Small-hf`) checkpoints executed successfully on CPU via `scripts/smoke_model.py`.
- Camera-mounting height prior anchoring (`anchor_depth_to_height`) correctly fitted the road plane and scaled depth.
- API pipeline tests verified full-duration H.264 video normalization and encoding, continuous mask flow tracking, spatial corridor mapping, GPS track parsing and alignment (CSV and GPX), cancellation, survey reprocessing (`/reprocess`), and exports.
- All dependencies verified and pinned in `requirements-lock.txt` (including `imageio-ffmpeg==0.6.0`).
- The running browser dashboard (`frontend/index.html` + `frontend/dashboard.js` + `frontend/demo.js`) exercises video playback, frame inspection, top-down local cross-sections, full-survey 2D spatial maps, full-video width strips, and export dialogs.

This validates prototype functionality and engineering integrity, not survey accuracy. Metric geometry was tested using synthetic ground truth; metric width accuracy on real roads, temporal robustness and generalization across environments remain unvalidated. Rough width envelopes and heuristic quality scores are not calibrated confidence intervals.

"""Opt-in real-model smoke test. Downloads public weights and an MMSeg demo image.

The short AVI repeats one public still image: it is an integration fixture,
not dashcam footage or an accuracy benchmark. Outputs stay in ignored data/.
"""
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import cv2
import numpy as np
import requests
from backend.model import RoadSegmenter, MetricDepth
from backend.geometry import analyze_mask
from backend.estimation import camera_matrix, rough_width, anchor_depth_to_height

folder = ROOT / "data" / "smoke"
folder.mkdir(parents=True, exist_ok=True)
source = "https://raw.githubusercontent.com/open-mmlab/mmsegmentation/main/demo/demo.png"
response = requests.get(source, timeout=60)
response.raise_for_status()
frame = cv2.imdecode(np.frombuffer(response.content, dtype=np.uint8), cv2.IMREAD_COLOR)
assert frame is not None
scale = min(1, 1280 / frame.shape[1])
frame = cv2.resize(frame, (round(frame.shape[1]*scale), round(frame.shape[0]*scale)))
cv2.imwrite(str(folder / "public-road-fixture.jpg"), frame)
started = time.monotonic()
model = RoadSegmenter()
depth_model = MetricDepth()
probability, mask, obstacles = model.predict(frame)
depth = depth_model.predict(frame)
result = analyze_mask(probability, mask, frame, obstacle_mask=obstacles)
assert result['width_m'] is None, 'Video without calibration must not emit calibrated metres'
assert len(result['polygon']) > 3, 'Road mask was not detected in public road fixture'

k = camera_matrix(frame.shape[1], frame.shape[0])
depth, anchor = anchor_depth_to_height(depth, mask, k)
rough_width(result, depth, mask, k)

overlay = frame.copy()
overlay[mask] = (overlay[mask]*.65 + np.array([160,230,160])*.35).astype(np.uint8)
cv2.imwrite(str(folder / 'actual-model-overlay.jpg'), overlay)
writer = cv2.VideoWriter(str(folder / 'public-still-integration-fixture.avi'), cv2.VideoWriter_fourcc(*'MJPG'), 5, (frame.shape[1], frame.shape[0]))
assert writer.isOpened()
for _ in range(15):
    writer.write(frame)
writer.release()
summary = {"source": source, "fixture": "Repeated public still, not dashcam footage", "elapsed_s": round(time.monotonic()-started, 2), "device": model.device,
           "road_fraction": float(mask.mean()), "anchor": anchor, "result": result}
(folder / 'model-smoke-result.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in summary.items() if k!='result'}, indent=2))
print('RESULT', result['status'], 'width_m:', result['width_m'], 'rough_width_m:', result.get('rough_width_m'), 'pixel_span:', result.get('pixel_span'))

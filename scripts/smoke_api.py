"""Exercise the running local API with the public repeated-still fixture."""
import json
import time
from pathlib import Path
import requests

root = Path(__file__).resolve().parents[1]
fixture = root / 'data/smoke/public-still-integration-fixture.avi'
session = requests.Session()
session.trust_env = False
base = 'http://127.0.0.1:8000'
with fixture.open('rb') as stream:
    response = session.post(base + '/api/jobs', files={'video': (fixture.name, stream, 'video/x-msvideo')}, data={'sample_hz': 1, 'estimate_mode': 'calibrated_only'}, timeout=30)
response.raise_for_status()
job_id = response.json()['id']
print('JOB', job_id, flush=True)
deadline = time.monotonic() + 120
while time.monotonic() < deadline:
    response = session.get(f'{base}/api/jobs/{job_id}', timeout=10)
    response.raise_for_status()
    job = response.json()
    if job['status'] in ['complete', 'failed', 'cancelled']:
        break
    time.sleep(.5)
assert job['status'] == 'complete', job.get('message')
assert len(job['results']) == 3
assert all(r['width_m'] is None and r['polygon'] for r in job['results'])
assert session.get(base + job['results'][0]['image'], timeout=10).status_code == 200
assert session.get(f'{base}/api/jobs/{job_id}/video?kind=source', timeout=10).status_code == 200
assert session.get(f'{base}/api/jobs/{job_id}/map', timeout=10).status_code == 200
csv = session.get(f'{base}/api/jobs/{job_id}/export?format=csv', timeout=10)
assert csv.status_code == 200 and 'Metric scale unavailable' in csv.text
(root / 'data/smoke/api-smoke-result.json').write_text(json.dumps(job, indent=2), encoding='utf-8')
print('PASS: actual ML video decode, masks, no-scale abstention, preview, video, map and CSV export')
print(f'VIEW {base}/?survey={job_id}')

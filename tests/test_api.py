import json
import time
import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient
import backend.server as api


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(api, 'DATA', tmp_path)
    monkeypatch.setattr(api, 'jobs', {})
    return TestClient(api.app)


def test_input_validation(client):
    assert client.get('/api/health').status_code == 200
    assert client.get('/').status_code == 200
    assert client.post('/api/jobs', files={'video': ('x.txt', b'x')}).status_code == 415
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'')}).status_code == 422
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}, data={'calibration': '{}'}).status_code == 422
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}, data={'sample_hz': 'nan'}).status_code == 422
    assert client.get('/api/jobs/missing').status_code == 404


def test_real_decode_job_and_exports_with_stub_segmenter(client, tmp_path, monkeypatch):
    # This checks decoding and the API contract, not ML accuracy.
    class FakeSegmenter:
        def predict(self, frame):
            h, w = frame.shape[:2]
            mask = np.zeros((h, w), np.uint8)
            cv2.fillPoly(mask, [np.array([[w*.45,h*.4],[w*.55,h*.4],[w*.9,h],[w*.1,h]],dtype=np.int32)], 1)
            return np.full((h,w), .96), mask, np.zeros_like(mask)
    monkeypatch.setattr(api, 'segmenter', FakeSegmenter())
    class FakeDepth:
        def predict(self, frame):
            return np.full(frame.shape[:2], 10, dtype=np.float32)
    monkeypatch.setattr(api, 'depth_model', FakeDepth())
    video = tmp_path / 'fixture.avi'
    writer = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*'MJPG'), 5, (320, 180))
    assert writer.isOpened()
    rng = np.random.default_rng(13)
    for _ in range(10):
        writer.write(rng.integers(30, 220, (180,320,3), dtype=np.uint8))
    writer.release()
    response = client.post('/api/jobs', files={'video': ('fixture.avi', video.read_bytes())}, data={'sample_hz': 1})
    assert response.status_code == 200
    job_id = response.json()['id']
    for _ in range(300):
        result = client.get(f'/api/jobs/{job_id}').json()
        if result['status'] in ['complete','failed']:
            break
        time.sleep(.05)
    assert result['status'] == 'complete', result
    assert len(result['results']) == 2
    assert all(r['width_m'] is None for r in result['results'])
    assert client.get(f'/api/jobs/{job_id}/frames/0').headers['content-type'] == 'image/jpeg'
    assert client.get(f'/api/jobs/{job_id}/frames/-1').status_code == 404
    csv = client.get(f'/api/jobs/{job_id}/export?format=csv').text
    assert 'timestamp_s' in csv and 'rough_width_m' in csv
    exported = client.get(f'/api/jobs/{job_id}/export').json()
    assert exported['calibration'] is None
    assert not list((tmp_path/job_id).glob('input.*'))
    assert client.get(f'/api/jobs/{job_id}/video').status_code == 200
    assert client.get(f'/api/jobs/{job_id}/map').status_code == 200
    assert (tmp_path/job_id/'source.mp4').exists()
    assert result['processed_video_frames'] == 10


def test_busy_queue_is_bounded(client):
    api.jobs['existing'] = {'status': 'processing'}
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}).status_code == 409


def test_reprocess_job(client, tmp_path, monkeypatch):
    class FakeSegmenter:
        def predict(self, frame):
            h, w = frame.shape[:2]
            mask = np.zeros((h, w), np.uint8)
            cv2.fillPoly(mask, [np.array([[w*.45,h*.4],[w*.55,h*.4],[w*.9,h],[w*.1,h]],dtype=np.int32)], 1)
            return np.full((h,w), .96), mask, np.zeros_like(mask)
    monkeypatch.setattr(api, 'segmenter', FakeSegmenter())
    class FakeDepth:
        def predict(self, frame):
            return np.full(frame.shape[:2], 10, dtype=np.float32)
    monkeypatch.setattr(api, 'depth_model', FakeDepth())

    video = tmp_path / 'fixture.avi'
    writer = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*'MJPG'), 5, (320, 180))
    for _ in range(10):
        writer.write(np.full((180, 320, 3), 100, dtype=np.uint8))
    writer.release()

    response = client.post('/api/jobs', files={'video': ('fixture.avi', video.read_bytes())}, data={'sample_hz': 1})
    job_id = response.json()['id']
    for _ in range(300):
        res = client.get(f'/api/jobs/{job_id}').json()
        if res['status'] in ['complete', 'failed']:
            break
        time.sleep(.05)
    assert res['status'] == 'complete'

    # Reprocess the completed job
    reproc = client.post(f'/api/jobs/{job_id}/reprocess')
    assert reproc.status_code == 200
    new_id = reproc.json()['id']
    assert new_id != job_id

    for _ in range(300):
        new_res = client.get(f'/api/jobs/{new_id}').json()
        if new_res['status'] in ['complete', 'failed']:
            break
        time.sleep(.05)
    assert new_res['status'] == 'complete'
    assert new_res['reprocessed_from'] == job_id


def test_gps_job_and_cancel(client, tmp_path, monkeypatch):
    class FakeSegmenter:
        def predict(self, frame):
            h, w = frame.shape[:2]
            return np.full((h,w), .95), np.ones((h, w), np.uint8), np.zeros((h, w), np.uint8)
    monkeypatch.setattr(api, 'segmenter', FakeSegmenter())
    class FakeDepth:
        def predict(self, frame):
            return np.full(frame.shape[:2], 8, dtype=np.float32)
    monkeypatch.setattr(api, 'depth_model', FakeDepth())

    video = tmp_path / 'fixture2.avi'
    writer = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*'MJPG'), 5, (320, 180))
    for _ in range(15):
        writer.write(np.full((180, 320, 3), 120, dtype=np.uint8))
    writer.release()

    gps_csv = (
        "timestamp_s,latitude,longitude\n"
        "0.0,51.500,-0.120\n"
        "1.0,51.501,-0.120\n"
        "2.0,51.502,-0.120\n"
        "3.0,51.503,-0.120\n"
    ).encode('utf-8')

    response = client.post(
        '/api/jobs',
        files={'video': ('fixture2.avi', video.read_bytes()), 'gps': ('track.csv', gps_csv, 'text/csv')},
        data={'sample_hz': 2, 'assumed_height_m': 1.6, 'hood_percent': 10, 'diagonal_fov': 95}
    )
    assert response.status_code == 200
    job_id = response.json()['id']

    # Test cancel endpoint
    cancel_res = client.post(f'/api/jobs/{job_id}/cancel')
    assert cancel_res.status_code == 200
    assert cancel_res.json()['ok'] is True

    for _ in range(300):
        res = client.get(f'/api/jobs/{job_id}').json()
        if res['status'] in ['complete', 'failed', 'cancelled']:
            break
        time.sleep(.05)
    assert res['status'] in ['complete', 'cancelled']


def test_options_validation(client):
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}, data={'sample_hz': 50}).status_code == 422
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}, data={'keyframe_hz': 0.1}).status_code == 422
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}, data={'diagonal_fov': 20}).status_code == 422
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}, data={'assumed_height_m': 10}).status_code == 422
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}, data={'hood_percent': 50}).status_code == 422
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}, data={'estimate_mode': 'invalid'}).status_code == 422
    assert client.post('/api/jobs', files={'video': ('x.mp4', b'x')}, data={'gps_offset_s': 1000000}).status_code == 422


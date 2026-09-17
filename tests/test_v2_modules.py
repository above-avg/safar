import math
import numpy as np
import pytest
import cv2
from backend.gps import parse_gps, gps_at
from backend.estimation import camera_matrix, backproject, anchor_depth_to_height, rough_width, displayed_width
from backend.mapping import SurveyMap, VisualOdometry
from backend.video import VideoEncoder, annotate
from backend.geometry import Calibration


def test_gps_csv_parsing_and_interpolation():
    csv_data = (
        "timestamp_s,latitude,longitude,accuracy_m\n"
        "0.0,51.5000,-0.1200,2.5\n"
        "1.0,51.5001,-0.1200,2.5\n"
        "2.0,51.5002,-0.1200,2.5\n"
    ).encode('utf-8')
    track = parse_gps(csv_data, 'route.csv', offset_s=5.0)
    assert track['origin']['latitude'] == 51.5000
    assert len(track['points']) == 3
    assert track['points'][0]['t'] == 5.0
    assert track['points'][1]['t'] == 6.0

    # Interpolate at t = 5.5
    pose = gps_at(track, 5.5)
    assert pose is not None
    assert pose['source'] == 'gps'
    assert pose['accuracy_m'] == 2.5
    assert pytest.approx(pose['x'], abs=0.5) == 0.0
    assert pose['y'] > 0

    # Outside bounds
    assert gps_at(track, 4.0) is None
    assert gps_at(track, 8.0) is None


def test_gps_gpx_parsing():
    gpx_data = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<gpx version="1.1" creator="test">\n'
        '  <trk><trkseg>\n'
        '    <trkpt lat="40.7128" lon="-74.0060"><time>2026-09-17T12:00:00Z</time></trkpt>\n'
        '    <trkpt lat="40.7129" lon="-74.0060"><time>2026-09-17T12:00:02Z</time></trkpt>\n'
        '  </trkseg></trk>\n'
        '</gpx>'
    ).encode('utf-8')
    track = parse_gps(gpx_data, 'track.gpx')
    assert len(track['points']) == 2
    assert track['points'][0]['t'] == 0.0
    assert track['points'][1]['t'] == 2.0


def test_gps_validation_rejections():
    # Entity injection
    with pytest.raises(ValueError, match="XML entities"):
        parse_gps(b'<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file">]><gpx></gpx>', 'test.gpx')

    # Non-increasing timestamps
    bad_csv = "timestamp_s,latitude,longitude\n1.0,10,10\n0.5,10,10\n".encode()
    with pytest.raises(ValueError, match="strictly increasing"):
        parse_gps(bad_csv, 'test.csv')

    # Unsupported format
    with pytest.raises(ValueError, match="CSV or GPX"):
        parse_gps(b'xyz', 'test.txt')


def test_camera_matrix_uncalibrated_and_calibrated():
    k = camera_matrix(1280, 720, diagonal_fov=90)
    assert k[0, 2] == 640.0
    assert k[1, 2] == 360.0
    assert k[0, 0] > 0
    assert k[0, 0] == k[1, 1]

    cal = Calibration(image_width=1920, image_height=1080, fx=1200, fy=1200, cx=960, cy=540, height_m=1.5, pitch_deg=5)
    k_cal = camera_matrix(1280, 720, calibration=cal)
    assert k_cal[0, 2] == pytest.approx(960 * (1280 / 1920))
    assert k_cal[1, 2] == pytest.approx(540 * (720 / 1080))


def test_backproject():
    k = np.array([[1000, 0, 500], [0, 1000, 500], [0, 0, 1]], dtype=float)
    depth = np.full((1000, 1000), 10.0, dtype=np.float32)
    pts = backproject([[500, 500], [600, 500]], depth, k)
    assert np.allclose(pts[0], [0.0, 0.0, 10.0])
    assert np.allclose(pts[1], [1.0, 0.0, 10.0])


def test_anchor_depth_to_height():
    h, w = 400, 600
    mask = np.zeros((h, w), dtype=bool)
    mask[200:380, 100:500] = True
    k = np.array([[500, 0, 300], [0, 500, 200], [0, 0, 1]], dtype=float)
    # Camera at height 1.5, pointing level: y_world = 1.5 => (pixel_y - cy) * Z / fy = 1.5 => Z = 1.5 * fy / (pixel_y - cy)
    depth = np.full((h, w), 5.0, dtype=np.float32)
    yy, xx = np.indices((h, w))
    valid_y = yy > 200
    depth[valid_y] = (1.5 * 500) / np.maximum(yy[valid_y] - 200, 1)

    scaled_depth, anchor = anchor_depth_to_height(depth, mask, k, height_m=1.5)
    assert anchor['applied'] is True
    assert pytest.approx(anchor['scale_factor'], abs=0.15) == 1.0


def test_rough_width_and_displayed_width():
    h, w = 360, 640
    k = camera_matrix(w, h, diagonal_fov=90)
    mask = np.zeros((h, w), dtype=bool)
    # Road polygon trapezoid: 6 meters wide road from 5m to 25m distance
    cv2.fillPoly(mask.view(np.uint8), [np.array([[200, 200], [440, 200], [550, 340], [90, 340]], dtype=np.int32)], 1)
    mask = mask.astype(bool)
    depth = np.full((h, w), 10.0, dtype=np.float32)
    result = {'pixel_pairs': [[[200, 220], [440, 220]], [[180, 260], [460, 260]], [[150, 300], [490, 300]]], 'reasons': []}

    rough_width(result, depth, mask, k, diagonal_fov=90)
    assert result['rough_width_m'] is not None
    assert result['rough_range_m'] is not None
    assert result['rough_range_m'][0] <= result['rough_width_m'] <= result['rough_range_m'][1]
    assert displayed_width(result) == result['rough_width_m']

    # When calibrated width_m is present, displayed_width prefers width_m
    result['width_m'] = 7.0
    assert displayed_width(result) == 7.0


def test_survey_map_lifecycle():
    sm = SurveyMap()
    k = camera_matrix(640, 360)
    depth = np.full((360, 640), 10.0, dtype=np.float32)
    labels = np.zeros((360, 640), dtype=np.uint8)

    # Add observations
    pose1 = {'x': 0.0, 'y': 0.0, 'yaw': 0.0, 'source': 'visual_depth', 'valid': True}
    res1 = {'width_m': 6.5, 'sections': [{'distance_m': 10.0, 'ground': [[-3.0, 10.0], [3.0, 10.0]]}, {'distance_m': 15.0, 'ground': [[-3.0, 15.0], [3.0, 15.0]]}]}
    sm.add(0.0, res1, depth, labels, k, pose1)

    pose2 = {'x': 0.0, 'y': 5.0, 'yaw': 0.0, 'source': 'visual_depth', 'valid': True}
    res2 = {'rough_width_m': 6.2, 'rough_sections': [{'distance_m': 10.0, 'ground': [[-3.1, 10.0], [3.1, 10.0]]}, {'distance_m': 15.0, 'ground': [[-3.1, 15.0], [3.1, 15.0]]}]}
    sm.add(1.0, res2, depth, labels, k, pose2)

    data = sm.finish()
    assert len(data['route']) == 2
    assert len(data['footprints']) == 2
    assert data['route_length_m'] == 5.0
    assert data['median_width_m'] == pytest.approx(6.35, abs=0.1)


def test_video_encoder_and_annotation(tmp_path):
    frame = np.zeros((180, 320, 3), dtype=np.uint8)
    mask = np.zeros((180, 320), dtype=bool)
    mask[80:160, 60:260] = True
    result = {'width_m': 6.5, 'rough_width_m': None, 'sections': [{'pixels': [[60, 120], [260, 120]]}]}

    annotated = annotate(frame, mask, result, tracked=False)
    assert annotated.shape == (180, 320, 3)

    out_file = tmp_path / "test_out.mp4"
    encoder = VideoEncoder(out_file, 320, 180, 10)
    for _ in range(5):
        encoder.write(annotated)
    encoder.close()

    assert out_file.exists()
    assert out_file.stat().st_size > 0

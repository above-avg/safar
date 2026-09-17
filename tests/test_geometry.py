import cv2
import numpy as np
import pytest
from backend.geometry import Calibration, ground_points, image_points, cross_sections, analyze_mask


def camera(**changes):
    return Calibration(image_width=1280, image_height=720, fx=900, fy=900, cx=640, cy=360, height_m=1.5, pitch_deg=5, **changes)


def test_projection_roundtrip_with_roll_and_distortion():
    c = camera(roll_deg=4, distortion=[.02, -.01, .001, .001, 0])
    ground = np.array([[-3.5, 6], [3.5, 6], [-3.5, 16], [3.5, 16]])
    pixel = image_points(ground, c, 1280, 720)
    assert np.allclose(ground_points(pixel, c, 1280, 720), ground, atol=1e-5)


def test_calibration_rescales_with_video_resolution():
    c = camera()
    assert np.allclose(ground_points([[300, 550]], c, 1280, 720), ground_points([[150, 275]], c, 640, 360))


def test_horizon_does_not_create_infinite_measurements():
    c = camera()
    assert np.isnan(ground_points([[640, 0]], c, 1280, 720)).all()


@pytest.mark.parametrize('slope', [0, .3, -.4])
def test_cross_sections_measure_perpendicular_to_centerline(slope):
    c = camera()
    # Parallel edges x = slope*z +/- half, whose perpendicular spacing is 7 m.
    half = 3.5 * np.sqrt(1 + slope*slope)
    pairs = []
    for z in np.linspace(5, 25, 36):
        pts = np.array([[slope*z-half, z], [slope*z+half, z]])
        pairs.append(image_points(pts, c, 1280, 720).tolist())
    sections = cross_sections(pairs, c, 1280, 720)
    assert len(sections) >= 3
    assert np.median([s['width_m'] for s in sections]) == pytest.approx(7, abs=.02)


def image_and_mask():
    rng = np.random.default_rng(7)
    frame = rng.integers(40, 210, (720, 1280, 3), dtype=np.uint8)
    mask = np.zeros((720, 1280), np.uint8)
    pts = image_points(np.array([[-3.5, 25], [3.5, 25], [3.5, 4], [-3.5, 4]]), camera(), 1280, 720)
    cv2.fillPoly(mask, [pts.astype(np.int32)], 1)
    return frame, mask


def test_video_only_never_emits_metres():
    frame, mask = image_and_mask()
    result = analyze_mask(np.full(mask.shape, .97), mask, frame)
    assert result['width_m'] is None
    assert result['sensitivity_m'] is None
    assert result['status'] == 'unscaled'
    assert result['pixel_span'] > 0


def test_known_ground_geometry_recovers_width():
    frame, mask = image_and_mask()
    result = analyze_mask(np.full(mask.shape, .97), mask, frame, camera())
    assert result['width_m'] == pytest.approx(7, abs=.08)
    assert result['sensitivity_m'][0] <= result['width_m'] <= result['sensitivity_m'][1]


def test_empty_and_cropped_masks_abstain():
    frame, mask = image_and_mask()
    for rejected_mask in [np.zeros_like(mask), np.ones_like(mask)]:
        result = analyze_mask(np.ones(mask.shape), rejected_mask, frame, camera())
        assert result['width_m'] is None
        assert result['reasons']


def test_occluded_cross_sections_abstain():
    frame, mask = image_and_mask()
    mask[:, 620:660] = 0
    # Two disconnected components must not be silently merged across an occluder.
    result = analyze_mask(np.full(mask.shape, .97), mask, frame, camera())
    assert result['width_m'] is None
    assert result['pixel_span'] < 600
    assert any('competing' in reason for reason in result['reasons'])


def test_blur_rejects_metric_output():
    frame, mask = image_and_mask()
    result = analyze_mask(np.full(mask.shape, .97), mask, np.full_like(frame, 120), camera())
    assert result['width_m'] is None
    assert any('Blur' in reason for reason in result['reasons'])


def test_obstacles_at_boundaries_block_metric_estimates():
    frame, mask = image_and_mask()
    obstacles = cv2.dilate(mask, np.ones((9, 9), np.uint8)) - mask
    result = analyze_mask(np.full(mask.shape, .97), mask, frame, camera(), obstacle_mask=obstacles)
    assert result['width_m'] is None
    assert any('occluded' in reason for reason in result['reasons'])


def test_invalid_calibration_is_rejected():
    with pytest.raises(ValueError):
        camera(height_error_m=2)

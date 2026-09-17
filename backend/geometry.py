"""Conservative image-to-ground geometry. World axes: right, down, forward."""
import math
import cv2
import numpy as np
from pydantic import BaseModel, Field, ConfigDict, model_validator


class Calibration(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False, extra="forbid")
    image_width: int = Field(gt=0, le=16384)
    image_height: int = Field(gt=0, le=16384)
    fx: float = Field(gt=0)
    fy: float = Field(gt=0)
    cx: float = Field(ge=0)
    cy: float = Field(ge=0)
    height_m: float = Field(gt=0.1, lt=10)
    pitch_deg: float = Field(ge=-30, le=45)
    roll_deg: float = Field(default=0, ge=-30, le=30)
    distortion: list[float] = Field(default_factory=lambda: [0, 0, 0, 0, 0], min_length=5, max_length=5)
    height_error_m: float = Field(default=0.05, gt=0, le=1)
    angle_error_deg: float = Field(default=1, gt=0, le=10)
    focal_error_pct: float = Field(default=2, gt=0, le=20)

    @model_validator(mode="after")
    def plausible_profile(self):
        if self.cx >= self.image_width or self.cy >= self.image_height:
            raise ValueError("Principal point must be inside the calibration image")
        if self.height_error_m >= self.height_m:
            raise ValueError("Height uncertainty must be smaller than camera height")
        return self


def rotation(c):
    p, r = math.radians(c.pitch_deg), math.radians(c.roll_deg)
    pitch = np.array([[1, 0, 0], [0, math.cos(p), math.sin(p)], [0, -math.sin(p), math.cos(p)]])
    roll = np.array([[math.cos(r), -math.sin(r), 0], [math.sin(r), math.cos(r), 0], [0, 0, 1]])
    return pitch @ roll


def intrinsics(c, width, height):
    sx, sy = width / c.image_width, height / c.image_height
    return np.array([[c.fx * sx, 0, c.cx * sx], [0, c.fy * sy, c.cy * sy], [0, 0, 1]], dtype=float)


def ground_points(pixels, c, width, height):
    pts = cv2.undistortPoints(np.array(pixels, dtype=float).reshape(-1, 1, 2), intrinsics(c, width, height), np.array(c.distortion)).reshape(-1, 2)
    rays = np.column_stack([pts, np.ones(len(pts))]) @ rotation(c).T
    good = rays[:, 1] > 0.025
    scale = np.divide(c.height_m, rays[:, 1], out=np.full(len(rays), np.nan), where=good)
    return (rays * scale[:, None])[:, [0, 2]]


def image_points(ground, c, width, height):
    world = np.column_stack([ground[:, 0], np.full(len(ground), c.height_m), ground[:, 1]])
    camera = world @ rotation(c)
    pixels, _ = cv2.projectPoints(camera, np.zeros(3), np.zeros(3), intrinsics(c, width, height), np.array(c.distortion))
    return pixels.reshape(-1, 2)


def cross_sections(pairs, c, width, height):
    left = ground_points([p[0] for p in pairs], c, width, height)
    right = ground_points([p[1] for p in pairs], c, width, height)
    valid = np.isfinite(left).all(axis=1) & np.isfinite(right).all(axis=1)
    valid &= (left[:, 1] > 2) & (left[:, 1] < 35) & (right[:, 1] > 2) & (right[:, 1] < 35)
    left, right = left[valid], right[valid]
    if len(left) < 5:
        return []
    left, right = left[np.argsort(left[:, 1])], right[np.argsort(right[:, 1])]
    near, far = max(left[0, 1], right[0, 1]), min(left[-1, 1], right[-1, 1])
    if far - near < 1:
        return []
    zs = np.linspace(near, far, 24)
    centers = (np.interp(zs, left[:, 1], left[:, 0]) + np.interp(zs, right[:, 1], right[:, 0])) / 2
    slopes = np.gradient(centers, zs)
    sections = []
    for i in range(2, len(zs) - 2, 2):
        center = np.array([centers[i], zs[i]])
        normal = np.array([1., -slopes[i]])
        normal /= np.linalg.norm(normal)
        hits = []
        for edge in (left, right):
            candidates = []
            for a, b in zip(edge[:-1], edge[1:]):
                mat = np.column_stack([normal, -(b - a)])
                if abs(np.linalg.det(mat)) < 1e-8:
                    continue
                t, u = np.linalg.solve(mat, a - center)
                if 0 <= u <= 1:
                    candidates.append((abs(t), t, center + t * normal))
            if not candidates:
                break
            hits.append(min(candidates, key=lambda x: x[0]))
        if len(hits) != 2 or hits[0][1] >= 0 or hits[1][1] <= 0:
            continue
        span = hits[1][1] - hits[0][1]
        if 1.5 <= span <= 25:
            ends = np.array([hits[0][2], hits[1][2]])
            sections.append({"width_m": float(span), "distance_m": float(zs[i]), "ground": ends.tolist(), "pixels": image_points(ends, c, width, height).tolist()})
    return sections


def analyze_mask(probability, road_mask, frame, calibration=None, previous_width=None, obstacle_mask=None):
    height, width = road_mask.shape
    count, labels, stats, _ = cv2.connectedComponentsWithStats(road_mask.astype(np.uint8), 8)
    reasons = []
    if count < 2:
        return {"status": "rejected", "reasons": ["No road surface detected"], "width_m": None, "quality": 0, "polygon": [], "sections": []}
    # Select the component occupying the lower central image, not the largest distant road.
    roi = labels[int(height * .6):int(height * .92), int(width * .3):int(width * .7)]
    votes = np.bincount(roi.ravel(), minlength=count)
    votes[0] = 0
    if votes.max() == 0:
        return {"status": "rejected", "reasons": ["No ego-road component visible"], "width_m": None, "quality": 0, "polygon": [], "sections": []}
    mask = labels == int(votes.argmax())
    ambiguous_components = int(np.count_nonzero(votes > votes.max() * .2)) > 1
    if ambiguous_components:
        reasons.append("Multiple competing road components: possible occlusion or divided geometry")
    contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contour = max(contours, key=cv2.contourArea)
    polygon = cv2.approxPolyDP(contour, 2, True).reshape(-1, 2).tolist()
    rings, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    mask_rings = [cv2.approxPolyDP(ring, 1, True).reshape(-1, 2).tolist() for ring in rings]
    pairs = []
    rejected_rows = 0
    road_rows = np.flatnonzero(mask.sum(axis=1) > width * .06)
    first_row = max(height * .25, road_rows[0])
    last_row = min(height * .94, road_rows[-1])
    for y in np.linspace(first_row, last_row, 64).astype(int):
        xs = np.flatnonzero(mask[y])
        if len(xs) < width * .06:
            continue
        l, r = int(xs[0]), int(xs[-1])
        if obstacle_mask is not None:
            radius = max(3, round(width * .006))
            if (np.any(obstacle_mask[max(0,y-2):y+3, max(0,l-radius):l+radius+1]) or
                    np.any(obstacle_mask[max(0,y-2):y+3, max(0,r-radius):r+radius+1])):
                rejected_rows += 1
                continue
        # Missing edge / internal obstacle means this cross-section is not observable.
        if l <= width * .015 or r >= width * .985 or np.mean(mask[y, l:r + 1]) < .985:
            rejected_rows += 1
            continue
        pairs.append([[l, int(y)], [r, int(y)]])
    confidence = float(np.mean(probability[mask]))
    blur = float(cv2.Laplacian(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY), cv2.CV_64F).var())
    light = float(np.mean(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)))
    visibility = min(1, len(pairs) / 18)
    quality = min(confidence, visibility, min(1, blur / 70))
    if ambiguous_components:
        quality = min(quality, .4)
    if len(pairs) < 6:
        reasons.append("Too few fully visible road cross-sections")
    if rejected_rows > 8:
        reasons.append("Road edges cropped or surface occluded")
    if confidence < .75:
        reasons.append("Weak road segmentation")
    if blur < 25:
        reasons.append("Blur or low image texture")
    if light < 35 or light > 225:
        reasons.append("Poor exposure")
        quality *= .6
    sections, metric, interval = [], None, None
    if calibration and len(pairs) >= 6:
        sections = cross_sections(pairs, calibration, width, height)
        if len(sections) >= 3 and quality >= .55:
            metric = float(np.median([s["width_m"] for s in sections]))
            samples = [metric]
            # Sensitivity envelope: perturb calibration and edges; not a statistical CI.
            for field, delta in [("height_m", calibration.height_error_m), ("pitch_deg", calibration.angle_error_deg), ("roll_deg", calibration.angle_error_deg), ("fx", calibration.fx * calibration.focal_error_pct / 100), ("fy", calibration.fy * calibration.focal_error_pct / 100)]:
                for sign in (-1, 1):
                    changed = calibration.model_copy(update={field: getattr(calibration, field) + sign * delta})
                    result = cross_sections(pairs, changed, width, height)
                    if len(result) >= 3:
                        samples.append(float(np.median([s["width_m"] for s in result])))
            for shift in (-3, 3):
                shifted = [[[l[0] - shift, l[1]], [r[0] + shift, r[1]]] for l, r in pairs]
                result = cross_sections(shifted, calibration, width, height)
                if len(result) >= 3:
                    samples.append(float(np.median([s["width_m"] for s in result])))
            interval = [round(min(samples), 2), round(max(samples), 2)]
            if previous_width and abs(metric - previous_width) / previous_width > .2:
                reasons.append("Abrupt width change: geometry or scene transition")
                quality *= .6
            if (interval[1] - interval[0]) / metric > .35:
                reasons.append("Highly sensitive to calibration")
                quality *= .6
        else:
            reasons.append("Insufficient reliable ground-plane geometry")
    if not calibration:
        reasons.append("Metric scale unavailable: calibrated camera required")
    if metric is not None and quality < .55:
        metric, interval = None, None
    status = "conditional" if metric is not None else ("unscaled" if not calibration and len(pairs) >= 6 and quality >= .55 else "review")
    return {"status": status, "width_m": round(metric, 3) if metric is not None else None,
            "sensitivity_m": interval, "quality": round(quality, 3),
            "road_probability": round(confidence, 3), "visibility": round(visibility, 3), "sharpness": round(blur, 1),
            "reasons": reasons, "polygon": polygon, "mask_rings": mask_rings, "sections": sections if metric is not None else [],
            "pixel_pairs": pairs, "pixel_span": int(np.median([r[0] - l[0] for l, r in pairs])) if pairs else None}

# Read the Road — measurement system

## Product contract

Upload dashcam footage, inspect an animated road-surface overlay and boundary traces, and review timestamped carriageway-width estimates with supporting evidence. Carriageway means the connected paved road surface, excluding sidewalks; it is not a lane count, lane width, or legal right of way. Medians separate carriageways. Parked vehicles, shoulders and intersections require an explicit labeling policy and review.

Absolute scale is not identifiable from arbitrary monocular video. Without a measured scale source, display road masks and pixel spans but abstain from metre-valued output. Camera height alone is insufficient: intrinsics and camera orientation relative to the road plane are also needed. A nominal lane width must never silently become ground truth.

## Pipeline

1. Decode timestamped frames; preserve original dimensions. Sample for offline inference and retain provenance.
2. Segment road pixels using a pretrained semantic road model. The initial model is SegFormer B0 fine-tuned on Cityscapes. Use its road class, not generic object detection boxes.
3. Select the ego-connected road component. Trace visible boundaries, reject fragmented/cropped cross-sections, and expose ambiguity rather than filling missing edges with invented geometry.
4. With camera calibration, intersect undistorted image rays with a local road plane. Fit a ground-plane centerline and measure across its normal, rather than assuming image-horizontal spans equal true widths on curves.
5. Aggregate accepted cross-sections robustly, track change over time, and flag instability. Do not smooth across intersections or conceal abrupt real narrowing.
6. Propagate boundary and calibration perturbations into a sensitivity interval. Keep this distinct from an empirically calibrated prediction interval. Quality scores are diagnostic heuristics until ground-truth validation calibrates them.
7. Show synchronized video, projected measurement lines, a bird's-eye view, width history, quality factors and rejection reasons. Export timestamped JSON and CSV.

## Scale and sensor modes

| Available input | Behavior |
| --- | --- |
| Video only | Road segmentation and pixel spans; metres withheld |
| Intrinsics, measured mounting height, pitch, roll | Conditional metric estimate under a local planar-road assumption |
| Calibration plus synchronized IMU | Update orientation; reject unreliable attitude intervals |
| Stereo or LiDAR | Metric 3D surface reconstruction and cross-section measurement |
| Video plus GPS / wheel odometry | Constrain visual-odometry scale over time; GPS alone is not a per-pixel depth map |
| Learned monocular metric depth | Experimental scale prior; cross-check against a measured anchor and domain-specific validation |

The prototype implements video and fixed-calibration modes. IMU fusion, stereo/LiDAR, visual odometry and learned depth are planned extensions, not enabled capabilities.

## Difficult environments

Road crests, dips, banked curves, changing camera pitch, intersections, dirt roads, night footage, rain, shadows, glare and severe occlusion violate baseline assumptions or shift the segmentation domain. Prototype diagnostics catch some visibility and instability failures, but do not reliably detect every such scene. Production must add scene classification, local piecewise 3D road surfaces, explicit obstacle/occlusion masks and out-of-distribution detection. Keep an unresolved state and a human review queue.

For fine-tuning, collect labeled local footage spanning urban, rural, divided, unmarked and unpaved roads. Label road edges, shoulder transitions, median/curb classes, visibility and ambiguous regions. Split evaluation by physical route, capture day and camera rig to prevent adjacent-frame leakage. Evaluate road IoU and boundary distance alongside width MAE, bias, P90/P95 error, interval coverage, accepted-measurement coverage and false acceptance rate. Report these by environment and measurement range; no universal accuracy promise is justified before evaluation.

## Deployment path

The local prototype uses a Python API, one inference worker and a browser dashboard. Production needs durable jobs, bounded GPU queues, resumable chunking, object storage, authentication, quotas, telemetry and a spatial database. Maintain camera profiles per vehicle and calibration validity checks. Record model version, calibration, source timestamps and quality reasons for every exported measurement. Only emit geospatial coordinates when a synchronized positioning source exists.

## References

- SegFormer Cityscapes model: https://huggingface.co/nvidia/segformer-b0-finetuned-cityscapes-1024-1024
- OpenCV calibration and 3D reconstruction: https://docs.opencv.org/4.x/d9/d0c/group__calib3d.html
- Depth Anything V2 metric-depth extension: https://github.com/DepthAnything/Depth-Anything-V2/tree/main/metric_depth

Review model and dataset licenses before commercial deployment. Pretrained Cityscapes performance does not establish accuracy on local survey footage.

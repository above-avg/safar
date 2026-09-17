"""Rough measurements from a learned metric-depth prior, never calibrated truth."""
import math
import cv2
import numpy as np
from .geometry import intrinsics


def camera_matrix(width, height, diagonal_fov=90, calibration=None):
    if calibration:
        return intrinsics(calibration, width, height)
    focal = math.hypot(width, height) / (2 * math.tan(math.radians(diagonal_fov) / 2))
    return np.array([[focal, 0, width/2], [0, focal, height/2], [0, 0, 1]], dtype=float)


def backproject(pixels, depth, k):
    pixels = np.asarray(pixels, dtype=float).reshape(-1,2)
    uv = np.rint(pixels).astype(int)
    uv[:,0] = np.clip(uv[:,0],0,depth.shape[1]-1)
    uv[:,1] = np.clip(uv[:,1],0,depth.shape[0]-1)
    z = depth[uv[:,1],uv[:,0]]
    return np.column_stack([(pixels[:,0]-k[0,2])*z/k[0,0],(pixels[:,1]-k[1,2])*z/k[1,1],z])


def anchor_depth_to_height(depth,mask,k,height_m=1.5):
    """Use a declared mounting-height prior to constrain arbitrary learned scale.

    A RANSAC plane fit uses visible road points. The height is an assumption unless
    measured, and is recorded; it must never be represented as recovered truth.
    """
    yy,xx=np.nonzero(mask)
    if len(xx)<300:
        return depth,{'applied':False,'reason':'Insufficient road plane support'}
    stride=max(1,len(xx)//1800)
    pts=backproject(np.column_stack([xx[::stride],yy[::stride]]),depth,k)
    pts=pts[(pts[:,2]>2)&(pts[:,2]<55)&np.isfinite(pts).all(axis=1)]
    if len(pts)<100:
        return depth,{'applied':False,'reason':'Road depth outside fitting range'}
    rng=np.random.default_rng(31)
    best=None
    best_count=0
    for _ in range(90):
        triple=pts[rng.choice(len(pts),3,replace=False)]
        normal=np.cross(triple[1]-triple[0],triple[2]-triple[0])
        norm=np.linalg.norm(normal)
        if norm<1e-6:
            continue
        normal/=norm
        if abs(normal[1])<.5:
            continue
        offset=-float(normal@triple[0])
        support=np.abs(pts@normal+offset)<max(.12,abs(offset)*.1)
        if support.sum()>best_count:
            best_count=int(support.sum())
            best=support
    if best is None or best_count/len(pts)<.55:
        return depth,{'applied':False,'reason':'No stable local road plane for height anchoring'}
    selected=pts[best]
    centroid=selected.mean(axis=0)
    _,_,vectors=np.linalg.svd(selected-centroid,full_matrices=False)
    normal=vectors[-1]
    inferred_height=abs(float(normal@centroid))
    if inferred_height<.2 or inferred_height>20:
        return depth,{'applied':False,'reason':'Predicted road-plane scale implausible'}
    factor=height_m/inferred_height
    return (depth*factor).astype(np.float32),{'applied':True,'assumed_height_m':height_m,'raw_depth_plane_height_m':round(inferred_height,3),'scale_factor':round(factor,4),'plane_support':round(best_count/len(pts),3),'normal':normal.tolist()}


def rough_width(result, depth, road_mask, k, diagonal_fov=90, calibrated_intrinsics=False):
    """Adds a separate approximate estimate without replacing calibrated width_m.

    Samples inside edges to avoid reading an obstacle's depth. Complete visible
    pairs are preferred. Image-truncated sections are a lower-bound observation,
    explicitly reported as such, rather than extrapolated to invented edges.
    """
    result.update(rough_width_m=None, rough_range_m=None, estimate_kind='unavailable', rough_sections=[])
    pairs = result.get('pixel_pairs', [])
    lower_bound = False
    if len(pairs) < 3:
        pairs = []
        h,w = road_mask.shape
        rows = np.flatnonzero(road_mask.sum(axis=1)>w*.15)
        if len(rows):
            for y in np.linspace(rows[0],rows[-1],24).astype(int):
                xs = np.flatnonzero(road_mask[y])
                if len(xs)<w*.15:
                    continue
                l,r = int(xs[0]),int(xs[-1])
                if np.mean(road_mask[y,l:r+1])<.92:
                    continue
                pairs.append([[l,int(y)],[r,int(y)]])
            lower_bound = True
    sections=[]
    h,w=depth.shape
    for left,right in pairs:
        l,y = left
        r,_ = right
        if r-l < 20:
            continue
        inset = max(2, min(8, round((r-l)*.025)))
        zs=[]
        for x in (l+inset,r-inset):
            patch=depth[max(0,y-2):min(h,y+3),max(0,x-2):min(w,x+3)]
            zs.append(float(np.median(patch)))
        if not all(1.5<z<55 and np.isfinite(z) for z in zs):
            continue
        # Pair depth inconsistency is often an occlusion or a segmentation error.
        if max(zs)/min(zs)>1.8:
            continue
        z=float(np.median(zs))
        x1=(l-k[0,2])*z/k[0,0]
        x2=(r-k[0,2])*z/k[0,0]
        span=x2-x1
        if not .8<span<35:
            continue
        sections.append({'width_m':float(span),'distance_m':z,'ground':[[x1,z],[x2,z]],'pixels':[left,right]})
    if len(sections)<3:
        result['reasons'].append('Depth/road evidence insufficient for a useful rough width')
        return result
    widths=np.array([s['width_m'] for s in sections])
    median=float(np.median(widths))
    # Robustly exclude gross inconsistent rows, without hiding the scatter from uncertainty.
    mad=float(np.median(np.abs(widths-median)))
    kept=[s for s in sections if abs(s['width_m']-median)<max(.4*median,3*mad)]
    if len(kept)<3:
        return result
    median=float(np.median([s['width_m'] for s in kept]))
    fov_low=1 if calibrated_intrinsics else math.tan(math.radians(max(35,diagonal_fov-20))/2)/math.tan(math.radians(diagonal_fov)/2)
    fov_high=1 if calibrated_intrinsics else math.tan(math.radians(min(150,diagonal_fov+20))/2)/math.tan(math.radians(diagonal_fov)/2)
    scatter=max(.35, min(.75, mad/max(median,.1)*2))
    low=max(.3,median*(1-scatter)*fov_low)
    high=median*(1+scatter)*fov_high
    result.update(rough_width_m=round(median,1),rough_range_m=[round(low,1),round(high,1)],
                  estimate_kind='visible_lower_bound' if lower_bound else 'learned_depth',rough_sections=kept,
                  estimate_assumptions={'depth':'outdoor learned metric prior; domain bias unknown',
                    'intrinsics':'calibrated' if calibrated_intrinsics else f'assumed {diagonal_fov:g} degree diagonal FOV',
                    'range':'scenario envelope, not a confidence interval', 'depth_sensitivity_fraction':scatter})
    result['reasons']=[r for r in result['reasons'] if not r.startswith('Metric scale unavailable')]
    result['reasons'].append('Rough AI depth estimate; absolute scale and road-edge bias are unvalidated')
    if lower_bound:
        result['reasons'].append('Edges incomplete: displayed width describes visible surface only; full road may be wider')
    if result.get('width_m') is None:
        result['status']='rough_lower_bound' if lower_bound else 'rough'
    return result


def displayed_width(row):
    return row.get('width_m') if row.get('width_m') is not None else row.get('rough_width_m')

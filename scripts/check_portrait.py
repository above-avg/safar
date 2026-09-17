import sys,json,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import cv2
from backend.model import RoadSegmenter,MetricDepth
from backend.geometry import analyze_mask
from backend.estimation import rough_width,camera_matrix,anchor_depth_to_height
from backend.video import annotate
segmenter=RoadSegmenter()
depth_model=MetricDepth()
for i in (0,7,14):
    frame=cv2.imread(str(ROOT/f'data/a7dc9dd33d7d45bc99dfd362318a3ab4/frame-{i:05d}.jpg'))
    start=time.monotonic()
    probability,mask,obstacles=segmenter.predict(frame)
    depth=depth_model.predict(frame)
    mask[int(frame.shape[0]*.85):]=False
    depth,anchor=anchor_depth_to_height(depth,mask,camera_matrix(frame.shape[1],frame.shape[0]))
    result=analyze_mask(probability,mask,frame,obstacle_mask=obstacles)
    rough_width(result,depth,mask,camera_matrix(frame.shape[1],frame.shape[0]))
    output=ROOT/'data/smoke'/f'portrait-v2-{i}.jpg'
    cv2.imwrite(str(output),annotate(frame,mask,result))
    print(json.dumps({'frame':i,'seconds':round(time.monotonic()-start,1),'rough':result['rough_width_m'],'range':result['rough_range_m'],'quality':result['quality'],'pairs':len(result.get('pixel_pairs',[])),'kind':result['estimate_kind'],'anchor':anchor,'reasons':result['reasons']}),flush=True)

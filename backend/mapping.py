"""Local road-corridor map with explicit positioning provenance and gaps."""
import math
import cv2
import numpy as np
from .estimation import backproject, displayed_width


class VisualOdometry:
    def __init__(self,k):
        self.k=k
        self.orb=cv2.ORB_create(nfeatures=2200, fastThreshold=12)
        self.previous=None
        self.rotation=np.eye(3)
        self.position=np.zeros(3)
        self.connected=True

    def update(self,frame,depth,labels,timestamp):
        gray=cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY)
        allowed=np.full(gray.shape,255,np.uint8)
        if labels is not None:
            allowed[(labels>=10)]=0 # sky, people and traffic
        allowed[:int(gray.shape[0]*.18)]=0
        keypoints,descriptors=self.orb.detectAndCompute(gray,allowed)
        current=(keypoints,descriptors,depth.copy(),timestamp,gray)
        if self.previous is None:
            self.previous=current
            return {'x':0.,'y':0.,'yaw':0.,'source':'visual_depth','valid':True,'inliers':0,'anchor':True}
        old_points,old_desc,old_depth,old_t,old_gray=self.previous
        self.previous=current
        def failure(reason):
            self.connected=False
            return {'source':'visual_depth','valid':False,'reason':reason}
        if not self.connected:
            return failure('Unregistered after a tracking gap; GPS can supply a separate position')
        if float(np.mean(np.abs(gray.astype(float)-old_gray.astype(float))))<.65:
            return {'x':float(self.position[0]),'y':float(self.position[2]),'yaw':math.atan2(self.rotation[0,2],self.rotation[2,2]),'source':'visual_depth','valid':True,'inliers':0,'stationary':True}
        if descriptors is None or old_desc is None or len(descriptors)<16 or len(old_desc)<16:
            return failure('Too few static visual features')
        matches=cv2.BFMatcher(cv2.NORM_HAMMING).knnMatch(old_desc,descriptors,k=2)
        good=[a for pair in matches if len(pair)==2 for a,b in [pair] if a.distance<.72*b.distance]
        if len(good)<16:
            return failure('Insufficient static feature matches')
        before=np.array([old_points[m.queryIdx].pt for m in good],np.float32)
        after=np.array([keypoints[m.trainIdx].pt for m in good],np.float32)
        xyz=backproject(before,old_depth,self.k)
        valid=np.isfinite(xyz).all(axis=1)&(xyz[:,2]>1)&(xyz[:,2]<60)
        if valid.sum()<16:
            return failure('Insufficient reliable depth for motion')
        success,rvec,tvec,inliers=cv2.solvePnPRansac(xyz[valid].astype(np.float32),after[valid],self.k,None,iterationsCount=150,reprojectionError=3.5,confidence=.995,flags=cv2.SOLVEPNP_EPNP)
        if not success or inliers is None or len(inliers)<12 or len(inliers)<valid.sum()*.25:
            return failure('Visual motion estimate rejected by RANSAC')
        relative,_=cv2.Rodrigues(rvec)
        delta=-relative.T@tvec.ravel()
        dt=max(.001,timestamp-old_t)
        if np.linalg.norm(delta)/dt>55 or np.linalg.norm(rvec)>1:
            return failure('Implausible visual speed or rotation')
        self.position+=self.rotation@delta
        self.rotation=self.rotation@relative.T
        return {'x':float(self.position[0]),'y':float(self.position[2]),'yaw':math.atan2(self.rotation[0,2],self.rotation[2,2]),'source':'visual_depth','valid':True,'inliers':len(inliers)}


class SurveyMap:
    def __init__(self,gps_track=None):
        self.gps_track=gps_track
        self.route=[]
        self.footprints=[]
        self.context={}
        self.skipped=0
        self.last_yaw=0

    @staticmethod
    def transform(points,pose):
        points=np.asarray(points,float)
        c,s=math.cos(pose['yaw']),math.sin(pose['yaw'])
        return np.column_stack([pose['x']+points[:,0]*c+points[:,1]*s,pose['y']-points[:,0]*s+points[:,1]*c])

    def add(self,timestamp,result,depth,labels,k,pose):
        if pose is None or not pose.get('valid',True):
            self.skipped+=1
            return
        pose=dict(pose)
        if pose.get('yaw') is None:
            pose['yaw']=self.last_yaw
        self.last_yaw=pose['yaw']
        result['position']={key:pose.get(key) for key in ('x','y','yaw','source','accuracy_m','inliers')}
        self.route.append({'timestamp_s':round(timestamp,3),'x':round(pose['x'],3),'y':round(pose['y'],3),'width_m':displayed_width(result),
                           'width_source':'calibrated' if result.get('width_m') is not None else result.get('estimate_kind','unavailable'),
                           'source':pose['source'],'gap_before':self.skipped>0 and (not self.route or timestamp-self.route[-1]['timestamp_s']>2),
                           'quality':result.get('quality',0)})
        sections=result.get('sections') or result.get('rough_sections') or []
        if len(sections)>=2:
            sections=sorted(sections,key=lambda s:s['distance_m'])
            ring=[s['ground'][0] for s in sections]+[s['ground'][1] for s in reversed(sections)]
            world=self.transform(ring,pose)
            self.footprints.append({'timestamp_s':round(timestamp,3),'points':np.round(world,2).tolist(),'width_m':displayed_width(result),
                                    'rough':result.get('width_m') is None,'lower_bound':result.get('estimate_kind')=='visible_lower_bound'})
        if labels is not None:
            h,w=depth.shape
            yy,xx=np.meshgrid(np.arange(0,h,20),np.arange(0,w,20),indexing='ij')
            ids=labels[yy,xx].ravel()
            points=backproject(np.column_stack([xx.ravel(),yy.ravel()]),depth,k)
            valid=np.isin(ids,[0,1,2,3,4,8,9])&(points[:,2]>2)&(points[:,2]<45)
            world=self.transform(points[valid][:,[0,2]],pose)
            for p,kind in zip(world,ids[valid]):
                key=(round(p[0]/.6),round(p[1]/.6),int(kind))
                if len(self.context)<60000 or key in self.context:
                    self.context[key]=[round(float(p[0]),2),round(float(p[1]),2),int(kind)]

    def finish(self):
        points=[[p['x'],p['y']] for p in self.route]+[p for f in self.footprints for p in f['points']]+[p[:2] for p in self.context.values()]
        if points:
            pts=np.asarray(points)
            bounds=[float(pts[:,0].min()),float(pts[:,1].min()),float(pts[:,0].max()),float(pts[:,1].max())]
        else:
            bounds=[-5,0,5,10]
        length=sum(math.hypot(b['x']-a['x'],b['y']-a['y']) for a,b in zip(self.route,self.route[1:]) if not b['gap_before'])
        widths=[p['width_m'] for p in self.route if p['width_m'] is not None]
        gps=bool(self.gps_track)
        return {'mode':'gps' if gps else 'visual_depth','units':'metres','coordinate_system':'local east/north' if gps else 'local initial-camera right/forward',
                'origin':self.gps_track['origin'] if gps else None,'route':self.route,'footprints':self.footprints,'context_points':list(self.context.values()),
                'bounds_m':bounds,'route_length_m':round(length,1),'extent_m':[round(bounds[2]-bounds[0],1),round(bounds[3]-bounds[1],1)],
                'median_width_m':round(float(np.median(widths)),1) if widths else None,'unregistered_frames':self.skipped,
                'disclaimer':('GPS locates the route; road widths and context projections still depend on camera/depth estimates. GPS gaps are not bridged.' if gps else
                    'Approximate visual odometry scaled by learned depth. Scale bias and accumulated drift can be substantial. Unregistered frames are excluded, not placed at invented positions.')+
                    ' This is a map of observed road corridor and projected context, not a complete aerial reconstruction of unseen landscape.'}

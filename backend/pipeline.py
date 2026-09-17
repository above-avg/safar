import json
import math
import subprocess
from pathlib import Path
import cv2
import numpy as np
import imageio_ffmpeg
from .geometry import analyze_mask
from .estimation import rough_width,camera_matrix,anchor_depth_to_height
from .model import TemporalRoad
from .gps import gps_at
from .mapping import VisualOdometry,SurveyMap
from .video import VideoEncoder,annotate


def normalize_video(source,target,fps):
    command=[imageio_ffmpeg.get_ffmpeg_exe(),'-y','-hide_banner','-loglevel','error','-i',str(source),'-an','-vf',
             f"scale=w='min(1280,iw)':h='min(1280,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
             '-r',str(fps),
             '-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(target)]
    proc=subprocess.run(command,capture_output=True,timeout=300,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    if proc.returncode:
        raise ValueError('Video conversion failed: '+proc.stderr.decode(errors='replace')[-500:])


def run_pipeline(job_id,path,calibration,gps_track,options,models,update,cancelled):
    cap=None
    encoder=None
    folder=path.parent
    results=[]
    try:
        cap=cv2.VideoCapture(str(path))
        if not cap.isOpened():
            raise ValueError('Video could not be decoded')
        fps=float(cap.get(cv2.CAP_PROP_FPS))
        count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        width=int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height=int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        cap.release()
        cap=None
        if not math.isfinite(fps) or fps<=0 or count<=0:
            raise ValueError('Video timing metadata unavailable')
        if count/fps>600:
            raise ValueError('Use clips up to 10 minutes')
        if calibration and abs((width/height)/(calibration.image_width/calibration.image_height)-1)>.01:
            raise ValueError('Calibration aspect ratio does not match the video')
        out_fps=min(fps,30)
        update(status='preparing',message='Preparing full-length browser video; preserving aspect ratio',duration_s=count/fps,source_width=width,source_height=height)
        normalize_video(path,folder/'source.mp4',out_fps)
        update(source_url=f'/api/jobs/{job_id}/video?kind=source')
        if cancelled():
            update(status='cancelled',message='Cancelled after video preparation')
            return
        update(status='loading',message='Loading SegFormer B2 + outdoor metric-depth models')
        segmenter,depth_model=models()
        cap=cv2.VideoCapture(str(folder/'source.mp4'))
        if not cap.isOpened():
            raise ValueError('Normalized video could not be opened')
        count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps=float(cap.get(cv2.CAP_PROP_FPS))
        width=int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height=int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        encoder=VideoEncoder(folder/'annotated.mp4',width,height,fps)
        temporal=TemporalRoad()
        k=camera_matrix(width,height,options['diagonal_fov'],calibration)
        vo=VisualOdometry(k)
        survey_map=SurveyMap(gps_track)
        inference_stride=max(1,round(fps/options['keyframe_hz']))
        snapshot_stride=max(1,round(fps/options['sample_hz']))
        previous_width=None
        last_keyframe=-999999
        semantic_count=0
        frame_index=0
        result={}
        depth_anchor={}
        update(status='processing',message='Segmenting keyframes, tracking masks on every frame and mapping the corridor',fps=fps,
               video_frames=count,expected=(count-1)//snapshot_stride+1,analysis_hz=fps/snapshot_stride,semantic_hz=fps/inference_stride,progress=0)
        while True:
            if cancelled():
                break
            ok,frame=cap.read()
            if not ok:
                break
            timestamp=frame_index/fps
            tracked=temporal.warp(frame)
            keyframe=not tracked or frame_index-last_keyframe>=inference_stride
            if keyframe:
                probability,mask,obstacles=segmenter.predict(frame)
                depth=depth_model.predict(frame)
                labels=getattr(segmenter,'last_labels',None)
                cut=int(height*(1-options.get('hood_percent',15)/100))
                mask[cut:]=False
                probability[cut:]=0
                depth,depth_anchor=anchor_depth_to_height(depth,mask,k,calibration.height_m if calibration else options.get('assumed_height_m',1.5))
                temporal.set_prediction(probability,mask,obstacles,depth,labels)
                last_keyframe=frame_index
                semantic_count+=1
            cut=int(height*(1-options.get('hood_percent',15)/100))
            temporal.mask[cut:]=False
            if temporal.labels is not None:
                temporal.labels[cut:]=255
            if keyframe or frame_index%snapshot_stride==0:
                result=analyze_mask(temporal.probability,temporal.mask,frame,calibration,previous_width,temporal.obstacles)
                previous_width=result.get('width_m')
                if options['estimate_mode']=='rough':
                    rough_width(result,temporal.depth,temporal.mask,k,options['diagonal_fov'],calibration is not None)
                    result['depth_anchor']=depth_anchor
                    if result.get('estimate_assumptions'):
                        result['estimate_assumptions']['height_prior']=depth_anchor
                        if depth_anchor.get('applied'):
                            result['reasons'].append(f"Scale anchored to {'measured' if calibration else 'assumed'} {depth_anchor['assumed_height_m']:g} m camera height")
                result.update(inference='semantic' if keyframe else 'flow_tracked',keyframe_age_s=round((frame_index-last_keyframe)/fps,3))
            if keyframe:
                if gps_track:
                    pose=gps_at(gps_track,timestamp)
                    if pose is None:
                        result['reasons'].append('No reliable synchronized GPS position; map omits this observation')
                else:
                    pose=vo.update(frame,temporal.depth,temporal.labels,timestamp)
                    if not pose.get('valid',False):
                        result['reasons'].append(pose.get('reason','Visual tracking unavailable'))
                survey_map.add(timestamp,result,temporal.depth,temporal.labels,k,pose)
            encoder.write(annotate(frame,temporal.mask,result,tracked=not keyframe))
            if frame_index%snapshot_stride==0:
                snapshot=dict(result)
                num=len(results)
                cv2.imwrite(str(folder/f'frame-{num:05d}.jpg'),frame,[cv2.IMWRITE_JPEG_QUALITY,86])
                snapshot.update(timestamp_s=round(timestamp,3),frame_index=frame_index,image=f'/api/jobs/{job_id}/frames/{num}',image_width=width,image_height=height)
                results.append(snapshot)
                update(results=list(results),progress=round((frame_index+1)/count*.97,4),processed_video_frames=frame_index+1,semantic_frames=semantic_count)
            frame_index+=1
        encoder.close()
        encoder=None
        if not results and not cancelled():
            raise ValueError('No frames were analyzed')
        map_data=survey_map.finish()
        (folder/'map.json').write_text(json.dumps(map_data,allow_nan=False),encoding='utf-8')
        is_cancelled=cancelled()
        update(status='cancelled' if is_cancelled else 'complete',message='Cancelled; processed video prefix and observations retained' if is_cancelled else 'Video and full-survey map ready',
               progress=frame_index/count if is_cancelled else 1,sampled_frames=len(results),processed_video_frames=frame_index,semantic_frames=semantic_count,
               truncated=is_cancelled,annotated_url=f'/api/jobs/{job_id}/video?kind=annotated' if frame_index else None,
               map_url=f'/api/jobs/{job_id}/map',map_summary={key:map_data[key] for key in ('mode','route_length_m','extent_m','median_width_m','unregistered_frames','disclaimer')})
    finally:
        if cap is not None:
            cap.release()
        if encoder is not None:
            encoder.close()
        # The normalized full video is retained for playback and repeat analysis.
        path.unlink(missing_ok=True)

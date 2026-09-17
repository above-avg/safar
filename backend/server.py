import csv
import io
import json
import math
import re
import shutil
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import cv2
from fastapi import FastAPI,File,Form,HTTPException,UploadFile
from fastapi.responses import FileResponse,Response
from fastapi.staticfiles import StaticFiles
from .geometry import Calibration
from .gps import parse_gps
from .model import RoadSegmenter,MetricDepth,MODEL_ID,MODEL_REVISION,DEPTH_ID,DEPTH_REVISION
from .pipeline import run_pipeline
from .video import VideoEncoder

ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'data'
DATA.mkdir(exist_ok=True)
app=FastAPI(title='Read the Road',version='0.2.0')
jobs={}
lock=threading.RLock()
pool=ThreadPoolExecutor(max_workers=1)
segmenter=None
depth_model=None
ACTIVE={'uploading','queued','preparing','loading','processing'}


def models():
    global segmenter,depth_model
    if segmenter is None:
        segmenter=RoadSegmenter()
    if depth_model is None:
        depth_model=MetricDepth()
    return segmenter,depth_model


def get_job(job_id):
    if not re.fullmatch(r'[a-f0-9]{32}',job_id):
        raise HTTPException(404,'Survey not found')
    with lock:
        if job_id not in jobs:
            path=DATA/job_id/'result.json'
            if not path.exists():
                raise HTTPException(404,'Survey not found')
            jobs[job_id]=json.loads(path.read_text(encoding='utf-8'))
            if jobs[job_id]['status'] in ACTIVE:
                jobs[job_id].update(status='interrupted',message='Server restarted during analysis; re-analyze retained source if available')
        return dict(jobs[job_id])


def update(job_id,**changes):
    with lock:
        jobs[job_id].update(changes)


def save(job_id):
    job=get_job(job_id)
    target=DATA/job_id/'result.json'
    temporary=target.with_suffix('.tmp')
    temporary.write_text(json.dumps(job,allow_nan=False),encoding='utf-8')
    temporary.replace(target)


def work(job_id,path,calibration,gps,options):
    try:
        run_pipeline(job_id,path,calibration,gps,options,models,lambda **changes:update(job_id,**changes),lambda:get_job(job_id).get('cancel_requested',False))
    except Exception as exc:
        update(job_id,status='failed',message=str(exc))
    finally:
        save(job_id)


def options_for(sample_hz,keyframe_hz,estimate_mode,diagonal_fov,assumed_height_m=1.5,hood_percent=15):
    if not .5<=sample_hz<=30 or not .5<=keyframe_hz<=10 or not 40<=diagonal_fov<=140:
        raise HTTPException(422,'Snapshot rate must be 0.5–30 Hz; semantic rate 0.5–10 Hz; diagonal FOV 40–140 degrees')
    if estimate_mode not in {'rough','calibrated_only'}:
        raise HTTPException(422,'Select rough or calibrated_only')
    if not .5<=assumed_height_m<=4 or not 0<=hood_percent<=35:
        raise HTTPException(422,'Camera height must be 0.5–4 m and bottom exclusion 0–35%')
    return {'sample_hz':sample_hz,'keyframe_hz':keyframe_hz,'estimate_mode':estimate_mode,'diagonal_fov':diagonal_fov,'assumed_height_m':assumed_height_m,'hood_percent':hood_percent}


def reserve(filename,calibration,gps,options,**extra):
    with lock:
        if any(j['status'] in ACTIVE for j in jobs.values()):
            raise HTTPException(409,'Another survey is running; cancel it or wait for completion')
        job_id=uuid.uuid4().hex
        jobs[job_id]={'id':job_id,'version':'0.2','filename':filename,'status':'uploading','progress':0,'results':[],
                      'calibration':calibration.model_dump() if calibration else None,'gps':gps,'options':options,'sample_hz':options['sample_hz'],
                      'model':MODEL_ID,'revision':MODEL_REVISION,'depth_model':DEPTH_ID,'depth_revision':DEPTH_REVISION,
                      'quality_policy':'Heuristic quality; rough ranges are scenario envelopes, not calibrated confidence intervals',
                      'width_definition':'Visible ego-connected carriageway; lower-bound estimates are marked',**extra}
    (DATA/job_id).mkdir()
    save(job_id)
    return job_id


@app.get('/api/health')
def health():
    return {'ok':True,'version':'0.2','model_loaded':segmenter is not None,'depth_loaded':depth_model is not None,'model':MODEL_ID,'metric_policy':'Rough learned-depth estimates are separate from calibrated widths'}


@app.post('/api/jobs')
async def create_job(video:UploadFile=File(...),calibration:str=Form(''),sample_hz:float=Form(5),keyframe_hz:float=Form(2),
                     estimate_mode:str=Form('rough'),diagonal_fov:float=Form(90),gps:UploadFile|None=File(None),gps_offset_s:float=Form(0),
                     assumed_height_m:float=Form(1.5),hood_percent:float=Form(15)):
    options=options_for(sample_hz,keyframe_hz,estimate_mode,diagonal_fov,assumed_height_m,hood_percent)
    try:
        cal=Calibration.model_validate_json(calibration) if calibration.strip() else None
        if not math.isfinite(gps_offset_s) or abs(gps_offset_s)>86400:
            raise ValueError('Invalid GPS offset')
        gps_track=None
        if gps and gps.filename:
            gps_bytes=await gps.read(5*1024*1024+1)
            if len(gps_bytes)>5*1024*1024:
                raise ValueError('GPS file exceeds 5 MB')
            gps_track=parse_gps(gps_bytes,gps.filename,gps_offset_s)
            await gps.close()
    except Exception as exc:
        raise HTTPException(422,str(exc))
    suffix=Path(video.filename or 'video.mp4').suffix.lower()
    if suffix not in {'.mp4','.mov','.avi','.mkv','.webm'}:
        raise HTTPException(415,'Use MP4, MOV, AVI, MKV or WebM')
    job_id=reserve(video.filename,cal,gps_track,options)
    path=DATA/job_id/('input'+suffix)
    try:
        total=0
        with path.open('wb') as stream:
            while chunk:=await video.read(1024*1024):
                total+=len(chunk)
                if total>500*1024*1024:
                    raise HTTPException(413,'Video exceeds 500 MB')
                stream.write(chunk)
        if not total:
            raise HTTPException(422,'Video is empty')
    except BaseException:
        path.unlink(missing_ok=True)
        update(job_id,status='failed',message='Upload failed')
        save(job_id)
        raise
    finally:
        await video.close()
    update(job_id,status='queued',message='Queued for full-video analysis')
    save(job_id)
    pool.submit(work,job_id,path,cal,gps_track,options)
    return {'id':job_id}


@app.get('/api/jobs/{job_id}')
def job_status(job_id:str,after:int=0):
    job=get_job(job_id)
    total=len(job['results'])
    if after<0 or after>total:
        raise HTTPException(422,'Invalid result cursor')
    job['results']=job['results'][after:]
    job['result_start']=after
    job['result_count']=total
    # GPS samples remain in the export, but polling only needs provenance.
    if job.get('gps'):
        job['gps']={'origin':job['gps']['origin'],'point_count':len(job['gps']['points']),'offset_s':job['gps']['offset_s']}
    return job


@app.post('/api/jobs/{job_id}/cancel')
def cancel_job(job_id:str):
    get_job(job_id)
    update(job_id,cancel_requested=True)
    return {'ok':True}


@app.get('/api/jobs/{job_id}/frames/{frame_id}')
def frame(job_id:str,frame_id:int):
    job=get_job(job_id)
    if not 0<=frame_id<len(job['results']):
        raise HTTPException(404,'Frame not found')
    return FileResponse(DATA/job_id/f'frame-{frame_id:05d}.jpg',media_type='image/jpeg')


@app.get('/api/jobs/{job_id}/video')
def video(job_id:str,kind:str='annotated',download:bool=False):
    get_job(job_id)
    if kind not in {'source','annotated'}:
        raise HTTPException(422,'Invalid video type')
    path=DATA/job_id/f'{kind}.mp4'
    if not path.exists() or (kind=='annotated' and get_job(job_id)['status'] in ACTIVE):
        raise HTTPException(404,'Video is not ready yet')
    return FileResponse(path,media_type='video/mp4',filename=f'road-{kind}.mp4' if download else None)


@app.get('/api/jobs/{job_id}/map')
def survey_map(job_id:str):
    get_job(job_id)
    path=DATA/job_id/'map.json'
    if not path.exists():
        raise HTTPException(404,'Map is available after processing')
    return FileResponse(path,media_type='application/json')


@app.get('/api/jobs/{job_id}/export')
def export(job_id:str,format:str='json'):
    job=get_job(job_id)
    if format=='csv':
        out=io.StringIO()
        writer=csv.writer(out)
        writer.writerow(['timestamp_s','frame_index','status','calibrated_width_m','rough_width_m','rough_low_m','rough_high_m','estimate_kind','quality_heuristic','inference','pixel_span','position_x_m','position_y_m','position_source','reasons','calibration_json','assumptions_json'])
        for row in job['results']:
            interval=row.get('rough_range_m') or [None,None]
            pos=row.get('position') or {}
            writer.writerow([row['timestamp_s'],row['frame_index'],row['status'],row.get('width_m'),row.get('rough_width_m'),*interval,row.get('estimate_kind'),row.get('quality'),row.get('inference'),row.get('pixel_span'),pos.get('x'),pos.get('y'),pos.get('source'),'; '.join(row['reasons']),json.dumps(job['calibration']),json.dumps(row.get('estimate_assumptions'))])
        return Response(out.getvalue(),media_type='text/csv',headers={'Content-Disposition':'attachment; filename="road-measurements.csv"'})
    if format!='json':
        raise HTTPException(422,'Use csv or json')
    return Response(json.dumps(job,allow_nan=False),media_type='application/json',headers={'Content-Disposition':'attachment; filename="road-survey.json"'})


@app.post('/api/jobs/{job_id}/reprocess')
def reprocess(job_id:str):
    old=get_job(job_id)
    if old['status'] in ACTIVE:
        raise HTTPException(409,'This survey is still running')
    options=old.get('options') or options_for(5,2,'rough',90)
    cal=Calibration.model_validate(old['calibration']) if old.get('calibration') else None
    source=DATA/job_id/'source.mp4'
    sparse=not source.exists()
    if sparse and len(old.get('results',[]))<2:
        raise HTTPException(422,'Original video unavailable; upload it again')
    new_id=reserve(old['filename'],cal,old.get('gps'),options,reprocessed_from=job_id,recovered_sparse=sparse,
                   source_notice='Recovered old sampled images only. Re-upload the original for continuous motion and dense masks.' if sparse else 'Reprocessed from retained full video')
    target=DATA/new_id/'input.mp4'
    try:
        if not sparse:
            shutil.copyfile(source,target)
        else:
            rows=old['results']
            first=cv2.imread(str(DATA/job_id/'frame-00000.jpg'))
            if first is None:
                raise ValueError('Saved frames unavailable; upload the original')
            fps=(len(rows)-1)/max(.001,rows[-1]['timestamp_s']-rows[0]['timestamp_s'])
            h,w=first.shape[:2]
            encoder=VideoEncoder(target,w-w%2,h-h%2,fps)
            try:
                for i in range(len(rows)):
                    image=cv2.imread(str(DATA/job_id/f'frame-{i:05d}.jpg'))
                    if image is None:
                        raise ValueError('Saved frame is missing')
                    encoder.write(image[:h-h%2,:w-w%2])
            finally:
                encoder.close()
        update(new_id,status='queued',message='Re-analyzing saved survey with upgraded models')
        save(new_id)
        pool.submit(work,new_id,target,cal,old.get('gps'),options)
    except Exception as exc:
        update(new_id,status='failed',message=str(exc))
        save(new_id)
        raise HTTPException(422,str(exc))
    return {'id':new_id,'recovered_sparse':sparse}


app.mount('/',StaticFiles(directory=ROOT/'frontend',html=True),name='frontend')

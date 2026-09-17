"""Optional time-aligned GPS. No extrapolation across gaps or implausible jumps."""
import csv
import io
import math
from datetime import datetime
import xml.etree.ElementTree as ET
import numpy as np


def parse_gps(content, filename, offset_s=0):
    text=content.decode('utf-8-sig')
    rows=[]
    if filename.lower().endswith('.gpx'):
        if '<!DOCTYPE' in text.upper() or '<!ENTITY' in text.upper():
            raise ValueError('GPX must not contain XML entities')
        root=ET.fromstring(text)
        for element in root.iter():
            if element.tag.split('}')[-1]!='trkpt':
                continue
            stamp=next((c.text for c in element if c.tag.split('}')[-1]=='time'),None)
            if not stamp:
                raise ValueError('Every GPX track point requires a timestamp')
            rows.append({'t':datetime.fromisoformat(stamp.replace('Z','+00:00')).timestamp(),'lat':float(element.attrib['lat']),'lon':float(element.attrib['lon']),'accuracy_m':None})
        if rows:
            origin_time=rows[0]['t']
            for row in rows:
                row['t']-=origin_time
    elif filename.lower().endswith('.csv'):
        for row in csv.DictReader(io.StringIO(text)):
            rows.append({'t':float(row['timestamp_s']),'lat':float(row['latitude']),'lon':float(row['longitude']),
                         'accuracy_m':float(row['accuracy_m']) if (row.get('accuracy_m') or '').strip() else None})
    else:
        raise ValueError('GPS input must be CSV or GPX')
    if not 2<=len(rows)<=100000:
        raise ValueError('GPS input must have 2–100,000 timed points')
    for i,row in enumerate(rows):
        if not all(math.isfinite(row[k]) for k in ('t','lat','lon')) or not -90<=row['lat']<=90 or not -180<=row['lon']<=180:
            raise ValueError('Invalid GPS coordinates or timestamp')
        if row['accuracy_m'] is not None and (not math.isfinite(row['accuracy_m']) or row['accuracy_m']<0):
            raise ValueError('GPS accuracy_m must be finite and nonnegative')
        row['t']+=offset_s
        if i and row['t']<=rows[i-1]['t']:
            raise ValueError('GPS timestamps must be strictly increasing')
    lat0,lon0=rows[0]['lat'],rows[0]['lon']
    for row in rows:
        dlon=(row['lon']-lon0+180)%360-180
        row['x']=6371000*math.radians(dlon)*math.cos(math.radians(lat0))
        row['y']=6371000*math.radians(row['lat']-lat0)
    return {'origin':{'latitude':lat0,'longitude':lon0},'points':rows,'offset_s':offset_s}


def gps_at(track,t):
    if not track:
        return None
    rows=track['points']
    times=[p['t'] for p in rows]
    if t<times[0] or t>times[-1]:
        return None
    i=min(max(0,int(np.searchsorted(times,t,side='right'))-1),len(rows)-2)
    a,b=rows[i:i+2]
    dt=b['t']-a['t']
    distance=math.hypot(b['x']-a['x'],b['y']-a['y'])
    if dt>15 or distance/dt>70 or any(p['accuracy_m'] is not None and p['accuracy_m']>30 for p in (a,b)):
        return None
    f=(t-a['t'])/dt
    return {'x':a['x']+f*(b['x']-a['x']),'y':a['y']+f*(b['y']-a['y']),
            'yaw':math.atan2(b['x']-a['x'],b['y']-a['y']) if distance>.3 else None,
            'accuracy_m':max(a['accuracy_m'] or 0,b['accuracy_m'] or 0) or None,'source':'gps'}

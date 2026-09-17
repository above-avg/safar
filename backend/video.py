"""H.264 output and actual per-frame overlays."""
import subprocess
import cv2
import numpy as np
import imageio_ffmpeg
from .estimation import displayed_width


class VideoEncoder:
    def __init__(self,path,width,height,fps):
        self.log=path.with_suffix('.encoder.log').open('wb')
        self.process=subprocess.Popen([imageio_ffmpeg.get_ffmpeg_exe(),'-y','-hide_banner','-loglevel','error','-f','rawvideo','-vcodec','rawvideo',
            '-pix_fmt','bgr24','-s',f'{width}x{height}','-r',str(fps),'-i','-','-an','-c:v','libx264','-preset','veryfast','-crf','22',
            '-pix_fmt','yuv420p','-movflags','+faststart',str(path)],stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=self.log,
            creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))

    def write(self,frame):
        self.process.stdin.write(np.ascontiguousarray(frame,dtype=np.uint8).tobytes())

    def close(self):
        if self.process.stdin and not self.process.stdin.closed:
            self.process.stdin.close()
        try:
            code=self.process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
            raise RuntimeError('Video encoding timed out')
        finally:
            self.log.close()
        if code:
            raise RuntimeError('Video encoding failed; inspect the encoder log')


def annotate(frame,mask,result,tracked=False):
    out=frame.copy()
    mask=mask.astype(bool)
    out[mask]=(out[mask]*.7+np.array([156,228,101])*.3).astype(np.uint8)
    contours,_=cv2.findContours(mask.astype(np.uint8),cv2.RETR_CCOMP,cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(out,contours,-1,(170,245,130),1,cv2.LINE_AA)
    sections=result.get('sections') or result.get('rough_sections') or []
    for section in sections[::max(1,len(sections)//4)]:
        a,b=np.rint(section['pixels']).astype(int)
        cv2.line(out,tuple(a),tuple(b),(125,249,210),1,cv2.LINE_AA)
    width=displayed_width(result)
    title=f"{'~ ' if result.get('width_m') is None else ''}{width:.1f} m" if width is not None else 'Width unavailable'
    if result.get('estimate_kind')=='visible_lower_bound' and result.get('width_m') is None:
        title+=' visible only'
    fontscale=max(.45,min(.85,frame.shape[1]/1100))
    h=round(83*fontscale/.6)
    cv2.rectangle(out,(10,10),(min(frame.shape[1]-10,490),h),(22,32,27),-1)
    cv2.putText(out,'READ THE ROAD  /  '+title,(22,35),cv2.FONT_HERSHEY_SIMPLEX,fontscale,(180,250,204),1,cv2.LINE_AA)
    subtitle='Calibrated plane estimate' if result.get('width_m') is not None else 'Rough AI estimate - not a survey measurement'
    cv2.putText(out,subtitle,(22,55),cv2.FONT_HERSHEY_SIMPLEX,fontscale*.7,(198,209,199),1,cv2.LINE_AA)
    cv2.putText(out,'FLOW TRACKED MASK' if tracked else 'SEMANTIC + DEPTH KEYFRAME',(22,73),cv2.FONT_HERSHEY_SIMPLEX,fontscale*.6,(156,186,159),1,cv2.LINE_AA)
    return out

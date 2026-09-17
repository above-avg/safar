"""Aspect-preserving semantic segmentation and outdoor metric-depth priors."""
import os
from pathlib import Path
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault('HF_HOME', str(ROOT / '.cache' / 'huggingface'))
MODEL_ID = 'nvidia/segformer-b2-finetuned-cityscapes-1024-1024'
MODEL_REVISION = 'c22ac7ec4097216a2248217f45bdd27c43b5dbe3'
DEPTH_ID = 'depth-anything/Depth-Anything-V2-Metric-Outdoor-Small-hf'
DEPTH_REVISION = 'fd2c22027eaf20374204f14099b8341e1925ad39'


def cached_load(cls, model_id, revision, **kwargs):
    try:
        return cls.from_pretrained(model_id, revision=revision, local_files_only=True, **kwargs)
    except OSError:
        return cls.from_pretrained(model_id, revision=revision, **kwargs)


def inference_size(shape, long_edge=1024, multiple=32):
    h, w = shape[:2]
    scale = long_edge / max(h, w)
    return {'height': max(multiple, round(h * scale / multiple) * multiple),
            'width': max(multiple, round(w * scale / multiple) * multiple)}


class RoadSegmenter:
    def __init__(self):
        import torch
        from transformers import AutoImageProcessor, SegformerForSemanticSegmentation
        self.torch = torch
        self.device = 'cuda' if torch.cuda.is_available() else 'cpu'
        torch.set_num_threads(min(4, os.cpu_count() or 1))
        self.processor = cached_load(AutoImageProcessor, MODEL_ID, MODEL_REVISION, use_fast=False)
        self.model = cached_load(SegformerForSemanticSegmentation, MODEL_ID, MODEL_REVISION).to(self.device).eval()
        self.road_id = next(int(k) for k, value in self.model.config.id2label.items() if value.lower() == 'road')
        self.last_labels = None

    def predict(self, frame):
        from PIL import Image
        torch = self.torch
        inputs = self.processor(images=Image.fromarray(frame[:, :, ::-1]), size=inference_size(frame.shape), return_tensors='pt').to(self.device)
        with torch.inference_mode():
            logits = self.model(**inputs).logits
            logits = torch.nn.functional.interpolate(logits, size=frame.shape[:2], mode='bilinear', align_corners=False)
            probs = logits.softmax(dim=1)[0]
            road = probs[self.road_id]
            classes = probs.argmax(dim=0)
            mask = (classes == self.road_id) & (road >= .45)
            obstacles = torch.zeros_like(mask)
            for class_id in [int(k) for k,v in self.model.config.id2label.items() if v.lower() in {'person','rider','car','truck','bus','train','motorcycle','bicycle'}]:
                obstacles |= classes == class_id
        self.last_labels = classes.cpu().numpy().astype(np.uint8)
        return road.cpu().numpy(), mask.cpu().numpy(), obstacles.cpu().numpy()


class MetricDepth:
    def __init__(self):
        import torch
        from transformers import AutoImageProcessor, AutoModelForDepthEstimation
        self.torch = torch
        self.device = 'cuda' if torch.cuda.is_available() else 'cpu'
        self.processor = cached_load(AutoImageProcessor, DEPTH_ID, DEPTH_REVISION, use_fast=False)
        self.model = cached_load(AutoModelForDepthEstimation, DEPTH_ID, DEPTH_REVISION).to(self.device).eval()

    def predict(self, frame):
        from PIL import Image
        t = self.torch
        inputs = self.processor(images=Image.fromarray(frame[:, :, ::-1]), return_tensors='pt').to(self.device)
        with t.inference_mode():
            depth = self.model(**inputs).predicted_depth
            depth = t.nn.functional.interpolate(depth.unsqueeze(1), size=frame.shape[:2], mode='bicubic', align_corners=False)[0, 0]
        return np.clip(depth.cpu().numpy(), .1, 80).astype(np.float32)


class TemporalRoad:
    """Backward optical flow propagates masks between semantic keyframes."""
    def __init__(self):
        self.gray = None
        self.probability = self.mask = self.obstacles = self.depth = self.labels = None

    def warp(self, frame):
        h, w = frame.shape[:2]
        size = (max(64, round(w * 384 / max(h,w))), max(64, round(h * 384 / max(h,w))))
        gray = cv2.resize(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY), size)
        if self.gray is None:
            self.gray = gray
            return False
        flow = cv2.calcOpticalFlowFarneback(gray, self.gray, None, .5, 3, 19, 3, 5, 1.2, 0)
        gx, gy = np.meshgrid(np.arange(size[0], dtype=np.float32), np.arange(size[1], dtype=np.float32))
        warped_gray = cv2.remap(self.gray, gx+flow[:,:,0], gy+flow[:,:,1], cv2.INTER_LINEAR)
        residual = float(np.mean(np.abs(gray.astype(float)-warped_gray.astype(float))))
        self.gray = gray
        if residual > 30 or self.probability is None:
            return False
        flow = cv2.resize(flow, (w,h))
        flow[:,:,0] *= w/size[0]
        flow[:,:,1] *= h/size[1]
        x,y = np.meshgrid(np.arange(w,dtype=np.float32),np.arange(h,dtype=np.float32))
        for name in ('probability','mask','obstacles','depth','labels'):
            value = getattr(self,name)
            if value is None:
                continue
            discrete = name in ('mask','obstacles','labels')
            warped = cv2.remap(value.astype(np.uint8) if discrete else value, x+flow[:,:,0], y+flow[:,:,1], cv2.INTER_NEAREST if discrete else cv2.INTER_LINEAR)
            setattr(self,name,warped.astype(bool) if name in ('mask','obstacles') else warped)
        return True

    def set_prediction(self, probability, mask, obstacles, depth, labels):
        if self.probability is not None:
            probability = .9*probability + .1*self.probability
        self.probability = probability.astype(np.float32)
        self.mask = mask & (probability >= .45) & ~obstacles.astype(bool)
        self.obstacles, self.depth, self.labels = obstacles, depth, labels

"""Visual features computed from a reduced decode of each file (read-only).

- 192-bit perceptual signature: average hash 8x8 + horizontal and vertical
  difference hashes. Same algorithm as upstream photo_dedup_batch.py, with
  EXIF orientation applied so rotated copies still match.
- Sharpness: Laplacian variance normalised by image variance (as upstream).
- ORB keypoints for scene matching, computed on demand and kept in memory.
"""
from __future__ import annotations

from functools import lru_cache
from typing import Optional

import cv2
import numpy as np
from PIL import Image, ImageOps

SIG_BITS = 192


def _open(path: str, max_side: int, mode: str) -> Optional[Image.Image]:
    try:
        from raw_loader import open_image_pil
        im = open_image_pil(path)
    except Exception:
        try:
            im = Image.open(path)
        except Exception:
            return None
    try:
        im.draft(mode, (max_side, max_side))       # fast JPEG downscale on decode
    except Exception:
        pass
    im = ImageOps.exif_transpose(im).convert(mode)
    im.thumbnail((max_side, max_side), Image.Resampling.BILINEAR)
    return im


def signature_and_sharpness(path: str) -> Optional[tuple[bytes, float]]:
    im = _open(path, 512, 'L')
    if im is None:
        return None
    a = np.asarray(im.resize((8, 8), Image.Resampling.BILINEAR), dtype=np.float32)
    dh = np.asarray(im.resize((9, 8), Image.Resampling.BILINEAR), dtype=np.float32)
    dv = np.asarray(im.resize((8, 9), Image.Resampling.BILINEAR), dtype=np.float32)
    bits = np.concatenate([(a > a.mean()).ravel(), (dh[:, 1:] > dh[:, :-1]).ravel(),
                           (dv[1:, :] > dv[:-1, :]).ravel()])
    g = np.asarray(im, dtype=np.float32)
    var = float(g.var()) or 1.0
    sharp = float(cv2.Laplacian(g, cv2.CV_32F).var()) / var * 100.0
    return np.packbits(bits).tobytes(), sharp


def unpack(sig: bytes) -> np.ndarray:
    return np.unpackbits(np.frombuffer(sig, np.uint8))[:SIG_BITS].astype(bool)


def similarity_matrix(sigs: np.ndarray) -> np.ndarray:
    """sigs: (n, 192) bool -> (n, n) similarity = 1 - hamming/192."""
    x = sigs.astype(np.float32)
    agree = x @ x.T + (1 - x) @ (1 - x).T
    return agree / SIG_BITS


_orb = None


@lru_cache(maxsize=4096)
def orb_features(path: str):
    global _orb
    if _orb is None:
        _orb = cv2.ORB_create(nfeatures=1500)
    im = _open(path, 800, 'L')
    if im is None:
        return None, None
    kp, des = _orb.detectAndCompute(np.asarray(im), None)
    pts = np.float32([k.pt for k in kp]) if kp else np.zeros((0, 2), np.float32)
    return pts, des


_bf = cv2.BFMatcher(cv2.NORM_HAMMING)


def scene_match(path_a: str, path_b: str) -> tuple[int, int]:
    """(good matches, RANSAC fundamental-matrix inliers). Inliers measure how
    strongly two photos show the same 3D scene, even from different positions
    or focal lengths."""
    pa, da = orb_features(path_a)
    pb, db = orb_features(path_b)
    if da is None or db is None or len(da) < 8 or len(db) < 8:
        return 0, 0
    m = _bf.knnMatch(da, db, k=2)
    good = [x[0] for x in m if len(x) == 2 and x[0].distance < 0.75 * x[1].distance]
    if len(good) < 12:
        return len(good), 0
    A = pa[[g.queryIdx for g in good]]
    B = pb[[g.trainIdx for g in good]]
    F, mask = cv2.findFundamentalMat(A, B, cv2.FM_RANSAC, 3.0, 0.99)
    # When no model is found OpenCV returns F=None and a mask with undefined
    # content (seen: values up to 254), so only trust the mask with a model.
    if F is None or mask is None:
        return len(good), 0
    return len(good), int(np.count_nonzero(mask.ravel() == 1))

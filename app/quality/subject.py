"""Sharpness of the subject, not of the whole photo (M10b, quality check v2).

The owner's rule: a photo is blurry only when its subject is soft. A soft
background (bokeh) is never a fault. The subject is

  1. the main faces (faces.main_faces: the 1-3 largest faces, each at least a
     quarter of the largest face's area; tiny background faces are ignored),
  2. else Apple Vision's objectness-based salient boxes (up to 3),
  3. else none: the photo keeps the whole-image focus tiers of scoring.py.

Measurement (CPU, worker processes): the photo is decoded at a fixed working
size (WORK_LONG px on the long side, about a full-screen view) and each
subject box (a face box as Vision gives it, a little taller for the brows) is cut into
TILE px tiles. Per tile: variance of the Laplacian over the tile's own
variance (the "detail over local contrast" idea of scoring.region_sharpness);
tiles with almost no contrast are skipped (flat skin or sky only measures
noise). The subject's sharpness is the TILE_PCT percentile of its tiles; with
several faces or salient boxes the sharpest one counts (two people at
different depths are not a fault).

Movement: second-derivative energy along four directions (0, 45, 90, 135
degrees) on the subject. Smearing along one direction removes detail in that
direction only, so max / min energy ("anisotropy") jumps: 1.8-3.4 on sharp
subjects of album test-10 (5.2 on one with long hair strands, still sharp),
at most 2.6 when blurred evenly, mostly 3.5-12 when smeared by 9-17 px. It
only counts when the subject is not sharp anyway.

Calibration (2026-11-16, album test-10, 19 photos, 18 with a subject): the
originals measure 2.4-20 (median about 6.9); the same photos blurred with
sigma 1 px at the working size 0.55-2.8, sigma 2 px 0.14-0.77, motion 9 px
0.4-3.4. With that median the lines are 0.83 (blurry) and 2.27 (soft): every
original is sharp, sigma 2 is blurry, sigma 1 is soft or blurry. These are
not yet checked against the owner's own marks (plan: about 60 marked photos).
"""
from __future__ import annotations

import json
from concurrent.futures import ProcessPoolExecutor
from multiprocessing import get_context
from typing import Callable, Optional

import cv2
import numpy as np

from app.collections import now_iso

WORK_LONG = 2048          # working size: long side in px (never enlarged)
TILE = 32                 # tile side at the working size
MIN_TILE_STD = 5.0        # grey levels; flatter tiles carry only noise
TILE_PCT = 80             # percentile of the subject's tiles
FACE_GROW = (0.0, 0.10, 0.0)     # grow a face box only upwards a little (brows); a larger box takes in
                                 # background, whose sharp tiles would hide a soft face

# Lines on the album median of subject sharpness, kept within absolute limits so a very sharp album does
# not flag good photos and an album of mostly soft photos still flags real blur.
BLUR_SHARE, BLUR_FLOOR, BLUR_CAP = 0.12, 0.6, 1.5      # below: blurry
SOFT_SHARE, SOFT_FLOOR, SOFT_CAP = 0.33, 1.2, 3.0      # below: soft
MIN_ALBUM = 5                                          # fewer measured subjects: the default lines
DEFAULT_BLUR, DEFAULT_SOFT = 0.8, 2.2                  # the lines for an album median of about 6.7
MOVEMENT_ANISO = 3.5                                   # directional detail ratio that means movement

_DIRECTIONS = (
    (np.array([[0, 0, 0], [1, -2, 1], [0, 0, 0]], np.float32), 1.0),
    (np.array([[0, 1, 0], [0, -2, 0], [0, 1, 0]], np.float32), 1.0),
    (np.array([[1, 0, 0], [0, -2, 0], [0, 0, 1]], np.float32), 0.25),    # diagonal step is sqrt(2) px
    (np.array([[0, 0, 1], [0, -2, 0], [1, 0, 0]], np.float32), 0.25),
)


def _grow(box, kind):
    x, y, w, h = box
    if kind == 'faces':
        side, top, bottom = FACE_GROW
        x, w = x - side * w, w * (1 + 2 * side)
        y, h = y - top * h, h * (1 + top + bottom)
    x0, y0 = max(0.0, x), max(0.0, y)
    x1, y1 = min(1.0, x + w), min(1.0, y + h)
    return x0, y0, max(0.0, x1 - x0), max(0.0, y1 - y0)


def subject_boxes(faces: list, salient: Optional[list]) -> tuple:
    """('faces' | 'salient' | 'none', [boxes]) with boxes normalised, origin top left.
    `faces` are helper face dicts (Vision boxes, origin bottom left); `salient` is [[x, y, w, h, conf]]."""
    from app.quality.faces import main_faces, top_left
    mains = main_faces(faces)
    if mains:
        return 'faces', [top_left(f['box']) for f in mains]
    boxes = [top_left(b[:4]) for b in (salient or []) if len(b) >= 4 and b[2] * b[3] > 0.0005]
    if boxes:
        return 'salient', boxes[:3]
    return 'none', []


def load_gray(path: str):
    """Grey image as displayed (EXIF orientation applied), long side at most WORK_LONG."""
    from raw_loader import imread_gray
    g = imread_gray(path, reduced=True)
    if g is None:
        return None
    h, w = g.shape[:2]
    if max(h, w) > WORK_LONG:
        s = WORK_LONG / max(h, w)
        g = cv2.resize(g, (max(1, int(round(w * s))), max(1, int(round(h * s)))), interpolation=cv2.INTER_AREA)
    return g


def sharpness(g: np.ndarray) -> Optional[float]:
    """TILE_PCT percentile of the normalised Laplacian over the tiles of `g`; None when every tile is flat."""
    gf = g.astype(np.float32)
    lap = cv2.Laplacian(gf, cv2.CV_32F, ksize=3)
    H, W = gf.shape
    scores = []
    for y in range(0, max(1, H - TILE // 2), TILE):
        for x in range(0, max(1, W - TILE // 2), TILE):
            tg = gf[y:y + TILE, x:x + TILE]
            if tg.size < 64:
                continue
            v = float(tg.var())
            if v < MIN_TILE_STD ** 2:
                continue
            scores.append(float(lap[y:y + TILE, x:x + TILE].var()) / v)
    return float(np.percentile(scores, TILE_PCT)) if scores else None


def anisotropy(g: np.ndarray) -> float:
    """Largest over smallest second-derivative energy across four directions (1 = the same everywhere)."""
    gf = g.astype(np.float32)
    e = [float((cv2.filter2D(gf, -1, k) ** 2).mean()) * s for k, s in _DIRECTIONS]
    return float(max(e) / max(min(e), 1e-6)) if max(e) > 0 else 1.0


def eye_lens(g: np.ndarray, face: dict) -> Optional[float]:
    """Brightness of the eye areas over the brightness of the cheeks (about 0.5-1 for eyes, below DARK_LENS
    in faces.py for dark sunglasses). None when the helper gave no eye boxes."""
    from app.quality.faces import top_left
    H, W = g.shape[:2]
    fx, fy, fw, fh = top_left(face['box'])
    cheeks = g[int((fy + 0.45 * fh) * H):int((fy + 0.8 * fh) * H), int((fx + 0.2 * fw) * W):int((fx + 0.8 * fw) * W)]
    if cheeks.size < 16:
        return None
    vals = []
    for k in ('left_eye_box', 'right_eye_box'):
        b = face.get(k)
        if not b:
            continue
        x, y, w, h = top_left(b)
        cx, cy, half = (x + w / 2) * W, (y + h / 2) * H, max(1.0, w * W * 0.6)
        p = g[int(cy - 0.6 * half):int(cy + 0.6 * half) + 1, int(cx - half):int(cx + half) + 1]
        if p.size:
            vals.append(float(np.median(p)))
    if not vals:
        return None
    return round(float(np.mean(vals)) / max(1.0, float(np.median(cheeks))), 3)


def measure(g: np.ndarray, kind: str, boxes: list, faces: Optional[list] = None) -> dict:
    """Subject and whole-photo sharpness, movement cue and eye brightness on a working-size grey image."""
    H, W = g.shape[:2]
    best, best_aniso, best_px = None, None, 0
    for b in boxes:
        x, y, w, h = _grow(b, kind)
        x0, y0, x1, y1 = int(x * W), int(y * H), int(round((x + w) * W)), int(round((y + h) * H))
        crop = g[y0:y1, x0:x1]
        if crop.shape[0] < 8 or crop.shape[1] < 8:
            continue
        s = sharpness(crop)
        if s is not None and (best is None or s > best):
            best, best_aniso, best_px = s, anisotropy(crop), int((crop.shape[0] * crop.shape[1]) ** 0.5)
    lenses = []
    for f in faces or []:
        try:
            lenses.append(eye_lens(g, f) if f.get('box') else None)
        except Exception:
            lenses.append(None)
    return {'subject': kind if best is not None else 'none', 'sharpness': best, 'whole': sharpness(g),
            'anisotropy': best_aniso if best is not None else anisotropy(g), 'subject_px': best_px,
            'eyes': lenses}


def analyze_path(path: str, kind: str, boxes: list, faces: Optional[list] = None) -> Optional[dict]:
    g = load_gray(path)
    if g is None:
        return None
    return measure(g, kind, boxes, faces)


def _safe(args):
    try:
        return analyze_path(*args)
    except Exception:
        return None


def compute_subject_focus(conn, progress: Optional[Callable] = None,
                          cancelled: Callable[[], bool] = lambda: False) -> dict:
    """Measure every photo that has helper results (faces table) and no subject_focus row yet."""
    from app.ai.throttle import Throttle
    from app.quality.scoring import PARALLEL_FROM, WORKERS
    rows = conn.execute(
        "SELECT f.sha256, f.faces_json, f.vision_json, MIN(s.path || '/' || a.rel_path) AS path FROM faces f "
        "JOIN assets a ON a.sha256 = f.sha256 JOIN sources s ON s.id = a.source_id "
        "WHERE a.status = 'present' AND a.kind = 'image' "
        'AND f.sha256 NOT IN (SELECT sha256 FROM subject_focus) GROUP BY f.sha256').fetchall()
    if not rows:
        return {'measured': 0}
    jobs = []
    for r in rows:
        vision = json.loads(r['vision_json'] or '{}')
        faces = json.loads(r['faces_json'] or '[]')
        kind, boxes = subject_boxes(faces, vision.get('salient'))
        jobs.append((r['path'], kind, boxes, faces))
    throttle = Throttle(cancelled, status=(lambda m: progress(m, 0, 0)) if progress else None, share=100)
    if progress:
        progress('Subject sharpness', 0, len(rows))
    ex = None
    if len(jobs) < PARALLEL_FROM or WORKERS == 1:
        results = (_safe(j) for j in jobs)
    else:
        ex = ProcessPoolExecutor(WORKERS, mp_context=get_context('spawn'))
        results = ex.map(_safe, jobs, chunksize=2)
    done = 0
    try:
        for i, (r, res) in enumerate(zip(rows, results)):
            if progress:
                progress('Subject sharpness', i + 1, len(rows))
            if res is not None:
                store(conn, r['sha256'], res)
                done += 1
            if cancelled():
                break
            if i < len(rows) - 1:
                throttle.after_work(0.0)
    finally:
        if ex is not None:
            ex.shutdown(wait=False, cancel_futures=True)
    return {'measured': done}


def store(conn, sha256: str, res: dict) -> None:
    with conn:
        conn.execute('INSERT OR REPLACE INTO subject_focus (sha256, subject, sharpness, whole, anisotropy, subject_px, '
                     'eyes_json, computed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                     (sha256, res['subject'], res['sharpness'], res['whole'], res['anisotropy'],
                      res.get('subject_px'), json.dumps(res.get('eyes') or []), now_iso()))


def subject_rows(conn) -> dict:
    """sha256 -> stored measurement (empty when the table is missing)."""
    try:
        return {r['sha256']: dict(r) for r in conn.execute(
            'SELECT sha256, subject, sharpness, whole, anisotropy, subject_px, eyes_json FROM subject_focus')}
    except Exception:
        return {}


def lines(values: list) -> tuple:
    """(blurry line, soft line) from the album's subject sharpness values."""
    values = [v for v in values if v is not None]
    if len(values) < MIN_ALBUM:
        return DEFAULT_BLUR, DEFAULT_SOFT
    m = float(np.median(values))
    blur = min(BLUR_CAP, max(BLUR_FLOOR, BLUR_SHARE * m))
    soft = min(SOFT_CAP, max(SOFT_FLOOR, SOFT_SHARE * m, 1.6 * blur))
    return blur, soft


def verdict(row: dict, blur_line: float, soft_line: float) -> tuple:
    """(sharp | soft | blurry, reason) for a photo with a measured subject. Reason: movement (smeared one way),
    whole (even the sharpest part of the photo is soft: missed focus or shake) or subject."""
    s = row['sharpness']
    moving = (row.get('anisotropy') or 1.0) >= MOVEMENT_ANISO
    if s >= soft_line:
        return 'sharp', None
    if s >= blur_line and not moving:
        return 'soft', None
    whole = row.get('whole')
    if moving:
        return 'blurry', 'movement'
    return 'blurry', 'whole' if whole is not None and whole < soft_line else 'subject'

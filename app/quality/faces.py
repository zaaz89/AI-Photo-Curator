"""Face quality and video metadata from the on-device Swift helper.

The helper (tools/mac-helper/PhotoCuratorHelper.swift, built by
scripts/build-helper.sh into local-data/bin/pc-helper) uses Apple Vision and
AVFoundation. No faces are identified or stored as identities; per face only
Apple's capture quality, head angles and eye openness are kept.

face_summary() turns that into the criteria the owner asked for when choosing
between near-identical photos: eyes open, looking at the camera, face sharp.
"""
from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Callable, Optional

from app.collections import data_dir, now_iso

EYE_CLOSED = 0.12        # eye contour height / width; below this the eye is treated as closed
EYE_OPEN = 0.18
LOOK_AWAY_RAD = 0.6      # about 35 degrees of head turn
BATCH = 12
FACE_WORKERS = 3


def helper_path() -> Path:
    return data_dir() / 'bin' / 'pc-helper'


def helper_available() -> bool:
    return helper_path().exists()


def _run(mode: str, paths: list[str], extra: Optional[list[str]] = None, timeout: int = 600) -> list[dict]:
    proc = subprocess.run([str(helper_path()), mode, *(extra or [])], input='\n'.join(paths),
                          capture_output=True, text=True, timeout=timeout)
    out = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith('{'):
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


MIN_FACE_AREA = 0.0004   # ignore tiny background faces
MAX_BOXES = 6


def _usable(faces: list) -> list:
    return [f for f in faces or [] if f.get('box') and f['box'][2] * f['box'][3] >= MIN_FACE_AREA]


def _eye_closed(f: dict) -> bool:
    eyes = [e for e in (f.get('left_eye'), f.get('right_eye')) if e is not None]
    return bool(eyes) and min(eyes) < EYE_CLOSED


def _looking_away(f: dict) -> bool:
    return abs(f.get('yaw') or 0.0) > LOOK_AWAY_RAD


def face_boxes(faces: list, limit: int = MAX_BOXES) -> list:
    """Up to `limit` faces as {x, y, w, h, eyes_closed, looking_away}, normalised to the image with the
    origin at the top left. The helper stores Apple Vision's boundingBox (origin bottom left), so y is flipped."""
    out = []
    for f in _usable(faces)[:limit]:
        x, y, w, h = (float(v) for v in f['box'])
        out.append({'x': round(x, 4), 'y': round(1.0 - (y + h), 4), 'w': round(w, 4), 'h': round(h, 4),
                    'eyes_closed': _eye_closed(f), 'looking_away': _looking_away(f)})
    return out


def face_summary(faces: list) -> Optional[dict]:
    """Per photo: counts, a 0-1 face score and the face boxes, or None when there are no faces."""
    faces = _usable(faces)
    if not faces:
        return None
    closed, away, scores = 0, 0, []
    for f in faces:
        eyes = [e for e in (f.get('left_eye'), f.get('right_eye')) if e is not None]
        eye = min(eyes) if eyes else None
        eye_ok = 1.0 if eye is None or eye >= EYE_OPEN else max(0.0, (eye - EYE_CLOSED) / (EYE_OPEN - EYE_CLOSED))
        if _eye_closed(f):
            closed += 1
        yaw = abs(f.get('yaw') or 0.0)
        facing = max(0.0, 1.0 - yaw / (2 * LOOK_AWAY_RAD))
        if _looking_away(f):
            away += 1
        q = f.get('quality')
        q = 0.5 if q is None else q
        scores.append(0.45 * q + 0.35 * eye_ok + 0.20 * facing)
    return {'faces': len(faces), 'eyes_closed': closed, 'looking_away': away,
            'score': round(sum(scores) / len(scores), 3), 'boxes': face_boxes(faces)}


def compute_faces(conn, progress: Optional[Callable] = None, cancelled: Callable[[], bool] = lambda: False) -> dict:
    if not helper_available():
        return {'skipped': 'helper not built; run scripts/build-helper.sh'}
    from app.ai.throttle import Throttle
    rows = conn.execute(
        "SELECT a.sha256, MIN(s.path || '/' || a.rel_path) AS path FROM assets a JOIN sources s ON s.id = a.source_id "
        "WHERE a.status = 'present' AND a.kind = 'image' AND a.sha256 != '' "
        'AND a.sha256 NOT IN (SELECT sha256 FROM faces) GROUP BY a.sha256').fetchall()
    # Apple Vision face detection is light: no AI duty cycle, and a few batches run at once
    # (thermal and battery pauses still apply; M9 speed-up, owner's OK 2026-11-16).
    throttle = Throttle(cancelled, status=(lambda m: progress(m, 0, 0)) if progress else None, share=100)
    done = 0
    chunks = [rows[i:i + BATCH] for i in range(0, len(rows), BATCH)]
    from concurrent.futures import ThreadPoolExecutor
    pool = ThreadPoolExecutor(FACE_WORKERS)
    try:
        futures = [pool.submit(_run, 'faces', [c['path'] for c in chunk]) for chunk in chunks]
    except Exception:
        pool.shutdown(wait=False, cancel_futures=True)
        raise
    for i, (chunk, fut) in enumerate(zip(chunks, futures)):
        if cancelled():
            pool.shutdown(wait=False, cancel_futures=True)
            break
        if progress:
            progress('Faces (Apple Vision)', i * BATCH, len(rows))
        try:
            res = {r['path']: r for r in fut.result()}
        except Exception:
            res = {}
        busy = 0.0
        with conn:
            for c in chunk:
                r = res.get(c['path'])
                if r is None:
                    continue
                faces = r.get('faces') or []
                conn.execute('INSERT OR REPLACE INTO faces (sha256, n_faces, faces_json, computed_at) VALUES (?, ?, ?, ?)',
                             (c['sha256'], len(faces), json.dumps(faces), now_iso()))
                done += 1
        throttle.after_work(busy)
    pool.shutdown(wait=False, cancel_futures=True)
    return {'analysed': done}


def compute_videos(conn, progress: Optional[Callable] = None, cancelled: Callable[[], bool] = lambda: False) -> dict:
    if not helper_available():
        return {'skipped': 'helper not built; run scripts/build-helper.sh'}
    rows = conn.execute(
        "SELECT a.sha256, MIN(s.path || '/' || a.rel_path) AS path FROM assets a JOIN sources s ON s.id = a.source_id "
        "WHERE a.status = 'present' AND a.kind = 'video' AND a.sha256 != '' "
        'AND a.sha256 NOT IN (SELECT sha256 FROM video_meta) GROUP BY a.sha256').fetchall()
    out_dir = data_dir() / 'cache' / 'video-thumbs'
    done = 0
    for i in range(0, len(rows), BATCH):
        if cancelled():
            break
        chunk = rows[i:i + BATCH]
        if progress:
            progress('Videos (poster frames)', i, len(rows))
        res = {r['path']: r for r in _run('video', [c['path'] for c in chunk], [str(out_dir)])}
        with conn:
            for c in chunk:
                r = res.get(c['path'], {'error': 'no answer from helper'})
                conn.execute('INSERT OR REPLACE INTO video_meta (sha256, duration, width, height, created, thumb, error, '
                             'computed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                             (c['sha256'], r.get('duration'), r.get('width'), r.get('height'), r.get('created'),
                              r.get('thumb'), r.get('error'), now_iso()))
                done += 1
    return {'videos': done}


def summaries(conn) -> dict:
    """sha256 -> face_summary (or None)."""
    return {r['sha256']: face_summary(json.loads(r['faces_json'])) for r in conn.execute('SELECT sha256, faces_json FROM faces')}

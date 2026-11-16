"""Face quality and video metadata from the on-device Swift helper.

The helper (tools/mac-helper/PhotoCuratorHelper.swift, built by
scripts/build-helper.sh into local-data/bin/pc-helper) uses Apple Vision and
AVFoundation. No faces are identified or stored as identities; per face only
Apple's capture quality, head angles and eye openness are kept.

face_summary() turns that into the criteria the owner asked for when choosing
between near-identical photos: eyes open, looking at the camera, face sharp.

M10b: per main face the eyes are open, closed or unsure (eye_state, then
apply_moment against the same face in the other frames of a moment). Helper
v2 also gives Apple's aesthetics score, the utility flag and salient boxes per
photo (faces.vision_json); app/quality/subject.py then measures blur on the
subject.
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


MAIN_SHARE = 0.25        # a main face has at least a quarter of the largest face's area
MAX_MAIN = 3


def top_left(box) -> tuple:
    """Vision box (origin bottom left) -> (x, y, w, h) with the origin at the top left."""
    x, y, w, h = (float(v) for v in box[:4])
    return x, 1.0 - (y + h), w, h


def main_faces(faces: list) -> list:
    """The 1-3 largest usable faces whose area is at least MAIN_SHARE of the largest (background people ignored)."""
    usable = sorted(_usable(faces), key=lambda f: -(f['box'][2] * f['box'][3]))
    if not usable:
        return []
    big = usable[0]['box'][2] * usable[0]['box'][3]
    return [f for f in usable if f['box'][2] * f['box'][3] >= MAIN_SHARE * big][:MAX_MAIN]


# Eye state per main face (M10b): open | closed | unsure. "Unsure" never leaves a photo out.
SMALL_FACE_PX = 128      # face side (sqrt of box area, original pixels) below which eye landmarks are too coarse
SMALL_FACE_AREA = 0.0025  # the same floor as a share of the image when the pixel size is unknown
EYE_SHUT = 0.08          # below this the eye is shut even if the face never looks better in the moment
LANDMARKS_MIN = 0.7      # Vision landmarks confidence below this: unsure
EYE_PRECISION_MAX = 0.02  # mean eye-contour position error (helper v2) above this: unsure (turned or hidden eyes)
DARK_LENS = 0.45         # eye area brightness / cheek brightness below this: dark sunglasses, unsure
PITCH_DOWN = 0.15        # head tilted down (Vision pitch > 0, about 9 degrees): a flat eye contour is not proof
REL_CLOSED = 0.65        # within a moment: closed when at most this share of the same face's best openness
REL_MAX = 0.20           # ... and below this openness (a normal eye next to wide-open eyes is not closed)
SAME_FACE = 0.6          # faces in two frames are the same when their centres are within this many face widths


def _eye_closed(f: dict) -> bool:
    eyes = [e for e in (f.get('left_eye'), f.get('right_eye')) if e is not None]
    return bool(eyes) and min(eyes) < EYE_CLOSED


def _looking_away(f: dict) -> bool:
    return abs(f.get('yaw') or 0.0) > LOOK_AWAY_RAD


def openness(f: dict) -> Optional[float]:
    """The less open eye (one shut eye counts), eye contour height / width."""
    eyes = [e for e in (f.get('left_eye'), f.get('right_eye')) if e is not None]
    return min(eyes) if eyes else None


def eye_state(f: dict, dims: Optional[tuple] = None, lens: Optional[float] = None) -> tuple:
    """(state, why) for one face on its own. why: small | turned | no_landmarks | low_confidence | sunglasses |
    looking_down | between | None. `dims` = (width, height) of the image in pixels, `lens` from subject.eye_lens."""
    x, y, w, h = (float(v) for v in f['box'][:4])
    if dims and dims[0] and dims[1]:
        if (w * h * dims[0] * dims[1]) ** 0.5 < SMALL_FACE_PX:
            return 'unsure', 'small'
    elif w * h < SMALL_FACE_AREA:
        return 'unsure', 'small'
    if _looking_away(f):
        return 'unsure', 'turned'
    o = openness(f)
    if o is None:
        return 'unsure', 'no_landmarks'
    lc, prec = f.get('landmarks_confidence'), f.get('eye_precision')
    if (lc is not None and lc < LANDMARKS_MIN) or (prec is not None and prec > EYE_PRECISION_MAX):
        return 'unsure', 'low_confidence'
    if lens is not None and lens < DARK_LENS:
        return 'unsure', 'sunglasses'
    if o >= EYE_OPEN:
        return 'open', None
    if (f.get('pitch') or 0.0) > PITCH_DOWN:
        return 'unsure', 'looking_down'        # looking down flattens the eye contour
    if o < EYE_CLOSED:
        return 'closed', None
    return 'unsure', 'between'


def _annotate(faces: list, dims=None, lenses=None) -> list:
    """Usable faces in helper order with box (top left), main flag, state and openness."""
    mains = {id(f) for f in main_faces(faces)}
    out = []
    for i, f in enumerate(faces or []):
        if not (f.get('box') and f['box'][2] * f['box'][3] >= MIN_FACE_AREA):
            continue
        lens = lenses[i] if lenses and i < len(lenses) else None
        state, why = eye_state(f, dims, lens)
        out.append({'f': f, 'box': top_left(f['box']), 'main': id(f) in mains, 'state': state, 'why': why,
                    'open': openness(f)})
    return out


def apply_moment(frames: list) -> None:
    """Compare each face with the same face (matched by box centre) in the other frames of a moment, in place.
    Closed: clearly below its own best in the moment. A laugh or squint is not closed when the face never
    looks more open in the moment (unless the eye is shut outright)."""
    def centre(a):
        x, y, w, h = a['box']
        return x + w / 2, y + h / 2, max(w, h)
    changes = []
    for i, frame in enumerate(frames):
        for a in frame:
            if a['why'] not in (None, 'between') or a['open'] is None:
                continue
            ax, ay, aw = centre(a)
            best, matched = a['open'], False
            for j, other in enumerate(frames):
                if j == i:
                    continue
                near = [b for b in other if b['why'] in (None, 'between') and b['open'] is not None]
                cand = [(abs(centre(b)[0] - ax) + abs(centre(b)[1] - ay), b) for b in near]
                cand = [c for c in cand if c[0] <= SAME_FACE * max(aw, centre(c[1])[2])]
                if cand:
                    matched = True
                    best = max(best, min(cand, key=lambda c: c[0])[1]['open'])
            if not matched:
                continue
            if a['state'] == 'closed' and a['open'] >= EYE_SHUT and best < EYE_OPEN:
                changes.append((a, 'unsure', 'squint'))
            elif a['state'] != 'closed' and best >= EYE_OPEN and a['open'] < REL_MAX and a['open'] <= REL_CLOSED * best:
                changes.append((a, 'closed', 'relative'))
    for a, state, why in changes:
        a['state'], a['why'] = state, why


def face_boxes(faces: list, limit: int = MAX_BOXES, dims=None, lenses=None, annotated=None) -> list:
    """Up to `limit` faces as {x, y, w, h, eyes_closed, looking_away, state, main}, normalised to the image with
    the origin at the top left (the helper keeps Vision's bottom-left origin, so y is flipped)."""
    out = []
    for a in (annotated if annotated is not None else _annotate(faces, dims, lenses))[:limit]:
        x, y, w, h = a['box']
        out.append({'x': round(x, 4), 'y': round(y, 4), 'w': round(w, 4), 'h': round(h, 4),
                    'eyes_closed': a['state'] == 'closed', 'looking_away': _looking_away(a['f']),
                    'state': a['state'], 'main': a['main']})
    return out


_EYE_OK = {'open': 1.0, 'unsure': 0.7, 'closed': 0.0}


def face_summary(faces: list, dims=None, lenses=None, annotated=None) -> Optional[dict]:
    """Per photo: counts, a 0-1 face score and the face boxes, or None when there are no faces.
    eyes_closed counts main faces whose eyes are closed; eyes = {open, closed, unsure} over main faces."""
    ann = annotated if annotated is not None else _annotate(faces, dims, lenses)
    if not ann:
        return None
    scores = []
    for a in ann:
        yaw = abs(a['f'].get('yaw') or 0.0)
        facing = max(0.0, 1.0 - yaw / (2 * LOOK_AWAY_RAD))
        q = a['f'].get('quality')
        q = 0.5 if q is None else q
        scores.append(0.45 * q + 0.35 * _EYE_OK[a['state']] + 0.20 * facing)
    mains = [a for a in ann if a['main']]
    eyes = {k: sum(1 for a in mains if a['state'] == k) for k in ('open', 'closed', 'unsure')}
    mq = [a['f'].get('quality') for a in mains if a['f'].get('quality') is not None]
    return {'faces': len(ann), 'main_faces': len(mains), 'eyes_closed': eyes['closed'], 'eyes': eyes,
            'looking_away': sum(1 for a in ann if _looking_away(a['f'])),
            'capture_quality': round(sum(mq) / len(mq), 3) if mq else None,
            'score': round(sum(scores) / len(scores), 3), 'boxes': face_boxes(faces, annotated=ann)}


def compute_faces(conn, progress: Optional[Callable] = None, cancelled: Callable[[], bool] = lambda: False) -> dict:
    """Helper results per photo (faces, aesthetics, utility, salient boxes), then the subject sharpness."""
    from app.quality.subject import compute_subject_focus
    if not helper_available():
        res = {'skipped': 'helper not built; run scripts/build-helper.sh'}
    else:
        res = _compute_helper(conn, progress, cancelled)
    if not cancelled():
        res['subject'] = compute_subject_focus(conn, progress, cancelled)
    return res


def _compute_helper(conn, progress: Optional[Callable] = None, cancelled: Callable[[], bool] = lambda: False) -> dict:
    from app.ai.throttle import Throttle
    rows = conn.execute(
        "SELECT a.sha256, MIN(s.path || '/' || a.rel_path) AS path FROM assets a JOIN sources s ON s.id = a.source_id "
        "WHERE a.status = 'present' AND a.kind = 'image' AND a.sha256 != '' "
        # rows from the older helper (no vision_json) are measured again once (M10b)
        'AND a.sha256 NOT IN (SELECT sha256 FROM faces WHERE vision_json IS NOT NULL) GROUP BY a.sha256').fetchall()
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
                vision = {k: r[k] for k in ('aesthetic', 'utility', 'salient') if k in r}
                conn.execute('INSERT OR REPLACE INTO faces (sha256, n_faces, faces_json, vision_json, computed_at) '
                             'VALUES (?, ?, ?, ?, ?)',
                             (c['sha256'], len(faces), json.dumps(faces), json.dumps(vision), now_iso()))
                conn.execute('DELETE FROM subject_focus WHERE sha256 = ?', (c['sha256'],))
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


def vision_info(conn) -> dict:
    """sha256 -> {aesthetic (-1..1 or None), utility (bool)} from the helper (Apple Vision aesthetics)."""
    out = {}
    for r in conn.execute('SELECT sha256, vision_json FROM faces'):
        v = json.loads(r['vision_json'] or '{}')
        out[r['sha256']] = {'aesthetic': v.get('aesthetic'), 'utility': bool(v.get('utility'))}
    return out


def moment_groups(conn) -> list:
    """The duplicate moments (exact and near groups) as lists of sha256."""
    groups = {}
    for r in conn.execute("SELECT m.group_id, a.sha256 FROM duplicate_members m JOIN duplicate_groups g ON g.id = m.group_id "
                          "JOIN assets a ON a.id = m.asset_id WHERE g.category IN ('exact', 'near')"):
        groups.setdefault(r['group_id'], []).append(r['sha256'])
    return list(groups.values())


def summaries(conn, moments: Optional[list] = None) -> dict:
    """sha256 -> face_summary (or None). Eye states use the image size, the eye brightness from the subject
    pass and the other frames of the same moment (`moments`: lists of sha256; default: the stored groups)."""
    from app.quality.subject import subject_rows
    dims = {r['sha256']: (r['width'], r['height']) for r in conn.execute(
        "SELECT sha256, MAX(width) AS width, MAX(height) AS height FROM assets WHERE sha256 != '' GROUP BY sha256")}
    lenses = {sha: json.loads(r.get('eyes_json') or '[]') for sha, r in subject_rows(conn).items()}
    ann = {}
    for r in conn.execute('SELECT sha256, faces_json FROM faces'):
        ann[r['sha256']] = (json.loads(r['faces_json']), _annotate(json.loads(r['faces_json']),
                                                                  dims.get(r['sha256']), lenses.get(r['sha256'])))
    for group in (moment_groups(conn) if moments is None else moments):
        shas = list(dict.fromkeys(s for s in group if s in ann))
        if len(shas) > 1:
            apply_moment([ann[s][1] for s in shas])
    return {sha: face_summary(faces, annotated=a) for sha, (faces, a) in ann.items()}

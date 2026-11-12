"""Focus tiers and photo ranking, moved from the upstream single-folder app
(photo_curator.py cull/rank steps and photo_ranking_v3.py) onto the
collection index (owner's decision 2026-11-12: one app, old page removed).

Per file content (SHA-256) the analysis stores:
  region_sharpness  90th percentile of tile focus (a sharp subject on soft
                    bokeh still counts as in focus)
  quick_quality     0-100 detail/contrast/colour proxy used to rescue soft
                    but well composed shots
  scores            composition, technical, sharpness, color, aesthetic
                    (0-100) plus sub-scores from AdvancedPhotoAnalyzer

Tiers are computed per collection with the upstream adaptive thresholds:
blur floor = max(30, 0.25 x median), sharp line = max(1.5 x floor, 0.7 x median),
rescue = soft and quick_quality >= 70th percentile. The owner can override a
tier; overrides are marks only and never move files.
"""
from __future__ import annotations

import json
import time
from typing import Callable, Optional

import cv2
import numpy as np

from app.collections import now_iso

CATEGORIES = ('composition', 'technical', 'sharpness', 'color', 'aesthetic')
DEFAULT_WEIGHTS = {'aesthetic': 30, 'composition': 22, 'technical': 20, 'sharpness': 16, 'color': 12}
SUB = ('rule_of_thirds', 'horizon_level', 'balance', 'exposure', 'dynamic_range', 'tonal',
       'white_balance', 'noise', 'colorfulness', 'harmony')


def region_sharpness(gray, tiles=8):
    h, w = gray.shape[:2]
    if max(h, w) > 1024:
        sc = 1024.0 / max(h, w)
        gray = cv2.resize(gray, (int(w * sc), int(h * sc)), interpolation=cv2.INTER_AREA)
    lap = cv2.Laplacian(gray, cv2.CV_64F)
    g = gray.astype('float32')
    H, W = g.shape
    th, tw = max(1, H // tiles), max(1, W // tiles)
    scores = []
    for y in range(0, H, th):
        for x in range(0, W, tw):
            tg = g[y:y + th, x:x + tw]
            if tg.size < 64:
                continue
            scores.append(float(lap[y:y + th, x:x + tw].var()) / (float(tg.var()) + 1e-6) * 1000.0)
    return float(np.percentile(np.array(scores), 90)) if scores else 0.0


def quick_quality(bgr, gray):
    edges = cv2.Canny(gray, 60, 160)
    ed = float(np.count_nonzero(edges)) / edges.size
    contrast = float(gray.std())
    b, gg, r = (bgr[:, :, i].astype('float32') for i in range(3))
    rg, yb = r - gg, 0.5 * (r + gg) - b
    cf = (rg.std() ** 2 + yb.std() ** 2) ** 0.5 + 0.3 * (rg.mean() ** 2 + yb.mean() ** 2) ** 0.5
    q = 0.5 * min(1, ed / 0.12) + 0.25 * min(1, contrast / 70) + 0.25 * min(1, cf / 80)
    return float(max(0.0, min(1.0, q)) * 100)


_analyzer = None


def analyze_file(path: str) -> Optional[dict]:
    """One decode, then focus, quality and ranking scores (CPU only)."""
    global _analyzer
    from photo_ranking_v3 import AdvancedPhotoAnalyzer
    if _analyzer is None:
        _analyzer = AdvancedPhotoAnalyzer()
    bgr, gray = _analyzer._load(path)
    if bgr is None:
        return None
    comp, rot, horizon, balance = _analyzer._composition(gray)
    tech, exposure, dr, tonal, wb, noise = _analyzer._technical(bgr, gray)
    sharp = _analyzer._sharpness(gray)
    color, colorfulness, harmony = _analyzer._color(bgr)
    aesthetic = 0.30 * comp + 0.22 * color + 0.20 * sharp + 0.16 * dr + 0.12 * exposure
    scores = {'composition': comp, 'technical': tech, 'sharpness': sharp, 'color': color, 'aesthetic': aesthetic,
              'rule_of_thirds': rot, 'horizon_level': horizon, 'balance': balance, 'exposure': exposure,
              'dynamic_range': dr, 'tonal': tonal, 'white_balance': wb, 'noise': noise,
              'colorfulness': colorfulness, 'harmony': harmony}
    return {'region_sharpness': region_sharpness(gray), 'quick_quality': quick_quality(bgr, gray),
            'scores': {k: round(float(v), 2) for k, v in scores.items()}}


def compute_quality(conn, progress: Optional[Callable] = None,
                    cancelled: Callable[[], bool] = lambda: False) -> dict:
    from app.ai.throttle import Throttle
    rows = conn.execute(
        "SELECT a.sha256, MIN(s.path || '/' || a.rel_path) AS path FROM assets a JOIN sources s ON s.id = a.source_id "
        "WHERE a.status = 'present' AND a.kind = 'image' AND a.sha256 != '' "
        'AND a.sha256 NOT IN (SELECT sha256 FROM quality) GROUP BY a.sha256').fetchall()
    throttle = Throttle(cancelled, status=(lambda m: progress(m, 0, 0)) if progress else None)
    done = failed = 0
    for i, r in enumerate(rows):
        if cancelled():
            break
        if progress:
            progress('Focus and ranking scores', i, len(rows))
        t0 = time.time()
        try:
            res = analyze_file(r['path'])
        except Exception:
            res = None
        busy = time.time() - t0
        if res is None:
            failed += 1
        else:
            with conn:
                conn.execute('INSERT OR REPLACE INTO quality (sha256, region_sharpness, quick_quality, scores_json, '
                             'computed_at) VALUES (?, ?, ?, ?, ?)',
                             (r['sha256'], res['region_sharpness'], res['quick_quality'],
                              json.dumps(res['scores']), now_iso()))
            done += 1
        if i < len(rows) - 1:
            throttle.after_work(busy)
    return {'scored': done, 'failed': failed}


def thresholds(values: list, strictness: float = 1.0) -> tuple:
    if not values:
        return 90.0 * strictness, 230.0 * strictness
    m = float(np.median(values))
    blur_lo = max(30.0, m * 0.25)
    sharp_hi = max(blur_lo * 1.5, m * 0.70)
    return blur_lo * strictness, sharp_hi * strictness


def classify(region_s, q, blur_lo, sharp_hi, q_rescue):
    if region_s >= sharp_hi:
        return 'sharp', False
    if region_s >= blur_lo:
        return 'soft', q >= q_rescue
    if q >= q_rescue and region_s >= blur_lo * 0.6:
        return 'soft', True
    return 'blurry', False


def focus_tiers(conn) -> dict:
    """asset_id -> {tier, rescued, region_sharpness, override}."""
    rows = conn.execute(
        'SELECT a.id, a.sha256, q.region_sharpness, q.quick_quality, m.focus AS override FROM assets a '
        'JOIN quality q ON q.sha256 = a.sha256 LEFT JOIN marks m ON m.sha256 = a.sha256 '
        "WHERE a.status = 'present'").fetchall()
    if not rows:
        return {}
    blur_lo, sharp_hi = thresholds([r['region_sharpness'] for r in rows])
    q_rescue = float(np.percentile([r['quick_quality'] for r in rows], 70))
    out = {}
    for r in rows:
        tier, rescued = classify(r['region_sharpness'], r['quick_quality'], blur_lo, sharp_hi, q_rescue)
        out[r['id']] = {'tier': r['override'] or tier, 'auto_tier': tier, 'rescued': rescued,
                        'region_sharpness': round(r['region_sharpness'], 1), 'override': r['override']}
    return out


def weighted(scores: dict, weights: dict) -> float:
    wsum = sum(max(0, float(weights.get(k, 0))) for k in CATEGORIES) or 1.0
    return sum(max(0, float(weights.get(k, 0))) * float(scores.get(k, 0)) for k in CATEGORIES) / wsum


def best_photos(conn, weights: Optional[dict] = None, topn: int = 50) -> list:
    """Ranking like the upstream Rank step: blurry photos, non-keeper duplicates
    and photos the owner removed are left out; the rest is ordered by the
    weighted score."""
    weights = {**DEFAULT_WEIGHTS, **(weights or {})}
    tiers = focus_tiers(conn)
    non_keepers = {r[0] for r in conn.execute(
        'SELECT m.asset_id FROM duplicate_members m JOIN duplicate_groups g ON g.id = m.group_id '
        "WHERE g.category IN ('exact', 'near') AND g.keeper_id IS NOT NULL AND g.keeper_id != m.asset_id")}
    rows = conn.execute(
        "SELECT a.id, a.filename, a.sha256, s.owner, s.path || '/' || a.rel_path AS path, q.scores_json, "
        'COALESCE(m.excluded, 0) AS excluded, COALESCE(m.wallpaper, 0) AS wallpaper FROM assets a '
        'JOIN sources s ON s.id = a.source_id JOIN quality q ON q.sha256 = a.sha256 '
        "LEFT JOIN marks m ON m.sha256 = a.sha256 WHERE a.status = 'present'").fetchall()
    seen, ranked = set(), []
    for r in rows:
        if r['sha256'] in seen or r['id'] in non_keepers or r['excluded']:
            continue
        if tiers.get(r['id'], {}).get('tier') == 'blurry':
            continue
        seen.add(r['sha256'])
        sc = json.loads(r['scores_json'])
        ranked.append({'id': r['id'], 'filename': r['filename'], 'owner': r['owner'], 'path': r['path'],
                       'score': round(weighted(sc, weights), 1), 'wallpaper': bool(r['wallpaper']),
                       'scores': {k: round(sc.get(k, 0)) for k in CATEGORIES},
                       'detail': {k: round(sc.get(k, 0)) for k in SUB}})
    ranked.sort(key=lambda x: -x['score'])
    for i, x in enumerate(ranked, 1):
        x['rank'] = i
    return ranked[:max(1, int(topn))]


def set_mark(conn, asset_id: int, **fields) -> dict:
    row = conn.execute('SELECT sha256 FROM assets WHERE id = ?', (asset_id,)).fetchone()
    if not row:
        raise ValueError('unknown photo')
    allowed = {'focus': (None, 'sharp', 'soft', 'blurry'), 'wallpaper': (True, False, 0, 1),
               'excluded': (True, False, 0, 1)}
    clean = {}
    for k, v in fields.items():
        if k not in allowed or v not in allowed[k]:
            raise ValueError(f'invalid mark {k}={v!r}')
        clean[k] = int(v) if isinstance(v, bool) else v
    with conn:
        conn.execute('INSERT OR IGNORE INTO marks (sha256, updated_at) VALUES (?, ?)', (row['sha256'], now_iso()))
        for k, v in clean.items():
            conn.execute(f'UPDATE marks SET {k} = ?, updated_at = ? WHERE sha256 = ?', (v, now_iso(), row['sha256']))
    r = conn.execute('SELECT focus, wallpaper, excluded FROM marks WHERE sha256 = ?', (row['sha256'],)).fetchone()
    return dict(r)


WALLPAPER_W, WALLPAPER_H = 1290, 2796


def crop_to_phone(img, target_w=WALLPAPER_W, target_h=WALLPAPER_H):
    """Centre-crop to a 19.5:9 portrait wallpaper (upstream feature), EXIF orientation applied."""
    from PIL import Image, ImageOps
    img = ImageOps.exif_transpose(img).convert('RGB')
    w, h = img.size
    target_ar = target_w / target_h
    if w / h > target_ar:
        new_w = int(round(h * target_ar))
        left = (w - new_w) // 2
        box = (left, 0, left + new_w, h)
    else:
        new_h = int(round(w / target_ar))
        top = (h - new_h) // 2
        box = (0, top, w, top + new_h)
    return img.crop(box).resize((target_w, target_h), Image.Resampling.LANCZOS)

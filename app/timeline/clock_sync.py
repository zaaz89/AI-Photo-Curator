"""Device clock offsets (brief section 4.3).

A "clock" is one device inside one source (source + make + model). The clock
with the most dated photos is the reference. For every other clock the module
looks for independent evidence of how far its clock is off:

  gps     camera time vs GPS UTC time in the same files (absolute; used for
          any clock, including the reference)
  scene   the same scene photographed by both devices (ORB + RANSAC geometry)
          within +/- 20 minutes. Each match gives a time difference; the
          suggestion is the value most independent matches agree on.

Rules from the brief: never infer a correction from one loosely similar
image; show evidence and confidence; corrections are reversible and stored
apart from the original metadata. A clock gets a suggestion only with at
least 3 independent matches that agree within 10 s and no competing cluster
of similar size. Otherwise the evidence is shown as "conflicting" or
"not enough". Suggestions are never applied automatically.
"""
from __future__ import annotations

import json
import statistics
from collections import defaultdict
from typing import Callable, Optional

from app.collections import now_iso
from app.duplicates.visual import scene_match
from app.metadata.exif_reader import first
from app.metadata.timestamp_resolver import parse_dt

WINDOW_S = 20 * 60
TOL_S = 10.0
MIN_INDEPENDENT = 3
MIN_INLIERS = 40
MAX_CANDIDATES = 40
CAVEAT = ('Scene matches show the same place from both devices; the two people may not have '
          'pressed the shutter at the same moment, so a small remaining difference is normal.')


def ensure_clocks(conn) -> dict:
    rows = conn.execute("SELECT DISTINCT source_id, COALESCE(make, '') AS make, COALESCE(model, '') AS model "
                        "FROM assets WHERE status = 'present'").fetchall()
    with conn:
        for r in rows:
            conn.execute('INSERT OR IGNORE INTO clocks (source_id, make, model) VALUES (?, ?, ?)',
                         (r['source_id'], r['make'], r['model']))
        for (cid,) in conn.execute('SELECT id FROM clocks').fetchall():
            conn.execute('INSERT OR IGNORE INTO clock_corrections (clock_id, updated_at) VALUES (?, ?)',
                         (cid, now_iso()))
    return {r['id']: r for r in conn.execute('SELECT * FROM clocks')}


def _photos(conn):
    """Dated images (UTC known) per clock, with raw (uncorrected) times."""
    rows = conn.execute(
        "SELECT a.id, k.id AS clock_id, s.path || '/' || a.rel_path AS path, a.rel_path, "
        "c.sort_key, c.utc_time, m.tags_json FROM assets a "
        "JOIN sources s ON s.id = a.source_id "
        "JOIN clocks k ON k.source_id = a.source_id AND k.make = COALESCE(a.make, '') "
        "  AND k.model = COALESCE(a.model, '') "
        "JOIN capture_time c ON c.asset_id = a.id "
        "LEFT JOIN metadata_raw m ON m.asset_id = a.id "
        "WHERE a.status = 'present' AND a.kind = 'image' AND c.utc_time IS NOT NULL "
        "AND c.confidence IN ('high', 'medium') ORDER BY c.sort_key").fetchall()
    per = defaultdict(list)
    for r in rows:
        per[r['clock_id']].append(r)
    return per


def _gps_evidence(photos) -> Optional[dict]:
    res = []
    for p in photos:
        tags = json.loads(p['tags_json'] or '{}')
        gps, off = parse_dt(first(tags, 'Composite:GPSDateTime', 'GPSDateTime'))
        if gps is None:
            continue
        from datetime import timezone
        gps_ts = gps.replace(tzinfo=timezone.utc).timestamp() - (off or 0) * 60
        res.append(gps_ts - p['sort_key'])
    if len(res) < MIN_INDEPENDENT:
        return None
    med = statistics.median(res)
    mad = statistics.median(abs(x - med) for x in res)
    if mad > 30:
        return {'status': 'conflicting', 'method': 'gps', 'n': len(res),
                'note': f'GPS times disagree (spread {mad:.0f} s)'}
    return {'status': 'suggested', 'method': 'gps', 'suggested_s': round(med, 1), 'n': len(res),
            'confidence': 'high' if len(res) >= 5 and mad <= 5 else 'medium',
            'note': f'median difference between camera clock and GPS time over {len(res)} photos '
                    f'(spread {mad:.1f} s)'}


def _clusters(matches):
    """Greedy windows of width 2*TOL over the sorted deltas; returns clusters by support."""
    ds = sorted(matches, key=lambda m: m['delta_s'])
    out, used = [], set()
    while True:
        best = None
        for i, a in enumerate(ds):
            if i in used:
                continue
            win = [j for j, b in enumerate(ds) if j not in used and 0 <= b['delta_s'] - a['delta_s'] <= 2 * TOL_S]
            if best is None or len(win) > len(best):
                best = win
        if not best:
            return out
        used.update(best)
        members = [ds[j] for j in best]
        out.append({'support': len(members), 'median_s': round(statistics.median(m['delta_s'] for m in members), 1),
                    'matches': members})


def _scene_evidence(ref_photos, photos, progress=None, cancelled=lambda: False) -> dict:
    best_per_photo = []
    for k, p in enumerate(photos):
        if cancelled():
            break
        if progress:
            progress('Matching scenes between devices', k, len(photos))
        cands = [r for r in ref_photos if abs(r['sort_key'] - p['sort_key']) <= WINDOW_S]
        cands.sort(key=lambda r: abs(r['sort_key'] - p['sort_key']))
        best = None
        for r in cands[:MAX_CANDIDATES]:
            good, inl = scene_match(p['path'], r['path'])
            if inl >= MIN_INLIERS and (best is None or inl > best['inliers']):
                best = {'photo': p['rel_path'], 'reference': r['rel_path'], 'inliers': inl,
                        'delta_s': round(r['sort_key'] - p['sort_key'], 1), 't': p['sort_key'],
                        'ref_id': r['id']}
        if best:
            best_per_photo.append(best)
    # Independent: one match per 10 s of this device's shooting and per reference photo.
    best_per_photo.sort(key=lambda m: -m['inliers'])
    indep, used_t, used_ref = [], [], set()
    for m in best_per_photo:
        if m['ref_id'] in used_ref or any(abs(m['t'] - t) < TOL_S for t in used_t):
            continue
        indep.append(m); used_t.append(m['t']); used_ref.add(m['ref_id'])
    for m in indep:
        m.pop('t', None); m.pop('ref_id', None)
    clusters = _clusters(indep)
    ev = {'method': 'scene', 'matches_found': len(best_per_photo), 'independent': len(indep),
          'clusters': [{k: c[k] for k in ('support', 'median_s')} for c in clusters[:3]],
          'examples': (clusters[0]['matches'][:6] if clusters else []), 'caveat': CAVEAT}
    if not clusters or clusters[0]['support'] < MIN_INDEPENDENT:
        agree = clusters[0]['support'] if clusters else 0
        ev.update(status='none', note=f'not enough evidence: {len(indep)} independent scene matches, '
                                      f'at most {agree} agree on one offset ({MIN_INDEPENDENT} needed)')
        return ev
    top = clusters[0]
    second = clusters[1]['support'] if len(clusters) > 1 else 0
    if second >= max(2, top['support'] / 2):
        ev.update(status='conflicting',
                  note=f'matches disagree: {top["support"]} point to {top["median_s"]:+.0f} s, '
                       f'{second} point to {clusters[1]["median_s"]:+.0f} s')
        return ev
    conf = 'high' if top['support'] >= 5 and second <= top['support'] / 3 else 'medium'
    ev.update(status='suggested', suggested_s=top['median_s'], confidence=conf,
              note=f'{top["support"]} independent scene matches agree on {top["median_s"]:+.0f} s')
    return ev


def sync_clocks(conn, progress: Optional[Callable] = None,
                cancelled: Callable[[], bool] = lambda: False) -> dict:
    clocks = ensure_clocks(conn)
    per = _photos(conn)
    if not per:
        return {}
    ref_id = max(per, key=lambda c: (len(per[c]), -c))
    results = {}
    for cid in clocks:
        photos = per.get(cid, [])
        ev = _gps_evidence(photos) if photos else None
        if cid == ref_id and not (ev and ev['status'] == 'suggested'):
            ev = {'status': 'reference', 'note': f'reference clock ({len(photos)} dated photos); '
                                                 'other devices are aligned to it'}
        elif ev is None or ev['status'] != 'suggested':
            ev = _scene_evidence(per[ref_id], photos, progress, cancelled) if photos else \
                {'status': 'none', 'note': 'no photos with a known time zone'}
        results[cid] = ev
        _store(conn, cid, ev)
    return {'reference': ref_id, 'clocks': {c: r['status'] for c, r in results.items()}}


def _store(conn, cid, ev):
    cur = conn.execute('SELECT status, applied_s FROM clock_corrections WHERE clock_id = ?', (cid,)).fetchone()
    keep_user = cur and cur['status'] in ('accepted', 'manual', 'rejected')
    status = cur['status'] if keep_user else ev['status']
    with conn:
        conn.execute('UPDATE clock_corrections SET suggested_s = ?, confidence = ?, method = ?, evidence_json = ?, '
                     'status = ?, updated_at = ? WHERE clock_id = ?',
                     (ev.get('suggested_s'), ev.get('confidence'), ev.get('method'),
                      json.dumps(ev, ensure_ascii=False), status, now_iso(), cid))


def set_correction(conn, clock_id: int, action: str, seconds: Optional[float] = None) -> dict:
    """accept (apply the suggestion) | manual (apply given seconds) | reset (back to none) | reject."""
    row = conn.execute('SELECT * FROM clock_corrections WHERE clock_id = ?', (clock_id,)).fetchone()
    if not row:
        raise ValueError('unknown clock')
    if action == 'accept':
        if row['suggested_s'] is None:
            raise ValueError('there is no suggestion to accept')
        applied, status = row['suggested_s'], 'accepted'
    elif action == 'manual':
        if seconds is None or abs(seconds) > 48 * 3600:
            raise ValueError('give the offset in seconds (at most 48 hours)')
        applied, status = float(seconds), 'manual'
    elif action == 'reject':
        applied, status = 0.0, 'rejected'
    elif action == 'reset':
        applied = 0.0
        status = 'suggested' if row['suggested_s'] is not None else 'none'
    else:
        raise ValueError('unknown action')
    with conn:
        conn.execute('UPDATE clock_corrections SET applied_s = ?, status = ?, updated_at = ? WHERE clock_id = ?',
                     (applied, status, now_iso(), clock_id))
    return {'applied_s': applied, 'status': status}


def list_clocks(conn) -> list:
    rows = conn.execute(
        "SELECT k.id, k.make, k.model, s.owner, s.id AS source_id, cc.*, "
        "(SELECT COUNT(*) FROM assets a WHERE a.source_id = k.source_id AND COALESCE(a.make,'') = k.make "
        " AND COALESCE(a.model,'') = k.model AND a.status = 'present') AS photos "
        "FROM clocks k JOIN sources s ON s.id = k.source_id "
        "LEFT JOIN clock_corrections cc ON cc.clock_id = k.id ORDER BY s.id, k.model").fetchall()
    out = []
    for r in rows:
        if not r['photos']:
            continue
        d = dict(r)
        d['evidence'] = json.loads(d.pop('evidence_json') or '{}')
        d['device'] = ' '.join(x for x in (r['make'], r['model']) if x) or 'unknown device'
        out.append(d)
    return out

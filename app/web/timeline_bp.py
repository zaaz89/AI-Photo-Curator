"""Collections and timeline: HTTP API + page at /timeline.

Registered on the existing Flask app, so the same loopback/Host/Origin guard
and security headers apply. Indexing runs in one background thread at a time.
"""
from __future__ import annotations

import os
import threading
import time
from pathlib import Path

from flask import Blueprint, jsonify, render_template, request

from app import collections as col
from app.analysis import analyze_collection
from app.collections import now_iso
from app.duplicates.groups import build_groups
from app.timeline.clock_sync import list_clocks, set_correction
from app.timeline.timeline_engine import duplicate_groups, timeline
from app.ai import vision_analyzer as vlm

bp = Blueprint('timeline', __name__, template_folder='templates', static_folder='static', static_url_path='/ui')

_job_lock = threading.Lock()
_job = {'running': False, 'collection': None, 'status': 'Idle', 'progress': 0,
        'result': None, 'error': None, 'cancel': False, 'started': None}

# Set by photo_curator.py so this module can open the native folder dialog
# without importing the big app module (avoids a circular import).
folder_dialog = None


def _err(msg, code=400):
    return jsonify({'ok': False, 'error': msg}), code


@bp.route('/api/collections', methods=['GET'])
def list_collections():
    return jsonify({'collections': col.list_all()})


@bp.route('/api/collections', methods=['POST'])
def create_collection():
    data = request.get_json() or {}
    try:
        slug = col.create(data.get('name', ''), (data.get('timezone') or '').strip() or None)
    except ValueError as e:
        return _err(str(e))
    return jsonify({'ok': True, 'id': slug})


@bp.route('/api/collections/<cid>/sources', methods=['GET'])
def list_sources(cid):
    try:
        conn = col.open_db(cid)
    except (FileNotFoundError, ValueError) as e:
        return _err(str(e), 404)
    rows = conn.execute(
        "SELECT s.*, (SELECT COUNT(*) FROM assets a WHERE a.source_id = s.id AND a.status = 'present') AS assets "
        'FROM sources s ORDER BY s.id').fetchall()
    return jsonify({'sources': [dict(r) for r in rows]})


@bp.route('/api/collections/<cid>/sources', methods=['POST'])
def add_source(cid):
    data = request.get_json() or {}
    path = (data.get('path') or '').strip()
    if not path and data.get('browse') and folder_dialog:
        path = folder_dialog('Choose a photo folder to add as a source') or ''
    if not path:
        return jsonify({'ok': False, 'cancelled': True})
    try:
        conn = col.open_db(cid)
        sid = col.add_source(conn, path, data.get('owner', ''), data.get('label'))
    except (FileNotFoundError, ValueError) as e:
        return _err(str(e))
    return jsonify({'ok': True, 'source_id': sid})


@bp.route('/api/collections/<cid>/sources/<int:sid>', methods=['PATCH'])
def update_source(cid, sid):
    data = request.get_json() or {}
    owner = (data.get('owner') or '').strip()
    if not owner:
        return _err('owner is required')
    try:
        conn = col.open_db(cid)
    except (FileNotFoundError, ValueError) as e:
        return _err(str(e), 404)
    with conn:
        n = conn.execute('UPDATE sources SET owner = ? WHERE id = ?', (owner, sid)).rowcount
    return jsonify({'ok': bool(n)})


def _run_index(cid):
    def progress(msg, i, n):
        _job['status'] = msg if not n else f'{msg} ({i}/{n})'
        _job['progress'] = int(i / n * 100) if n else _job['progress']
    try:
        conn = col.open_db(cid)
        _job['result'] = analyze_collection(conn, progress, cancelled=lambda: _job['cancel'])
        _job['status'] = 'Cancelled' if _job['cancel'] else \
            f"Done in {time.time() - _job['started']:.0f} s"
        _job['progress'] = 100
    except Exception as e:                       # reported to the UI, never swallowed
        _job['error'] = str(e)
        _job['status'] = f'Error: {e}'
    finally:
        _job['running'] = False


@bp.route('/api/collections/<cid>/index', methods=['POST'])
def start_index(cid):
    try:
        col.db_path(cid)
    except ValueError as e:
        return _err(str(e), 404)
    with _job_lock:
        if _job['running']:
            return _err(f"indexing {_job['collection']} is still running", 409)
        _job.update(running=True, collection=cid, status='Starting…', progress=0,
                    result=None, error=None, cancel=False, started=time.time())
    threading.Thread(target=_run_index, args=(cid,), daemon=True).start()
    return jsonify({'ok': True})


@bp.route('/api/collections/<cid>/index', methods=['GET'])
def index_status(cid):
    return jsonify({k: _job[k] for k in ('running', 'collection', 'status', 'progress', 'result', 'error')})


@bp.route('/api/collections/<cid>/index', methods=['DELETE'])
def cancel_index(cid):
    if _job['running'] and _job['collection'] == cid:
        _job['cancel'] = True
    return jsonify({'ok': True})


@bp.route('/api/collections/<cid>/timeline')
def get_timeline(cid):
    try:
        conn = col.open_db(cid)
    except (FileNotFoundError, ValueError) as e:
        return _err(str(e), 404)
    data = timeline(conn)
    name = conn.execute('SELECT name, timezone FROM collection WHERE id = 1').fetchone()
    data['collection'] = {'id': cid, 'name': name['name'], 'timezone': name['timezone']}
    return jsonify(data)


def _open(cid):
    try:
        return col.open_db(cid), None
    except (FileNotFoundError, ValueError) as e:
        return None, _err(str(e), 404)


@bp.route('/api/collections/<cid>/clocks')
def get_clocks(cid):
    conn, err = _open(cid)
    if err:
        return err
    return jsonify({'clocks': list_clocks(conn)})


@bp.route('/api/collections/<cid>/clocks/<int:clock_id>', methods=['POST'])
def change_clock(cid, clock_id):
    """Body: {"action": "accept" | "manual" | "reject" | "reset", "seconds": float}."""
    conn, err = _open(cid)
    if err:
        return err
    data = request.get_json() or {}
    try:
        sec = data.get('seconds')
        res = set_correction(conn, clock_id, data.get('action', ''), float(sec) if sec not in (None, '') else None)
    except (ValueError, TypeError) as e:
        return _err(str(e))
    build_groups(conn)          # burst detection uses corrected times
    from app.timeline.event_detector import detect_events
    detect_events(conn)         # so do events
    return jsonify({'ok': True, **res})


@bp.route('/api/collections/<cid>/duplicates')
def get_duplicates(cid):
    conn, err = _open(cid)
    if err:
        return err
    return jsonify({'groups': duplicate_groups(conn)})


@bp.route('/api/collections/<cid>/duplicates/<int:gid>/keeper', methods=['POST'])
def choose_keeper(cid, gid):
    """Body: {"asset_id": int} to choose, or {"asset_id": null} to go back to the recommendation.
    Only stores the choice; no file is touched."""
    conn, err = _open(cid)
    if err:
        return err
    g = conn.execute('SELECT group_key, category FROM duplicate_groups WHERE id = ?', (gid,)).fetchone()
    if not g or g['category'] == 'similar_scene':
        return _err('unknown duplicate group', 404)
    aid = (request.get_json() or {}).get('asset_id')
    with conn:
        if aid is None:
            conn.execute('DELETE FROM keeper_choices WHERE group_key = ?', (g['group_key'],))
        else:
            row = conn.execute('SELECT a.sha256 FROM duplicate_members m JOIN assets a ON a.id = m.asset_id '
                               'WHERE m.group_id = ? AND m.asset_id = ?', (gid, aid)).fetchone()
            if not row:
                return _err('that photo is not in this group')
            conn.execute('INSERT INTO keeper_choices (group_key, sha256, decided_at) VALUES (?, ?, ?) '
                         'ON CONFLICT(group_key) DO UPDATE SET sha256 = excluded.sha256, '
                         'decided_at = excluded.decided_at', (g['group_key'], row['sha256'], now_iso()))
    build_groups(conn)
    return jsonify({'ok': True})



@bp.route('/api/ai/status')
def ai_status():
    from app.ai.models import EMBED_MODEL, models_dir
    from app.quality.faces import helper_available
    return jsonify({'search_model': EMBED_MODEL,
                    'search_ready': (models_dir() / 'huggingface').exists(),
                    'faces_ready': helper_available(),
                    'vlm': vlm.status()})


@bp.route('/api/collections/<cid>/search')
def search_photos(cid):
    conn, err = _open(cid)
    if err:
        return err
    from app.ai.embeddings import ModelUnavailable
    from app.ai.search import search
    try:
        return jsonify(search(conn, request.args.get('q', ''), translate=request.args.get('translate') != '0'))
    except ModelUnavailable as e:
        return _err(str(e), 503)


def _run_describe(cid, limit):
    def progress(msg, i, n):
        _job['status'] = msg if not n else f'{msg} ({i}/{n})'
        _job['progress'] = int(i / n * 100) if n else _job['progress']
    try:
        conn = col.open_db(cid)
        _job['result'] = vlm.describe_collection(conn, progress, cancelled=lambda: _job['cancel'], limit=limit)
        r = _job['result']
        _job['status'] = ('Cancelled' if _job['cancel'] else 'Done') + \
            f": {r['described']} described, {r['failed']} failed, {r['remaining']} left"
        _job['progress'] = 100
    except Exception as e:
        _job['error'] = str(e)
        _job['status'] = f'Error: {e}'
    finally:
        _job['running'] = False


@bp.route('/api/collections/<cid>/describe', methods=['POST'])
def start_describe(cid):
    """Describe photos with the local VLM in the background (same job slot as indexing)."""
    try:
        col.db_path(cid)
    except ValueError as e:
        return _err(str(e), 404)
    limit = (request.get_json() or {}).get('limit')
    with _job_lock:
        if _job['running']:
            return _err(f"a job for {_job['collection']} is still running", 409)
        _job.update(running=True, collection=cid, status='Starting local AI…', progress=0,
                    result=None, error=None, cancel=False, started=time.time())
    threading.Thread(target=_run_describe, args=(cid, int(limit) if limit else None), daemon=True).start()
    return jsonify({'ok': True})


@bp.route('/api/settings', methods=['GET'])
def get_settings():
    from app import settings
    return jsonify({'settings': settings.load(), 'choices': settings.CHOICES})


@bp.route('/api/settings', methods=['POST'])
def change_settings():
    from app import settings
    try:
        return jsonify({'ok': True, 'settings': settings.save(request.get_json() or {})})
    except ValueError as e:
        return _err(str(e))



@bp.route('/api/collections/<cid>/events/<int:eid>', methods=['POST'])
def edit_event(cid, eid):
    """Body: {"action": "rename", "name": str} | {"action": "merge_previous"}."""
    conn, err = _open(cid)
    if err:
        return err
    from app.timeline import event_detector as ed
    data = request.get_json() or {}
    try:
        if data.get('action') == 'rename':
            ed.rename_event(conn, eid, data.get('name', ''))
        elif data.get('action') == 'merge_previous':
            ed.merge_with_previous(conn, eid)
        else:
            return _err('unknown action')
    except ValueError as e:
        return _err(str(e))
    return jsonify({'ok': True})


@bp.route('/api/collections/<cid>/events/split', methods=['POST'])
def split_event(cid):
    """Body: {"asset_id": int} starts a new event at that photo."""
    conn, err = _open(cid)
    if err:
        return err
    from app.timeline import event_detector as ed
    try:
        new_id = ed.split_at(conn, int((request.get_json() or {}).get('asset_id', 0)))
    except (ValueError, TypeError) as e:
        return _err(str(e))
    return jsonify({'ok': True, 'event_id': new_id})


@bp.route('/api/collections/<cid>/events/reset', methods=['POST'])
def reset_events(cid):
    """Body: {"day": "YYYY-MM-DD"} drops the owner's edits for that day."""
    conn, err = _open(cid)
    if err:
        return err
    from app.timeline import event_detector as ed
    day = (request.get_json() or {}).get('day', '')
    if not day:
        return _err('day is required')
    ed.reset_day(conn, day)
    return jsonify({'ok': True})



def _export_options(data):
    from app import settings
    if data.get('preset') == 'google_photos':
        # One folder, the kept photos (no rejected, no blurry unless favourite, no extra duplicates),
        # Live Photo videos next to their stills.
        return {'template': 'default', 'folders': 'flat', 'duplicates': 'skip', 'selection': 'no_blurry',
                'topn': 50, 'weights': settings.load()['rank_weights']}
    return {'template': data.get('template', 'default'), 'folders': data.get('folders', 'day'),
            'duplicates': data.get('duplicates', 'skip'), 'selection': data.get('selection', 'all'),
            'topn': int(data.get('topn') or 50), 'weights': settings.load()['rank_weights']}


@bp.route('/api/collections/<cid>/export/preview', methods=['POST'])
def export_preview(cid):
    """Plan only: no file is read for content or written."""
    conn, err = _open(cid)
    if err:
        return err
    from app.organization.export_plan import plan_export
    data = request.get_json() or {}
    try:
        plan = plan_export(conn, **_export_options(data))
        plan['writes_metadata'] = data.get('preset') == 'google_photos' or bool(data.get('write_metadata'))
    except ValueError as e:
        return _err(str(e))
    return jsonify(plan)


def _run_smart_export(cid, opts, dest, resume_dir, write_meta=False):
    def progress(msg, i, n):
        _job['status'] = f'{msg} ({i}/{n})' if n else msg
        _job['progress'] = int(i / n * 100) if n else _job['progress']
    try:
        from app.organization.export_plan import plan_export, run_export
        from app.safety.safe_export import ExportError
        conn = col.open_db(cid)
        plan = plan_export(conn, **opts)
        try:
            res = run_export(conn, dest, plan, resume_dir=resume_dir, progress=progress, write_meta=write_meta)
        except ExportError as e:
            raise RuntimeError(str(e))
        _job['result'] = {'export': {'ok': res.ok, 'dest': res.job_dir, 'manifest': res.manifest,
                                     'verified': res.verified, 'failed': res.failed, 'skipped': res.skipped,
                                     'metadata': res.metadata}}
        _job['status'] = (f'Export done: {res.verified} files copied and verified in {res.job_dir}' if res.ok else
                          f'Export incomplete: {res.verified} verified, {res.failed} failed, {res.skipped} skipped. '
                          f'See {res.manifest}')
        _job['progress'] = 100
    except Exception as e:
        _job['error'] = str(e)
        _job['status'] = f'Error: {e}'
    finally:
        _job['running'] = False


@bp.route('/api/collections/<cid>/export', methods=['POST'])
def start_smart_export(cid):
    """Body: template, folders, duplicates, optional dest (else a folder dialog), optional resume_dir."""
    try:
        col.db_path(cid)
    except ValueError as e:
        return _err(str(e), 404)
    data = request.get_json() or {}
    dest = data.get('dest') or (folder_dialog('Choose where to export (outside your photo folders)')
                                if folder_dialog else None)
    if not dest:
        return jsonify({'ok': False, 'cancelled': True})
    with _job_lock:
        if _job['running']:
            return _err(f"a job for {_job['collection']} is still running", 409)
        _job.update(running=True, collection=cid, status='Preparing export…', progress=0,
                    result=None, error=None, cancel=False, started=time.time())
    threading.Thread(target=_run_smart_export,
                     args=(cid, _export_options(data), dest, data.get('resume_dir'),
                           data.get('preset') == 'google_photos' or bool(data.get('write_metadata'))),
                     daemon=True).start()
    return jsonify({'ok': True, 'dest': dest})



@bp.route('/api/collections/<cid>/marks', methods=['POST'])
def set_marks(cid):
    """Body: {"asset_id": int, "focus": "sharp"|"soft"|"blurry"|null, "wallpaper": bool, "excluded": bool}.
    Marks only; no file is moved."""
    conn, err = _open(cid)
    if err:
        return err
    from app.quality.scoring import set_mark
    data = dict(request.get_json() or {})
    try:
        aid = int(data.pop('asset_id'))
        return jsonify({'ok': True, 'marks': set_mark(conn, aid, **data)})
    except (KeyError, TypeError, ValueError) as e:
        return _err(str(e))


@bp.route('/api/collections/<cid>/best')
def get_best(cid):
    conn, err = _open(cid)
    if err:
        return err
    from app import settings
    from app.quality.scoring import best_photos
    return jsonify({'weights': settings.load()['rank_weights'],
                    'photos': best_photos(conn, settings.load()['rank_weights'], int(request.args.get('topn', 50)))})


def _run_wallpapers(cid, dest):
    try:
        from app.quality.scoring import crop_to_phone
        from app.safety.safe_export import ExportItem, ExportError, export_copies
        conn = col.open_db(cid)
        rows = conn.execute("SELECT a.filename, s.path || '/' || a.rel_path AS path FROM assets a "
                            'JOIN sources s ON s.id = a.source_id JOIN marks m ON m.sha256 = a.sha256 '
                            "WHERE m.wallpaper = 1 AND a.status = 'present' GROUP BY a.sha256").fetchall()
        items = []
        for k, r in enumerate(rows, 1):
            stem = f"{k:03d}_{Path(r['filename']).stem}"
            items.append(ExportItem(source=r['path'], dest_name=f"Original/{stem}{Path(r['filename']).suffix}"))
            items.append(ExportItem(source=r['path'], dest_name=f'Wallpaper_19.5x9/{stem}.jpg', kind='derived'))

        def derive(it, target):
            from raw_loader import open_image_pil
            with open_image_pil(it.source) as im, open(target, 'xb') as fout:
                crop_to_phone(im).save(fout, format='JPEG', quality=92)

        roots = [r[0] for r in conn.execute('SELECT path FROM sources')]
        res = export_copies(items, dest, roots, 'Phone wallpapers', derive=derive)
        _job['result'] = {'export': {'ok': res.ok, 'dest': res.job_dir, 'verified': res.verified,
                                     'failed': res.failed}}
        _job['status'] = (f'Wallpapers done: {len(rows)} photos in {res.job_dir}' if res.ok
                          else f'Wallpapers incomplete: {res.failed} failed. See {res.manifest}')
        _job['progress'] = 100
    except Exception as e:
        _job['error'] = str(e)
        _job['status'] = f'Error: {e}'
    finally:
        _job['running'] = False


@bp.route('/api/collections/<cid>/export/wallpapers', methods=['POST'])
def export_wallpapers(cid):
    """Flagged photos as verified originals plus 1290x2796 phone crops (upstream Phone BG feature)."""
    conn, err = _open(cid)
    if err:
        return err
    n = conn.execute('SELECT COUNT(*) FROM marks WHERE wallpaper = 1').fetchone()[0]
    if not n:
        return _err('No photos are flagged as wallpaper yet.')
    data = request.get_json() or {}
    dest = data.get('dest') or (folder_dialog('Choose where to export wallpapers') if folder_dialog else None)
    if not dest:
        return jsonify({'ok': False, 'cancelled': True})
    with _job_lock:
        if _job['running']:
            return _err(f"a job for {_job['collection']} is still running", 409)
        _job.update(running=True, collection=cid, status='Exporting wallpapers…', progress=0,
                    result=None, error=None, cancel=False, started=time.time())
    threading.Thread(target=_run_wallpapers, args=(cid, dest), daemon=True).start()
    return jsonify({'ok': True})



@bp.route('/api/collections/<cid>/marks/batch', methods=['POST'])
def set_marks_batch(cid):
    """Body: {"asset_ids": [...], "favorite"|"rejected"|"focus"|"wallpaper"|"excluded": value}."""
    conn, err = _open(cid)
    if err:
        return err
    from app.quality.scoring import set_mark
    data = dict(request.get_json() or {})
    ids = data.pop('asset_ids', None) or []
    try:
        for a in ids:
            set_mark(conn, int(a), **data)
    except (TypeError, ValueError) as e:
        return _err(str(e))
    return jsonify({'ok': True, 'count': len(ids)})


@bp.route('/api/collections/<cid>/events/move', methods=['POST'])
def move_photos(cid):
    """Body: {"asset_ids": [...], "event_id": int | null, "name": str (for a new event)}."""
    conn, err = _open(cid)
    if err:
        return err
    from app.timeline.event_detector import move_to_event
    data = request.get_json() or {}
    try:
        eid = move_to_event(conn, [int(a) for a in data.get('asset_ids') or []], data.get('event_id'),
                            (data.get('name') or '').strip() or None)
    except (TypeError, ValueError) as e:
        return _err(str(e))
    return jsonify({'ok': True, 'event_id': eid})


@bp.route('/api/collections/<cid>/workflow', methods=['GET', 'POST'])
def workflow(cid):
    """The trip checklist. POST {"step": str, "done": bool}."""
    conn, err = _open(cid)
    if err:
        return err
    steps = ('import', 'times', 'duplicates', 'blurry', 'events', 'descriptions', 'export')
    if request.method == 'POST':
        data = request.get_json() or {}
        if data.get('step') not in steps:
            return _err('unknown step')
        with conn:
            conn.execute('INSERT INTO workflow (step, done, updated_at) VALUES (?, ?, ?) ON CONFLICT(step) '
                         'DO UPDATE SET done = excluded.done, updated_at = excluded.updated_at',
                         (data['step'], int(bool(data.get('done'))), now_iso()))
    done = {r['step']: bool(r['done']) for r in conn.execute('SELECT step, done FROM workflow')}
    return jsonify({'steps': [{'step': s, 'done': done.get(s, False)} for s in steps]})


@bp.route('/api/collections/<cid>/poster/<int:asset_id>')
def video_poster(cid, asset_id):
    """Poster frame of a video, made by the helper into local-data/cache/video-thumbs."""
    conn, err = _open(cid)
    if err:
        return err
    from flask import abort, send_file
    row = conn.execute('SELECT v.thumb FROM assets a JOIN video_meta v ON v.sha256 = a.sha256 WHERE a.id = ?',
                       (asset_id,)).fetchone()
    base = os.path.realpath(col.data_dir() / 'cache' / 'video-thumbs')
    if not row or not row['thumb'] or not os.path.realpath(row['thumb']).startswith(base + os.sep):
        abort(404)
    return send_file(row['thumb'], mimetype='image/jpeg', max_age=86400)


@bp.route('/api/collections/<cid>/media/<int:asset_id>')
def media(cid, asset_id):
    """Stream a video (read-only, range requests) from a source folder of this collection."""
    conn, err = _open(cid)
    if err:
        return err
    from flask import abort, send_file
    row = conn.execute("SELECT s.path AS root, a.rel_path, a.kind FROM assets a JOIN sources s ON s.id = a.source_id "
                       "WHERE a.id = ? AND a.status = 'present'", (asset_id,)).fetchone()
    if not row or row['kind'] != 'video':
        abort(404)
    root = os.path.realpath(row['root'])
    path = os.path.realpath(os.path.join(root, row['rel_path']))
    if not path.startswith(root + os.sep) or not os.path.isfile(path):
        abort(404)
    return send_file(path, conditional=True, max_age=0)


@bp.route('/api/reveal-export', methods=['POST'])
def reveal_export():
    """Open a finished export folder in Finder. Only folders that hold this app's
    export manifest are accepted, so the endpoint cannot open arbitrary paths."""
    import subprocess
    from app.safety.safe_export import MANIFEST_NAME
    path = os.path.realpath(str((request.get_json() or {}).get('path') or ''))
    if not path or not os.path.isdir(path) or not os.path.isfile(os.path.join(path, MANIFEST_NAME)):
        return _err('not an export folder', 404)
    subprocess.run(['open', path], timeout=10)
    return jsonify({'ok': True})


@bp.route('/api/browse-folder', methods=['POST'])
def browse_folder():
    """Native folder picker; returns the chosen path only (nothing is added)."""
    prompt = (request.get_json() or {}).get('prompt') or 'Choose a folder'
    path = folder_dialog(str(prompt)[:120]) if folder_dialog else None
    return jsonify({'path': path})

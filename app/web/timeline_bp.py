"""Collections and timeline: HTTP API + page at /timeline.

Registered on the existing Flask app, so the same loopback/Host/Origin guard
and security headers apply. Indexing runs in one background thread at a time.
"""
from __future__ import annotations

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

bp = Blueprint('timeline', __name__, template_folder='templates')

_job_lock = threading.Lock()
_job = {'running': False, 'collection': None, 'status': 'Idle', 'progress': 0,
        'result': None, 'error': None, 'cancel': False, 'started': None}

# Set by photo_curator.py so this module can open the native folder dialog
# without importing the big app module (avoids a circular import).
folder_dialog = None


def _err(msg, code=400):
    return jsonify({'ok': False, 'error': msg}), code


@bp.route('/timeline')
def page():
    return render_template('timeline.html')


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
    return jsonify({'search_model': EMBED_MODEL,
                    'search_ready': (models_dir() / 'huggingface').exists(),
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

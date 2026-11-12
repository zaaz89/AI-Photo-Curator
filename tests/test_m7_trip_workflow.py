"""M7: face-aware keeper, favourites and left-out photos, moving photos between events,
the trip checklist, video routes, the Google Photos export with metadata in copies."""
import json
import shutil
import time
from pathlib import Path

import pytest

from app import collections as col, settings
from app.analysis import analyze_collection
from app.duplicates.groups import _recommend
from app.organization.export_plan import plan_export, run_export
from app.organization.metadata_writer import tag_args, write_into_copies
from app.quality.faces import face_summary
from conftest import make_photo, snapshot, textured_scene

HAS_EXIFTOOL = shutil.which('exiftool') is not None


# ---------- faces ----------

def _face(q=0.8, left=0.3, right=0.3, yaw=0.0, box=(0.3, 0.3, 0.2, 0.2)):
    return {'quality': q, 'left_eye': left, 'right_eye': right, 'yaw': yaw, 'box': list(box)}


def test_face_summary_flags_closed_eyes_and_looking_away():
    assert face_summary([]) is None
    assert face_summary([_face(box=(0, 0, 0.01, 0.01))]) is None        # tiny background face ignored
    open_ = face_summary([_face()])
    closed = face_summary([_face(left=0.05, right=0.3)])                 # one eye shut counts
    away = face_summary([_face(yaw=1.0)])
    assert open_['eyes_closed'] == 0 and open_['looking_away'] == 0
    assert closed['eyes_closed'] == 1 and closed['score'] < open_['score']
    assert away['looking_away'] == 1 and away['score'] < open_['score']


def test_keeper_prefers_open_eyes_over_a_slightly_sharper_frame():
    rows = {0: {'id': 1, 'sha256': 'a', 'width': 4000, 'height': 3000, 'source_id': 1, 'rel_path': 'a.jpg'},
            1: {'id': 2, 'sha256': 'b', 'width': 4000, 'height': 3000, 'source_id': 1, 'rel_path': 'b.jpg'}}
    feats = {'a': (None, 100.0), 'b': (None, 110.0)}
    faces = {'a': face_summary([_face()]), 'b': face_summary([_face(left=0.04, right=0.05)])}
    quality = {'a': (100.0, 70), 'b': (110.0, 70)}
    keeper, reasons = _recommend(rows, feats, [0, 1], 'near', None, faces, quality)
    assert keeper == 1
    assert any('eyes open' in r for r in reasons)
    # With faces switched off in the settings, sharpness decides.
    keeper2, _ = _recommend(rows, feats, [0, 1], 'near', None, faces, quality, {'faces': 0})
    assert keeper2 == 2
    # The owner's choice always wins.
    assert _recommend(rows, feats, [0, 1], 'near', 'b', faces, quality)[0] == 2


def test_keeper_weights_setting_is_validated():
    with pytest.raises(ValueError):
        settings.save({'keeper_weights': {'smile': 10}})
    s = settings.save({'keeper_weights': {'faces': 500, 'focus': -3}})
    assert s['keeper_weights'] == {'faces': 100, 'focus': 0, 'look': 0, 'resolution': 0}
    settings.save({'keeper_weights': settings.DEFAULTS['keeper_weights']})


# ---------- a small trip ----------

@pytest.fixture
def trip(tmp_path):
    src = tmp_path / 'me'
    textured_scene(src / 'A.jpg', seed=21, dto='2026:10:24 09:00:00')
    textured_scene(src / 'B.jpg', seed=22, dto='2026:10:24 12:00:00')
    textured_scene(src / 'C.jpg', seed=23, dto='2026:10:24 18:00:00')
    make_photo(src / 'Z.jpg', seed=5, dto='2026:10:24 19:00:00', blur=True)
    (src / 'clip.MOV').write_bytes(b'\x00\x00\x00\x18ftypqt  ' + b'x' * 4000)
    slug = col.create('M7 trip')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Me')
    analyze_collection(conn)
    return src, conn, slug


def _id(conn, name):
    return conn.execute('SELECT id FROM assets WHERE filename = ?', (name,)).fetchone()[0]


def test_favourite_and_left_out_marks_drive_the_export(client, H, trip):
    src, conn, slug = trip
    a, z = _id(conn, 'A.jpg'), _id(conn, 'Z.jpg')
    r = client.post(f'/api/collections/{slug}/marks/batch', json={'asset_ids': [a], 'rejected': True}, headers=H)
    assert r.get_json()['count'] == 1
    client.post(f'/api/collections/{slug}/marks/batch', json={'asset_ids': [z], 'favorite': True}, headers=H)
    assert client.post(f'/api/collections/{slug}/marks/batch', json={'asset_ids': [a], 'favorite': 'yes'},
                       headers=H).status_code == 400
    items = {i['filename']: i for i in client.get(f'/api/collections/{slug}/timeline', headers=H).get_json()['items']}
    assert items['A.jpg']['rejected'] and items['Z.jpg']['favorite']

    plan = plan_export(conn, selection='no_blurry')
    names = [e['original_name'] for e in plan['entries']]
    assert 'A.jpg' not in names                        # left out by the owner
    assert 'Z.jpg' in names                            # blurry, but a favourite survives no_blurry
    assert plan['warnings'].get('rejected by you') == 1


def test_move_photos_to_a_new_named_event_and_lock_the_day(client, H, trip):
    src, conn, slug = trip
    ids = [_id(conn, 'B.jpg'), _id(conn, 'C.jpg')]
    r = client.post(f'/api/collections/{slug}/events/move', json={'asset_ids': ids, 'event_id': None,
                                                                  'name': 'Dinner'}, headers=H).get_json()
    assert r['ok']
    ev = conn.execute('SELECT name, name_source, locked FROM events WHERE id = ?', (r['event_id'],)).fetchone()
    assert (ev['name'], ev['name_source'], ev['locked']) == ('Dinner', 'user', 1)
    analyze_collection(conn)                           # re-analysis keeps the owner's arrangement
    members = {m[0] for m in conn.execute('SELECT asset_id FROM event_members WHERE event_id = ?', (r['event_id'],))}
    assert set(ids) <= members
    assert client.post(f'/api/collections/{slug}/events/move', json={'asset_ids': []}, headers=H).status_code == 400


def test_workflow_checklist(client, H, trip):
    src, conn, slug = trip
    steps = client.get(f'/api/collections/{slug}/workflow', headers=H).get_json()['steps']
    assert [s['step'] for s in steps] == ['import', 'times', 'duplicates', 'blurry', 'events', 'descriptions', 'export']
    assert not any(s['done'] for s in steps)
    r = client.post(f'/api/collections/{slug}/workflow', json={'step': 'times', 'done': True}, headers=H).get_json()
    assert {s['step']: s['done'] for s in r['steps']}['times'] is True
    assert client.post(f'/api/collections/{slug}/workflow', json={'step': 'nope'}, headers=H).status_code == 400


def test_video_routes_only_serve_this_collection_s_videos(client, H, trip):
    src, conn, slug = trip
    vid, img = _id(conn, 'clip.MOV'), _id(conn, 'A.jpg')
    r = client.get(f'/api/collections/{slug}/media/{vid}', headers={**H, 'Range': 'bytes=0-99'})
    assert r.status_code == 206 and len(r.data) == 100
    assert client.get(f'/api/collections/{slug}/media/{img}', headers=H).status_code == 404     # photos: not here
    assert client.get(f'/api/collections/{slug}/media/999999', headers=H).status_code == 404
    assert client.get(f'/api/collections/{slug}/poster/{vid}', headers=H).status_code == 404    # no poster made
    # A poster path that points outside the cache is refused even if it is in the database.
    sha = conn.execute('SELECT sha256 FROM assets WHERE id = ?', (vid,)).fetchone()[0]
    with conn:
        conn.execute("INSERT OR REPLACE INTO video_meta (sha256, thumb, computed_at) VALUES (?, ?, 'x')",
                     (sha, str(src / 'A.jpg')))
    assert client.get(f'/api/collections/{slug}/poster/{vid}', headers=H).status_code == 404


def test_reveal_only_opens_export_folders(client, H, tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr('subprocess.run', lambda args, **kw: calls.append(args))
    assert client.post('/api/reveal-export', json={'path': str(tmp_path)}, headers=H).status_code == 404
    (tmp_path / 'manifest.json').write_text('{}')
    assert client.post('/api/reveal-export', json={'path': str(tmp_path)}, headers=H).get_json()['ok']
    assert calls == [['open', str(tmp_path.resolve())]]


def test_folder_dialog_prompt_is_not_spliced_into_applescript(pc, monkeypatch):
    seen = {}

    class R:
        stdout = '/Users/x/Desktop/Trip/\n'

    def fake(args, **kw):
        seen['args'] = args
        return R()
    monkeypatch.setattr(pc.subprocess, 'run', fake)
    evil = 'Ana" & do shell script "touch /tmp/pwned'
    assert pc.native_folder_dialog(evil) == '/Users/x/Desktop/Trip'
    assert seen['args'][-1] == evil                                   # passed as argv
    assert not any(evil in a for a in seen['args'][:-1])              # never inside the script


# ---------- Google Photos export ----------

def test_google_photos_preset_preview(client, H, trip):
    src, conn, slug = trip
    r = client.post(f'/api/collections/{slug}/export/preview', json={'preset': 'google_photos'}, headers=H).get_json()
    assert r['writes_metadata'] is True
    assert all('/' not in e['dest'] for e in r['entries'])            # one flat folder
    assert 'Z.jpg' not in [e['original_name'] for e in r['entries']]  # blurry, not a favourite


def test_tag_args():
    args = tag_args({'datetime': '2026:10:24 09:00:00', 'offset': '+02:00', 'description': 'Two people\non a bridge.',
                     'city': 'Florence', 'country': 'Italy', 'favorite': True})
    assert '-EXIF:DateTimeOriginal=2026:10:24 09:00:00' in args and '-EXIF:OffsetTimeOriginal=+02:00' in args
    assert '-XMP-dc:Description=Two people on a bridge.' in args
    assert '-XMP-photoshop:City=Florence' in args and '-XMP-xmp:Rating=5' in args
    assert tag_args({}) == []


@pytest.mark.skipif(not HAS_EXIFTOOL, reason='ExifTool not installed')
def test_metadata_writer_refuses_anything_outside_the_export(tmp_path):
    src = tmp_path / 'src'
    make_photo(src / 'orig.jpg', seed=3)
    job = tmp_path / 'out' / 'job'
    job.mkdir(parents=True)
    before = snapshot(src)
    items = [{'dest': str(src / 'orig.jpg'), 'meta': {'description': 'x'}}]      # a source file
    res = write_into_copies(str(job), items, [str(src)])
    assert res['failed'] == 1 and 'refused' in items[0]['metadata_error']
    assert snapshot(src) == before


@pytest.mark.skipif(not HAS_EXIFTOOL, reason='ExifTool not installed')
def test_google_photos_export_writes_into_copies_only(trip, tmp_path):
    src, conn, slug = trip
    z = _id(conn, 'Z.jpg')
    from app.quality.scoring import set_mark
    set_mark(conn, z, favorite=True)
    with conn:
        sha = conn.execute('SELECT sha256 FROM assets WHERE id = ?', (_id(conn, 'B.jpg'),)).fetchone()[0]
        conn.execute("INSERT OR REPLACE INTO ai_annotations (sha256, model, prompt_version, description, created_at) "
                     "VALUES (?, 'test', 'v1', 'A stone church at noon.', 'x')", (sha,))
    before = snapshot(src)
    plan = plan_export(conn, folders='flat', selection='no_blurry')
    dest = tmp_path / 'gp'
    dest.mkdir()
    res = run_export(conn, str(dest), plan, write_meta=True)
    assert res.ok
    assert snapshot(src) == before                                   # originals untouched
    manifest = json.loads((Path(res.job_dir) / 'manifest.json').read_text())
    written = [f for f in manifest['items'] if f.get('metadata_written')]
    assert written and all(f.get('metadata_verified') for f in written)
    import subprocess
    out = json.loads(subprocess.run(['exiftool', '-j', '-r', '-XMP-dc:Description', '-XMP-xmp:Rating', res.job_dir],
                                    capture_output=True, text=True, timeout=60).stdout)
    by_name = {Path(o['SourceFile']).name: o for o in out}
    assert any(o.get('Description') == 'A stone church at noon.' for o in by_name.values())
    assert any(o.get('Rating') == 5 for o in by_name.values())

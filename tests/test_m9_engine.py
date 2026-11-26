"""M9 engine: rename album, owner descriptions, favourite extra frames, overview funnel/people/cover/highlights,
face boxes."""
import json

import pytest

from app import collections as col
from app.analysis import analyze_collection
from app.assistant import overview
from app.organization.export_plan import google_photos_options, plan_export
from app.quality.faces import face_boxes, face_summary
from app.quality.scoring import set_mark
from conftest import make_photo, make_view, snapshot, textured_scene


@pytest.fixture
def album(tmp_path):
    """Me: A+B burst (each with a Live Photo video), C (+video), D blurry, E left out (+video).
    Partner: P, one photo."""
    me, partner = tmp_path / 'me', tmp_path / 'partner'
    textured_scene(me / 'A.jpg', seed=61, dto='2026:10:24 09:00:00', model='iPhone 15')
    make_view(me / 'A.jpg', me / 'B.jpg', crop=0.01, brightness=1.02, dto='2026:10:24 09:00:01', model='iPhone 15')
    textured_scene(me / 'C.jpg', seed=62, dto='2026:10:24 12:00:00', model='iPhone 15')
    make_photo(me / 'D.jpg', seed=5, dto='2026:10:24 15:00:00', blur=True, model='iPhone 15')
    textured_scene(me / 'E.jpg', seed=63, dto='2026:10:25 10:00:00', model='iPhone 15')
    for n in 'ABCE':
        (me / f'{n}.MOV').write_bytes(b'fake video ' + n.encode())
    textured_scene(partner / 'P.jpg', seed=64, dto='2026:10:25 11:00:00', model='Pixel 8')
    slug = col.create('M9 album')
    conn = col.open_db(slug)
    col.add_source(conn, str(me), 'Me')
    col.add_source(conn, str(partner), 'Partner')
    analyze_collection(conn)
    return conn, slug


def _id(conn, name):
    return conn.execute('SELECT id FROM assets WHERE filename = ?', (name,)).fetchone()[0]


def _non_keeper(conn):
    return conn.execute("SELECT m.asset_id FROM duplicate_members m JOIN duplicate_groups g ON g.id = m.group_id "
                        "WHERE g.category IN ('exact', 'near') AND g.keeper_id != m.asset_id").fetchone()[0]


# ---- 1. rename ----

def test_rename_album(client, H, album):
    conn, slug = album
    r = client.patch(f'/api/collections/{slug}', json={'name': '  Tuscany 2026 '}, headers=H)
    assert r.get_json() == {'ok': True, 'id': slug, 'name': 'Tuscany 2026'}
    assert [c['name'] for c in client.get('/api/collections', headers=H).get_json()['collections']
            if c['id'] == slug] == ['Tuscany 2026']
    for bad in ('', '   ', 'x' * 121, 5, None):
        assert client.patch(f'/api/collections/{slug}', json={'name': bad}, headers=H).status_code == 400
    assert client.patch(f'/api/collections/{slug}', json={}, headers=H).status_code == 400
    assert client.patch('/api/collections/nope-nothing', json={'name': 'x'}, headers=H).status_code == 404


# ---- 2. no descriptions in the export (decided 2026-11-16: Google Photos writes its own) ----

def test_export_writes_no_description(album):
    conn, _ = album
    c = _id(conn, 'C.jpg')
    sha = conn.execute('SELECT sha256 FROM assets WHERE id = ?', (c,)).fetchone()[0]
    with conn:
        conn.execute("INSERT INTO ai_annotations (sha256, model, prompt_version, description, tags_json, created_at) "
                     "VALUES (?, 'm', 'p1', 'AI says a red thing.', '[\"red\"]', 'now')", (sha,))
    meta = next(e['meta'] for e in plan_export(conn, **google_photos_options())['entries'] if e['asset_id'] == c)
    assert 'description' not in meta


def _timeline_item(client, H, slug, aid):
    items = client.get(f'/api/collections/{slug}/timeline', headers=H).get_json()['items']
    return next(i for i in items if i['id'] == aid)


# ---- 3. favourite extra frames ----

def test_favourite_non_keeper_is_exported_with_its_pair(album):
    conn, _ = album
    nk = _non_keeper(conn)
    name = conn.execute('SELECT filename FROM assets WHERE id = ?', (nk,)).fetchone()[0]
    stem = name.split('.')[0]
    plain = plan_export(conn, **google_photos_options())
    assert nk not in {e['asset_id'] for e in plain['entries']}
    set_mark(conn, nk, favorite=True)
    kept = plan_export(conn, **google_photos_options())
    got = {e['original_name'] for e in kept['entries']}
    assert name in got and f'{stem}.MOV' in got                    # the frame and its video follow
    assert kept['files'] == plain['files'] + 2
    meta = next(e['meta'] for e in kept['entries'] if e['asset_id'] == nk)
    assert meta['favorite'] is True
    alt = plan_export(conn, **{**google_photos_options(), 'duplicates': 'alternatives'})
    assert next(e for e in alt['entries'] if e['asset_id'] == nk)['dest'].startswith('Selected/')
    o = overview(conn)
    photos = sum(1 for e in kept['entries'] if e['paired_with'] is None)
    assert o['export']['photos'] == photos and o['funnel']['in_album'] == photos == kept['photo_counts']['in_album']


# ---- 4. overview additions ----

def test_funnel_identity_and_pairs(album):
    conn, slug = album
    o = overview(conn)
    f = o['funnel']
    # Photos, not files: a Live Photo (still + video) is one photo, as the owner sees it.
    assert f['taken'] == 6
    assert f['taken'] == f['left_out'] + f['blurry'] + f['extra_frames'] + f['in_album']
    plan = plan_export(conn, **google_photos_options())
    assert f['in_album'] == o['export']['photos'] == sum(1 for e in plan['entries'] if e['paired_with'] is None)
    assert (f['left_out'], f['blurry'], f['extra_frames'], f['in_album']) == (0, 1, 1, 4)    # D; the non-keeper of A/B
    c = plan['counts']                                             # the plan still counts files too
    assert c['taken'] == 10 and c['taken'] == c['left_out'] + c['blurry'] + c['not_selected'] + c['extra_frames'] + c['in_album']

    set_mark(conn, _id(conn, 'E.jpg'), rejected=True)
    f = overview(conn)['funnel']
    assert f['left_out'] == 1                                      # E (its video follows it, not counted again)
    assert f['taken'] == f['left_out'] + f['blurry'] + f['extra_frames'] + f['in_album']

    set_mark(conn, _id(conn, 'D.jpg'), favorite=True)              # a favourite blurry photo stays in
    f2 = overview(conn)['funnel']
    assert f2['blurry'] == 0 and f2['in_album'] == f['in_album'] + 1
    assert f2['taken'] == f2['left_out'] + f2['blurry'] + f2['extra_frames'] + f2['in_album']


def test_funnel_when_a_pair_secondary_is_left_out_alone(album):
    conn, _ = album
    set_mark(conn, _id(conn, 'C.MOV'), rejected=True)
    o = overview(conn)
    f = o['funnel']
    # the photo C is still in the album; only its video stays out, so the photo funnel does not change
    assert f['left_out'] == 0 and f['in_album'] == 4
    assert f['taken'] == f['left_out'] + f['blurry'] + f['extra_frames'] + f['in_album']


def test_overview_survives_a_failing_album_summary(album, monkeypatch):
    conn, _ = album
    import app.assistant as a

    def boom(*_):
        raise RuntimeError('broken ranking')
    monkeypatch.setattr(a, '_cover_and_highlights', boom)
    o = overview(conn)
    assert o['facts']['photos'] == 10 and o['funnel']['in_album'] == 0 and o['highlights'] == []


def test_funnel_without_analysis_is_zero_filled(tmp_path):
    conn = col.open_db(col.create('Empty'))
    o = overview(conn)
    assert o['funnel'] == {'taken': 0, 'left_out': 0, 'screenshots': 0, 'blurry': 0, 'extra_frames': 0, 'in_album': 0}
    assert o['people'] == [] and o['cover_id'] is None and o['highlights'] == []


def test_people_per_source(album):
    conn, _ = album
    set_mark(conn, _id(conn, 'E.jpg'), rejected=True)
    people = overview(conn)['people']
    assert [(p['owner'], p['taken']) for p in people] == [('Me', 5), ('Partner', 1)]
    assert [p['in_album'] for p in people] == [2, 1]
    assert [p['source_id'] for p in people] == sorted(p['source_id'] for p in people)
    f = overview(conn)['funnel']
    assert sum(p['taken'] for p in people) == f['taken'] and sum(p['in_album'] for p in people) == f['in_album']


def test_cover_and_highlights(album):
    from app.quality.scoring import best_photos
    from app import settings
    conn, _ = album
    o = overview(conn)
    in_album = {e['asset_id'] for e in plan_export(conn, **google_photos_options())['entries']}
    ranked = [b['id'] for b in best_photos(conn, settings.load()['rank_weights'], 100) if b['id'] in in_album]
    assert o['cover_id'] == ranked[0]
    assert set(o['highlights']) <= in_album and 1 <= len(o['highlights']) <= 12
    assert D_not_in(o, conn)
    # highlights are sorted by capture time
    t = {r['id']: r['sort_key'] for r in conn.execute(
        'SELECT a.id, c.sort_key FROM assets a JOIN capture_time c ON c.asset_id = a.id')}
    assert [t[i] for i in o['highlights']] == sorted(t[i] for i in o['highlights'])
    # a favourite with a lower rank still becomes the cover
    worst = ranked[-1]
    set_mark(conn, worst, favorite=True)
    assert overview(conn)['cover_id'] == worst


def D_not_in(o, conn):
    d = _id(conn, 'D.jpg')
    return d != o['cover_id'] and d not in o['highlights']


def test_highlights_cap_per_event_and_total(tmp_path):
    src = tmp_path / 'many'
    for i in range(7):                                             # one day, one event, 7 different photos
        textured_scene(src / f'{i}.jpg', seed=100 + i, dto=f'2026:10:24 09:0{i}:00')
    conn = col.open_db(col.create('Many'))
    col.add_source(conn, str(src), 'Me')
    analyze_collection(conn)
    o = overview(conn)
    n_events = conn.execute('SELECT COUNT(*) FROM events').fetchone()[0]
    assert len(o['highlights']) == min(7, 2 * n_events)


# ---- 5. face boxes ----

def _face(box, **kw):
    return {'box': box, 'quality': 0.8, 'yaw': 0.0, 'left_eye': 0.3, 'right_eye': 0.3, **kw}


def test_face_boxes_flip_to_top_left_and_flags():
    # Vision: origin bottom left. A face in the TOP-left corner has a large Vision y.
    # M10b: a closed-looking eye on a turned head is "unsure", not closed.
    boxes = face_boxes([_face([0.1, 0.6, 0.2, 0.3], left_eye=0.05, yaw=0.9)])
    assert boxes == [{'x': 0.1, 'y': 0.1, 'w': 0.2, 'h': 0.3, 'eyes_closed': False, 'looking_away': True,
                      'state': 'unsure', 'main': True}]
    assert face_boxes([_face([0.1, 0.6, 0.2, 0.3], left_eye=0.05)])[0]['eyes_closed'] is True
    ok = face_boxes([_face([0.5, 0.2, 0.1, 0.1])])[0]
    assert ok['eyes_closed'] is False and ok['looking_away'] is False and ok['y'] == 0.7


def test_face_boxes_filter_and_limit_match_the_summary():
    tiny = _face([0.1, 0.1, 0.01, 0.01])                           # area 0.0001 < 0.0004
    many = [_face([0.05 * i, 0.1, 0.1, 0.1]) for i in range(8)]
    s = face_summary([tiny] + many)
    assert s['faces'] == 8 and len(s['boxes']) == 6                # boxes capped, counts are not
    assert face_boxes([tiny]) == [] and face_summary([tiny]) is None
    assert s['eyes_closed'] == 0


def test_timeline_items_carry_boxes(client, H, album):
    conn, slug = album
    c = _id(conn, 'C.jpg')
    sha = conn.execute('SELECT sha256 FROM assets WHERE id = ?', (c,)).fetchone()[0]
    faces = [_face([0.2, 0.5, 0.2, 0.3], right_eye=0.02)]
    with conn:
        conn.execute('INSERT OR REPLACE INTO faces (sha256, n_faces, faces_json, computed_at) VALUES (?, 1, ?, ?)',
                     (sha, json.dumps(faces), 'now'))
    f = _timeline_item(client, H, slug, c)['faces']
    assert f['faces'] == 1 and f['eyes_closed'] == 1
    assert f['boxes'] == [{'x': 0.2, 'y': 0.2, 'w': 0.2, 'h': 0.3, 'eyes_closed': True, 'looking_away': False,
                           'state': 'closed', 'main': True}]
    assert _timeline_item(client, H, slug, _id(conn, 'P.jpg'))['faces'] is None


def test_keep_too_exports_an_extra_frame_without_making_it_a_favourite(album):
    """M10 review: "Yes" on another frame of a moment keeps it (mark `keep`), but no 5 stars in the export."""
    conn, _ = album
    nk = _non_keeper(conn)
    assert nk not in {e['asset_id'] for e in plan_export(conn, **google_photos_options())['entries']}
    set_mark(conn, nk, keep=True)
    plan = plan_export(conn, **google_photos_options())
    entry = next(e for e in plan['entries'] if e['asset_id'] == nk)
    assert 'favorite' not in entry['meta']
    o = overview(conn)
    assert o['funnel']['extra_frames'] == 0 and o['funnel']['in_album'] == plan['photo_counts']['in_album']


def test_helper_measures_again_only_when_newer(album, monkeypatch):
    import app.quality.faces as F
    conn, _ = album
    calls = []

    def fake_run(mode, paths, extra=None, timeout=600):
        calls.append(len(paths))
        return [{'path': p, 'faces': [], 'aesthetic': 0.1, 'utility': False} for p in paths]

    monkeypatch.setattr(F, '_run', fake_run)
    monkeypatch.setattr(F, 'helper_available', lambda: True)
    monkeypatch.setattr(F, '_HELPER_VERSION', 1)
    F._compute_helper(conn)
    assert sum(calls) == 6                                             # first measurement by helper 1
    calls.clear()
    F._compute_helper(conn)
    assert calls == []                                                 # an old helper never re-measures
    monkeypatch.setattr(F, '_HELPER_VERSION', 2)
    F._compute_helper(conn)
    assert sum(calls) == 6                                             # the six photos, once
    calls.clear()
    F._compute_helper(conn)
    assert calls == []                                                 # and not again

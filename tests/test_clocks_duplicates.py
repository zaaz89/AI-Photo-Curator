"""M2: device clock offsets and duplicate groups."""
import pytest

from app import collections as col
from app.analysis import analyze_collection
from app.timeline.clock_sync import list_clocks, set_correction
from app.timeline.timeline_engine import duplicate_groups, timeline
from conftest import make_photo, make_view, snapshot, textured_scene


def _t(minute, sec=0, hour=18):
    return f'2026:10:23 {hour:02d}:{minute:02d}:{sec:02d}'


def _two_devices(tmp_path, skews):
    """Device A (reference, iPhone) and device B (Pixel) photograph the same
    scenes. skews[i] = how many seconds B's clock reads later than A's for scene i."""
    a, b = tmp_path / 'andraz', tmp_path / 'tjasa'
    for i, skew in enumerate(skews):
        src = textured_scene(a / f'IMG_{i:04d}.JPG', seed=100 + i, dto=_t(2 * i))
        make_view(src, b / f'PXL_{i:04d}.jpg', dto=_t(2 * i, skew) if skew < 60 else _t(2 * i + skew // 60, skew % 60))
    # Extra reference photos so A has more photos than B.
    for j in range(3):
        textured_scene(a / f'IMG_9{j}.JPG', seed=900 + j, dto=_t(40 + j))
    slug = col.create('clock test')
    conn = col.open_db(slug)
    col.add_source(conn, str(a), 'Andraž')
    col.add_source(conn, str(b), 'Tjaša')
    return a, b, conn


def _clock(conn, model):
    return next(c for c in list_clocks(conn) if c['model'] == model)


def test_consistent_scene_matches_give_a_suggestion(tmp_path):
    a, b, conn = _two_devices(tmp_path, [50] * 5)
    before = snapshot(a), snapshot(b)
    analyze_collection(conn)
    assert (snapshot(a), snapshot(b)) == before
    ref = _clock(conn, 'iPhone 15')
    px = _clock(conn, 'Pixel 8')
    assert ref['status'] == 'reference'
    assert px['status'] == 'suggested' and px['method'] == 'scene'
    assert px['suggested_s'] == pytest.approx(-50, abs=1)
    assert px['confidence'] == 'high'
    assert px['applied_s'] == 0                       # never applied automatically


def test_accepting_reorders_timeline_and_undo_restores(tmp_path):
    a, b, conn = _two_devices(tmp_path, [50] * 5)
    analyze_collection(conn)
    raw_order = [i['rel_path'] for i in timeline(conn)['items']]
    assert raw_order.index('IMG_0000.JPG') < raw_order.index('PXL_0000.jpg')
    px = _clock(conn, 'Pixel 8')

    set_correction(conn, px['clock_id'], 'accept')
    items = timeline(conn)['items']
    pxl = next(i for i in items if i['rel_path'] == 'PXL_0000.jpg')
    assert pxl['clock_correction_s'] == pytest.approx(-50, abs=1)
    assert pxl['local_time'] == '2026-10-23T18:00:50'           # file value kept
    assert pxl['corrected_local_time'].startswith('2026-10-23T18:00:0')

    set_correction(conn, px['clock_id'], 'reset')
    assert [i['rel_path'] for i in timeline(conn)['items']] == raw_order


def test_conflicting_matches_give_no_suggestion(tmp_path):
    a, b, conn = _two_devices(tmp_path, [50, 50, 50, 5, 5, 5])
    analyze_collection(conn)
    px = _clock(conn, 'Pixel 8')
    assert px['status'] == 'conflicting' and px['suggested_s'] is None


def test_one_match_is_not_enough(tmp_path):
    a, b, conn = _two_devices(tmp_path, [50])
    analyze_collection(conn)
    px = _clock(conn, 'Pixel 8')
    assert px['status'] == 'none' and px['suggested_s'] is None
    with pytest.raises(ValueError):
        set_correction(conn, px['clock_id'], 'accept')


def test_gps_time_reveals_camera_clock_error(tmp_path):
    a, b = tmp_path / 'a', tmp_path / 'b'
    for i in range(4):
        textured_scene(a / f'A{i}.jpg', seed=i, dto=_t(i * 5))
    src = textured_scene(tmp_path / 'tmp.jpg', seed=50)
    for i in range(4):   # camera runs 30 s fast: shows 18:mm:30 when GPS says 16:mm:00 UTC
        make_view(src, b / f'B{i}.jpg', dto=_t(i * 5, 30), offset='+02:00',
                  gps_utc=f'2026:10:23 16:{i * 5:02d}:00')
    slug = col.create('gps test')
    conn = col.open_db(slug)
    col.add_source(conn, str(a), 'A')
    col.add_source(conn, str(b), 'B')
    analyze_collection(conn)
    c = _clock(conn, 'Pixel 8')
    assert c['method'] == 'gps' and c['suggested_s'] == pytest.approx(-30, abs=1)


def test_manual_correction_limits(tmp_path):
    a, b, conn = _two_devices(tmp_path, [50])
    analyze_collection(conn)
    cid = _clock(conn, 'Pixel 8')['clock_id']
    with pytest.raises(ValueError):
        set_correction(conn, cid, 'manual', 49 * 3600)
    assert set_correction(conn, cid, 'manual', -120)['status'] == 'manual'


def test_duplicate_groups_and_keeper_choice(tmp_path):
    src = tmp_path / 'cam'
    make_photo(src / 'IMG_1.JPG', seed=1, dto=_t(0, 0))
    (src / 'copy_of_IMG_1.JPG').write_bytes((src / 'IMG_1.JPG').read_bytes())     # exact
    textured_scene(src / 'IMG_2.JPG', seed=7, dto=_t(5, 0))
    make_view(src / 'IMG_2.JPG', src / 'IMG_3.JPG', crop=0.01, brightness=1.03,   # burst frame
              dto=_t(5, 1), model='iPhone 15', offset='+02:00')
    make_photo(src / 'IMG_4.JPG', seed=40, dto=_t(30, 0))                          # unrelated
    before = snapshot(src)
    slug = col.create('dups')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Cam')
    analyze_collection(conn)
    groups = duplicate_groups(conn)
    cats = sorted(g['category'] for g in groups if g['category'] != 'similar_scene')
    assert cats == ['exact', 'near']
    near = next(g for g in groups if g['category'] == 'near')
    assert {m['filename'] for m in near['members']} == {'IMG_2.JPG', 'IMG_3.JPG'}
    assert not any(m['filename'] == 'IMG_4.JPG' for g in groups for m in g['members'])

    # The owner overrides the keeper; the choice survives a full re-analysis.
    other = next(m['id'] for m in near['members'] if m['id'] != near['keeper_id'])
    from app.web.timeline_bp import bp  # noqa: F401  (route module imports cleanly)
    sha = conn.execute('SELECT sha256 FROM assets WHERE id = ?', (other,)).fetchone()[0]
    key = conn.execute('SELECT group_key FROM duplicate_groups WHERE id = ?', (near['id'],)).fetchone()[0]
    with conn:
        conn.execute("INSERT INTO keeper_choices VALUES (?, ?, 'now')", (key, sha))
    analyze_collection(conn)
    near2 = next(g for g in duplicate_groups(conn) if g['category'] == 'near')
    assert near2['keeper_id'] == other and near2['reasons']['keeper'] == ['chosen by you']
    assert snapshot(src) == before


def test_duplicate_and_clock_api(pc, client, H, tmp_path):
    a, b, conn = _two_devices(tmp_path, [50] * 5)
    cid = conn.execute('PRAGMA database_list').fetchone()[2].split('/')[-2]
    analyze_collection(conn)
    clocks = client.get(f'/api/collections/{cid}/clocks', headers=H).get_json()['clocks']
    px = next(c for c in clocks if c['model'] == 'Pixel 8')
    r = client.post(f'/api/collections/{cid}/clocks/{px["clock_id"]}', json={'action': 'accept'}, headers=H)
    assert r.get_json()['status'] == 'accepted'
    r = client.post(f'/api/collections/{cid}/clocks/{px["clock_id"]}', json={'action': 'bogus'}, headers=H)
    assert r.status_code == 400
    assert client.get(f'/api/collections/{cid}/duplicates', headers=H).status_code == 200
    r = client.post(f'/api/collections/{cid}/duplicates/999/keeper', json={'asset_id': 1}, headers=H)
    assert r.status_code == 404

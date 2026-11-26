"""M14a: remove a folder from an album, remove a whole album. Only the app's working data goes; the photo folders
stay byte-identical (same style as test_source_safety.py)."""
import shutil

from app import analysis_events as ev
from app import collections as col
from app.analysis import analyze_collection
from app.quality.scoring import set_mark
from app.web import timeline_bp
from conftest import make_photo, make_view, snapshot, textured_scene

DAYS = ('2026:10:24', '2026:10:25', '2026:10:26')


def _album(tmp_path, name):
    """Me: three days, a burst pair on day 1. Partner: day 1 only, a near view of my scene and one more photo,
    plus an exact copy of my day-2 photo (its analysis must stay with my copy)."""
    root = tmp_path / name
    me, partner = root / 'me', root / 'partner'
    a = textured_scene(me / 'D0_A.jpg', seed=11, dto=f'{DAYS[0]} 10:00:00')
    make_view(a, me / 'D0_A2.jpg', crop=0.01, brightness=1.03, dto=f'{DAYS[0]} 10:00:01', model='iPhone 15')
    textured_scene(me / 'D1_B.jpg', seed=12, dto=f'{DAYS[1]} 12:00:00')
    make_photo(me / 'D1_blur.jpg', seed=13, dto=f'{DAYS[1]} 19:00:00', blur=True)
    textured_scene(me / 'D2_C.jpg', seed=15, dto=f'{DAYS[2]} 09:00:00')            # a day only I have
    make_view(a, partner / 'PXL_1.jpg', crop=0.06, dto=f'{DAYS[0]} 10:00:30')
    textured_scene(partner / 'PXL_2.jpg', seed=14, dto=f'{DAYS[0]} 11:00:00', model='Pixel 8')
    partner.mkdir(parents=True, exist_ok=True)
    shutil.copy(me / 'D1_B.jpg', partner / 'copy_of_B.jpg')
    slug = col.create(name)
    conn = col.open_db(slug)
    col.add_source(conn, str(me), 'Me')
    col.add_source(conn, str(partner), 'Partner')
    analyze_collection(conn)
    return slug, conn, me, partner


def _sid(conn, owner):
    return conn.execute('SELECT id FROM sources WHERE owner = ?', (owner,)).fetchone()[0]


def test_remove_source_keeps_every_file_and_drops_its_rows(pc, client, H, tmp_path):
    slug, conn, me, partner = _album(tmp_path, 'Remove folder')
    pid = _sid(conn, 'Partner')
    pxl = conn.execute("SELECT id FROM assets WHERE filename = 'PXL_2.jpg'").fetchone()[0]
    set_mark(conn, pxl, focus='blurry')                                   # an owner mark on the partner's photo
    mine = conn.execute("SELECT id FROM assets WHERE filename = 'D1_B.jpg'").fetchone()[0]
    set_mark(conn, mine, wallpaper=True)                                  # and one on my photo (same content!)
    partner_ids = [r[0] for r in conn.execute('SELECT id FROM assets WHERE source_id = ?', (pid,))]
    assert partner_ids
    conn.close()
    before = snapshot(me), snapshot(partner)

    r = client.delete(f'/api/collections/{slug}/sources/{pid}', headers=H)
    assert r.status_code == 200, r.get_json()
    body = r.get_json()
    assert body['ok'] and body['removed_photos'] == len(partner_ids)
    assert body['photos_left'] == 5

    assert (snapshot(me), snapshot(partner)) == before, 'a photo folder changed'
    assert partner.is_dir() and me.is_dir()

    conn = col.open_db(slug)
    assert conn.execute('SELECT COUNT(*) FROM sources').fetchone()[0] == 1
    assert conn.execute('SELECT COUNT(*) FROM assets WHERE source_id = ?', (pid,)).fetchone()[0] == 0
    # No row anywhere still points at a removed photo.
    for table, column in (('analysis_events', 'asset_id'), ('analysis_events', 'keeper_id'),
                          ('duplicate_members', 'asset_id'), ('event_members', 'asset_id'),
                          ('capture_time', 'asset_id'), ('places', 'asset_id'), ('screenshot_checks', 'asset_id')):
        q = f'SELECT COUNT(*) FROM {table} WHERE {column} IN ({",".join("?" * len(partner_ids))})'
        assert conn.execute(q, partner_ids).fetchone()[0] == 0, table
    # Content-keyed analysis: the partner-only photo's rows are gone, the shared copy keeps mine.
    shas = {r[0] for r in conn.execute('SELECT sha256 FROM assets')}
    for table in ('visual_features', 'quality', 'marks'):
        orphan = conn.execute(f'SELECT COUNT(*) FROM {table} WHERE sha256 NOT IN '
                              f'(SELECT sha256 FROM assets)').fetchone()[0]
        assert orphan == 0, table
    b_sha = conn.execute("SELECT sha256 FROM assets WHERE filename = 'D1_B.jpg'").fetchone()[0]
    assert b_sha in shas
    assert conn.execute('SELECT wallpaper FROM marks WHERE sha256 = ?', (b_sha,)).fetchone()[0] == 1
    assert conn.execute('SELECT COUNT(*) FROM quality WHERE sha256 = ?', (b_sha,)).fetchone()[0] == 1
    # Moments and chapters never keep fewer than two / zero photos.
    assert conn.execute('SELECT COUNT(*) FROM duplicate_groups WHERE id NOT IN (SELECT group_id FROM '
                        'duplicate_members GROUP BY group_id HAVING COUNT(*) >= 2)').fetchone()[0] == 0
    assert conn.execute('SELECT COUNT(*) FROM events WHERE id NOT IN '
                        '(SELECT event_id FROM event_members)').fetchone()[0] == 0
    # Days 1 and 2 lost photos: rebuilt and settled again with their new signature; day 3 left as it was.
    assert set(body['rebuilt_days']) == {DAYS[0].replace(':', '-'), DAYS[1].replace(':', '-')}
    current = {d: ev.signature(a) for d, a in ev.day_plan(conn)}
    assert ev.settled_days(conn) == current
    # The album still works: a resume finds nothing to do and the folder can be added again.
    res = analyze_collection(conn)
    assert res['days']['already_settled'] == res['days']['total'] == 3
    assert snapshot(partner) == before[1]
    col.add_source(conn, str(partner), 'Partner')
    analyze_collection(conn)
    assert conn.execute("SELECT COUNT(*) FROM assets WHERE status = 'present'").fetchone()[0] == 8
    assert (snapshot(me), snapshot(partner)) == before
    conn.close()


def test_remove_source_refused_while_running_and_for_unknown_ids(client, H, tmp_path):
    slug, conn, me, partner = _album(tmp_path, 'Remove refused')
    pid = _sid(conn, 'Partner')
    conn.close()
    before = snapshot(partner)
    timeline_bp._job.update(running=True, collection=slug)
    try:
        assert client.delete(f'/api/collections/{slug}/sources/{pid}', headers=H).status_code == 409
    finally:
        timeline_bp._job.update(running=False, collection=None)
    assert client.delete(f'/api/collections/{slug}/sources/9999', headers=H).status_code == 404
    assert client.delete(f'/api/collections/does-not-exist/sources/{pid}', headers=H).status_code == 404
    conn = col.open_db(slug)
    assert conn.execute('SELECT COUNT(*) FROM sources').fetchone()[0] == 2
    conn.close()
    assert snapshot(partner) == before


def test_remove_album_removes_all_working_data_and_no_photo(pc, client, H, tmp_path):
    slug, conn, me, partner = _album(tmp_path, 'Remove album')
    assert conn.execute('SELECT COUNT(*) FROM analysis_events').fetchone()[0] > 0
    paths = [r[0] for r in conn.execute("SELECT s.path || '/' || a.rel_path FROM assets a "
                                        "JOIN sources s ON s.id = a.source_id")]
    conn.close()
    pc._coll_roots_cache['t'] = 0
    thumbs = []
    for p in paths[:3]:
        assert client.get('/api/thumb', query_string={'path': p}, headers=H).status_code == 200
        thumbs.append(pc._thumb_cache_path(p))
    assert all(t.exists() for t in thumbs)
    before = snapshot(me), snapshot(partner)

    r = client.delete(f'/api/collections/{slug}', headers=H).get_json()
    assert r['ok'] and r['removed_cache_files'] >= 3
    assert not (col.collections_dir() / slug).exists()                 # database, events, days, AI data
    assert not any(t.exists() for t in thumbs)                          # its thumbnails
    assert (snapshot(me), snapshot(partner)) == before                  # photos untouched
    ids = [c['id'] for c in client.get('/api/collections', headers=H).get_json()['collections']]
    assert slug not in ids


def test_overview_reports_sorted_days(tmp_path):
    from app.assistant import overview
    slug, conn, me, partner = _album(tmp_path, 'Days')
    assert overview(conn)['analysis'] == {'days': 3, 'settled': 3}
    extra = tmp_path / 'Days' / 'later'
    textured_scene(extra / 'X.jpg', seed=77, dto='2026:10:28 08:00:00')
    col.add_source(conn, str(extra), 'Later')
    from app.importers.local_importer import index_collection
    index_collection(conn)
    a = overview(conn)['analysis']
    assert a['days'] == 4 and a['settled'] == 3                         # the new day waits for the analysis
    analyze_collection(conn)
    assert overview(conn)['analysis'] == {'days': 4, 'settled': 4}
    conn.close()


def test_sources_list_their_devices(client, H, tmp_path):
    slug, conn, me, partner = _album(tmp_path, 'Devices')
    conn.close()
    src = client.get(f'/api/collections/{slug}/sources', headers=H).get_json()['sources']
    by_owner = {s['owner']: s for s in src}
    assert 'iPhone 15' in by_owner['Me']['devices']
    assert 'Pixel 8' in by_owner['Partner']['devices']
    assert all(len(s['devices']) <= 3 for s in src)

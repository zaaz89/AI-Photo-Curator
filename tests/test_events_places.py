"""M4: offline places from GPS, events, owner's event edits."""
import pytest

from app import collections as col
from app.analysis import analyze_collection
from app.places import geocoder
from app.places.geocoder import Index
from app.timeline import event_detector as ed
from app.timeline.timeline_engine import timeline
from conftest import make_photo, snapshot

# name, lat, lon, population, country, admin1
CITIES = [('Bigtown', 43.7700, 11.2500, 360000, 'IT', '16'),
          ('Hamlet', 43.7750, 11.2550, 600, 'IT', '16'),
          ('Hilltown', 43.0770, 11.6790, 2000, 'IT', '16')]
REGIONS = {'IT.16': 'Tuscany'}
COUNTRIES = {'IT': 'Italy'}


@pytest.fixture(autouse=True)
def fake_geo():
    idx = Index.from_rows(CITIES, REGIONS, COUNTRIES)
    idx.aliases = ['Firence,Firenze', '', '']
    geocoder.set_index(idx)
    yield
    geocoder.set_index(None)


def test_reverse_rules():
    idx = geocoder.get_index()
    r = idx.reverse(43.7748, 11.2548)              # closer to Hamlet, but inside Bigtown's 2.5 km
    assert (r['name'], r['precision'], r['label']) == ('Bigtown', 'in', 'Bigtown')
    r = idx.reverse(43.1100, 11.6790)              # 3.7 km from Hilltown
    assert (r['precision'], r['label']) == ('near', 'near Hilltown')
    r = idx.reverse(42.6000, 11.0000)              # far from everything
    assert (r['precision'], r['name'], r['label']) == ('region', None, 'Tuscany, Italy')


def _trip(tmp_path):
    a = tmp_path / 'phone'
    # Day 1: morning in Bigtown (two photos 20 min apart), afternoon after a drive to Hilltown.
    make_photo(a / 'IMG_1.JPG', seed=1, dto='2026:10:24 09:00:00', gps_utc=None)
    make_photo(a / 'IMG_2.JPG', seed=2, dto='2026:10:24 09:20:00')
    make_photo(a / 'IMG_3.JPG', seed=3, dto='2026:10:24 15:00:00')
    # Day 2: one evening photo.
    make_photo(a / 'IMG_4.JPG', seed=4, dto='2026:10:25 19:00:00')
    slug = col.create('trip')
    conn = col.open_db(slug)
    col.add_source(conn, str(a), 'Me')
    analyze_collection(conn)
    gps = {'IMG_1.JPG': (43.7701, 11.2501), 'IMG_2.JPG': (43.7705, 11.2510),
           'IMG_3.JPG': (43.0780, 11.6800), 'IMG_4.JPG': (43.7690, 11.2490)}
    with conn:
        for name, (la, lo) in gps.items():
            conn.execute('UPDATE assets SET gps_lat = ?, gps_lon = ? WHERE filename = ?', (la, lo, name))
    from app.places.places import assign_places
    assign_places(conn)
    ed.detect_events(conn)
    return a, conn


def _events(conn):
    return [(e['day'], e['name'], e['count']) for e in timeline(conn)['events']]


def test_events_split_by_time_and_place_and_are_named_from_facts(tmp_path):
    a, conn = _trip(tmp_path)
    assert _events(conn) == [('2026-10-24', 'Bigtown, morning', 2),
                             ('2026-10-24', 'Hilltown, afternoon', 1),
                             ('2026-10-25', 'Bigtown, evening', 1)]


def test_owner_edits_survive_reanalysis_and_can_be_undone(tmp_path):
    a, conn = _trip(tmp_path)
    before = snapshot(a)
    ev = {e['name']: e['id'] for e in timeline(conn)['events']}
    ed.rename_event(conn, ev['Bigtown, morning'], 'Breakfast walk')
    ed.merge_with_previous(conn, ev['Hilltown, afternoon'])
    analyze_collection(conn)                       # re-analysis keeps the edited day
    assert _events(conn)[0] == ('2026-10-24', 'Breakfast walk', 3)
    first = next(i for i in timeline(conn)['items'] if i['filename'] == 'IMG_2.JPG')
    ed.split_at(conn, first['id'])
    # The new event holds 09:20 (Bigtown) and 15:00 (Hilltown): middle photo is 15:00 -> afternoon.
    assert [n for d, n, c in _events(conn) if d == '2026-10-24'] == ['Breakfast walk', 'Bigtown, afternoon']
    ed.reset_day(conn, '2026-10-24')
    assert _events(conn)[:2] == [('2026-10-24', 'Bigtown, morning', 2), ('2026-10-24', 'Hilltown, afternoon', 1)]
    assert snapshot(a) == before
    with pytest.raises(ValueError):
        ed.merge_with_previous(conn, timeline(conn)['events'][0]['id'])   # first of the day


def test_photo_without_gps_has_no_place(tmp_path):
    a, conn = _trip(tmp_path)
    with conn:
        conn.execute("UPDATE assets SET gps_lat = NULL, gps_lon = NULL WHERE filename = 'IMG_4.JPG'")
    from app.places.places import assign_places
    assign_places(conn)
    ed.detect_events(conn)
    item = next(i for i in timeline(conn)['items'] if i['filename'] == 'IMG_4.JPG')
    assert item['place'] is None
    assert _events(conn)[-1] == ('2026-10-25', 'Evening', 1)


def test_place_aliases_help_search(tmp_path, monkeypatch):
    from app.ai import embeddings, search as search_mod, vision_analyzer as vlm
    import numpy as np

    class Flat:
        name = 'flat'
        def images(self, ims): return np.ones((len(ims), 2), np.float32) / np.sqrt(2)
        def texts(self, ts): return np.ones((len(ts), 2), np.float32) / np.sqrt(2)

    embeddings.set_embedder(Flat())
    monkeypatch.setattr(vlm, 'status', lambda: {'running': False, 'model_ready': False, 'model': 'x'})
    try:
        a, conn = _trip(tmp_path)
        analyze_collection(conn)
        res = search_mod.search(conn, 'Firence')
        top = res['results'][0]
        assert top['place_match'] and top['filename'] in ('IMG_1.JPG', 'IMG_2.JPG', 'IMG_4.JPG')
    finally:
        embeddings.set_embedder(None)


def test_event_api(pc, client, H, tmp_path):
    a, conn = _trip(tmp_path)
    cid = conn.execute('PRAGMA database_list').fetchone()[2].split('/')[-2]
    eid = timeline(conn)['events'][1]['id']
    assert client.post(f'/api/collections/{cid}/events/{eid}', json={'action': 'rename', 'name': 'Hill'},
                       headers=H).get_json()['ok']
    assert client.post(f'/api/collections/{cid}/events/{eid}', json={'action': 'rename', 'name': ' '},
                       headers=H).status_code == 400
    assert client.post(f'/api/collections/{cid}/events/reset', json={'day': '2026-10-24'}, headers=H).get_json()['ok']


def test_clock_within_two_seconds_of_gps_needs_no_correction(tmp_path):
    from app.timeline.clock_sync import list_clocks
    from conftest import make_view, textured_scene
    a, b = tmp_path / 'a', tmp_path / 'b'
    for i in range(4):
        textured_scene(a / f'A{i}.jpg', seed=i, dto=f'2026:10:23 18:{i * 5:02d}:00')
    src = textured_scene(tmp_path / 'tmp.jpg', seed=50)
    for i in range(4):   # GPS one second behind the clock: normal fix delay, not a wrong clock
        make_view(src, b / f'B{i}.jpg', dto=f'2026:10:23 18:{i * 5:02d}:01', gps_utc=f'2026:10:23 16:{i * 5:02d}:00')
    slug = col.create('gps agree')
    conn = col.open_db(slug)
    col.add_source(conn, str(a), 'A')
    col.add_source(conn, str(b), 'B')
    analyze_collection(conn)
    c = next(x for x in list_clocks(conn) if x['model'] == 'Pixel 8')
    assert c['status'] == 'agrees' and c['suggested_s'] is None

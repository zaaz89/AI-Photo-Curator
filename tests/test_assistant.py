"""M8 phase 2: suggestions for the New Album wizard, device memory, keeper confidence, overview."""
import os

import pytest
from PIL import Image

from app import collections as col, settings
from app.analysis import analyze_collection
from app.places import geocoder
from app.places.geocoder import Index
from conftest import make_photo, snapshot, textured_scene


@pytest.fixture(autouse=True)
def fake_geo():
    geocoder.set_index(Index.from_rows([('Pienza', 43.0767, 11.6789, 2000, 'IT', '16'),
                                        ('Florence', 43.7696, 11.2558, 360000, 'IT', '16')],
                                       {'IT.16': 'Tuscany'}, {'IT': 'Italy'}))
    yield
    geocoder.set_index(None)


def _with_artist(path, artist):
    im = Image.open(path)
    ex = im.getexif()
    ex[315] = artist                                    # EXIF Artist
    im.save(path, exif=ex, quality=92)


def test_suggest_owners_devices_dates_and_place(client, H, tmp_path):
    me, partner, cam = tmp_path / 'Andrej iPhone', tmp_path / 'DCIM', tmp_path / 'Export'
    make_photo(me / 'a.jpg', seed=1, dto='2026:10:23 18:00:00', model='iPhone 15', gps_utc='2026:10:23 16:00:00')
    make_photo(me / 'b.jpg', seed=2, dto='2026:10:25 09:00:00', model='iPhone 15')
    make_photo(partner / 'c.jpg', seed=3, dto='2026:10:24 12:00:00', model='iPhone 16 Pro')
    _with_artist(partner / 'c.jpg', 'Maja K.')
    make_photo(cam / 'd.jpg', seed=4, dto='2026:10:28 20:00:00', model='Pixel 8')
    settings.save({'device_owners': {'Apple Pixel 8': 'Ana'}})
    before = snapshot(tmp_path)
    try:
        r = client.post('/api/suggest', json={'paths': [str(me), str(partner), str(cam)]}, headers=H).get_json()
    finally:
        settings.save({'device_owners': {}})
    f = {os.path.basename(x['path']): x for x in r['folders']}
    assert f['Andrej iPhone']['owner'] == 'Andrej iPhone' and f['Andrej iPhone']['owner_from'] == 'folder'
    assert f['Andrej iPhone']['count'] == 2 and f['Andrej iPhone']['devices'][0]['name'] == 'Apple iPhone 15'
    assert f['DCIM']['owner'] == 'Maja K.' and f['DCIM']['owner_from'] == 'exif'
    assert f['Export']['owner'] == 'Ana' and f['Export']['owner_from'] == 'remembered'
    assert r['album']['start'] == '2026-10-23' and r['album']['end'] == '2026-10-28'
    assert r['album']['place'] == 'Pienza' and r['album']['country'] == 'Italy'
    assert snapshot(tmp_path) == before                 # nothing written into the folders


def test_suggest_rejects_bad_input(client, H, tmp_path):
    f = tmp_path / 'one.jpg'
    make_photo(f, seed=1)
    empty = tmp_path / 'empty'
    empty.mkdir()
    r = client.post('/api/suggest', json={'paths': [str(f), str(empty), str(tmp_path / 'nope')]}, headers=H).get_json()
    problems = {os.path.basename(x['path']): x['problem'] for x in r['rejected']}
    assert problems == {'one.jpg': 'not a folder', 'empty': 'no photos or videos', 'nope': 'not found'}
    assert r['folders'] == []
    nested = client.post('/api/suggest', json={'paths': [str(tmp_path), str(tmp_path)]}, headers=H).get_json()
    assert len(nested['folders']) == 1                  # the same folder twice counts once


def test_device_owners_setting_is_validated():
    with pytest.raises(ValueError):
        settings.save({'device_owners': ['x']})
    s = settings.save({'device_owners': {'Apple iPhone 15': '  Me  '}})
    assert s['device_owners'] == {'Apple iPhone 15': 'Me'}
    settings.save({'device_owners': {}})


@pytest.fixture
def album(tmp_path):
    src = tmp_path / 'me'
    textured_scene(src / 'A.jpg', seed=41, dto='2026:10:24 09:00:00')
    textured_scene(src / 'B.jpg', seed=42, dto='2026:10:24 12:00:00')
    make_photo(src / 'Z.jpg', seed=5, dto='2026:10:24 19:00:00', blur=True)
    slug = col.create('Overview test')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Me')
    analyze_collection(conn)
    return conn, slug


def test_overview_reports_what_needs_a_decision(client, H, album):
    conn, slug = album
    r = client.get(f'/api/collections/{slug}/overview', headers=H).get_json()
    assert r['facts']['photos'] == 3 and r['facts']['people'] == 1 and r['facts']['days'] == 1
    assert r['blurry']['total'] == 1 and r['blurry']['left_out'] == 0
    assert set(r['moments']) >= {'total', 'decided', 'chosen', 'need_you'}
    assert r['descriptions'] == {'done': 0, 'photos': 3, 'minutes_left': 1}
    assert r['export'] == {'done': False, 'photos': 3}
    assert set(r['clocks']) >= {'pending', 'applied', 'devices'}
    assert r['analysing'] is False


def test_keeper_margin_marks_clear_decisions():
    from app.duplicates.groups import _recommend
    rows = {0: {'id': 1, 'sha256': 'a', 'width': 4000, 'height': 3000, 'source_id': 1, 'rel_path': 'a'},
            1: {'id': 2, 'sha256': 'b', 'width': 4000, 'height': 3000, 'source_id': 1, 'rel_path': 'b'}}
    feats = {'a': (None, 100.0), 'b': (None, 30.0)}
    info = {}
    _recommend(rows, feats, [0, 1], 'near', None, {}, {'a': (100.0, 70), 'b': (30.0, 40)}, None, info)
    assert info['margin'] >= 0.12
    close = {}
    _recommend(rows, {'a': (None, 100.0), 'b': (None, 99.0)}, [0, 1], 'near', None, {},
               {'a': (100.0, 70), 'b': (99.0, 70)}, None, close)
    assert close['margin'] < 0.12

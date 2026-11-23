"""M12: screenshots leave the album by themselves (owner 2026-11-19). Reversible with keep; the archive keeps them."""
import json

import numpy as np
import pytest
from PIL import Image

from app import collections as col
from app.analysis import analyze_collection
from app.assistant import overview
from app.organization.export_plan import google_photos_options, plan_export
from app.quality.scoring import set_mark
from app.quality.screenshots import detect, is_screenshot, screenshot_ids
from conftest import snapshot, textured_scene


def screenshot_png(path, comment='Screenshot'):
    """A phone screen capture: PNG, no Make, UserComment written by the phone."""
    path.parent.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(7)
    img = Image.fromarray(rng.integers(0, 255, (640, 300, 3), dtype=np.uint8))
    exif = Image.Exif()
    exif[0x0131] = '26.1'                                   # Software (iOS version), no Make
    if comment is not None:
        exif.get_ifd(0x8769)[0x9286] = b'ASCII\x00\x00\x00' + comment.encode()
    img.save(path, exif=exif)


# ---- the rule ----

@pytest.mark.parametrize('comment,name,make,want', [
    ('Screenshot', 'IMG_0412.PNG', None, 'mark'),
    ('Screenshot\x00', 'IMG_0412.PNG', None, 'mark'),
    ('screenshot', 'x.png', 'Apple', 'mark'),                  # the phone's own mark wins
    (None, 'Screenshot 2026-10-24 at 10.12.03.png', None, 'filename'),
    (None, 'Posnetek zaslona 2026-10-24 ob 10.12.03.png', None, 'filename'),
    (None, 'Bildschirmfoto 2026-10-24.png', '', 'filename'),
    (None, 'Screenshot_ok.jpg', 'SONY', None),                 # a camera wrote it, whatever its name
    (None, 'IMG_0274.HEIC', None, None),                       # received picture, no mark
    ('Lovely sunset', 'IMG_1.jpg', None, None),
])
def test_rule(comment, name, make, want):
    assert is_screenshot(comment, name, make) == want


# ---- in an album ----

@pytest.fixture
def album(tmp_path):
    me = tmp_path / 'me'
    textured_scene(me / 'A.jpg', seed=71, dto='2026:10:24 09:00:00')
    textured_scene(me / 'B.jpg', seed=72, dto='2026:10:24 12:00:00')
    screenshot_png(me / 'IMG_0412.PNG')
    screenshot_png(me / 'IMG_0413.PNG', comment=None)          # a received picture: no mark, no Make
    slug = col.create('Shots')
    conn = col.open_db(slug)
    col.add_source(conn, str(me), 'Me')
    before = snapshot(me)
    analyze_collection(conn)
    assert snapshot(me) == before                               # nothing written into the source
    return conn


def _id(conn, name):
    return conn.execute('SELECT id FROM assets WHERE filename = ?', (name,)).fetchone()[0]


def test_detected_after_indexing(album):
    conn = album
    assert screenshot_ids(conn) == {_id(conn, 'IMG_0412.PNG')}
    assert conn.execute('SELECT reason FROM screenshot_checks WHERE asset_id = ?',
                        (_id(conn, 'IMG_0412.PNG'),)).fetchone()[0] == 'mark'


def test_album_exports_leave_it_out_archive_keeps_it(album):
    conn = album
    s = _id(conn, 'IMG_0412.PNG')
    plan = plan_export(conn, **google_photos_options())
    assert s not in {e['asset_id'] for e in plan['entries']}
    for c in (plan['counts'], plan['photo_counts']):
        assert c['screenshots'] == 1
        assert c['taken'] == sum(v for k, v in c.items() if k != 'taken')
    best = plan_export(conn, selection='best', topn=50)
    assert s not in {e['asset_id'] for e in best['entries']} and best['counts']['screenshots'] == 1
    archive = plan_export(conn, selection='all')
    assert s in {e['asset_id'] for e in archive['entries']} and archive['counts']['screenshots'] == 0


@pytest.mark.parametrize('mark', ['keep', 'favorite'])
def test_owner_keeps_it(album, mark):
    conn = album
    s = _id(conn, 'IMG_0412.PNG')
    set_mark(conn, s, **{mark: True})
    plan = plan_export(conn, **google_photos_options())
    assert s in {e['asset_id'] for e in plan['entries']} and plan['counts']['screenshots'] == 0


def test_funnel_and_timeline(client, H, album):
    conn = album
    f = overview(conn)['funnel']
    assert f['screenshots'] == 1
    assert f['taken'] == f['left_out'] + f['screenshots'] + f['blurry'] + f['extra_frames'] + f['in_album']
    slug = conn.execute('SELECT name FROM collection').fetchone()[0]
    s = _id(conn, 'IMG_0412.PNG')
    for c in client.get('/api/collections', headers=H).get_json()['collections']:
        if c['name'] == slug:
            items = client.get(f"/api/collections/{c['id']}/timeline", headers=H).get_json()['items']
            got = {i['id']: i['screenshot'] for i in items}
            assert got[s] is True and got[_id(conn, 'A.jpg')] is False


def test_older_album_is_read_again_once(album):
    """Albums indexed before UserComment was read: make-less images are read again, camera photos are not."""
    conn = album
    s = _id(conn, 'IMG_0412.PNG')
    with conn:
        conn.execute('DELETE FROM screenshot_checks')
        for r in conn.execute('SELECT asset_id, tags_json FROM metadata_raw').fetchall():
            tags = {k: v for k, v in json.loads(r[1]).items() if not k.endswith(':UserComment')}
            conn.execute('UPDATE metadata_raw SET tags_json = ? WHERE asset_id = ?', (json.dumps(tags), r[0]))
    asked = []

    def read(paths):
        asked.extend(paths)
        return {p: ({'EXIF:UserComment': 'Screenshot'} if p.endswith('IMG_0412.PNG') else {}) for p in paths}

    res = detect(conn, read=read)
    assert sorted(p.rsplit('/', 1)[-1] for p in asked) == ['IMG_0412.PNG', 'IMG_0413.PNG']
    assert res['screenshots'] == 1 and screenshot_ids(conn) == {s}
    asked.clear()
    assert detect(conn, read=read)['checked'] == 0 and asked == []      # settled: nothing read twice

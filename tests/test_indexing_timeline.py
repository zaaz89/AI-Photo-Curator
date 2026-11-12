"""M1: multi-source indexing and unified timeline (brief section 22 milestone)."""
import json
import os
import time

import pytest

from app import collections as col
from app.importers.local_importer import index_collection, link_relationships
from app.timeline.timeline_engine import timeline
from conftest import make_photo, snapshot


@pytest.fixture
def two_phones(tmp_path):
    a, b = tmp_path / 'phone_andraz', tmp_path / 'phone_tjasa'
    # Same file names on both phones; times interleave.
    make_photo(a / 'IMG_0001.JPG', seed=1, dto='2026:10:23 18:00:00', offset='+02:00')
    make_photo(a / 'IMG_0002.JPG', seed=2, dto='2026:10:23 18:20:00', offset='+02:00')
    make_photo(a / 'sub' / 'IMG_0003.JPG', seed=3, dto='2026:10:23 18:40:00', offset='+02:00')
    # Phone B writes no offset but has GPS UTC time.
    make_photo(b / 'IMG_0001.JPG', seed=4, dto='2026:10:23 18:10:00', offset=None,
               gps_utc='2026:10:23 16:10:00')
    make_photo(b / 'IMG_0002.JPG', seed=5, dto='2026:10:23 18:30:00', offset=None,
               gps_utc='2026:10:23 16:30:00')
    # No offset, no GPS: offset is assumed from phone B's other files.
    make_photo(b / 'IMG_0003.JPG', seed=6, dto='2026:10:23 18:50:00', offset=None)
    # No capture metadata at all.
    make_photo(b / 'IMG_0004.JPG', seed=7, dto=None, offset=None, datetime_ifd0=None)
    # Exact copy of phone A's first photo (shared through chat).
    (b / 'shared.jpg').write_bytes((a / 'IMG_0001.JPG').read_bytes())
    # Hidden and AppleDouble files are ignored.
    (b / '.hidden.jpg').write_bytes(b'x')
    (b / '._IMG_0001.JPG').write_bytes(b'x')
    return a, b


def _collection(a, b):
    slug = col.create('Tuscany test')
    conn = col.open_db(slug)
    col.add_source(conn, str(a), 'Andraž')
    col.add_source(conn, str(b), 'Tjaša')
    return slug, conn


def test_two_sources_merge_into_one_correct_timeline(two_phones):
    a, b = two_phones
    before = snapshot(a), snapshot(b)
    slug, conn = _collection(a, b)
    res = index_collection(conn)
    assert (snapshot(a), snapshot(b)) == before, 'indexing changed a source folder'

    items = timeline(conn)['items']
    dated = [i for i in items if i['confidence'] != 'unknown']
    order = [(i['owner'], i['rel_path']) for i in dated]
    # shared.jpg has identical capture time to Andraž's IMG_0001; ties go by source order.
    assert order == [
        ('Andraž', 'IMG_0001.JPG'), ('Tjaša', 'shared.jpg'), ('Tjaša', 'IMG_0001.JPG'),
        ('Andraž', 'IMG_0002.JPG'), ('Tjaša', 'IMG_0002.JPG'), ('Andraž', 'sub/IMG_0003.JPG'),
        ('Tjaša', 'IMG_0003.JPG')]

    by = {(i['owner'], i['rel_path']): i for i in items}
    assert by[('Andraž', 'IMG_0001.JPG')]['rule'] == 'exif_dto_offset'
    assert by[('Tjaša', 'IMG_0001.JPG')]['rule'] == 'exif_dto_gps'
    assert by[('Tjaša', 'IMG_0001.JPG')]['utc_time'] == '2026-10-23T16:10:00Z'
    assumed = by[('Tjaša', 'IMG_0003.JPG')]
    assert assumed['confidence'] == 'medium' and assumed['rule'] == 'exif_dto_assumed'
    nodate = by[('Tjaša', 'IMG_0004.JPG')]
    assert nodate['confidence'] == 'unknown' and nodate['rule'] == 'file_mtime'
    assert by[('Tjaša', 'shared.jpg')]['exact_copies'] == 1
    assert not any(i['filename'].startswith('.') for i in items)
    assert res['sources'] and all(s['errors'] == 0 for s in res['sources'].values())


def test_reindex_is_incremental_and_tracks_changes(two_phones):
    a, b = two_phones
    slug, conn = _collection(a, b)
    index_collection(conn)
    again = index_collection(conn)
    assert all(s['new'] == 0 and s['changed'] == 0 for s in again['sources'].values())

    make_photo(a / 'IMG_0002.JPG', seed=99, dto='2026:10:23 18:21:00')   # edited by the user
    os.utime(a / 'IMG_0002.JPG', (time.time() + 5, time.time() + 5))
    (b / 'IMG_0004.JPG').unlink()                                          # deleted by the user
    third = index_collection(conn)
    stats = list(third['sources'].values())
    assert stats[0]['changed'] == 1 and stats[1]['missing'] == 1
    assert conn.execute("SELECT COUNT(*) FROM assets WHERE status = 'missing'").fetchone()[0] == 1
    assert conn.execute("SELECT COUNT(*) FROM assets").fetchone()[0] == 8  # 3 + 5 files, none dropped from the index


def test_raw_jpeg_and_live_photo_pairs(tmp_path):
    src = tmp_path / 'cam'
    make_photo(src / 'DSC_0001.JPG', seed=1)
    (src / 'DSC_0001.ARW').write_bytes(b'not really raw')
    make_photo(src / 'IMG_0100.HEIC.jpg', seed=2)   # placeholder still
    slug = col.create('pairs')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Cam')
    index_collection(conn)
    kinds = {r['kind'] for r in conn.execute('SELECT kind FROM relationships')}
    assert 'raw_jpeg' in kinds

    # Live Photo pairing by ContentIdentifier (metadata as ExifTool reports it).
    ids = [r['id'] for r in conn.execute('SELECT id FROM assets ORDER BY id')]
    with conn:
        conn.execute("UPDATE assets SET kind = 'video', ext = '.mov' WHERE id = ?", (ids[0],))
        conn.execute('UPDATE metadata_raw SET tags_json = ? WHERE asset_id = ?',
                     (json.dumps({'QuickTime:ContentIdentifier': 'ABC-1'}), ids[0]))
        conn.execute('UPDATE metadata_raw SET tags_json = ? WHERE asset_id = ?',
                     (json.dumps({'MakerNotes:ContentIdentifier': 'ABC-1'}), ids[2]))
    link_relationships(conn)
    live = conn.execute("SELECT asset_a, asset_b FROM relationships WHERE kind = 'live_photo'").fetchall()
    assert [(r['asset_a'], r['asset_b']) for r in live] == [(ids[2], ids[0])]


def test_overlapping_or_data_folder_sources_are_refused(tmp_path):
    slug = col.create('overlap')
    conn = col.open_db(slug)
    (tmp_path / 'photos' / 'trip').mkdir(parents=True)
    col.add_source(conn, str(tmp_path / 'photos'), 'A')
    with pytest.raises(ValueError):
        col.add_source(conn, str(tmp_path / 'photos' / 'trip'), 'B')
    with pytest.raises(ValueError):
        col.add_source(conn, str(col.data_dir()), 'C')


def test_timeline_api_and_thumbnails(pc, client, H, two_phones):
    a, b = two_phones
    before = snapshot(a), snapshot(b)
    d = client.post('/api/collections', json={'name': 'API trip'}, headers=H).get_json()
    cid = d['id']
    for path, owner in ((a, 'Andraž'), (b, 'Tjaša')):
        assert client.post(f'/api/collections/{cid}/sources', json={'path': str(path), 'owner': owner},
                           headers=H).get_json()['ok']
    assert client.post(f'/api/collections/{cid}/index', headers=H).get_json()['ok']
    for _ in range(200):
        st = client.get(f'/api/collections/{cid}/index', headers=H).get_json()
        if not st['running']:
            break
        time.sleep(0.05)
    assert st['error'] is None
    tl = client.get(f'/api/collections/{cid}/timeline', headers=H).get_json()
    assert tl['summary']['assets'] == 8
    pc._coll_roots_cache['t'] = 0           # pick up the new sources now
    first = tl['items'][0]['path']
    assert client.get('/api/thumb', query_string={'path': first}, headers=H).status_code == 200
    assert client.get('/timeline', headers=H).status_code == 200
    assert (snapshot(a), snapshot(b)) == before

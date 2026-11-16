"""M8: "Finish album" removes only the app's working data for one album; originals stay."""
from app import collections as col
from app.analysis import analyze_collection
from app.web import timeline_bp
from conftest import make_photo, snapshot, textured_scene


def _album(tmp_path, name):
    src = tmp_path / name / 'me'
    textured_scene(src / 'A.jpg', seed=31, dto='2026:10:24 09:00:00')
    make_photo(src / 'B.jpg', seed=32, dto='2026:10:24 10:00:00')
    slug = col.create(name)
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Me')
    analyze_collection(conn)
    conn.close()
    return src, slug


def test_finish_album_removes_working_data_only(pc, client, H, tmp_path):
    src, slug = _album(tmp_path, 'Wedding')
    _, other = _album(tmp_path, 'Birthday')
    pc._coll_roots_cache['t'] = 0                     # allowed folders are cached for 5 s
    thumb = client.get('/api/thumb', query_string={'path': str(src / 'A.jpg')}, headers=H)
    assert thumb.status_code == 200
    cached = pc._thumb_cache_path(str(src / 'A.jpg'))
    assert cached.exists()
    before = snapshot(src)

    r = client.delete(f'/api/collections/{slug}', headers=H).get_json()
    assert r['ok'] and r['removed_cache_files'] >= 1 and r['freed_bytes'] > 0
    assert not (col.collections_dir() / slug).exists()
    assert not cached.exists()
    assert snapshot(src) == before                                  # originals untouched
    ids = [c['id'] for c in client.get('/api/collections', headers=H).get_json()['collections']]
    assert slug not in ids and other in ids                         # the other album stays


def test_finish_album_refused_while_its_job_runs(client, H, tmp_path):
    _, slug = _album(tmp_path, 'Running')
    timeline_bp._job.update(running=True, collection=slug)
    try:
        assert client.delete(f'/api/collections/{slug}', headers=H).status_code == 409
    finally:
        timeline_bp._job.update(running=False, collection=None)
    assert (col.collections_dir() / slug).exists()


def test_finish_album_rejects_bad_ids(client, H):
    assert client.delete('/api/collections/..', headers=H).status_code in (404, 405)
    assert client.delete('/api/collections/does-not-exist', headers=H).status_code == 404

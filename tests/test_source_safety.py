"""Source folders stay byte-identical through the whole app, and the old
move/organize endpoints of the upstream page do not exist any more."""
import json
from pathlib import Path

from app import collections as col
from app.analysis import analyze_collection
from app.organization.export_plan import plan_export, run_export
from app.quality.scoring import set_mark
from conftest import make_photo, snapshot, textured_scene, make_view


def _folder(tmp_path):
    src = tmp_path / 'phone_a'
    textured_scene(src / 'IMG_0001.JPG', seed=1, dto='2026:10:23 18:14:32')
    make_view(src / 'IMG_0001.JPG', src / 'IMG_0002.JPG', crop=0.01, brightness=1.03,
              dto='2026:10:23 18:14:33', model='iPhone 15')                       # burst duplicate
    make_photo(src / 'IMG_0003.JPG', seed=2, dto='2026:10:23 18:30:00', blur=True)
    textured_scene(src / 'IMG_0004.JPG', seed=3, dto='2026:10:23 19:00:00')
    (src / 'IMG_0004.MOV').write_bytes(b'live photo video')
    return src


def test_whole_workflow_leaves_sources_untouched(pc, client, H, tmp_path):
    src = _folder(tmp_path)
    before = snapshot(src)
    slug = col.create('safety')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'A')
    analyze_collection(conn)                                  # index, clocks, places, events, duplicates, quality
    a = conn.execute("SELECT id FROM assets WHERE filename = 'IMG_0004.JPG'").fetchone()[0]
    set_mark(conn, a, focus='blurry', wallpaper=True)         # marks only
    dest = tmp_path / 'out'
    dest.mkdir()
    for sel in ('all', 'no_blurry', 'best'):
        res = run_export(conn, str(dest), plan_export(conn, selection=sel, duplicates='alternatives'))
        assert res.ok
        m = json.loads(Path(res.manifest).read_text())
        assert all(i['sha256_source'] == i['sha256_dest'] for i in m['items'])
    r = client.post(f'/api/collections/{slug}/export/wallpapers', json={'dest': str(dest)}, headers=H)
    assert r.get_json()['ok']
    import time
    for _ in range(100):
        if not client.get(f'/api/collections/{slug}/index', headers=H).get_json()['running']:
            break
        time.sleep(0.05)
    assert snapshot(src) == before, 'a source folder changed'
    assert not any(p.name.startswith('.') for p in src.rglob('*'))   # no hidden cache files either


def test_old_move_endpoints_are_gone(client, H):
    for path in ('/api/move-blurry', '/api/set-auto', '/api/toggle-status', '/api/run/cull',
                 '/api/export', '/api/export-phonebg'):
        assert client.post(path, json={}, headers=H).status_code in (404, 405), path


def test_app_page_and_assets_load(client, H):
    r = client.get('/', headers=H)
    assert r.status_code == 200 and b'/ui/app.js' in r.data
    assert client.get('/ui/app.js', headers=H).status_code == 200
    assert client.get('/ui/app.css', headers=H).status_code == 200
    assert client.get('/timeline', headers=H).status_code == 302
    csp = r.headers['Content-Security-Policy']
    assert 'https:' not in csp                                 # nothing loaded from the internet

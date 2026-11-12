"""M0 safety lock: source folders stay byte-identical, exports are verified copies."""
import json
from pathlib import Path

from conftest import make_photo, snapshot, wait_step


def _folder(tmp_path):
    src = tmp_path / 'phone_a'
    make_photo(src / 'IMG_0001.JPG', seed=1, dto='2026:10:23 18:14:32')
    make_photo(src / 'IMG_0002.JPG', seed=1, dto='2026:10:23 18:14:33')   # same picture
    make_photo(src / 'IMG_0003.JPG', seed=2, dto='2026:10:23 18:30:00', blur=True)
    make_photo(src / 'IMG_0004.JPG', seed=3, dto='2026:10:23 19:00:00')
    make_photo(src / 'IMG_0005.JPG', seed=4, dto='2026:10:23 19:30:00')
    return src


def test_full_workflow_leaves_source_untouched(pc, client, H, tmp_path):
    src = _folder(tmp_path)
    dest = tmp_path / 'exports'
    dest.mkdir()
    before = snapshot(src)

    assert client.post('/api/run/cull', json={'folder': str(src)}, headers=H).status_code == 200
    wait_step(pc, 'cull')
    # Manual tier change on a sharp photo: must only mark it.
    r = client.post('/api/toggle-status', json={'path': str(src / 'IMG_0004.JPG'),
                                                'tier': 'blurry'}, headers=H)
    assert r.get_json()['path'] == str(src / 'IMG_0004.JPG')
    client.post('/api/toggle-status', json={'path': str(src / 'IMG_0004.JPG'),
                                            'tier': 'sharp'}, headers=H)

    client.post('/api/run/dedup', json={'folder': str(src), 'opt': 0.8}, headers=H)
    wait_step(pc, 'dedup')
    client.post('/api/run/rank', json={'folder': str(src), 'topn': 3}, headers=H)
    wait_step(pc, 'rank')

    top = pc.build_topn(topn=3)
    assert top, 'rank produced no results'
    client.post('/api/toggle-phonebg', json={'path': top[0]['path']}, headers=H)

    r = client.post('/api/export', json={'topn': 3, 'dest': str(dest)}, headers=H).get_json()
    assert r['ok'] and r['verified'] == len(top) and r['failed'] == 0
    r2 = client.post('/api/export-phonebg', json={'dest': str(dest)}, headers=H).get_json()
    assert r2['ok'] and r2['verified'] == 1 and r2['cropped'] == 1

    assert snapshot(src) == before, 'source folder changed'

    # Exported copies are byte-identical to their sources and listed in the manifest.
    manifest = json.loads(Path(r['manifest']).read_text())
    assert manifest['status'] == 'completed'
    for it in manifest['items']:
        assert it['status'] == 'verified'
        assert it['sha256_source'] == it['sha256_dest'] == before[Path(it['source']).name]
        assert Path(it['dest']).is_file()


def test_no_move_endpoints_remain(client, H):
    assert client.post('/api/move-blurry', headers=H).status_code in (404, 405)
    assert client.post('/api/set-auto', json={'step': 'dedup', 'enabled': True},
                       headers=H).status_code in (404, 405)


def test_export_refuses_destination_inside_source(pc, client, H, tmp_path):
    src = _folder(tmp_path)
    client.post('/api/run/rank', json={'folder': str(src), 'topn': 2}, headers=H)
    wait_step(pc, 'rank')
    before = snapshot(src)
    r = client.post('/api/export', json={'topn': 2, 'dest': str(src)}, headers=H)
    assert r.status_code == 400 and 'inside a source folder' in r.get_json()['error']
    assert snapshot(src) == before


def test_export_never_overwrites(pc, client, H, tmp_path):
    src = _folder(tmp_path)
    dest = tmp_path / 'exports'
    dest.mkdir()
    client.post('/api/run/rank', json={'folder': str(src), 'topn': 2}, headers=H)
    wait_step(pc, 'rank')
    a = client.post('/api/export', json={'topn': 2, 'dest': str(dest)}, headers=H).get_json()
    b = client.post('/api/export', json={'topn': 2, 'dest': str(dest)}, headers=H).get_json()
    assert a['ok'] and b['ok'] and a['dest'] != b['dest']
    assert len([p for p in dest.iterdir() if p.is_dir()]) == 2


def test_caches_are_written_outside_source(pc, client, H, tmp_path):
    src = _folder(tmp_path)
    client.post('/api/run/dedup', json={'folder': str(src), 'opt': 0.8}, headers=H)
    wait_step(pc, 'dedup')
    assert not (src / '.dedup_sig_cache.json').exists()
    assert pc.DEDUP_CACHE_FILE.exists()
    assert str(pc.DATA_DIR) not in str(src)


def test_second_start_is_rejected(pc, client, H, tmp_path):
    pc.state['cull']['running'] = True
    try:
        r = client.post('/api/run/dedup', json={'folder': str(tmp_path)}, headers=H)
        assert r.status_code == 409
    finally:
        pc.state['cull']['running'] = False

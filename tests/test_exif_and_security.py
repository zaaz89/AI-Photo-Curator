from conftest import make_photo, wait_step


def test_exif_panel_uses_capture_time_not_edit_time(pc, client, H, tmp_path):
    p = make_photo(tmp_path / 'a' / 'IMG_1.JPG', seed=1, dto='2026:10:23 18:14:32',
                   offset='+02:00', datetime_ifd0='2026:10:23 20:00:00')
    pc.state['folder'] = str(p.parent)
    d = client.get('/api/exif', query_string={'path': str(p)}, headers=H).get_json()
    assert d['date'] == '2026-10-23'
    assert d['time'] == '18:14:32 (+02:00)'


def test_exif_panel_labels_modified_time_fallback(pc, client, H, tmp_path):
    p = make_photo(tmp_path / 'b' / 'IMG_2.JPG', seed=2, dto=None, offset=None,
                   datetime_ifd0='2026:10:23 20:00:00')
    pc.state['folder'] = str(p.parent)
    d = client.get('/api/exif', query_string={'path': str(p)}, headers=H).get_json()
    assert 'not capture time' in d['time']


def test_dedup_reads_date_time_original(tmp_path):
    from photo_dedup_batch import FastBatchDeduplicator
    import time
    p = make_photo(tmp_path / 'IMG_3.JPG', seed=3, dto='2026:10:23 18:14:32',
                   datetime_ifd0='2026:10:23 20:00:00')
    t = FastBatchDeduplicator(threshold=0.8)._capture_time(str(p))
    assert time.strftime('%H:%M:%S', time.localtime(t)) == '18:14:32'


def test_rejects_foreign_host(client):
    assert client.get('/api/shortcuts', headers={'Host': 'evil.example'}).status_code == 403


def test_rejects_cross_origin(client, H):
    r = client.post('/api/restore', json={'all': True},
                    headers={**H, 'Origin': 'https://evil.example'})
    assert r.status_code == 403


def test_rejects_path_traversal(pc, client, H, tmp_path):
    pc.state['folder'] = str(tmp_path)
    r = client.get('/api/image', query_string={'path': str(tmp_path / '..' / '..' / 'etc' / 'passwd')},
                   headers=H)
    assert r.status_code == 404

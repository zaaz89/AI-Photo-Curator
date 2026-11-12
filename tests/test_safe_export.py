import json

import pytest

from app.safety.safe_export import (ExportError, ExportItem, export_copies,
                                    safe_name, validate_destination)
from conftest import make_photo, snapshot


def test_missing_source_is_reported_not_success(tmp_path):
    src = tmp_path / 'src'
    make_photo(src / 'a.jpg', seed=1)
    dest = tmp_path / 'out'
    dest.mkdir()
    items = [ExportItem(str(src / 'a.jpg'), 'a.jpg'), ExportItem(str(src / 'gone.jpg'), 'gone.jpg')]
    res = export_copies(items, str(dest), [str(src)], 'job')
    assert not res.ok and res.verified == 1 and res.skipped == 1
    assert json.loads((dest / res.job_dir).joinpath('manifest.json').read_text())['status'] == 'failed'


def test_failed_derive_is_reported(tmp_path):
    src = tmp_path / 'src'
    make_photo(src / 'a.jpg', seed=1)
    dest = tmp_path / 'out'
    dest.mkdir()

    def boom(item, target):
        raise RuntimeError('crop failed')

    res = export_copies([ExportItem(str(src / 'a.jpg'), 'x.jpg', kind='derived')],
                        str(dest), [str(src)], 'job', derive=boom)
    assert not res.ok and res.failed == 1 and 'crop failed' in res.items[0]['error']


def test_colliding_names_get_suffixes(tmp_path):
    a, b = tmp_path / 'phone_a', tmp_path / 'phone_b'
    make_photo(a / 'IMG_0001.JPG', seed=1)
    make_photo(b / 'IMG_0001.JPG', seed=2)
    dest = tmp_path / 'out'
    dest.mkdir()
    before = snapshot(tmp_path / 'phone_a'), snapshot(tmp_path / 'phone_b')
    res = export_copies([ExportItem(str(a / 'IMG_0001.JPG'), 'IMG_0001.JPG'),
                         ExportItem(str(b / 'IMG_0001.JPG'), 'IMG_0001.JPG')],
                        str(dest), [str(a), str(b)], 'job')
    names = sorted(p.split('/')[-1] for p in (i['dest'] for i in res.items))
    assert res.ok and names == ['IMG_0001.JPG', 'IMG_0001_2.JPG']
    assert (snapshot(a), snapshot(b)) == before


def test_source_inside_destination_is_refused(tmp_path):
    with pytest.raises(ExportError):
        validate_destination(str(tmp_path), [str(tmp_path / 'photos')])


def test_safe_name_strips_separators():
    assert '/' not in safe_name('../../etc/passwd')
    assert safe_name('a:b?.jpg') == 'a_b_.jpg'

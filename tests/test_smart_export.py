"""M5: smart export names, folders, pairs, duplicates, verification, resume."""
import json
import os
from pathlib import Path

import pytest

from app import collections as col
from app.analysis import analyze_collection
from app.organization.export_plan import clean_part, plan_export, run_export
from app.places import geocoder
from app.places.geocoder import Index
from app.timeline import event_detector as ed
from conftest import make_photo, snapshot, textured_scene, make_view


@pytest.fixture(autouse=True)
def fake_geo():
    geocoder.set_index(Index.from_rows([('Bigtown', 43.77, 11.25, 360000, 'IT', '16')],
                                       {'IT.16': 'Tuscany'}, {'IT': 'Italy'}))
    yield
    geocoder.set_index(None)


@pytest.fixture
def trip(tmp_path):
    src = tmp_path / 'phone'
    textured_scene(src / 'IMG_0001.HEIC.jpg', seed=1, dto='2026:10:24 09:00:00')          # odd name on purpose
    textured_scene(src / 'IMG_0002.JPG', seed=2, dto='2026:10:24 09:00:00')                # same second
    textured_scene(src / 'IMG_0003.JPG', seed=3, dto='2026:10:24 09:10:00')
    make_view(src / 'IMG_0003.JPG', src / 'IMG_0004.JPG', crop=0.01, brightness=1.03,      # burst duplicate
              dto='2026:10:24 09:10:01', model='iPhone 15')
    make_photo(src / 'scan.JPG', seed=9, dto=None, offset=None, datetime_ifd0=None)       # no capture time
    (src / 'IMG_0003.MOV').write_bytes(b'fake live photo video')                           # pairs with IMG_0003
    slug = col.create('Tuscany 2026')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Me')
    analyze_collection(conn)
    with conn:
        conn.execute("UPDATE assets SET gps_lat = 43.7701, gps_lon = 11.2501 WHERE kind = 'image'")
    from app.places.places import assign_places
    assign_places(conn)
    ed.detect_events(conn)
    return src, conn, slug


def names(plan):
    return [e['dest'] for e in plan['entries']]


def test_default_names_folders_and_facts(trip):
    src, conn, _ = trip
    before = snapshot(src)
    plan = plan_export(conn)
    assert snapshot(src) == before                                     # preview touches nothing
    n = names(plan)
    assert '2026-10-24_Bigtown/2026-10-24_09-00-00_Bigtown_morning_001.jpg' in n
    assert '2026-10-24_Bigtown/2026-10-24_09-00-00_Bigtown_morning_002.JPG' in n   # same second, no collision
    assert 'undated/undated_scan.JPG' in n                             # documented fallback, no invented date
    assert len(n) == len(set(n))
    assert plan['warnings']['duplicates skipped'] == 1
    assert plan['warnings']['no trustworthy capture time'] == 1


def test_live_photo_video_shares_the_name(trip):
    src, conn, _ = trip
    n = names(plan_export(conn))
    still = next(x for x in n if x.endswith('_003.JPG'))
    assert still[:-4] + '.MOV' in n


def test_duplicates_as_alternatives_and_other_layouts(trip):
    src, conn, _ = trip
    n = names(plan_export(conn, duplicates='alternatives'))
    assert any(x.startswith('Alternatives/') for x in n) and any(x.startswith('Selected/') for x in n)
    n = names(plan_export(conn, template='original', folders='place'))
    assert 'Italy/Bigtown/20261024_090000_IMG_0002.JPG' in n
    n = names(plan_export(conn, template='trip', folders='flat'))
    assert any(x.startswith('Tuscany-2026_Day-1_Bigtown-morning_') for x in n)
    with pytest.raises(ValueError):
        plan_export(conn, template='nope')


def test_user_event_names_and_unicode(trip):
    src, conn, _ = trip
    eid = conn.execute("SELECT id FROM events WHERE day = '2026-10-24'").fetchone()[0]
    ed.rename_event(conn, eid, 'Zajtrk z Žažem: kava/čaj?')
    n = names(plan_export(conn, folders='event'))
    assert any('/Zajtrk-z-Žažem-kavačaj/' in x for x in n)
    assert clean_part(' a/b:c*?d  e ') == 'abcd-e'


def test_export_copies_verifies_and_records_original_names(trip, tmp_path):
    src, conn, _ = trip
    dest = tmp_path / 'out'
    dest.mkdir()
    before = snapshot(src)
    plan = plan_export(conn)
    res = run_export(conn, str(dest), plan)
    assert res.ok and res.verified == plan['files']
    m = json.loads(Path(res.manifest).read_text())
    assert m['plan']['template'] == 'default'
    assert m['original_names']['undated/undated_scan.JPG'] == 'scan.JPG'
    assert all(i['sha256_source'] == i['sha256_dest'] for i in m['items'])
    assert snapshot(src) == before


def test_resume_copies_only_what_is_missing(trip, tmp_path):
    src, conn, _ = trip
    dest = tmp_path / 'out'
    dest.mkdir()
    plan = plan_export(conn)
    first = run_export(conn, str(dest), plan)
    victim = Path(first.items[0]['dest'])
    victim.unlink()                                                    # an interrupted copy
    res = run_export(conn, str(dest), plan, resume_dir=first.job_dir)
    assert res.ok and res.job_dir == first.job_dir and victim.exists()
    assert len([p for p in dest.iterdir() if p.is_dir()]) == 1        # no second job folder
    with pytest.raises(Exception):
        run_export(conn, str(dest), plan, resume_dir=str(tmp_path))   # not an export folder


def test_export_api(pc, client, H, trip, tmp_path):
    src, conn, slug = trip
    r = client.post(f'/api/collections/{slug}/export/preview', json={'folders': 'date'}, headers=H).get_json()
    assert r['files'] > 0 and all(e['dest'].startswith(('2026-10-24/', 'undated/')) for e in r['entries'])
    assert client.post(f'/api/collections/{slug}/export/preview', json={'folders': 'x'}, headers=H).status_code == 400
    dest = tmp_path / 'api-out'
    dest.mkdir()
    import time
    assert client.post(f'/api/collections/{slug}/export', json={'dest': str(dest)}, headers=H).get_json()['ok']
    for _ in range(100):
        st = client.get(f'/api/collections/{slug}/index', headers=H).get_json()
        if not st['running']:
            break
        time.sleep(0.05)
    assert st['error'] is None and st['result']['export']['ok']

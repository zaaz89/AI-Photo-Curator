"""M6: focus tiers, Best photos, marks, export selection, UI settings."""
import pytest

from app import collections as col, settings
from app.analysis import analyze_collection
from app.organization.export_plan import plan_export
from app.quality.scoring import best_photos, classify, focus_tiers, set_mark, thresholds
from conftest import make_photo, textured_scene


@pytest.fixture
def coll(tmp_path):
    src = tmp_path / 'cam'
    for i in range(4):
        textured_scene(src / f'S{i}.jpg', seed=10 + i, dto=f'2026:10:23 1{i}:00:00')
    make_photo(src / 'B0.jpg', seed=1, dto='2026:10:23 15:00:00', blur=True)
    slug = col.create('quality')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Cam')
    analyze_collection(conn)
    return slug, conn


def _id(conn, name):
    return conn.execute('SELECT id FROM assets WHERE filename = ?', (name,)).fetchone()[0]


def test_upstream_tier_rules():
    lo, hi = thresholds([100, 200, 300])
    assert (lo, hi) == (50.0, 140.0)
    assert classify(150, 10, lo, hi, 70) == ('sharp', False)
    assert classify(60, 80, lo, hi, 70) == ('soft', True)       # soft but well composed: rescued
    assert classify(20, 90, lo, hi, 70) == ('blurry', False)    # too far below the floor


def test_blurry_photo_is_found_and_left_out_of_best(coll):
    slug, conn = coll
    tiers = focus_tiers(conn)
    assert tiers[_id(conn, 'B0.jpg')]['tier'] == 'blurry'
    names = [b['filename'] for b in best_photos(conn, topn=10)]
    assert 'B0.jpg' not in names and len(names) == 4
    assert all(set(b['scores']) == {'composition', 'technical', 'sharpness', 'color', 'aesthetic'}
               for b in best_photos(conn, topn=10))


def test_marks_override_and_survive_reanalysis(coll):
    slug, conn = coll
    s1 = _id(conn, 'S1.jpg')
    set_mark(conn, s1, focus='blurry', excluded=True, wallpaper=True)
    analyze_collection(conn)
    assert focus_tiers(conn)[s1]['tier'] == 'blurry' and focus_tiers(conn)[s1]['override'] == 'blurry'
    assert 'S1.jpg' not in [b['filename'] for b in best_photos(conn)]
    set_mark(conn, s1, focus=None, excluded=False)
    assert focus_tiers(conn)[s1]['override'] is None
    with pytest.raises(ValueError):
        set_mark(conn, s1, focus='great')


def test_export_selection(coll):
    slug, conn = coll
    assert plan_export(conn, selection='all')['files'] == 5
    assert plan_export(conn, selection='no_blurry')['files'] == 4
    p = plan_export(conn, selection='best', topn=2)
    assert p['files'] == 2 and p['warnings']['left out by selection (best)'] == 3


def test_ui_settings(client, H):
    assert client.post('/api/settings', json={'ui_language': 'sl'}, headers=H).get_json()['settings']['ui_language'] == 'sl'
    assert client.post('/api/settings', json={'ui_language': 'de'}, headers=H).status_code == 400
    r = client.post('/api/settings', json={'rank_weights': {'aesthetic': 80, 'color': 500}}, headers=H).get_json()
    assert r['settings']['rank_weights']['color'] == 100 and r['settings']['rank_weights']['composition'] == 0
    assert client.post('/api/settings', json={'rank_weights': {'nope': 1}}, headers=H).status_code == 400
    settings.save({'ui_language': 'en', 'rank_weights': {'aesthetic': 30, 'composition': 22, 'technical': 20,
                                                          'sharpness': 16, 'color': 12}})


def test_marks_and_best_api(coll, client, H):
    slug, conn = coll
    s2 = _id(conn, 'S2.jpg')
    r = client.post(f'/api/collections/{slug}/marks', json={'asset_id': s2, 'wallpaper': True}, headers=H).get_json()
    assert r['marks']['wallpaper'] == 1
    assert client.post(f'/api/collections/{slug}/marks', json={'asset_id': s2, 'focus': 'x'}, headers=H).status_code == 400
    best = client.get(f'/api/collections/{slug}/best?topn=3', headers=H).get_json()
    assert len(best['photos']) == 3 and best['photos'][0]['rank'] == 1

"""M13: per-day pipeline, live event stream, resume at day granularity, bench time shift."""
import json
import shutil

from app import analysis_events as ev
from app import collections as col
from app.analysis import analyze_collection, analyze_collection_all_at_once
from app.quality.scoring import focus_tiers
from conftest import make_photo, make_view, snapshot, textured_scene

DAYS = ('2026:10:24', '2026:10:25', '2026:10:26')


def _trip(root):
    """Three days. Me: per day a scene and its burst frame, two other scenes, one blurry photo; an exact copy on
    day 2. Partner (another clock): two photos on day 1 only, one of them a near view of my day-1 scene."""
    me, partner = root / 'me', root / 'partner'
    for d, date in enumerate(DAYS):
        a = textured_scene(me / f'D{d}_A.jpg', seed=100 + d, dto=f'{date} 10:00:00')
        make_view(a, me / f'D{d}_A2.jpg', crop=0.01, brightness=1.03, dto=f'{date} 10:00:01', model='iPhone 15')
        textured_scene(me / f'D{d}_B.jpg', seed=200 + d, dto=f'{date} 13:00:00')
        textured_scene(me / f'D{d}_C.jpg', seed=300 + d, dto=f'{date} 17:30:00')
        make_photo(me / f'D{d}_blur.jpg', seed=400 + d, dto=f'{date} 19:00:00', blur=True)
    shutil.copy(me / 'D1_B.jpg', me / 'D1_B_copy.jpg')
    make_view(me / 'D0_A.jpg', partner / 'PXL_1.jpg', crop=0.06, dto=f'{DAYS[0]} 10:00:30')
    textured_scene(partner / 'PXL_2.jpg', seed=500, dto=f'{DAYS[0]} 11:00:00', model='Pixel 8')
    return me, partner


def _album(tmp_path, name):
    root = tmp_path / name
    me, partner = _trip(root)
    slug = col.create(name)
    conn = col.open_db(slug)
    col.add_source(conn, str(me), 'Me')
    col.add_source(conn, str(partner), 'Partner')
    return slug, conn, me, partner


def _results(conn) -> dict:
    """What the owner sees, keyed by file name: moments (category, members, keeper, reasons), places, focus."""
    name = {r['id']: r['filename'] for r in conn.execute('SELECT id, filename FROM assets')}
    groups = set()
    for g in conn.execute('SELECT id, category, keeper_id, reasons_json FROM duplicate_groups'):
        members = frozenset(name[r[0]] for r in conn.execute(
            'SELECT asset_id FROM duplicate_members WHERE group_id = ?', (g['id'],)))
        groups.add((g['category'], members, name.get(g['keeper_id']), g['reasons_json']))
    places = {name[k]: v for k, v in ev.places(conn, list(name)).items()}
    tiers = {name[k]: v['tier'] for k, v in focus_tiers(conn).items()}
    return {'groups': groups, 'places': places, 'tiers': tiers}


def test_per_day_pipeline_equals_all_at_once(tmp_path):
    _, old, _, _ = _album(tmp_path, 'Old order')
    analyze_collection_all_at_once(old)
    slug, new, me, partner = _album(tmp_path, 'Per day')
    before = snapshot(me), snapshot(partner)
    res = analyze_collection(new)
    assert (snapshot(me), snapshot(partner)) == before                 # originals untouched
    assert res['days']['total'] == 3 and res['days']['settled'] == 3
    a, b = _results(old), _results(new)
    assert a['groups'] and any(c == 'near' for c, *_ in a['groups']) and any(c == 'exact' for c, *_ in a['groups'])
    assert any(v[0] == 'removed' for v in a['places'].values())        # the blurry ones
    assert b == a


def test_events_ordered_and_complete(tmp_path):
    slug, conn, _, _ = _album(tmp_path, 'Events')
    analyze_collection(conn)
    events = ev.events_since(conn, 0, 100000)['events']
    seqs = [e['seq'] for e in events]
    assert seqs == sorted(seqs) and len(set(seqs)) == len(seqs)
    assert {e['kind'] for e in events} <= set(ev.KINDS)
    ids = {r[0] for r in conn.execute("SELECT id FROM assets WHERE status = 'present'")}
    first = {}
    for e in events:
        if e['asset_id'] is not None:
            first.setdefault(e['asset_id'], e['kind'])
    assert set(first) == ids and set(first.values()) == {'read'}       # every photo is read before anything else
    last = {}
    for e in events:
        if e['asset_id'] is not None:
            last[e['asset_id']] = (e['kind'], e.get('reason'), e.get('keeper_id'))
    assert last == ev.places(conn, ids)                                 # the newest event is the current place
    settled = [e for e in events if e['kind'] == 'settled_day']
    assert [e['day'] for e in settled] == ['2026-10-24', '2026-10-25', '2026-10-26']    # chronological
    for s in settled:                                                    # a day settles after its photos' places
        mine = [e for e in events if e['day'] == s['day'] and e['kind'] in ('scored', 'removed', 'stacked')]
        assert mine and all(e['seq'] < s['seq'] for e in mine[:len(mine)])
    stacked = [e for e in events if e['kind'] == 'stacked']
    assert stacked and all(e['keeper_id'] for e in stacked)
    removed = [e for e in events if e['kind'] == 'removed']
    assert removed and all(e['reason'] for e in removed)
    # A second run with nothing new adds no place events and settles nothing again.
    n = len(events)
    res = analyze_collection(conn)
    assert res['days']['already_settled'] == 3
    assert len(ev.events_since(conn, 0, 100000)['events']) == n


def test_resume_after_cancel_gives_identical_results(tmp_path):
    _, full, _, _ = _album(tmp_path, 'Uninterrupted')
    analyze_collection(full)
    _, conn, _, _ = _album(tmp_path, 'Stopped')
    stop = {'now': False}
    analyze_collection(conn, cancelled=lambda: stop['now'], overall=lambda f: stop.update(now=True))
    assert list(ev.settled_days(conn)) == ['2026-10-24']               # stopped after the first day
    assert [e['day'] for e in ev.events_since(conn, 0, 100000)['events'] if e['kind'] == 'settled_day'] == \
        ['2026-10-24']
    res = analyze_collection(conn)
    assert res['days']['already_settled'] == 1 and res['days']['settled'] == 3
    assert _results(conn) == _results(full)
    days = [e['day'] for e in ev.events_since(conn, 0, 100000)['events'] if e['kind'] == 'settled_day']
    assert days == ['2026-10-24', '2026-10-25', '2026-10-26']


def test_clock_change_rebuilds_only_affected_days(client, H, tmp_path):
    slug, conn, _, _ = _album(tmp_path, 'Clocks')
    analyze_collection(conn)
    assert ev.rebuild_changed_days(conn)['rebuilt_days'] == []         # nothing moved
    clock = conn.execute("SELECT k.id FROM clocks k JOIN sources s ON s.id = k.source_id "
                         "WHERE s.owner = 'Partner'").fetchone()[0]
    r = client.post(f'/api/collections/{slug}/clocks/{clock}', json={'action': 'manual', 'seconds': 86400},
                    headers=H).get_json()
    assert r['ok']
    assert sorted(r['rebuilt_days']) == ['2026-10-24', '2026-10-25']    # the partner's photos moved a day
    assert '2026-10-26' in ev.settled_days(conn)


def test_events_endpoint_pagination(client, H, tmp_path):
    slug, conn, _, _ = _album(tmp_path, 'Paging')
    analyze_collection(conn)
    everything = ev.events_since(conn, 0, 100000)['events']
    got, since, pages = [], 0, 0
    while True:
        r = client.get(f'/api/collections/{slug}/events', query_string={'since': since, 'limit': 7}, headers=H)
        assert r.status_code == 200
        page = r.get_json()
        assert len(page['events']) <= 7 and page['latest'] == everything[-1]['seq']
        got += page['events']
        since, pages = page['next'], pages + 1
        if not page['more']:
            break
    assert got == everything and pages == -(-len(everything) // 7)
    empty = client.get(f'/api/collections/{slug}/events', query_string={'since': since}, headers=H).get_json()
    assert empty['events'] == [] and empty['next'] == since and not empty['more']
    assert client.get(f'/api/collections/{slug}/events', query_string={'since': 'x'}, headers=H).status_code == 400
    assert client.get(f'/api/collections/{slug}/events', query_string={'limit': 0}, headers=H).status_code == 400
    assert client.get('/api/collections/nope/events', headers=H).status_code == 404
    assert ev.prune(conn) == len(everything)
    assert ev.events_since(conn, 0)['events'] == []


def test_bench_time_shift_only_in_bench_folder(tmp_path, monkeypatch):
    from app.importers import local_importer as li
    from app.metadata.timestamp_resolver import ResolvedTime
    bench = tmp_path / 'bench'
    bench.mkdir()
    (bench / 'bench-times.json').write_text(json.dumps({'shift_s': {'x.jpg': 86400}}))
    monkeypatch.delenv('PHOTOCURATOR_BENCH_TIMES', raising=False)
    assert li.bench_time_shifts() == {}                                 # normal runs: nothing
    monkeypatch.setenv('PHOTOCURATOR_BENCH_TIMES', str(bench / 'bench-times.json'))
    shifts = li.bench_time_shifts()

    def res():
        return ResolvedTime('exif', 'high', local_time='2026-10-24T10:00:00', utc_time='2026-10-24T08:00:00Z',
                            offset_minutes=120, sort_key=1000.0)
    r = res()
    li._apply_bench_shift(r, shifts, str(bench / 'src'), 'x.jpg')
    assert r.local_time == '2026-10-25T10:00:00' and r.utc_time == '2026-10-25T08:00:00Z' and r.sort_key == 87400.0
    r = res()
    li._apply_bench_shift(r, shifts, str(tmp_path / 'photos'), 'x.jpg')  # a real folder: never shifted
    assert r.local_time == '2026-10-24T10:00:00' and r.sort_key == 1000.0

"""M14c: the Analysis station's fixes. Days are known as soon as the clocks are (not "No date" / "day 1 of 1"),
one phase plan for the status and the bar, folder chips that tell folders apart and say what they are doing."""
from app import analysis_events as ev
from app import collections as col
from app.analysis import analyze_collection
from app.analysis_progress import PHASES, PhasePlan
from app.assistant import _analysis_days
from app.source_chips import chip_labels, pretty_device, source_state
from app.timeline.event_detector import asset_days
from app.web import timeline_bp
from conftest import make_photo, textured_scene

DAYS = ('2026:10:22', '2026:10:23', '2026:10:25', '2026:10:28')


def _album(tmp_path, name):
    """A week in Tuscany: the photographer's two folders (same person, same camera) over four days, a phone folder
    on two of them. Just-after-midnight photos (+02:00) check that the local day, not the UTC one, is used."""
    root = tmp_path / name
    ceremony, portraits, phone = root / 'Ceremony', root / 'Portraits', root / 'Toskana 2026'
    for d, date in enumerate(DAYS):
        textured_scene(ceremony / f'C{d}_a.jpg', seed=10 + d, dto=f'{date} 10:00:00', model='ILCE-7M4', make='SONY')
        make_photo(ceremony / f'C{d}_b.jpg', seed=20 + d, dto=f'{date} 00:30:00', model='ILCE-7M4', make='SONY')
    make_photo(portraits / 'P_1.jpg', seed=31, dto=f'{DAYS[1]} 17:00:00', model='ILCE-7M4', make='SONY')
    make_photo(phone / 'IMG_1.jpg', seed=41, dto=f'{DAYS[0]} 12:00:00', model='iPhone 15 Pro')
    make_photo(phone / 'IMG_2.jpg', seed=42, dto=f'{DAYS[3]} 08:00:00', model='iPhone 15 Pro')
    slug = col.create(name)
    conn = col.open_db(slug)
    col.add_source(conn, str(ceremony), 'Jarek Pawlak')
    col.add_source(conn, str(portraits), 'Jarek Pawlak')
    col.add_source(conn, str(phone), 'Toskana 2026')
    return slug, conn, (ceremony, portraits, phone)


def _iso(d):
    return d.replace(':', '-')


def test_photos_group_by_their_real_day_as_soon_as_clocks_are_known(tmp_path):
    slug, conn, _ = _album(tmp_path, 'Tuscany')
    seen = []

    def report(state):
        days = None
        if state['phase'] in ('clocks', 'places') and not any(s['phase'] == state['phase'] for s in seen):
            days = set(asset_days(conn).values())        # what the app reads on this phase change
        seen.append({**state, 'asset_days': days})

    res = analyze_collection(conn, report=report)
    want = {_iso(d) for d in DAYS}
    assert res['days']['total'] == 4 and res['days']['settled'] == 4
    # The day plan and every event name the real days; nothing is "unknown".
    assert [d for d, _ in ev.day_plan(conn)] == sorted(want)
    events = ev.events_since(conn, 0, 10000)['events']
    assert {e['day'] for e in events} == want
    assert {e['day'] for e in events if e['kind'] == 'settled_day'} == want
    # At the first report of the clocks and places phases the days are already known (the app reloads there).
    first = {s['phase']: s for s in reversed(seen)}
    assert first['clocks']['asset_days'] == want and first['places']['asset_days'] == want
    # The overview says "of 4 days", never "of 1".
    assert _analysis_days(conn) == {'days': 4, 'settled': 4}


def test_overview_has_no_days_while_folders_are_still_read(tmp_path):
    from app.importers.local_importer import index_source, resolve_all
    slug, conn, _ = _album(tmp_path, 'Reading')
    sid = conn.execute('SELECT MIN(id) FROM sources').fetchone()[0]
    index_source(conn, sid)                      # photos exist, capture times not resolved yet
    assert conn.execute('SELECT COUNT(*) FROM assets').fetchone()[0] > 0
    assert _analysis_days(conn)['days'] == 0     # before M14c: 1 ("unknown"), shown as "day 1 of 1"
    resolve_all(conn)
    assert _analysis_days(conn)['days'] == 4


def test_phase_plan_moves_forward_only(tmp_path):
    slug, conn, _ = _album(tmp_path, 'Plan')
    states = []
    analyze_collection(conn, report=states.append)
    phases = [s['phase'] for s in states]
    order = [PHASES.index(p) for p in phases]
    assert order == sorted(order)                                    # reading -> clocks -> places -> days -> finishing
    assert set(phases) == set(PHASES)
    progress = [s['progress'] for s in states]
    assert progress == sorted(progress) and progress[-1] >= 97       # one bar, never jumps back
    reading = [s for s in states if s['phase'] == 'reading']
    assert {s['source'] for s in reading} == {1, 2, 3} and all(s['sources'] == 3 for s in reading)
    days = [s for s in states if s['phase'] == 'days']
    assert {s['day'] for s in days} == {1, 2, 3, 4} and all(s['days'] == 4 for s in days)
    assert {'focus', 'moments'} <= {s['step'] for s in days}


def test_phase_plan_unit():
    p = PhasePlan(sources=2)
    p.start_source(0, 2, 7)
    p.update('[A] Hashing x', 5, 10)
    a = p.progress
    p.start_source(1, 2, 8)                      # the second folder starts at 0 of its files: the bar does not
    p.update('[B] Hashing y', 0, 10)
    assert p.progress >= a and p.state()['source_id'] == 8
    p.enter('clocks')
    p.update('Matching scenes between devices', 10, 10)
    assert p.progress == 25
    p.enter('reading')                           # never back
    assert p.phase == 'clocks'
    p.enter('places')
    p.start_day(2, 7)
    p.update('Day 3 of 7: Focus and ranking scores', 5, 10)
    s = p.state()
    assert (s['phase'], s['step'], s['day'], s['days'], s['done'], s['total']) == ('days', 'focus', 3, 7, 5, 10)
    before = p.progress
    p.update('Day 3 of 7: Moments (near duplicates)', 0, 0)
    assert p.state()['step'] == 'moments' and p.progress >= before
    p.day_done(6)
    p.finish()
    assert p.progress == 100


def test_job_status_carries_the_stage(pc, client, H, tmp_path):
    slug, conn, _ = _album(tmp_path, 'Job')
    conn.close()
    timeline_bp._job.update(running=True, collection=slug, kind='analysis', status='', progress=0, stage=None,
                            result=None, error=None, cancel=False, started=0)
    timeline_bp._run_index(slug)
    st = client.get(f'/api/collections/{slug}/index', headers=H).get_json()
    assert st['stage']['phase'] == 'finishing' and st['stage']['days'] == 4 and st['progress'] == 100


def test_device_names_people_know():
    assert pretty_device('SONY', 'ILCE-7M4') == 'Sony A7 IV'
    assert pretty_device('SONY', 'ILCE-7RM5') == 'Sony A7R V'
    assert pretty_device('SONY', 'ILCE-6400') == 'Sony A6400'
    assert pretty_device('Apple', 'iPhone 15 Pro') == 'iPhone 15 Pro'
    assert pretty_device('Google', 'Pixel 8') == 'Pixel 8'
    assert pretty_device('Canon', 'Canon EOS R5') == 'Canon EOS R5'
    assert pretty_device('NIKON CORPORATION', 'NIKON Z 6_2') == 'Nikon Z 6 II'
    assert pretty_device('FUJIFILM', 'X-T5') == 'Fujifilm X-T5'
    assert pretty_device('', '') == ''


def test_chips_tell_folders_apart():
    src = [{'id': 1, 'owner': 'Jarek Pawlak', 'path': '/t/Ceremony', 'devices': ['Sony A7 IV']},
           {'id': 2, 'owner': 'Jarek Pawlak', 'path': '/t/Portraits', 'devices': ['Sony A7 IV']},
           {'id': 3, 'owner': 'Toskana 2026', 'path': '/t/Toskana 2026', 'devices': ['iPhone 15 Pro']}]
    assert chip_labels(src) == {1: 'Jarek Pawlak · Ceremony', 2: 'Jarek Pawlak · Portraits',
                                3: 'iPhone 15 Pro · Toskana 2026'}
    # Different cameras are enough; the same person with one folder keeps "person · camera".
    two = [{'id': 1, 'owner': 'Ana', 'path': '/a/x', 'devices': ['iPhone 15']},
           {'id': 2, 'owner': 'Ana', 'path': '/b/x', 'devices': ['Sony A7 IV']}]
    assert chip_labels(two) == {1: 'Ana · iPhone 15', 2: 'Ana · Sony A7 IV'}
    # Same person, camera and folder name: numbered. No person, no camera: the folder.
    same = [{'id': 1, 'owner': 'Ana', 'path': '/a/x', 'devices': []}, {'id': 2, 'owner': 'Ana', 'path': '/b/x', 'devices': []},
            {'id': 3, 'owner': '', 'path': '/c/Holiday', 'devices': []}]
    labels = chip_labels(same)
    assert labels[1] != labels[2] and labels[1].startswith('Ana · x') and labels[3] == 'Holiday'
    assert len(set(chip_labels(src).values())) == 3


def test_chip_states():
    running = {'running': True, 'stage': {'phase': 'reading', 'source': 2, 'source_id': 8, 'done': 12, 'total': 80}}
    assert source_state({'id': 7, 'assets': 50}, 0, True, running)['state'] == 'read'
    assert source_state({'id': 8, 'assets': 12}, 1, True, running) == {'state': 'reading', 'done': 12, 'total': 80}
    assert source_state({'id': 9, 'assets': 0}, 2, True, running)['state'] == 'waiting'
    assert source_state({'id': 9, 'assets': 0}, 2, True, None)['state'] == 'empty'
    failed = source_state({'id': 9, 'assets': 0}, 2, False, None)
    assert failed['state'] == 'failed' and failed['reason'] == 'folder not found'


def test_sources_endpoint_has_chip_and_state(client, H, tmp_path):
    slug, conn, (ceremony, portraits, phone) = _album(tmp_path, 'Chips')
    empty = tmp_path / 'Chips' / 'Empty'
    empty.mkdir()
    col.add_source(conn, str(empty), 'Empty')
    analyze_collection(conn)
    conn.close()
    src = client.get(f'/api/collections/{slug}/sources', headers=H).get_json()['sources']
    chips = {s['chip'] for s in src}
    assert len(chips) == len(src)
    assert 'Jarek Pawlak · Ceremony' in chips and 'Jarek Pawlak · Portraits' in chips
    assert 'iPhone 15 Pro · Toskana 2026' in chips
    by_chip = {s['chip']: s for s in src}
    assert by_chip['Jarek Pawlak · Ceremony']['devices'] == ['Sony A7 IV']
    assert by_chip['Jarek Pawlak · Ceremony']['read_state']['state'] == 'read'
    assert by_chip['Empty']['read_state']['state'] == 'empty'

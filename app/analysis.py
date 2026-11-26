"""Full pipeline for a collection (M13: per day).

index all (cheap) -> screenshots -> clocks -> places/events -> then day by day in chronological order:
visual signatures -> focus and ranking -> faces (Apple Vision) -> videos -> moments. A day is settled once its
moments exist; the Sorting page follows it through the event stream (app/analysis_events.py).

Clocks are computed once from the metadata of every file before the per-day loop, so a later day never moves
an earlier one. A stopped analysis resumes at the first unsettled day (the stages skip what is already
measured). Focus verdicts are relative to the whole album, so after the last day the keepers are chosen again
without comparing photos and every photo whose place changed gets a new event.

`analyze_collection_all_at_once` is the pre-M13 order (each stage over the whole album, moments last); the
tests compare both and the benchmark can time both.
"""
from __future__ import annotations

import time
from typing import Callable, Optional

from app.duplicates.groups import build_groups, compute_features, refresh_keepers
from app.importers.local_importer import index_collection
from app.timeline.clock_sync import sync_clocks


def _prepare(conn, progress, cancelled, res: dict, timings: dict, plan=None, report=None) -> bool:
    """index -> screenshots -> clocks -> places/events; False when cancelled. `plan` (a PhasePlan) and
    `report(state)` follow the phases (M14c)."""
    def enter(phase):
        if plan is not None:
            plan.enter(phase)
            if report:
                report(plan.state())

    def on_source(k, n, sid):
        if plan is not None:
            plan.start_source(k, n, sid)
            if report:
                report(plan.state())
    t = time.time()
    res.update(index_collection(conn, progress, cancelled, on_source=on_source))
    timings['index'] = time.time() - t
    if cancelled():
        return False
    # M14c: capture times are known from here on (resolve_all ran inside index_collection); the app reloads the
    # photos on this phase change, so the stage groups them by day before any event arrives.
    enter('clocks')
    from app.quality.screenshots import detect as detect_screenshots
    t = time.time()
    res['screenshots'] = detect_screenshots(conn)
    res['clocks'] = sync_clocks(conn, progress, cancelled)
    timings['clocks'] = time.time() - t
    if cancelled():
        return False
    enter('places')                      # clock corrections are applied from here on
    from app.places.places import assign_places
    from app.timeline.event_detector import detect_events
    t = time.time()
    res['places'] = assign_places(conn)
    res['events'] = detect_events(conn)
    timings['places_events'] = time.time() - t
    return True


def _add(total: dict, part) -> None:
    """Sums the numbers of a stage result into `total` (strings are kept from the first day)."""
    if not isinstance(part, dict):
        return
    for k, v in part.items():
        if isinstance(v, bool) or not isinstance(v, (int, float, dict)):
            total.setdefault(k, v)
        elif isinstance(v, dict):
            _add(total.setdefault(k, {}), v)
        else:
            total[k] = total.get(k, 0) + v


def analyze_collection(conn, progress: Optional[Callable] = None,
                       cancelled: Callable[[], bool] = lambda: False,
                       overall: Optional[Callable[[float], None]] = None,
                       report: Optional[Callable[[dict], None]] = None) -> dict:
    """The per-day pipeline. `overall(fraction)` (optional) reports the share of days done (0-1); `report(state)`
    (optional, M14c) the phase plan's state after every step (`app/analysis_progress.py`)."""
    from app import analysis_events as ev
    from app.analysis_progress import PhasePlan
    from app.quality.faces import compute_faces, compute_videos
    from app.quality.scoring import compute_quality
    from app.timeline.event_detector import asset_days
    res: dict = {}
    timings: dict = {}
    res['timings_s'] = timings
    phases = PhasePlan(conn.execute('SELECT COUNT(*) FROM sources').fetchone()[0])
    user_progress = progress

    def progress(msg, a, n):              # noqa: F811 - the caller's callback plus the phase plan
        phases.update(msg, a, n)
        if user_progress:
            user_progress(msg, a, n)
        if report:
            report(phases.state())
    if not _prepare(conn, progress, cancelled, res, timings, phases, report):
        return res
    plan = ev.day_plan(conn)
    ev.emit_read(conn, plan)
    day_of = asset_days(conn)
    done = ev.settled_days(conn)
    stage_time = {k: 0.0 for k in ('features', 'quality', 'faces', 'videos', 'moments')}
    timings['per_day'] = stage_time
    totals = {'features_computed': 0, 'quality': {}, 'faces': {}, 'videos': {}, 'duplicate_groups': {}}
    days = {'total': len(plan), 'settled': 0, 'already_settled': 0, 'first_settled_s': None}
    res['days'] = days
    started = time.time()
    for i, (day, assets) in enumerate(plan):
        if cancelled():
            break
        shas = {a['sha256'] for a in assets if a['sha256']}
        phases.start_day(i, len(plan))
        if report:
            report(phases.state())

        def p(msg, a, n, _i=i):
            if progress:
                progress(f'Day {_i + 1} of {len(plan)}: {msg}', a, n)
        t = time.time()
        nf = compute_features(conn, p, cancelled, shas=shas)
        stage_time['features'] += time.time() - t
        totals['features_computed'] += nf
        t = time.time()
        q = compute_quality(conn, p, cancelled, shas=shas)
        stage_time['quality'] += time.time() - t
        t = time.time()
        f = compute_faces(conn, p, cancelled, shas=shas)
        stage_time['faces'] += time.time() - t
        t = time.time()
        v = compute_videos(conn, p, cancelled, shas=shas)
        stage_time['videos'] += time.time() - t
        for key, part in (('quality', q), ('faces', f), ('videos', v)):
            _add(totals[key], part)
        if cancelled():
            break                               # this day is not settled: a resume starts here
        sig = ev.signature(assets)
        new_work = nf or (q.get('scored') or 0) or (f.get('analysed') or 0) \
            or ((f.get('subject') or {}).get('measured') or 0) or (v.get('videos') or 0)
        if done.get(day) == sig and not new_work:
            days['already_settled'] += 1
            days['settled'] += 1
        else:
            if progress:
                p('Moments (near duplicates)', 0, 0)
            t = time.time()
            g = build_groups(conn, p, cancelled, day=day, day_of=day_of)
            stage_time['moments'] += time.time() - t
            if g.get('cancelled') or cancelled():
                break
            _add(totals['duplicate_groups'], g)
            ev.mark_settled(conn, day, sig)
            ev.emit_places(conn, plan, days={day}, settled=True)
            days['settled'] += 1
            if days['first_settled_s'] is None:
                days['first_settled_s'] = round(time.time() - started, 2)
        if overall:
            overall((i + 1) / max(1, len(plan)))
        phases.day_done(i)
        if report:
            report(phases.state())
    if not cancelled():
        phases.enter('finishing')
        if report:
            report(phases.state())
        # Days that no longer exist (photos removed or moved by a clock change) are forgotten.
        ev.forget_days(conn, [d for d in ev.settled_days(conn) if d not in {d for d, _ in plan}])
        t = time.time()
        changed = refresh_keepers(conn)
        ev.emit_places(conn, plan, days=set(ev.settled_days(conn)))
        timings['final_keepers'] = time.time() - t
        res['keepers_changed_after_all_days'] = len(changed)
    res.update(totals)
    for k in stage_time:
        stage_time[k] = round(stage_time[k], 3)
    for k in ('index', 'clocks', 'places_events', 'final_keepers'):
        if k in timings:
            timings[k] = round(timings[k], 3)
    # The search index (M3) is not built here: the first search builds it (M9 speed-up, owner's OK
    # 2026-11-16), so an album is ready to work on sooner and albums nobody searches never pay for it.
    return res


def analyze_collection_all_at_once(conn, progress: Optional[Callable] = None,
                                   cancelled: Callable[[], bool] = lambda: False) -> dict:
    """The pre-M13 order: every stage over the whole album, moments last (for tests and benchmarks)."""
    res: dict = {}
    timings: dict = {}
    res['timings_s'] = timings
    if not _prepare(conn, progress, cancelled, res, timings):
        return res
    if progress:
        progress('Visual signatures', 0, 0)
    t = time.time()
    res['features_computed'] = compute_features(conn, progress, cancelled)
    timings['features'] = round(time.time() - t, 3)
    from app.quality.faces import compute_faces, compute_videos
    from app.quality.scoring import compute_quality
    for key, fn in (('quality', compute_quality), ('faces', compute_faces), ('videos', compute_videos)):
        t = time.time()
        res[key] = fn(conn, progress, cancelled)
        timings[key] = round(time.time() - t, 3)
    t = time.time()
    res['duplicate_groups'] = build_groups(conn, progress, cancelled)
    timings['moments'] = round(time.time() - t, 3)
    return res

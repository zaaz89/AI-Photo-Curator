"""Gentle AI jobs: duty-cycle pauses, thermal/battery pause, settings."""
import pytest

from app import settings
from app.ai import throttle as th


@pytest.fixture
def slept(monkeypatch):
    calls = []
    monkeypatch.setattr(th.Throttle, '_sleep', lambda self, s: calls.append(round(s, 3)))
    monkeypatch.setattr(th, 'thermal_warning', lambda: False)
    monkeypatch.setattr(th, 'on_battery', lambda: False)
    return calls


def test_duty_cycle_matches_the_setting(slept):
    settings.save({'ai_gpu_share': 30, 'ai_pause_on_battery': False})
    t = th.Throttle()
    t.after_work(3.0)
    assert slept == [7.0]                      # 3 s busy -> 7 s rest = 30 % busy
    settings.save({'ai_gpu_share': 50})
    t.after_work(4.0)
    assert slept[-1] == 4.0
    settings.save({'ai_gpu_share': 100})
    slept.clear()
    t.after_work(4.0)
    assert slept == []                         # no limit
    settings.save({'ai_gpu_share': 30})


def test_pauses_on_thermal_warning_until_it_clears(slept, monkeypatch):
    states = iter([True, True, False])
    monkeypatch.setattr(th, 'thermal_warning', lambda: next(states))
    settings.save({'ai_gpu_share': 100})
    msgs = []
    th.Throttle(status=msgs.append).after_work(1.0)
    assert len(msgs) == 2 and 'thermal' in msgs[0]
    assert slept == [th.CHECK_EVERY_S, th.CHECK_EVERY_S]
    settings.save({'ai_gpu_share': 30})


def test_battery_pause_only_when_enabled(slept, monkeypatch):
    monkeypatch.setattr(th, 'on_battery', lambda: True)
    settings.save({'ai_gpu_share': 100, 'ai_pause_on_battery': False})
    assert th.pause_reason(settings.load()) is None
    settings.save({'ai_pause_on_battery': True})
    assert 'battery' in th.pause_reason(settings.load())
    settings.save({'ai_gpu_share': 30, 'ai_pause_on_battery': False})


def test_cancel_stops_a_pause(monkeypatch):
    monkeypatch.setattr(th, 'thermal_warning', lambda: True)
    t = th.Throttle(cancelled=lambda: True)
    t.after_work(1.0)                          # returns at once instead of waiting


def test_thermal_parser(monkeypatch):
    monkeypatch.setattr(th, '_pmset', lambda *a: 'Note: No thermal warning level has been recorded\n')
    assert th.thermal_warning() is False
    monkeypatch.setattr(th, '_pmset', lambda *a: 'Thermal warning level set to 2.\n')
    assert th.thermal_warning() is True
    monkeypatch.setattr(th, '_pmset', lambda *a: 'CPU_Speed_Limit \t= 70\n')
    assert th.thermal_warning() is True


def test_settings_validation_and_api(client, H):
    assert settings.save({'ai_gpu_share': 77})['ai_gpu_share'] == 77      # any share 10-100 (M11 slider)
    for bad in (9, 101, True, 'fast', None):
        with pytest.raises(ValueError):
            settings.save({'ai_gpu_share': bad})
    with pytest.raises(ValueError):
        settings.save({'unknown': 1})
    with pytest.raises(ValueError):
        settings.save({'quality_strictness': 'extreme'})
    body = client.get('/api/settings', headers=H).get_json()
    assert 10 <= body['settings']['ai_gpu_share'] <= 100 and body['ranges']['ai_gpu_share'] == [10, 100]
    assert body['settings']['quality_strictness'] == 'normal' and 'speed' in body
    r = client.post('/api/settings', json={'ai_gpu_share': 25}, headers=H)
    assert r.get_json()['settings']['ai_gpu_share'] == 25
    assert client.post('/api/settings', json={'ai_gpu_share': 5}, headers=H).status_code == 400
    settings.save({'ai_gpu_share': 30})


# M11: the share applies to every phase, parallel work runs in rounds, the speed of this Mac is measured.

def test_throttled_map_rests_after_each_round(slept):
    from concurrent.futures import ThreadPoolExecutor
    settings.save({'ai_gpu_share': 25})
    t = th.Throttle(share=None)
    out = list(th.throttled_map(lambda x: x * 2, range(10), t, workers=2, make_pool=ThreadPoolExecutor,
                                chunksize=2))
    assert out == [(i, i * 2) for i in range(10)]          # order kept
    assert len(slept) == 3                                # rounds of 4, 4, 2, each followed by a rest
    slept.clear()
    list(th.throttled_map(lambda x: x, range(3), th.Throttle(), workers=1))
    assert len(slept) == 3                                # one worker: every item is a round
    settings.save({'ai_gpu_share': 100})
    slept.clear()
    out = list(th.throttled_map(lambda x: x, range(40), th.Throttle(), workers=2,
                                make_pool=ThreadPoolExecutor, chunksize=2))
    assert len(out) == 40 and slept == []                 # no limit: big rounds, no rest
    settings.save({'ai_gpu_share': 30})


def test_measured_work_sets_the_rest(slept, monkeypatch):
    settings.save({'ai_gpu_share': 50})
    clock = iter([100.0, 102.0])                          # made at 100 s, work ends at 102 s
    monkeypatch.setattr(th.time, 'time', lambda: next(clock, 102.0))
    th.reset_totals()
    t = th.Throttle()
    t.after_work()
    assert slept == [2.0] and th.TOTALS['busy'] == 2.0    # 2 s of work at 50 % -> 2 s rest
    settings.save({'ai_gpu_share': 30})


def test_cancel_stops_throttled_map():
    flag = {'stop': False}

    def work(x):
        flag['stop'] = x >= 1
        return x
    settings.save({'ai_gpu_share': 100})
    out = list(th.throttled_map(work, range(5), th.Throttle(cancelled=lambda: flag['stop'])))
    assert [i for i, _ in out] == [0, 1]
    settings.save({'ai_gpu_share': 30})


def test_speed_record_and_estimate():
    th.reset_totals()
    th.TOTALS.update(busy=6.0, rested=14.0)               # 6 s of throttled work, 14 s of rest
    assert th.record_speed(3, 30.0) is None              # too few photos to measure
    m = th.record_speed(10, 30.0)                         # 30 s in all: 10 s of other work
    assert m['throttled_per_photo'] == 0.6 and m['other_per_photo'] == 1.0
    assert th.speed()['photos'] == 10
    assert th.estimate_seconds(100, 100) == 160.0         # 100 x (1.0 + 0.6)
    assert th.estimate_seconds(100, 30) == 300.0          # 100 x (1.0 + 0.6 x 100/30)
    assert th.estimate_seconds(0, 30) is None

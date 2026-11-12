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
    with pytest.raises(ValueError):
        settings.save({'ai_gpu_share': 77})
    with pytest.raises(ValueError):
        settings.save({'unknown': 1})
    assert client.get('/api/settings', headers=H).get_json()['settings']['ai_gpu_share'] in (25, 30, 50, 100)
    r = client.post('/api/settings', json={'ai_gpu_share': 25}, headers=H)
    assert r.get_json()['settings']['ai_gpu_share'] == 25
    assert client.post('/api/settings', json={'ai_gpu_share': 5}, headers=H).status_code == 400
    settings.save({'ai_gpu_share': 30})

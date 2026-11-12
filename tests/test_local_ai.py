"""M3: search index, semantic search and VLM descriptions, with fake models.

The real models (SigLIP 2, Qwen3-VL) are exercised manually on the owner's
photos (notes/m3-local-ai.md). Here fakes make the logic deterministic:
the fake embedder maps a photo's dominant colour and the words red/green/blue
into the same 3-d space.
"""
import json

import numpy as np
import pytest
from PIL import Image

from app import collections as col
from app.ai import embeddings, search as search_mod, vision_analyzer as vlm
from app.analysis import analyze_collection
from conftest import snapshot


class FakeEmbedder:
    name = 'fake-colour'
    WORDS = {'red': [1, 0, 0], 'green': [0, 1, 0], 'blue': [0, 0, 1]}

    def images(self, ims):
        out = []
        for im in ims:
            v = np.asarray(im.resize((8, 8)), np.float32).reshape(-1, 3).mean(0)
            out.append(v / (np.linalg.norm(v) or 1))
        return np.stack(out)

    def texts(self, texts):
        out = []
        for t in texts:
            v = np.zeros(3, np.float32)
            for w, vec in self.WORDS.items():
                if w in t.lower():
                    v += vec
            out.append(v / (np.linalg.norm(v) or 1))
        return np.stack(out)


def _solid(path, rgb, dto='2026:10:23 18:00:00'):
    """Mostly one colour, with a different light pattern per colour so the
    duplicate detector does not treat the three photos as one picture."""
    from conftest import textured_scene
    tmp = textured_scene(path.with_suffix('.tmp.png'), seed=rgb[0] * 7 + rgb[1] * 3 + rgb[2])
    base = Image.open(tmp).convert('RGB')
    tmp.unlink()
    im = Image.blend(base, Image.new('RGB', base.size, rgb), 0.75)   # structure differs, colour dominates
    exif = Image.Exif()
    exif.get_ifd(0x8769)[36867] = dto
    exif.get_ifd(0x8769)[36881] = '+02:00'
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, exif=exif, quality=95)
    return path


@pytest.fixture
def colours(tmp_path, monkeypatch):
    embeddings.set_embedder(FakeEmbedder())
    monkeypatch.setattr(vlm, 'status', lambda: {'running': False, 'model_ready': False, 'model': 'x'})
    src = tmp_path / 'cam'
    _solid(src / 'red.jpg', (220, 20, 20), '2026:10:23 18:00:00')
    _solid(src / 'green.jpg', (20, 200, 30), '2026:10:23 18:05:00')
    _solid(src / 'blue.jpg', (20, 30, 210), '2026:10:23 18:10:00')
    slug = col.create('colours')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Cam')
    yield src, conn
    embeddings.set_embedder(None)


def test_index_builds_search_vectors_once(colours):
    src, conn = colours
    before = snapshot(src)
    res = analyze_collection(conn)
    assert res['search_index'] == {'embedded': 3, 'failed': 0}
    assert analyze_collection(conn)['search_index'] == {'embedded': 0, 'failed': 0}   # cached by content
    assert snapshot(src) == before


def test_search_ranks_by_meaning(colours):
    src, conn = colours
    analyze_collection(conn)
    res = search_mod.search(conn, 'something green')
    assert [r['filename'] for r in res['results']][0] == 'green.jpg'
    assert res['english'] is None and 'unavailable' in res['translation']


def test_translation_is_used_and_cached(colours, monkeypatch):
    src, conn = colours
    analyze_collection(conn)
    calls = []
    monkeypatch.setattr(vlm, 'status', lambda: {'running': True, 'model_ready': True, 'model': 'x'})
    monkeypatch.setattr(vlm, 'translate_to_english', lambda q: calls.append(q) or 'blue sky')
    res = search_mod.search(conn, 'modro nebo')
    assert res['english'] == 'blue sky' and res['results'][0]['filename'] == 'blue.jpg'
    search_mod.search(conn, 'modro nebo')
    assert calls == ['modro nebo']                                   # second time from cache


def test_tag_match_boost_is_labelled(colours):
    src, conn = colours
    analyze_collection(conn)
    sha = conn.execute("SELECT sha256 FROM assets WHERE filename = 'red.jpg'").fetchone()[0]
    with conn:
        conn.execute("INSERT INTO ai_annotations (sha256, model, prompt_version, description, tags_json, created_at) "
                     "VALUES (?, 'm', 'p1', 'a lighthouse', '[\"lighthouse\"]', 'now')", (sha,))
    res = search_mod.search(conn, 'lighthouse')
    top = res['results'][0]
    assert top['filename'] == 'red.jpg' and top['tag_match'] is True


def test_clean_removes_junk_and_place_markers():
    out = vlm.clean({'description': '  a  stone tower ', 'tags': ['Bell', 'bell', 'text_visible: empty', '', 'x' * 50],
                     'people': '2', 'text_visible': 'empty'})
    assert out == {'description': 'A stone tower.', 'tags': ['bell'], 'people': 2, 'text_visible': ''}
    assert vlm.tidy_description('a light building with arches. no people visible. text visible is empty.') == \
        'A light building with arches.'
    assert vlm.tidy_description('a path to an urn; no people visible; no readable text.') == 'A path to an urn.'


def test_describe_collection_skips_duplicates_and_caches(colours, monkeypatch, tmp_path):
    src, conn = colours
    (src / 'red_copy.jpg').write_bytes((src / 'red.jpg').read_bytes())     # exact duplicate
    analyze_collection(conn)
    monkeypatch.setattr(vlm, 'ensure_running', lambda: None)
    monkeypatch.setattr(vlm, 'status', lambda: {'running': True, 'model_ready': True, 'model': vlm.VLM_MODEL})
    seen = []

    def fake_describe(path):
        seen.append(path.rsplit('/', 1)[-1])
        if path.endswith('blue.jpg'):
            raise ValueError('decode failed')
        return vlm.clean({'description': 'a plain colour', 'tags': ['colour'], 'people': 0, 'text_visible': ''})

    monkeypatch.setattr(vlm, 'describe', fake_describe)
    res = vlm.describe_collection(conn)

    assert res == {'described': 2, 'failed': 1, 'remaining': 0}
    assert 'red_copy.jpg' not in seen and len(seen) == 3                    # one copy of the exact pair
    seen.clear()
    res = vlm.describe_collection(conn)                                       # only the failed one is retried
    assert seen == ['blue.jpg'] and res['failed'] == 1
    from app.timeline.timeline_engine import timeline
    items = {i['filename']: i for i in timeline(conn)['items']}
    assert items['green.jpg']['ai']['description'] == 'A plain colour.'
    assert items['blue.jpg']['ai'] is None                                    # errors are not shown as descriptions


def test_search_api_without_model(pc, client, H, tmp_path, monkeypatch):
    embeddings.set_embedder(None)
    monkeypatch.setattr(embeddings, 'Embedder', lambda: (_ for _ in ()).throw(embeddings.ModelUnavailable('not downloaded')))
    cid = client.post('/api/collections', json={'name': 'nomodel'}, headers=H).get_json()['id']
    r = client.get(f'/api/collections/{cid}/search', query_string={'q': 'red'}, headers=H)
    assert r.status_code == 503 and 'not downloaded' in r.get_json()['error']
    s = client.get('/api/ai/status', headers=H).get_json()
    assert 'vlm' in s and 'search_ready' in s


def test_describe_retries_cut_off_json(monkeypatch, tmp_path):
    from conftest import textured_scene
    p = textured_scene(tmp_path / 'x.jpg', seed=5)
    answers = iter(['{"description": "a tower", "tags": ["tower", "tower", "tow',      # cut off
                    '{"description": "a tower", "tags": ["tower"], "people": 0, "text_visible": ""}'])
    sent = []
    monkeypatch.setattr(vlm, '_post', lambda path, body, timeout=300: sent.append(body['options']) or
                        {'response': next(answers)})
    assert vlm.describe(str(p))['description'] == 'A tower.'
    assert sent[1].get('repeat_penalty') == 1.3


def test_empty_answer_is_an_error_not_a_description(monkeypatch, tmp_path):
    from conftest import textured_scene
    p = textured_scene(tmp_path / 'y.jpg', seed=6)
    monkeypatch.setattr(vlm, '_post', lambda path, body, timeout=300:
                        {'response': '', 'thinking': 'Got it, ...', 'done_reason': 'length'})
    with pytest.raises(ValueError, match='empty answer'):
        vlm.describe(str(p))

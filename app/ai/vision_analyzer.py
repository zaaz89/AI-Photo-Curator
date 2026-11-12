"""Descriptions and tags from a local vision-language model served by Ollama.

Only a downscaled JPEG copy (max 768 px, in memory) is sent, and only to the
Ollama server on 127.0.0.1. The prompt forbids naming places, buildings,
people or events (brief section 6.2): descriptions stay generic unless real
evidence is added in a later milestone. Results are cached per file content,
model and prompt version, and are labelled as unverified AI output.
"""
from __future__ import annotations

import base64
import io
import json
import re
import subprocess
import time
import urllib.error
import urllib.request
from typing import Callable, Optional

from app.ai.models import OLLAMA_SCRIPT, OLLAMA_URL, VLM_MODEL
from app.collections import now_iso

PROMPT_VERSION = 'p1'
PROMPT = ('Describe this photo for a private travel photo archive. Rules: describe only what is visible; '
          'do not name any city, region, country, building, landmark, person or event, even if you think '
          'you recognise it; one or two plain sentences; 3 to 8 short lowercase tags; people = number of '
          'people visible; text_visible = readable text in the image, or an empty string.')
SCHEMA = {'type': 'object', 'properties': {
    'description': {'type': 'string'},
    'tags': {'type': 'array', 'items': {'type': 'string'}},
    'people': {'type': 'integer'},
    'text_visible': {'type': 'string'}},
    'required': ['description', 'tags', 'people', 'text_visible']}


class OllamaUnavailable(RuntimeError):
    pass


def _post(path: str, body: dict, timeout: float = 300) -> dict:
    req = urllib.request.Request(OLLAMA_URL + path, json.dumps(body).encode(),
                                 {'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def _get(path: str, timeout: float = 3) -> dict:
    with urllib.request.urlopen(OLLAMA_URL + path, timeout=timeout) as r:
        return json.load(r)


def status() -> dict:
    try:
        tags = _get('/api/tags')
    except Exception:
        return {'running': False, 'model_ready': False, 'model': VLM_MODEL}
    names = {m.get('name') for m in tags.get('models', [])}
    return {'running': True, 'model_ready': VLM_MODEL in names, 'model': VLM_MODEL}


def ensure_running(wait_s: float = 20) -> None:
    """Start the project-local Ollama server (scripts/ollama-serve.sh) if needed."""
    if status()['running']:
        return
    if not OLLAMA_SCRIPT.exists():
        raise OllamaUnavailable('scripts/ollama-serve.sh is missing')
    try:
        subprocess.Popen([str(OLLAMA_SCRIPT)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError as e:
        raise OllamaUnavailable(f'could not start Ollama: {e}. Install it with: brew install ollama')
    t0 = time.time()
    while time.time() - t0 < wait_s:
        if status()['running']:
            return
        time.sleep(0.5)
    raise OllamaUnavailable('Ollama did not start; run scripts/ollama-serve.sh and check its output')


def _jpeg_b64(path: str) -> Optional[str]:
    from app.ai.embeddings import load_image
    im = load_image(path, side=1024)
    if im is None:
        return None
    im.thumbnail((768, 768))
    buf = io.BytesIO()
    im.save(buf, 'JPEG', quality=85)
    return base64.b64encode(buf.getvalue()).decode()


_ECHO = re.compile(r'(no (people|person|humans?) (are )?visible|text[ _]visible|no (readable|visible) text|'
                   r'readable text)', re.I)


def tidy_description(desc: str) -> str:
    """Drop sentences that only echo the prompt's fields (people count, visible text)."""
    desc = re.sub(r'\s+', ' ', str(desc or '')).strip()
    parts = re.split(r'(?<=[.;])\s+', desc)
    kept = [p for p in parts if not _ECHO.search(p)]
    out = ' '.join(kept).strip().rstrip(';').strip()
    if out and out[-1] not in '.!?':
        out += '.'
    return out[:1].upper() + out[1:] if out else ''


def clean(raw: dict) -> dict:
    """Normalise model output: drop junk tags and empty markers, tidy the description."""
    desc = tidy_description(raw.get('description'))
    tags, seen = [], set()
    for t in raw.get('tags') or []:
        t = re.sub(r'\s+', ' ', str(t)).strip().lower()
        if not t or ':' in t or len(t) > 40 or t in seen:
            continue
        seen.add(t)
        tags.append(t)
    text = str(raw.get('text_visible') or '').strip()
    if text.lower() in ('empty', 'none', 'n/a', '""', "''", 'no text'):
        text = ''
    try:
        people = max(0, int(raw.get('people')))
    except (TypeError, ValueError):
        people = None
    return {'description': desc, 'tags': tags[:8], 'people': people, 'text_visible': text}


def describe(path: str) -> dict:
    img = _jpeg_b64(path)
    if img is None:
        raise ValueError('image could not be decoded')
    r = _post('/api/generate', {'model': VLM_MODEL, 'prompt': PROMPT, 'images': [img], 'format': SCHEMA,
                                'stream': False, 'think': False, 'keep_alive': '2m',
                                # Cap the answer: the model sometimes keeps listing tags for 1,000+ tokens.
                                'options': {'temperature': 0, 'num_predict': 320}})
    return clean(json.loads(r.get('response') or '{}'))


def translate_to_english(text: str) -> str:
    r = _post('/api/generate', {
        'model': VLM_MODEL, 'stream': False, 'think': False, 'keep_alive': '2m',
        'options': {'temperature': 0},
        'prompt': ('Translate this photo search query into short natural English. If it is already English, '
                   'repeat it unchanged. Answer with the query only, no quotes.\n\nQuery: ' + text)}, timeout=12)
    out = (r.get('response') or '').strip().strip('"\'').splitlines()
    return out[0].strip() if out else text


def describe_collection(conn, progress: Optional[Callable] = None,
                        cancelled: Callable[[], bool] = lambda: False, limit: Optional[int] = None) -> dict:
    """Describe present images that are not marked as non-keeper duplicates and
    have no description for this model + prompt version yet."""
    ensure_running()
    if not status()['model_ready']:
        raise OllamaUnavailable(f'model {VLM_MODEL} is not downloaded; run scripts/download-models.sh')
    rows = conn.execute(
        "SELECT a.sha256, MIN(s.path || '/' || a.rel_path) AS path, MIN(c.sort_key) AS t FROM assets a "
        'JOIN sources s ON s.id = a.source_id LEFT JOIN capture_time c ON c.asset_id = a.id '
        "WHERE a.status = 'present' AND a.kind = 'image' AND a.sha256 != '' "
        'AND a.id NOT IN (SELECT m.asset_id FROM duplicate_members m JOIN duplicate_groups g ON g.id = m.group_id '
        "                 WHERE g.category IN ('exact', 'near') AND g.keeper_id IS NOT NULL AND g.keeper_id != m.asset_id) "
        'AND a.sha256 NOT IN (SELECT sha256 FROM ai_annotations WHERE model = ? AND prompt_version = ? AND error IS NULL) '
        'GROUP BY a.sha256 ORDER BY t', (VLM_MODEL, PROMPT_VERSION)).fetchall()
    if limit:
        rows = rows[:limit]
    from app.ai.throttle import Throttle
    throttle = Throttle(cancelled, status=(lambda m: progress(m, 0, 0)) if progress else None)
    done = failed = 0
    t0 = time.time()
    try:
        for i, r in enumerate(rows):
            if cancelled():
                break
            if progress:
                eta = ((time.time() - t0) / i * (len(rows) - i)) if i else 0
                lim = f', limited to {throttle.share} % GPU time' if throttle.share < 100 else ''
                progress(f'Describing photos (about {eta / 60:.0f} min left{lim})' if i
                         else f'Describing photos{lim}', i, len(rows))
            busy = time.time()
            try:
                res, err = describe(r['path']), None
                done += 1
            except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError) as e:
                res, err = {'description': None, 'tags': [], 'people': None, 'text_visible': None}, str(e)
                failed += 1
            busy = time.time() - busy
            with conn:
                conn.execute('INSERT OR REPLACE INTO ai_annotations (sha256, model, prompt_version, description, '
                             'tags_json, people, text_visible, error, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                             (r['sha256'], VLM_MODEL, PROMPT_VERSION, res['description'],
                              json.dumps(res['tags'], ensure_ascii=False), res['people'], res['text_visible'],
                              err, now_iso()))
            if i < len(rows) - 1:
                throttle.after_work(busy)
    finally:
        unload()
    return {'described': done, 'failed': failed, 'remaining': len(rows) - done - failed}


def unload() -> None:
    """Free the model's memory right away instead of after Ollama's idle timeout."""
    try:
        _post('/api/generate', {'model': VLM_MODEL, 'keep_alive': 0}, timeout=10)
    except Exception:
        pass

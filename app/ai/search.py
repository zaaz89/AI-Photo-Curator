"""Semantic photo search: text query -> ranked photos.

Score = SigLIP 2 similarity between the query and each photo. Non-English
queries are also translated to English by the local VLM (cached), because the
model ranks English text more reliably (measured on the owner's photos); the
better of the two scores counts. A word that appears in the photo's AI tags
or description adds a small, labelled boost; a word that matches the GPS place
(e.g. "Florence", "Tuscany") adds a larger one.
"""
from __future__ import annotations

import json
import re

import numpy as np

from app.ai import vision_analyzer as vlm
from app.ai.embeddings import get_embedder, load_matrix
from app.ai.models import VLM_MODEL

TAG_BOOST = 0.02
PLACE_BOOST = 0.10


def _english_variant(conn, query: str) -> tuple[str | None, str]:
    q = query.strip()
    row = conn.execute('SELECT english FROM query_translations WHERE query = ?', (q.lower(),)).fetchone()
    if row:
        return (row['english'] if row['english'].lower() != q.lower() else None), 'cached'
    try:
        if not vlm.status()['model_ready']:
            return None, 'translation unavailable (local AI not running)'
        en = vlm.translate_to_english(q)
    except Exception as e:
        busy = 'timed out' in str(e).lower()
        return None, ('translation skipped: the local AI is busy (for example describing photos)' if busy
                      else f'translation failed: {e}')
    with conn:
        conn.execute('INSERT OR REPLACE INTO query_translations (query, english, model) VALUES (?, ?, ?)',
                     (q.lower(), en, VLM_MODEL))
    return (en if en.lower() != q.lower() else None), 'translated'


def search(conn, query: str, limit: int = 60, translate: bool = True) -> dict:
    query = (query or '').strip()
    if not query:
        return {'query': query, 'results': [], 'note': 'empty query'}
    emb = get_embedder()
    shas, mat = load_matrix(conn, emb.name)
    if not shas:
        return {'query': query, 'results': [], 'note': 'no search index yet: index photos first'}
    variants = [query]
    english, tnote = _english_variant(conn, query) if translate else (None, 'off')
    if english:
        variants.append(english)
    qv = emb.texts(variants)
    scores = (qv @ mat.T).max(axis=0)

    words = {w for v in variants for w in re.findall(r'\w{3,}', v.lower())}
    ann = {r['sha256']: r for r in conn.execute(
        'SELECT sha256, description, tags_json FROM ai_annotations WHERE error IS NULL')}
    place_text = {}
    for r in conn.execute("SELECT a.sha256, p.label, p.region, p.country, p.aliases FROM places p "
                          "JOIN assets a ON a.id = p.asset_id WHERE a.status = 'present'"):
        place_text[r['sha256']] = ' '.join(x for x in (r['label'], r['region'], r['country'], r['aliases']) if x).lower()
    boosted = np.zeros(len(shas), np.float32)
    place_hit = np.zeros(len(shas), bool)
    for i, s in enumerate(shas):
        if not words:
            break
        a = ann.get(s)
        if a:
            text = (a['description'] or '').lower() + ' ' + ' '.join(json.loads(a['tags_json'] or '[]'))
            if any(w in text for w in words):
                boosted[i] += TAG_BOOST
        if any(w in place_text.get(s, '') for w in words):
            boosted[i] += PLACE_BOOST            # GPS place name: a fact, so a larger boost
            place_hit[i] = True
    final = scores + boosted
    order = np.argsort(-final)[:limit]

    by_sha = {}
    for r in conn.execute(
            "SELECT a.id, a.sha256, a.filename, s.owner, s.path || '/' || a.rel_path AS path, c.local_time "
            'FROM assets a JOIN sources s ON s.id = a.source_id LEFT JOIN capture_time c ON c.asset_id = a.id '
            "WHERE a.status = 'present' ORDER BY a.source_id, a.rel_path"):
        by_sha.setdefault(r['sha256'], r)
    results = []
    for i in order:
        r = by_sha.get(shas[i])
        if r is None:
            continue
        results.append({'id': r['id'], 'filename': r['filename'], 'owner': r['owner'], 'path': r['path'],
                        'local_time': r['local_time'], 'score': round(float(final[i]), 4),
                        'tag_match': bool(boosted[i]) and not place_hit[i], 'place_match': bool(place_hit[i])})
    return {'query': query, 'english': english, 'translation': tnote, 'model': emb.name, 'results': results}

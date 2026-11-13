"""The owner's own description of a photo (M9). Stored by content (sha256), so it survives re-indexing,
and it wins over the AI text everywhere a description is read. Needs no AI model."""
from __future__ import annotations

import re

from app.collections import now_iso

MAX_LEN = 1000


def owner_descriptions(conn) -> dict:
    """sha256 -> the owner's text."""
    return {r['sha256']: r['text'] for r in conn.execute('SELECT sha256, text FROM owner_descriptions')}


def set_owner_description(conn, asset_id: int, text) -> str | None:
    """Set (or, for empty text, remove) the description of the photo's content. Returns the stored text or None."""
    if not isinstance(text, str):
        raise ValueError('text must be a string')
    row = conn.execute('SELECT sha256 FROM assets WHERE id = ?', (asset_id,)).fetchone()
    if not row or not row['sha256']:
        raise LookupError('unknown photo')
    text = re.sub(r'\s+', ' ', text).strip()
    if len(text) > MAX_LEN:
        raise ValueError(f'the description is longer than {MAX_LEN} characters')
    with conn:
        if text:
            conn.execute('INSERT OR REPLACE INTO owner_descriptions (sha256, text, updated_at) VALUES (?, ?, ?)',
                         (row['sha256'], text, now_iso()))
        else:
            conn.execute('DELETE FROM owner_descriptions WHERE sha256 = ?', (row['sha256'],))
    return text or None

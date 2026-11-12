"""Collections: one folder per collection under <data dir>/collections/<slug>/."""
from __future__ import annotations

import os
import re
import sqlite3
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

from app.database.db import connect

REPO = Path(__file__).resolve().parents[1]


def data_dir() -> Path:
    return Path(os.environ.get('PHOTOCURATOR_DATA_DIR', REPO / 'local-data'))


def collections_dir() -> Path:
    return data_dir() / 'collections'


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')


def slugify(name: str) -> str:
    s = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    s = re.sub(r'[^A-Za-z0-9]+', '-', s).strip('-').lower()
    return s or 'collection'


def db_path(slug: str) -> Path:
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]*', slug or ''):
        raise ValueError('invalid collection id')
    return collections_dir() / slug / 'curator.db'


def create(name: str, timezone_name: str | None = None) -> str:
    name = (name or '').strip()
    if not name:
        raise ValueError('collection name is required')
    base = slugify(name)
    slug, n = base, 2
    while (collections_dir() / slug).exists():
        slug, n = f'{base}-{n}', n + 1
    conn = connect(db_path(slug))
    with conn:
        conn.execute('INSERT INTO collection (id, name, timezone, created_at) VALUES (1, ?, ?, ?)',
                     (name, timezone_name, now_iso()))
    conn.close()
    return slug


def open_db(slug: str) -> sqlite3.Connection:
    path = db_path(slug)
    if not path.exists():
        raise FileNotFoundError(f'collection {slug} not found')
    return connect(path)


def list_all() -> list[dict]:
    out = []
    root = collections_dir()
    if not root.is_dir():
        return out
    for d in sorted(root.iterdir()):
        db = d / 'curator.db'
        if not db.exists():
            continue
        conn = connect(db)
        row = conn.execute('SELECT name, created_at FROM collection WHERE id = 1').fetchone()
        n = conn.execute("SELECT COUNT(*) FROM assets WHERE status = 'present'").fetchone()[0]
        conn.close()
        if row:
            out.append({'id': d.name, 'name': row['name'], 'created_at': row['created_at'], 'assets': n})
    return out


def add_source(conn: sqlite3.Connection, path: str, owner: str, label: str | None = None) -> int:
    real = os.path.realpath(os.path.expanduser(path))
    if not os.path.isdir(real):
        raise ValueError(f'not a folder: {path}')
    if not (owner or '').strip():
        raise ValueError('owner is required')
    data = os.path.realpath(data_dir())
    if real == data or real.startswith(data + os.sep) or data.startswith(real + os.sep):
        raise ValueError('a source folder cannot contain or be inside the app data folder')
    for row in conn.execute('SELECT path FROM sources'):
        other = row['path']
        if real != other and (real.startswith(other + os.sep) or other.startswith(real + os.sep)):
            raise ValueError(f'overlaps with an existing source: {other}')
    with conn:
        cur = conn.execute(
            'INSERT INTO sources (path, owner, label, added_at) VALUES (?, ?, ?, ?) '
            'ON CONFLICT(path) DO UPDATE SET owner = excluded.owner, label = excluded.label',
            (real, owner.strip(), (label or '').strip() or None, now_iso()))
    return conn.execute('SELECT id FROM sources WHERE path = ?', (real,)).fetchone()[0]


def all_source_paths() -> list[str]:
    """Every source folder of every collection (used as the read whitelist)."""
    paths = []
    root = collections_dir()
    if not root.is_dir():
        return paths
    for d in root.iterdir():
        db = d / 'curator.db'
        if db.exists():
            conn = connect(db)
            paths += [r['path'] for r in conn.execute('SELECT path FROM sources')]
            conn.close()
    return paths

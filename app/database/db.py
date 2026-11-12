"""SQLite storage for one collection.

Each collection lives in its own folder under local-data/collections/<slug>/
with a single curator.db. Schema changes are applied as numbered migrations
tracked in PRAGMA user_version, so old databases upgrade in place.

Original metadata (metadata_raw) and derived values (capture_time, assets
columns filled by the resolver) are stored separately (brief section 14).
"""
from __future__ import annotations

import sqlite3
from pathlib import Path

MIGRATIONS = [
    # 1: initial schema
    """
    CREATE TABLE collection (
        id          INTEGER PRIMARY KEY CHECK (id = 1),
        name        TEXT NOT NULL,
        timezone    TEXT,                 -- optional IANA zone, used only as a labelled assumption
        created_at  TEXT NOT NULL
    );
    CREATE TABLE sources (
        id              INTEGER PRIMARY KEY,
        path            TEXT NOT NULL UNIQUE,  -- resolved absolute folder path
        owner           TEXT NOT NULL,         -- user-editable person name
        label           TEXT,
        added_at        TEXT NOT NULL,
        last_indexed_at TEXT
    );
    CREATE TABLE assets (
        id          INTEGER PRIMARY KEY,
        source_id   INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        rel_path    TEXT NOT NULL,             -- path relative to the source folder
        filename    TEXT NOT NULL,
        ext         TEXT NOT NULL,
        kind        TEXT NOT NULL,             -- image | video
        size        INTEGER NOT NULL,
        mtime       REAL NOT NULL,
        sha256      TEXT NOT NULL,
        status      TEXT NOT NULL DEFAULT 'present',   -- present | missing
        make        TEXT,
        model       TEXT,
        lens        TEXT,
        width       INTEGER,
        height      INTEGER,
        gps_lat     REAL,
        gps_lon     REAL,
        indexed_at  TEXT NOT NULL,
        error       TEXT,
        UNIQUE (source_id, rel_path)
    );
    CREATE INDEX assets_sha ON assets(sha256);
    CREATE TABLE metadata_raw (
        asset_id    INTEGER PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
        reader      TEXT NOT NULL,             -- e.g. "exiftool 13.55" or "pillow"
        tags_json   TEXT NOT NULL              -- original values, untouched
    );
    CREATE TABLE capture_time (
        asset_id        INTEGER PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
        local_time      TEXT,                  -- wall clock as recorded, ISO, no offset
        utc_time        TEXT,                  -- ISO with Z, NULL when the offset is unknown
        offset_minutes  INTEGER,
        rule            TEXT NOT NULL,         -- which rule produced it
        confidence      TEXT NOT NULL,         -- high | medium | low | unknown
        notes_json      TEXT NOT NULL,         -- assumptions and evidence
        sort_key        REAL NOT NULL          -- seconds; UTC when known
    );
    CREATE INDEX capture_sort ON capture_time(sort_key);
    CREATE TABLE relationships (
        id       INTEGER PRIMARY KEY,
        kind     TEXT NOT NULL,                -- live_photo | raw_jpeg
        asset_a  INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        asset_b  INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        evidence TEXT NOT NULL,
        UNIQUE (kind, asset_a, asset_b)
    );
    """,
]


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), timeout=30, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA foreign_keys = ON')
    conn.execute('PRAGMA journal_mode = WAL')
    migrate(conn)
    return conn


def migrate(conn: sqlite3.Connection) -> int:
    version = conn.execute('PRAGMA user_version').fetchone()[0]
    for i, sql in enumerate(MIGRATIONS[version:], start=version + 1):
        with conn:
            conn.executescript(sql)
            conn.execute(f'PRAGMA user_version = {i}')
    return conn.execute('PRAGMA user_version').fetchone()[0]

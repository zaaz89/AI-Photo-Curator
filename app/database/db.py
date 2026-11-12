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
    # 2: visual features, duplicate groups, device clocks and corrections (M2)
    """
    CREATE TABLE visual_features (
        sha256      TEXT PRIMARY KEY,         -- keyed by content, shared by exact copies
        sig         BLOB NOT NULL,            -- 192-bit perceptual signature (aHash + dHash h/v)
        sharpness   REAL NOT NULL,            -- Laplacian variance / image variance
        computed_at TEXT NOT NULL
    );
    CREATE TABLE duplicate_groups (
        id           INTEGER PRIMARY KEY,
        group_key    TEXT NOT NULL UNIQUE,    -- sorted member sha256s, stable across runs
        category     TEXT NOT NULL,           -- exact | near | similar_scene
        keeper_id    INTEGER REFERENCES assets(id) ON DELETE SET NULL,  -- recommended
        reasons_json TEXT NOT NULL
    );
    CREATE TABLE duplicate_members (
        group_id  INTEGER NOT NULL REFERENCES duplicate_groups(id) ON DELETE CASCADE,
        asset_id  INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        score     REAL,
        PRIMARY KEY (group_id, asset_id)
    );
    CREATE TABLE keeper_choices (             -- the owner's override, survives re-analysis
        group_key  TEXT PRIMARY KEY,
        sha256     TEXT NOT NULL,             -- chosen file, by content
        decided_at TEXT NOT NULL
    );
    CREATE TABLE clocks (
        id        INTEGER PRIMARY KEY,
        source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        make      TEXT NOT NULL DEFAULT '',
        model     TEXT NOT NULL DEFAULT '',
        UNIQUE (source_id, make, model)
    );
    CREATE TABLE clock_corrections (
        clock_id      INTEGER PRIMARY KEY REFERENCES clocks(id) ON DELETE CASCADE,
        suggested_s   REAL,                   -- latest suggestion (NULL = none)
        confidence    TEXT,
        method        TEXT,
        evidence_json TEXT NOT NULL DEFAULT '{}',
        applied_s     REAL NOT NULL DEFAULT 0, -- what the timeline uses; 0 = no correction
        status        TEXT NOT NULL DEFAULT 'none',  -- none | suggested | conflicting | accepted | manual | rejected
        updated_at    TEXT NOT NULL
    );
    """,
    # 3: local AI (M3): image embeddings for search, VLM descriptions and tags
    """
    CREATE TABLE image_embeddings (
        sha256      TEXT NOT NULL,
        model       TEXT NOT NULL,
        vec         BLOB NOT NULL,            -- float16, L2-normalised
        computed_at TEXT NOT NULL,
        PRIMARY KEY (sha256, model)
    );
    CREATE TABLE ai_annotations (
        sha256         TEXT NOT NULL,
        model          TEXT NOT NULL,         -- e.g. qwen3-vl:4b
        prompt_version TEXT NOT NULL,
        description    TEXT,
        tags_json      TEXT NOT NULL DEFAULT '[]',
        people         INTEGER,
        text_visible   TEXT,
        error          TEXT,
        created_at     TEXT NOT NULL,
        PRIMARY KEY (sha256, model, prompt_version)
    );
    CREATE TABLE query_translations (
        query       TEXT PRIMARY KEY,
        english     TEXT NOT NULL,
        model       TEXT NOT NULL
    );
    """,
    # 4: places from GPS and events (M4)
    """
    CREATE TABLE places (
        asset_id    INTEGER PRIMARY KEY REFERENCES assets(id) ON DELETE CASCADE,
        name        TEXT,                     -- NULL when only the region is known
        label       TEXT NOT NULL,            -- what the UI shows, e.g. "near Pienza"
        precision   TEXT NOT NULL,            -- in | near | region
        distance_km REAL NOT NULL,
        region      TEXT,
        country     TEXT,
        source      TEXT NOT NULL             -- e.g. "gps + geonames cities500"
    );
    CREATE TABLE events (
        id          INTEGER PRIMARY KEY,
        day         TEXT NOT NULL,            -- local date YYYY-MM-DD
        start_key   REAL NOT NULL,            -- sort key of the first photo
        end_key     REAL NOT NULL,
        name        TEXT NOT NULL,
        name_source TEXT NOT NULL,            -- auto | user
        place_label TEXT,
        locked      INTEGER NOT NULL DEFAULT 0  -- 1 = the owner edited this day; keep it on re-analysis
    );
    CREATE INDEX events_day ON events(day);
    CREATE TABLE event_members (
        event_id INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
        asset_id INTEGER NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
        PRIMARY KEY (asset_id)
    );
    """,
    # 5: other names of a place (e.g. Firence, Firenze) so search works in any language
    "ALTER TABLE places ADD COLUMN aliases TEXT;",
    # 6: focus and ranking scores (moved from the upstream cull/rank steps) and the owner's marks
    """
    CREATE TABLE quality (
        sha256           TEXT PRIMARY KEY,
        region_sharpness REAL NOT NULL,
        quick_quality    REAL NOT NULL,
        scores_json      TEXT NOT NULL,       -- composition, technical, sharpness, color, aesthetic + sub-scores
        computed_at      TEXT NOT NULL
    );
    CREATE TABLE marks (                      -- by content, so they survive re-indexing; never move files
        sha256     TEXT PRIMARY KEY,
        focus      TEXT,                      -- owner's override: sharp | soft | blurry
        wallpaper  INTEGER NOT NULL DEFAULT 0, -- flagged as phone wallpaper
        excluded   INTEGER NOT NULL DEFAULT 0, -- removed from Best photos
        updated_at TEXT NOT NULL
    );
    """,
    # 7: face quality (Apple Vision, no identities), video metadata, favourite / reject marks
    """
    CREATE TABLE faces (
        sha256      TEXT PRIMARY KEY,
        n_faces     INTEGER NOT NULL,
        faces_json  TEXT NOT NULL,            -- quality, yaw/roll/pitch, eye openness, box; no identity
        computed_at TEXT NOT NULL
    );
    CREATE TABLE video_meta (
        sha256      TEXT PRIMARY KEY,
        duration    REAL,
        width       INTEGER,
        height      INTEGER,
        created     TEXT,
        thumb       TEXT,                     -- poster frame in local-data/cache/video-thumbs
        error       TEXT,
        computed_at TEXT NOT NULL
    );
    ALTER TABLE marks ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE marks ADD COLUMN rejected INTEGER NOT NULL DEFAULT 0;
    """,
    # 8: the trip checklist (which steps the owner marked done)
    """
    CREATE TABLE workflow (
        step       TEXT PRIMARY KEY,
        done       INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
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

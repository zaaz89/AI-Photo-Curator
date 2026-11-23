"""Screenshots (M12, owner's decision 2026-11-19: they leave the album by themselves).

A photo is a screenshot when
  - its EXIF UserComment is "Screenshot" (iPhone writes this itself; checked with ExifTool on the owner's
    screenshots: PNG, no Make), or
  - it has no camera Make and its file name is a screenshot name (Screenshot..., Posnetek zaslona...).
Apple's "utility" flag is not used here: it also catches camera photos of receipts, menus or a market stall,
which stay in "Have a look". Nothing is ever moved or changed: a screenshot is only left out of the album
export (and can be put back with "keep"); the archive export still copies it.
"""
from __future__ import annotations

import json
import re
import unicodedata
from typing import Optional

MARK = 'screenshot'
NAME = re.compile(
    r'^(screenshot|screen shot|posnetek zaslona|bildschirmfoto|capture d.?(e|é)cran|schermata|'
    r'captura de pantalla|zrzut ekranu|snímek obrazovky|snimka zaslona|snimak ekrana)',
    re.IGNORECASE)


def is_screenshot(user_comment: Optional[str], filename: str, make: Optional[str]) -> Optional[str]:
    """The reason ('mark' or 'filename') when the file is a screenshot, else None."""
    if user_comment and str(user_comment).strip('\x00 ').lower() == MARK:
        return 'mark'
    if make and str(make).strip():
        return None                      # a camera wrote this file
    name = unicodedata.normalize('NFC', filename or '').strip()
    return 'filename' if NAME.match(name) else None


def _comment(tags: dict) -> tuple[bool, Optional[str]]:
    """(tag was read, value). Albums indexed before UserComment was in TAGS have no such key at all."""
    for k, v in tags.items():
        if k.split(':', 1)[-1] == 'UserComment':
            return True, (str(v) if v is not None else None)
    return False, None


def detect(conn, read=None) -> dict:
    """Check every present image that has no verdict yet. Camera photos (with a Make) are settled without
    reading anything; make-less images from older albums are read again with ExifTool for UserComment only.
    `read` is injectable for tests: read(paths) -> {path: tags}."""
    rows = conn.execute(
        "SELECT a.id, a.filename, a.make, a.kind, s.path || '/' || a.rel_path AS path, m.tags_json "
        'FROM assets a JOIN sources s ON s.id = a.source_id '
        'LEFT JOIN metadata_raw m ON m.asset_id = a.id '
        'LEFT JOIN screenshot_checks sc ON sc.asset_id = a.id '
        "WHERE a.status = 'present' AND sc.asset_id IS NULL").fetchall()
    verdicts, reread = {}, {}
    for r in rows:
        if r['kind'] != 'image' or (r['make'] and str(r['make']).strip()):
            verdicts[r['id']] = None
            continue
        seen, comment = _comment(json.loads(r['tags_json'] or '{}'))
        if seen:
            verdicts[r['id']] = is_screenshot(comment, r['filename'], r['make'])
        else:
            reread[r['path']] = r
    if reread:
        if read is None:
            from app.metadata.exif_reader import read_metadata
            read = lambda paths: read_metadata(paths)[0]      # noqa: E731
        found = read(list(reread))
        for path, r in reread.items():
            _, comment = _comment(found.get(path) or {})
            verdicts[r['id']] = is_screenshot(comment, r['filename'], r['make'])
    with conn:
        conn.executemany('INSERT OR REPLACE INTO screenshot_checks (asset_id, screenshot, reason) VALUES (?, ?, ?)',
                         [(i, 1 if v else 0, v) for i, v in verdicts.items()])
    return {'checked': len(verdicts), 'screenshots': sum(1 for v in verdicts.values() if v),
            'read_again': len(reread)}


def screenshot_ids(conn) -> set:
    return {r[0] for r in conn.execute(
        "SELECT sc.asset_id FROM screenshot_checks sc JOIN assets a ON a.id = sc.asset_id "
        "WHERE sc.screenshot = 1 AND a.status = 'present'")}

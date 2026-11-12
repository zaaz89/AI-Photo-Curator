#!/usr/bin/env python3
"""
AI Photo Curator: local web app (Flask) on 127.0.0.1.

Forked from kotyzap/Photo-Curator v7.0 (MIT). The upstream single-folder
Cull / Dedup / Rank page was replaced in M6 by one app over collections
(app/web/templates/app.html); its focus and ranking logic now lives in
app/quality/scoring.py. This file keeps the server, the request guard, the
security headers and the read-only file endpoints (thumbnails, images, EXIF).

Rule: source folders are read-only. App data lives in local-data/; exports
are verified copies in a destination the owner chooses.
"""

import os
import sys
import json
import time
import hashlib
import logging
import subprocess
import threading
from pathlib import Path

from flask import Flask, request, jsonify, send_file, abort, redirect, render_template
from PIL import Image, ImageOps

from raw_loader import (RAW_EXTS, HAS_RAWPY, HEIF_EXTS, HAS_HEIF, needs_jpeg_preview, open_image_pil)
from app.collections import all_source_paths
from app.web import timeline_bp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# macOS reserves port 5000 for the AirPlay Receiver (returns HTTP 403).
# Default to 5014 ('50mm f/1.4'). Override with PHOTOCURATOR_PORT if needed.
PORT = int(os.environ.get('PHOTOCURATOR_PORT', '5014'))

# Host headers we accept. A DNS-rebinding attacker's page reaches us with the
# attacker's domain in the Host header, not one of these, so it's rejected.
_ALLOWED_HOSTS = {f'127.0.0.1:{PORT}', f'localhost:{PORT}', '127.0.0.1', 'localhost'}


@app.before_request
def _guard_request():
    """Block requests forged by a malicious web page (DNS rebinding / CSRF):
    the Host must be our loopback address and any Origin must be loopback."""
    host = (request.host or '').lower()
    if host not in _ALLOWED_HOSTS:
        abort(403)
    origin = request.headers.get('Origin')
    if origin:
        from urllib.parse import urlparse
        if urlparse(origin).hostname not in ('127.0.0.1', 'localhost'):
            abort(403)


@app.after_request
def _security_headers(resp):
    resp.headers['X-Content-Type-Options'] = 'nosniff'
    resp.headers['X-Frame-Options'] = 'DENY'
    resp.headers['Referrer-Policy'] = 'no-referrer'
    # Everything is served by this app; nothing is loaded from the internet.
    resp.headers.setdefault(
        'Content-Security-Policy',
        "default-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; "
        "script-src 'self' 'unsafe-inline'; connect-src 'self'")
    return resp


IMG_EXTS = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp', '.webp'}
if HAS_RAWPY:
    IMG_EXTS |= RAW_EXTS
else:
    logger.warning('rawpy is not installed: RAW files will be ignored (pip install rawpy)')
if HAS_HEIF:
    IMG_EXTS |= HEIF_EXTS
else:
    logger.warning('pillow-heif is not installed: HEIC files will be ignored (pip install pillow-heif)')

# All app data (caches, recents) lives in the project's local-data/ folder,
# which git ignores. Nothing is ever written inside a photo (source) folder.
# PHOTOCURATOR_DATA_DIR overrides the location (used by the tests).
DATA_DIR = Path(os.environ.get('PHOTOCURATOR_DATA_DIR', Path(__file__).resolve().parent / 'local-data'))
CACHE_DIR = DATA_DIR / 'cache'
RECENTS_FILE = DATA_DIR / 'recents.json'
THUMB_DIR = CACHE_DIR / 'thumbs'
THUMB_DIR.mkdir(parents=True, exist_ok=True)

state = {'folder': None}      # kept for the read whitelist (recent folders); the app works on collections


# --------------------------------------------------------------------------- #
#  Read whitelist: only files inside a collection source (or a recent folder)
#  are served, so a crafted ?path= cannot read arbitrary files.
# --------------------------------------------------------------------------- #
_coll_roots_cache = {'t': 0.0, 'paths': []}

def _collection_roots():
    """Source folders of all collections (cached for 5 s; thumbnails ask often)."""
    if time.time() - _coll_roots_cache['t'] > 5:
        try:
            _coll_roots_cache['paths'] = all_source_paths()
        except Exception as e:
            logger.warning(f"collection roots: {e}")
        _coll_roots_cache['t'] = time.time()
    return _coll_roots_cache['paths']


def _allowed_roots():
    """Resolved real paths the app is permitted to read from: the current
    folder, recently-used folders and the source folders of collections."""
    roots = []
    cur = state.get('folder')
    if cur:
        roots.append(cur)
    try:
        roots.extend(load_recents())
    except Exception:
        pass
    roots.extend(_collection_roots())
    out = []
    for r in roots:
        try:
            out.append(os.path.realpath(r))
        except Exception:
            continue
    return out


def _safe_image_path(raw):
    """Resolve a user-supplied ?path= to a real file and confirm it is an
    allowed image inside an allowed root. Returns a Path or None.

    realpath() collapses '..' and resolves symlinks, so neither path
    traversal nor a symlink planted in a watched folder can escape."""
    if not raw:
        return None
    try:
        real = os.path.realpath(raw)
    except Exception:
        return None
    p = Path(real)
    if not p.is_file() or p.suffix.lower() not in IMG_EXTS:
        return None
    roots = _allowed_roots()
    if not roots:
        return None
    for root in roots:
        # Match the resolved file against each allowed root. The os.sep guard
        # prevents '/photos-evil' from matching an allowed '/photos'.
        if real == root or real.startswith(root + os.sep):
            return p
    return None


def _thumb_cache_path(image_path):
    p = Path(image_path)
    try:
        mtime = p.stat().st_mtime
    except OSError:
        mtime = 0
    # The trailing version tag invalidates old cached thumbnails when the
    # thumbnail logic changes (v2 = EXIF orientation applied).
    key = hashlib.md5(f"{image_path}:{mtime}:v2".encode()).hexdigest()
    return THUMB_DIR / f"{key}.jpg"


def make_thumb_file(image_path, size=300):
    out = _thumb_cache_path(image_path)
    if out.exists():
        return out
    try:
        img = open_image_pil(image_path)   # RAW-aware (uses embedded preview)
        img.draft('RGB', (size * 2, size * 2))
        # Honor the EXIF orientation flag so portrait photos aren't shown
        # sideways in thumbnails (the full-size view already auto-rotates).
        img = ImageOps.exif_transpose(img)
        img = img.convert('RGB')
        img.thumbnail((size, size), Image.Resampling.BILINEAR)
        img.save(out, format='JPEG', quality=80)
        return out
    except Exception as e:
        logger.warning(f"thumb fail {image_path}: {e}")
        return None


def load_recents():
    try:
        if RECENTS_FILE.exists():
            return json.loads(RECENTS_FILE.read_text())
    except Exception:
        pass
    return []


def save_recent(folder):
    recents = [r for r in load_recents() if r != folder]
    recents.insert(0, folder)
    try:
        RECENTS_FILE.write_text(json.dumps(recents[:8]))
    except Exception as e:
        logger.warning(f"save recents fail: {e}")


def native_folder_dialog(prompt="Select a folder"):
    try:
        # The prompt is passed as an argument, never spliced into the script, so a
        # name with quotes cannot run AppleScript.
        out = subprocess.run(['osascript', '-e', 'on run argv',
                              '-e', 'activate',
                              '-e', 'POSIX path of (choose folder with prompt (item 1 of argv))',
                              '-e', 'end run', str(prompt)],
                             capture_output=True, text=True, timeout=300)
        path = out.stdout.strip()
        if path:
            return path.rstrip('/')
    except Exception as e:
        logger.warning(f"folder dialog fail: {e}")
    return None


@app.route('/api/thumb')
def api_thumb():
    p = _safe_image_path(request.args.get('path', ''))
    if not p:
        abort(404)
    f = make_thumb_file(str(p))
    if not f:
        abort(404)
    resp = send_file(str(f))
    resp.headers['Cache-Control'] = 'public, max-age=86400'
    return resp


def _raw_preview_file(image_path):
    """Browser-displayable JPEG for a RAW or HEIC file (browsers can't render
    CR2/NEF, and only Safari renders HEIC).
    Cached on disk like thumbnails, keyed by path+mtime."""
    try:
        mtime = os.path.getmtime(image_path)
    except OSError:
        return None
    key = hashlib.md5(f"{image_path}:{mtime}:preview-v1".encode()).hexdigest()
    out = THUMB_DIR / f"{key}_full.jpg"
    if out.exists():
        return out
    try:
        img = open_image_pil(image_path)
        img = ImageOps.exif_transpose(img).convert('RGB')
        img.save(out, format='JPEG', quality=90)
        return out
    except Exception as e:
        logger.warning(f"raw preview fail {image_path}: {e}")
        return None


@app.route('/api/image')
def api_image():
    p = _safe_image_path(request.args.get('path', ''))
    if not p:
        abort(404)
    if needs_jpeg_preview(p):
        f = _raw_preview_file(str(p))
        if not f:
            abort(404)
        resp = send_file(str(f))
        resp.headers['Cache-Control'] = 'public, max-age=86400'
        return resp
    return send_file(str(p))


def _ratio(v):
    try:
        return float(v)
    except Exception:
        try:
            return v.numerator / v.denominator
        except Exception:
            return None


def _gps_to_deg(val, ref):
    try:
        d = _ratio(val[0]); m = _ratio(val[1]); s = _ratio(val[2])
        deg = d + m / 60.0 + s / 3600.0
        if ref in ('S', 'W'):
            deg = -deg
        return round(deg, 6)
    except Exception:
        return None


def extract_exif(path):
    """Pull human-friendly capture details from a photo's EXIF."""
    from PIL.ExifTags import TAGS, GPSTAGS
    out = {}
    try:
        # RAW-aware: for RAW files this reads the embedded JPEG preview,
        # which carries the camera's full EXIF block.
        with open_image_pil(path) as img:
            exif = img.getexif()
            if not exif:
                return out
            tags = {TAGS.get(k, k): v for k, v in exif.items()}
            # Camera / lens
            make = (tags.get('Make') or '').strip()
            model = (tags.get('Model') or '').strip()
            if make or model:
                out['camera'] = (make + ' ' + model).strip() if model and not model.startswith(make) else (model or make)
            lens = tags.get('LensModel')
            if lens:
                out['lens'] = str(lens).strip()
            # Shooting settings (live in the Exif sub-IFD)
            try:
                sub = exif.get_ifd(0x8769)
                subtags = {TAGS.get(k, k): v for k, v in sub.items()}
            except Exception:
                subtags = {}
            # Capture time: DateTimeOriginal (Exif sub-IFD, rarely IFD0). IFD0
            # DateTime is the last save/edit time, used only as a labelled
            # fallback so it is never mistaken for the capture time.
            dto = subtags.get('DateTimeOriginal') or tags.get('DateTimeOriginal')
            if isinstance(dto, str) and ' ' in dto:
                d, t = dto.split(' ', 1)
                out['date'] = d.replace(':', '-'); out['time'] = t
                off = subtags.get('OffsetTimeOriginal')
                if isinstance(off, str) and off.strip():
                    out['time'] = f"{t} ({off.strip()})"
            else:
                dt = tags.get('DateTime')
                if isinstance(dt, str) and ' ' in dt:
                    d, t = dt.split(' ', 1)
                    out['date'] = d.replace(':', '-')
                    out['time'] = f"{t} (file modified, not capture time)"
            fnum = _ratio(subtags.get('FNumber'))
            if fnum:
                out['aperture'] = 'f/' + (str(int(fnum)) if fnum == int(fnum) else str(round(fnum, 1)))
            exp = subtags.get('ExposureTime')
            if exp is not None:
                er = _ratio(exp)
                if er and er < 1:
                    out['shutter'] = '1/' + str(int(round(1 / er))) + 's'
                elif er:
                    out['shutter'] = str(round(er, 1)) + 's'
            iso = subtags.get('ISOSpeedRatings') or subtags.get('PhotographicSensitivity')
            if iso:
                out['iso'] = 'ISO ' + str(iso if not isinstance(iso, (list, tuple)) else iso[0])
            fl = _ratio(subtags.get('FocalLength'))
            if fl:
                out['focal'] = str(int(round(fl))) + 'mm'
            lm = subtags.get('LensModel')
            if lm and 'lens' not in out:
                out['lens'] = str(lm).strip()
            # GPS
            try:
                gps = exif.get_ifd(0x8825)
            except Exception:
                gps = None
            if gps:
                g = {GPSTAGS.get(k, k): v for k, v in gps.items()}
                lat = _gps_to_deg(g.get('GPSLatitude'), g.get('GPSLatitudeRef'))
                lon = _gps_to_deg(g.get('GPSLongitude'), g.get('GPSLongitudeRef'))
                if lat is not None and lon is not None:
                    out['lat'] = lat; out['lon'] = lon
    except Exception:
        pass
    return out


@app.route('/api/exif')
def api_exif():
    p = _safe_image_path(request.args.get('path', ''))
    if not p:
        abort(404)
    return jsonify(extract_exif(str(p)))


@app.route('/')
def index():
    return render_template('app.html')


@app.route('/timeline')
def old_timeline():
    return redirect('/')


# Collections, timeline, AI, export (app/web/timeline_bp.py). Same app, so the
# same request guard and security headers apply.
timeline_bp.folder_dialog = native_folder_dialog


def _cache_files_for(image_path):
    """Cached thumbnail and preview of one photo (used by "Finish album")."""
    out = [_thumb_cache_path(image_path)]
    try:
        mtime = os.path.getmtime(image_path)
        key = hashlib.md5(f"{image_path}:{mtime}:preview-v1".encode()).hexdigest()
        out.append(THUMB_DIR / f"{key}_full.jpg")
    except OSError:
        pass
    return out


timeline_bp.cache_files_for = _cache_files_for
app.register_blueprint(timeline_bp.bp)


if __name__ == '__main__':
    import atexit
    import signal
    from app.ai.vision_analyzer import stop_started_ollama
    # The Mac app stops the server with SIGTERM; exit cleanly so the Ollama server
    # this app started (if any) is stopped too.
    atexit.register(stop_started_ollama)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    # Bind to loopback only: never reachable from the local network.
    app.run(host='127.0.0.1', port=PORT, debug=False, threaded=True)

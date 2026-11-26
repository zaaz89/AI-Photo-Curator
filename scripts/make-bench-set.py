#!/usr/bin/env python3
"""Build the M13 benchmark set: a synthetic two-person trip made from a few test photos.

  uv run python scripts/make-bench-set.py                          # test-photos/test-10 -> local-data/bench/bench-3000
  uv run python scripts/make-bench-set.py --source DIR --count 30 --videos 2 --out local-data/bench/smoke

Every file is a NEW file in the output folder (inside local-data/, ignored by git). The source photos are only
read: never written, moved or re-tagged. Variants are deterministic (--seed): the same command makes the same
bytes.

Mix (of --count files): 3 sources (cam-a, cam-b, phone-c), 7 days, 8 % near-duplicate bursts (2-4 frames
0.5 s apart, tiny crop/exposure changes), 5 % blurry, 2 % screenshots (PNG without camera EXIF), --videos short
clips made with ffmpeg from stills (skipped with a message when ffmpeg is missing), the rest distinct photos
(random crop of 30-60 % of a source frame, optional mirror, channel order, exposure, JPEG quality 70-95).

Times: each variant keeps the EXIF of the photo it was made from; `bench-times.json` maps file name -> seconds
to shift its capture time, so the album spans 7 days. The indexer reads that map only when
PHOTOCURATOR_BENCH_TIMES points at it (scripts/bench.sh) and only for files inside this folder.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import random
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))

from PIL import Image, ImageEnhance, ImageFilter, ImageOps  # noqa: E402

IMAGE_EXT = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.heic', '.heif', '.arw', '.cr2', '.cr3', '.nef', '.dng',
             '.raf', '.orf', '.rw2'}
SOURCES = ('cam-a', 'cam-b', 'phone-c')
DAYS = 7
EXIF_IFD, DTO, OFFSET_TAG, MAKE, MODEL = 0x8769, 36867, 36881, 0x010F, 0x0110


def load_sources(folder: Path, max_side: int) -> list:
    """[(name, PIL image reduced to work size, exif bytes or None, capture datetime or None)]"""
    from raw_loader import open_image_pil
    out = []
    for p in sorted(folder.iterdir()):
        if p.suffix.lower() not in IMAGE_EXT or p.name.startswith('.'):
            continue
        try:
            im = open_image_pil(str(p))
            im = ImageOps.exif_transpose(im).convert('RGB')
        except Exception as e:                       # unreadable: say so, go on
            print(f'  skipped {p.name}: {e}', file=sys.stderr)
            continue
        im.thumbnail((int(max_side * 1.6), int(max_side * 1.6)), Image.Resampling.LANCZOS)
        exif, when = None, None
        try:
            with Image.open(p) as raw:
                ex = raw.getexif()
                if ex:
                    sub = ex.get_ifd(EXIF_IFD)
                    v = sub.get(DTO) or ex.get(306)
                    if v:
                        when = datetime.strptime(str(v).strip('\x00 ')[:19], '%Y:%m:%d %H:%M:%S')
                    ex[0x0112] = 1                    # pixels are already upright
                    exif = ex.tobytes()
        except Exception:
            pass
        out.append((p.name, im, exif, when))
    return out


def fallback_exif(when: datetime, make: str, model: str) -> bytes:
    ex = Image.Exif()
    ex[MAKE], ex[MODEL] = make, model
    sub = ex.get_ifd(EXIF_IFD)
    sub[DTO] = when.strftime('%Y:%m:%d %H:%M:%S')
    sub[OFFSET_TAG] = '+02:00'
    return ex.tobytes()


def distinct(rng: random.Random, im: Image.Image, max_side: int) -> Image.Image:
    w, h = im.size
    share = rng.uniform(0.30, 0.60)
    cw, ch = int(w * share ** 0.5), int(h * share ** 0.5)
    x, y = rng.randint(0, w - cw), rng.randint(0, h - ch)
    out = im.crop((x, y, x + cw, y + ch))
    if rng.random() < 0.5:
        out = ImageOps.mirror(out)
    if rng.random() < 0.5:
        r, g, b = out.split()
        order = rng.choice([(g, r, b), (b, g, r), (r, b, g)])
        out = Image.merge('RGB', order)
    out = ImageEnhance.Brightness(out).enhance(rng.uniform(0.8, 1.2))
    out.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    return out


def burst_frame(rng: random.Random, base: Image.Image) -> Image.Image:
    w, h = base.size
    dx, dy = int(w * rng.uniform(0, 0.02)), int(h * rng.uniform(0, 0.02))
    out = base.crop((dx, dy, w - int(w * rng.uniform(0, 0.02)), h - int(h * rng.uniform(0, 0.02)))).resize((w, h))
    return ImageEnhance.Brightness(out).enhance(rng.uniform(0.97, 1.03))


def jpeg(im: Image.Image, path: Path, exif: bytes, quality: int) -> None:
    buf = io.BytesIO()
    im.save(buf, 'JPEG', quality=quality, exif=exif)
    path.write_bytes(buf.getvalue())


def slot_time(day: int, k: int, n: int, start: datetime) -> datetime:
    """The k-th of n moments on a day, spread 08:00-21:00."""
    base = datetime(start.year, start.month, start.day, 8) + timedelta(days=day)
    return base + timedelta(seconds=int(13 * 3600 * (k + 0.5) / max(1, n)))


def make_videos(stills: list, out: Path, n: int, rng: random.Random, start: datetime, ffmpeg: str) -> int:
    made = 0
    for i in range(n):
        src_name, path, when = stills[i % len(stills)]
        dst = out / SOURCES[2] / f'VID_{i:04d}.mp4'
        utc = (when + timedelta(minutes=rng.randint(0, 50)) - timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%S.000000Z')
        cmd = [ffmpeg, '-nostdin', '-loglevel', 'error', '-y', '-loop', '1', '-i', str(path), '-t', '3', '-r', '24',
               '-vf', 'scale=1280:-2', '-c:v', 'libx264',
               '-pix_fmt', 'yuv420p', '-metadata', f'creation_time={utc}', str(dst)]
        if subprocess.run(cmd).returncode == 0:
            made += 1
        else:
            print(f'  ffmpeg failed for {dst.name} (from {src_name})', file=sys.stderr)
    return made


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--source', default=str(REPO / 'test-photos' / 'test-10'))
    ap.add_argument('--out', default=str(REPO / 'local-data' / 'bench' / 'bench-3000'))
    ap.add_argument('--count', type=int, default=3000, help='files in total, videos included')
    ap.add_argument('--videos', type=int, default=60)
    ap.add_argument('--max-side', type=int, default=3000, help='long side of the variants in pixels')
    ap.add_argument('--seed', type=int, default=13)
    ap.add_argument('--force', action='store_true', help='replace an existing output folder')
    a = ap.parse_args(argv)

    src, out = Path(a.source).resolve(), Path(a.out).resolve()
    data = Path(os.environ.get('PHOTOCURATOR_DATA_DIR', REPO / 'local-data')).resolve()
    if not (str(out).startswith(str(data) + os.sep) or str(out).startswith(str(REPO / 'local-data') + os.sep)):
        print(f'refused: the output must be inside {data} (git-ignored app data)', file=sys.stderr)
        return 2
    if str(out).startswith(str(src) + os.sep) or str(src).startswith(str(out) + os.sep) or out == src:
        print('refused: output and source folders overlap', file=sys.stderr)
        return 2
    if not src.is_dir():
        print(f'no source folder {src}', file=sys.stderr)
        return 2
    if out.exists():
        if not a.force:
            print(f'{out} exists; use --force to replace it', file=sys.stderr)
            return 2
        if not (out / 'manifest.json').exists():
            print(f'refused: {out} was not made by this script (no manifest.json)', file=sys.stderr)
            return 2
        shutil.rmtree(out)

    rng = random.Random(a.seed)
    bases = load_sources(src, a.max_side)
    if not bases:
        print('no readable photos in the source folder', file=sys.stderr)
        return 2
    for s in SOURCES:
        (out / s).mkdir(parents=True)
    start = min((w for _, _, _, w in bases if w), default=datetime(2026, 10, 20, 8))

    ffmpeg = shutil.which('ffmpeg')
    n_videos = a.videos if ffmpeg else 0
    n_photos = max(0, a.count - n_videos)
    n_burst = int(round(n_photos * 0.08))
    n_blur = int(round(n_photos * 0.05))
    n_shot = int(round(n_photos * 0.02))
    n_plain = max(0, n_photos - n_burst - n_blur - n_shot)

    # Plan: (kind, frames) units; spread over 7 days in a deterministic shuffled order.
    units = [('plain', 1)] * n_plain + [('blurry', 1)] * n_blur + [('screenshot', 1)] * n_shot
    left = n_burst
    while left > 0:
        k = min(left, rng.randint(2, 4))
        units.append(('burst', k))
        left -= k
    rng.shuffle(units)
    per_day = [units[d::DAYS] for d in range(DAYS)]

    shifts, counts, stills = {}, {'plain': 0, 'blurry': 0, 'screenshot': 0, 'burst_frames': 0, 'bursts': 0}, []
    idx = 0
    for day, day_units in enumerate(per_day):
        for k, (kind, frames) in enumerate(day_units):
            source = SOURCES[rng.randrange(len(SOURCES))]
            name, base_im, exif, when = bases[rng.randrange(len(bases))]
            target = slot_time(day, k, len(day_units), start)
            if kind == 'screenshot':
                im = distinct(rng, base_im, min(a.max_side, 1600))
                fn = f'Screenshot {target:%Y-%m-%d at %H.%M.%S}.png'
                im.save(out / SOURCES[2] / fn, 'PNG')
                counts['screenshot'] += 1
                idx += 1
                continue
            ex = exif or fallback_exif(start, 'Sony', 'ILCE-7M4')
            shift = (target - when).total_seconds() if when else (target - start).total_seconds()
            im = distinct(rng, base_im, a.max_side)
            if kind == 'blurry':
                im = im.filter(ImageFilter.GaussianBlur(rng.uniform(4, 9)))
            for f in range(frames):
                frame = burst_frame(rng, im) if f else im
                fn = f'B{idx:05d}_{source}.jpg'
                jpeg(frame, out / source / fn, ex, rng.randint(70, 95))
                shifts[fn] = round(shift + 0.5 * f, 1)
                idx += 1
            if kind == 'burst':
                counts['bursts'] += 1
                counts['burst_frames'] += frames
            else:
                counts[kind] += 1
            if kind == 'plain' and len(stills) < max(1, n_videos):
                stills.append((fn, out / source / fn, target))

    made_videos = make_videos(stills, out, n_videos, rng, start, ffmpeg) if n_videos else 0
    (out / 'bench-times.json').write_text(json.dumps({'shift_s': shifts}, indent=0, sort_keys=True))
    manifest = {'source': str(src), 'seed': a.seed, 'count': a.count, 'max_side': a.max_side, 'days': DAYS,
                'sources': list(SOURCES), 'files': idx + made_videos, **counts, 'videos': made_videos,
                'videos_skipped': None if ffmpeg else 'ffmpeg not found: no videos made',
                'made_at': datetime.now().isoformat(timespec='seconds')}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    print(json.dumps(manifest, indent=2))
    if not ffmpeg:
        print('NOTE: ffmpeg not found, so the set has no videos.', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())

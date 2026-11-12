import hashlib
import os
import sys
import tempfile
import time
from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO))

# App data for the whole test session goes to a throwaway folder, never to the
# real local-data/. Must be set before photo_curator is imported.
_DATA = tempfile.mkdtemp(prefix='pc_test_data_')
os.environ['PHOTOCURATOR_DATA_DIR'] = _DATA


def make_photo(path: Path, seed: int, dto: str | None = '2026:10:23 18:14:32',
               offset: str | None = '+02:00', datetime_ifd0: str | None = '2026:10:23 20:00:00',
               blur: bool = False, model: str = 'iPhone 15', size=(800, 600),
               gps_utc: str | None = None):
    """A structured synthetic photo (shapes on a gradient) with chosen EXIF."""
    rng = np.random.default_rng(seed)
    w, h = size
    grad = np.linspace(0, 255, w, dtype=np.float32)[None, :, None].repeat(h, 0).repeat(3, 2)
    grad = (grad * rng.uniform(0.3, 1.0, size=3)).astype('uint8')
    img = Image.fromarray(grad)
    d = ImageDraw.Draw(img)
    for _ in range(12):
        x0, y0 = rng.integers(0, w - 60), rng.integers(0, h - 60)
        x1, y1 = x0 + rng.integers(20, 200), y0 + rng.integers(20, 200)
        color = tuple(int(c) for c in rng.integers(0, 255, 3))
        if rng.random() < 0.5:
            d.rectangle([x0, y0, x1, y1], fill=color)
        else:
            d.ellipse([x0, y0, x1, y1], fill=color)
    if blur:
        img = img.filter(ImageFilter.GaussianBlur(10))
    exif = Image.Exif()
    exif[0x010F] = 'Apple'
    exif[0x0110] = model
    if datetime_ifd0:
        exif[306] = datetime_ifd0
    sub = exif.get_ifd(0x8769)
    if dto:
        sub[36867] = dto
    if offset:
        sub[36881] = offset
    if gps_utc:                                 # 'YYYY:MM:DD HH:MM:SS' in UTC
        d, t = gps_utc.split(' ')
        h, m, s = (int(x) for x in t.split(':'))
        gps = exif.get_ifd(0x8825)
        gps[1], gps[2] = 'N', (43.0, 4.0, 30.0)
        gps[3], gps[4] = 'E', (11.0, 40.0, 50.0)
        gps[7] = (float(h), float(m), float(s))
        gps[29] = d
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, exif=exif, quality=92)
    return path


def snapshot(folder: Path) -> dict:
    """Every file (including hidden ones) under folder -> sha256."""
    out = {}
    for p in sorted(folder.rglob('*')):
        if p.is_file():
            out[str(p.relative_to(folder))] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


@pytest.fixture(scope='session')
def pc():
    import photo_curator
    return photo_curator


@pytest.fixture
def client(pc):
    for step in ('cull', 'dedup', 'rank'):
        pc.state[step]['running'] = False
    pc.state['phone_bg'].clear()
    pc.state['excluded'].clear()
    return pc.app.test_client()


@pytest.fixture
def H(pc):
    return {'Host': f'127.0.0.1:{pc.PORT}'}


def wait_step(pc, step, timeout=60):
    t0 = time.time()
    time.sleep(0.05)
    while pc.state[step]['running']:
        if time.time() - t0 > timeout:
            raise TimeoutError(step)
        time.sleep(0.05)

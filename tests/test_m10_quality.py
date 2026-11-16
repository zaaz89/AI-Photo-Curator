"""M10b quality check v2: blur on the subject (bokeh is not a fault), movement, eye states per main face
(small, turned, looking down, relative within a moment), keeper order, all_bad and the timeline fields.
The Swift helper is not used: helper output is written into the faces table by hand."""
import json

import cv2
import numpy as np
import pytest
from PIL import Image

from app import collections as col
from app.analysis import analyze_collection
from app.duplicates.groups import _recommend
from app.quality.faces import apply_moment, _annotate, eye_state, face_summary
from app.quality.scoring import focus_tiers, set_mark
from app.quality.subject import compute_subject_focus, lines, verdict
from conftest import textured_scene

W, H = 1200, 900
SUBJECT = (0.375, 0.3, 0.25, 0.4)          # face-like centre region, top-left origin


def _texture(seed, size):
    """Natural-looking detail (1/f noise, like skin, hair, fabric or foliage) with real contrast."""
    rng = np.random.default_rng(seed)
    w, h = size
    img = np.zeros((h, w), np.float32)
    for scale in (1, 2, 4, 8, 16, 32):
        n = rng.normal(0, 1, (h // scale + 1, w // scale + 1)).astype(np.float32)
        img += scale ** 0.5 * cv2.resize(n, (w, h), interpolation=cv2.INTER_CUBIC)
    img = (img - img.mean()) / (img.std() + 1e-6)
    return np.clip(128 + 45 * img, 0, 255)


def _scene(seed):
    rng = np.random.default_rng(seed)
    img = _texture(seed, (W, H))
    for _ in range(60):
        x, y, s = int(rng.integers(0, W - 80)), int(rng.integers(0, H - 80)), int(rng.integers(20, 80))
        cv2.rectangle(img, (x, y), (x + s, y + s), float(rng.integers(0, 255)), -1)
    return img


def _region():
    x, y, w, h = SUBJECT
    return int(x * W), int(y * H), int((x + w) * W), int((y + h) * H)


def _save(path, gray, dto):
    rgb = np.repeat(np.clip(gray, 0, 255).astype(np.uint8)[:, :, None], 3, 2)
    exif = Image.Exif()
    exif[0x010F], exif[0x0110] = 'Sony', 'ILCE-7M4'
    exif.get_ifd(0x8769)[36867] = dto
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgb).save(path, exif=exif, quality=95)


def _motion(img, length=21):
    k = np.zeros((length, length), np.float32)
    k[length // 2, :] = 1.0 / length
    return cv2.filter2D(img, -1, k)


def bokeh(path, dto='2026:10:24 09:00:00'):
    """Sharp subject on a heavily blurred background."""
    img = cv2.GaussianBlur(_scene(1), (0, 0), 12)
    x0, y0, x1, y1 = _region()
    img[y0:y1, x0:x1] = _texture(2, (x1 - x0, y1 - y0))
    _save(path, img, dto)


def all_blurred(path, dto='2026:10:24 10:00:00'):
    img = _scene(3)
    x0, y0, x1, y1 = _region()
    img[y0:y1, x0:x1] = _texture(4, (x1 - x0, y1 - y0))
    _save(path, cv2.GaussianBlur(img, (0, 0), 4), dto)


def moving_subject(path, dto='2026:10:24 11:00:00'):
    """Sharp background, the person (a little larger than the face box) smeared sideways."""
    img = _scene(5)
    x0, y0, x1, y1 = _region()
    dx, dy = (x1 - x0) // 5, (y1 - y0) // 5
    x0, y0, x1, y1 = x0 - dx, y0 - dy, x1 + dx, y1 + dy
    img[y0:y1, x0:x1] = _motion(_texture(6, (x1 - x0, y1 - y0)), 21)
    _save(path, img, dto)


def sharp_subject(path, dto='2026:10:24 12:00:00', seed=7):
    img = _scene(seed)
    x0, y0, x1, y1 = _region()
    img[y0:y1, x0:x1] = _texture(seed + 1, (x1 - x0, y1 - y0))
    _save(path, img, dto)


def vision_face(box=SUBJECT, **kw):
    """Helper output for one face, box given with the origin at the top left (stored the Vision way)."""
    x, y, w, h = box
    return {'box': [x, 1 - (y + h), w, h], 'quality': 0.7, 'yaw': 0.0, 'pitch': 0.0, 'left_eye': 0.3,
            'right_eye': 0.3, 'landmarks_confidence': 0.9, 'eye_precision': 0.008, **kw}


def put_helper(conn, name, faces, aesthetic=0.5, utility=False, salient=None):
    sha = conn.execute('SELECT sha256 FROM assets WHERE filename = ?', (name,)).fetchone()[0]
    vision = {'aesthetic': aesthetic, 'utility': utility, 'salient': salient or []}
    with conn:
        conn.execute('INSERT OR REPLACE INTO faces (sha256, n_faces, faces_json, vision_json, computed_at) '
                     'VALUES (?, ?, ?, ?, ?)', (sha, len(faces), json.dumps(faces), json.dumps(vision), 'now'))
        conn.execute('DELETE FROM subject_focus WHERE sha256 = ?', (sha,))
    return sha


def _id(conn, name):
    return conn.execute('SELECT id FROM assets WHERE filename = ?', (name,)).fetchone()[0]


@pytest.fixture
def blur_album(tmp_path):
    src = tmp_path / 'cam'
    bokeh(src / 'bokeh.jpg')
    all_blurred(src / 'blurred.jpg')
    moving_subject(src / 'moving.jpg')
    sharp_subject(src / 'sharp.jpg')
    sharp_subject(src / 'sharp2.jpg', dto='2026:10:24 13:00:00', seed=9)
    slug = col.create('M10 blur')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Me')
    analyze_collection(conn)
    for n in ('bokeh.jpg', 'blurred.jpg', 'moving.jpg', 'sharp.jpg', 'sharp2.jpg'):
        put_helper(conn, n, [vision_face()])
    assert compute_subject_focus(conn)['measured'] == 5
    yield conn, slug
    col.remove_album(slug)


# ---------- blur on the subject ----------

def test_bokeh_is_not_blurry_but_blur_and_movement_are(blur_album):
    conn, _ = blur_album
    t = focus_tiers(conn)
    v = {n: t[_id(conn, n)] for n in ('bokeh.jpg', 'blurred.jpg', 'moving.jpg', 'sharp.jpg')}
    assert v['bokeh.jpg']['tier'] == 'sharp' and v['bokeh.jpg']['subject'] == 'faces'
    assert v['bokeh.jpg']['blur_reason'] is None
    assert v['sharp.jpg']['tier'] == 'sharp'
    assert v['blurred.jpg']['tier'] == 'blurry' and v['blurred.jpg']['blur_reason'] == 'whole'
    assert v['moving.jpg']['tier'] == 'blurry' and v['moving.jpg']['blur_reason'] == 'movement'


def test_owner_override_wins_and_export_follows_the_subject_verdict(blur_album):
    conn, _ = blur_album
    from app.organization.export_plan import plan_export
    plan = plan_export(conn, selection='no_blurry')
    assert plan['counts']['blurry'] == 2                          # blurred.jpg and moving.jpg, not bokeh.jpg
    blurry = {a for a, v in focus_tiers(conn).items() if v['tier'] == 'blurry'}
    assert blurry == {_id(conn, 'blurred.jpg'), _id(conn, 'moving.jpg')}
    set_mark(conn, _id(conn, 'moving.jpg'), focus='sharp')
    t = focus_tiers(conn)[_id(conn, 'moving.jpg')]
    assert t['tier'] == 'sharp' and t['auto_tier'] == 'blurry' and t['blur_reason'] is None
    assert plan_export(conn, selection='no_blurry')['counts']['blurry'] == 1


def test_without_a_subject_the_whole_image_tiers_decide(blur_album):
    conn, _ = blur_album
    put_helper(conn, 'blurred.jpg', [])            # no faces, no salient boxes
    compute_subject_focus(conn)
    t = focus_tiers(conn)[_id(conn, 'blurred.jpg')]
    assert t['subject'] == 'none' and t['subject_sharpness'] is None
    assert t['tier'] == t['auto_tier']             # the region tiers, as before M10b


def test_lines_are_album_relative_within_limits():
    assert lines([]) == lines([5.0] * 4)           # too few measurements: default lines
    lo, hi = lines([8.0] * 10)
    assert 0.6 <= lo < hi <= 3.0
    assert lines([100.0] * 10) == (1.5, 3.0)       # a very sharp album does not flag good photos
    assert lines([1.0] * 10)[0] == 0.6             # a soft album still flags real blur
    row = {'sharpness': 0.3, 'whole': 9.0, 'anisotropy': 1.5}
    assert verdict(row, 1.0, 2.6) == ('blurry', 'subject')
    assert verdict({**row, 'sharpness': 1.5}, 1.0, 2.6) == ('soft', None)
    assert verdict({**row, 'sharpness': 1.5, 'anisotropy': 6.0}, 1.0, 2.6) == ('blurry', 'movement')
    assert verdict({**row, 'whole': 0.5}, 1.0, 2.6) == ('blurry', 'whole')


# ---------- eyes ----------

def _f(**kw):
    return vision_face((0.3, 0.3, 0.2, 0.2), **kw)


def test_eye_states_open_closed_unsure():
    assert eye_state(_f())[0] == 'open'
    assert eye_state(_f(left_eye=0.05, right_eye=0.06)) == ('closed', None)
    assert eye_state(_f(left_eye=0.15, right_eye=0.15)) == ('unsure', 'between')
    assert eye_state(_f(left_eye=0.05, yaw=0.9)) == ('unsure', 'turned')
    assert eye_state(_f(left_eye=None, right_eye=None)) == ('unsure', 'no_landmarks')
    assert eye_state(_f(left_eye=0.05, landmarks_confidence=0.5)) == ('unsure', 'low_confidence')
    assert eye_state(_f(left_eye=0.05, eye_precision=0.03)) == ('unsure', 'low_confidence')
    assert eye_state(_f(left_eye=0.05), lens=0.2) == ('unsure', 'sunglasses')


def test_small_faces_are_unsure():
    small = vision_face((0.4, 0.4, 0.03, 0.03), left_eye=0.05, right_eye=0.05)
    assert eye_state(small, dims=(4000, 3000)) == ('unsure', 'small')       # about 104 px: below 128
    assert eye_state(small, dims=(8000, 6000))[0] == 'closed'                # about 208 px: measured
    assert eye_state(small)[0] == 'unsure'                                   # no size known: area floor


def test_looking_down_is_unsure_not_closed():
    # IMG_0571 (test-10): head down over a laptop, pitch 0.195, eyes 0.125 / 0.152 -> was "closed".
    down = _f(pitch=0.195, left_eye=0.10, right_eye=0.11)
    assert eye_state(down) == ('unsure', 'looking_down')
    assert eye_state({**down, 'pitch': 0.0}) == ('closed', None)
    assert eye_state({**down, 'pitch': -0.38})[0] == 'closed'                # head tilted back: no excuse
    assert eye_state(_f(pitch=0.25))[0] == 'open'                             # clearly open stays open


def test_only_main_faces_count():
    big = vision_face((0.3, 0.3, 0.3, 0.3))
    background = vision_face((0.8, 0.1, 0.05, 0.05), left_eye=0.03, right_eye=0.03)
    s = face_summary([big, background])
    assert s['faces'] == 2 and s['main_faces'] == 1
    assert s['eyes_closed'] == 0 and s['eyes'] == {'open': 1, 'closed': 0, 'unsure': 0}
    assert [b['main'] for b in s['boxes']] == [True, False]
    assert s['boxes'][1]['state'] == 'closed'


def test_relative_closed_and_laughter_within_a_moment():
    # Half-blink: 0.15 is "between" alone, but this face is 0.32 in the next frame -> closed.
    a = _annotate([_f(left_eye=0.15, right_eye=0.16)])
    b = _annotate([vision_face((0.31, 0.31, 0.2, 0.2), left_eye=0.32, right_eye=0.33)])
    apply_moment([a, b])
    assert a[0]['state'] == 'closed' and b[0]['state'] == 'open'
    # Laughing in every frame: 0.10 alone reads closed, but the face is never more open in the moment.
    c = _annotate([_f(left_eye=0.10, right_eye=0.11)])
    d = _annotate([_f(left_eye=0.13, right_eye=0.14)])
    apply_moment([c, d])
    assert c[0]['state'] == 'unsure' and c[0]['why'] == 'squint'
    # Shut outright stays closed.
    e = _annotate([_f(left_eye=0.04, right_eye=0.05)])
    f = _annotate([_f(left_eye=0.13, right_eye=0.14)])
    apply_moment([e, f])
    assert e[0]['state'] == 'closed'
    # A different person (far away box) is not compared.
    g = _annotate([_f(left_eye=0.15, right_eye=0.16)])
    h = _annotate([vision_face((0.7, 0.7, 0.2, 0.2), left_eye=0.35, right_eye=0.35)])
    apply_moment([g, h])
    assert g[0]['state'] == 'unsure'


# ---------- keeper ----------

def _rows(n):
    return {i: {'id': i + 1, 'sha256': 'abcdef'[i], 'width': 4000, 'height': 3000, 'source_id': 1,
                'rel_path': f'{i}.jpg'} for i in range(n)}


def test_keeper_avoids_closed_eyes_even_when_sharper():
    rows = _rows(2)
    feats = {'a': (None, 100.0), 'b': (None, 100.0)}
    faces = {'a': face_summary([_f(left_eye=0.05, right_eye=0.05, quality=0.9)]), 'b': face_summary([_f()])}
    verdicts = {'a': {'blur': 'sharp', 'sharpness': 12.0, 'aesthetic': 0.9},
                'b': {'blur': 'sharp', 'sharpness': 4.0, 'aesthetic': 0.1}}
    info = {}
    keeper, reasons = _recommend(rows, feats, [0, 1], 'near', None, faces, {}, None, info, verdicts)
    assert keeper == 2 and 'eyes open (closed eyes in another frame)' in reasons
    assert info['margin'] >= 0.12 and info['all_bad'] is False


def test_keeper_avoids_a_blurry_subject_then_uses_aesthetics():
    rows = _rows(3)
    feats = {s: (None, 100.0) for s in 'abc'}
    faces = {s: face_summary([_f()]) for s in 'abc'}
    verdicts = {'a': {'blur': 'blurry', 'sharpness': 0.4, 'aesthetic': 0.1},
                'b': {'blur': 'sharp', 'sharpness': 6.0, 'aesthetic': 0.2},
                'c': {'blur': 'sharp', 'sharpness': 6.0, 'aesthetic': 0.8}}
    keeper, reasons = _recommend(rows, feats, [0, 1, 2], 'near', None, faces, {}, None, {}, verdicts)
    assert keeper == 3
    assert 'subject sharp (blurred subject in another frame)' in reasons and 'best overall look' in reasons


def test_all_frames_with_a_problem_are_flagged():
    rows = _rows(2)
    feats = {'a': (None, 100.0), 'b': (None, 100.0)}
    faces = {'a': face_summary([_f(left_eye=0.05, right_eye=0.05)]), 'b': face_summary([_f()])}
    verdicts = {'a': {'blur': 'sharp', 'sharpness': 6.0, 'aesthetic': 0.5},
                'b': {'blur': 'blurry', 'sharpness': 0.3, 'aesthetic': 0.5}}
    info = {}
    _, reasons = _recommend(rows, feats, [0, 1], 'near', None, faces, {}, None, info, verdicts)
    assert info['all_bad'] is True and 'all frames have a problem' in reasons
    info2 = {}
    _, reasons2 = _recommend(rows, feats, [0, 1], 'near', 'a', faces, {}, None, info2, verdicts)
    assert reasons2 == ['chosen by you'] and info2['all_bad'] is True


# ---------- timeline and stored groups ----------

def _item(client, H, slug, aid):
    data = client.get(f'/api/collections/{slug}/timeline', headers=H).get_json()
    return next(i for i in data['items'] if i['id'] == aid)


def test_timeline_exposes_quality_and_eye_states(client, H, blur_album):
    conn, slug = blur_album
    put_helper(conn, 'sharp.jpg', [vision_face(left_eye=0.05, right_eye=0.06)], aesthetic=-0.4, utility=True)
    compute_subject_focus(conn)
    q = _item(client, H, slug, _id(conn, 'sharp.jpg'))
    assert q['quality'] == {'blur': 'sharp', 'blur_reason': None, 'aesthetic': -0.4, 'utility': True,
                            'reasons': ['eyes_closed', 'utility_image']}
    assert q['faces']['boxes'][0]['state'] == 'closed' and q['faces']['boxes'][0]['main'] is True
    m = _item(client, H, slug, _id(conn, 'moving.jpg'))['quality']
    assert m['blur'] == 'blurry' and m['blur_reason'] == 'movement' and m['reasons'] == ['movement_blur']
    assert _item(client, H, slug, _id(conn, 'blurred.jpg'))['quality']['reasons'] == ['whole_blurry']
    assert _item(client, H, slug, _id(conn, 'bokeh.jpg'))['quality']['reasons'] == []


@pytest.fixture
def burst(tmp_path):
    src = tmp_path / 'cam'
    textured_scene(src / 'A.jpg', seed=71, dto='2026:10:24 09:00:00')
    from conftest import make_view
    make_view(src / 'A.jpg', src / 'B.jpg', crop=0.01, brightness=1.02, dto='2026:10:24 09:00:01', model='iPhone 15')
    slug = col.create('M10 burst')
    conn = col.open_db(slug)
    col.add_source(conn, str(src), 'Me')
    analyze_collection(conn)
    yield conn, slug
    col.remove_album(slug)


def test_stored_moment_marks_extra_frame_and_all_bad(client, H, burst):
    conn, slug = burst
    from app.duplicates.groups import build_groups
    put_helper(conn, 'A.jpg', [_f(left_eye=0.05, right_eye=0.05)])
    put_helper(conn, 'B.jpg', [_f(left_eye=0.04, right_eye=0.05)])
    build_groups(conn)
    g = conn.execute("SELECT keeper_id, reasons_json FROM duplicate_groups WHERE category = 'near'").fetchone()
    assert g is not None
    reasons = json.loads(g['reasons_json'])
    assert reasons['all_bad'] is True and 'all frames have a problem' in reasons['keeper']
    other = _id(conn, 'B.jpg') if g['keeper_id'] == _id(conn, 'A.jpg') else _id(conn, 'A.jpg')
    assert 'extra_frame' in _item(client, H, slug, other)['quality']['reasons']
    # Open eyes in one frame: that frame is the keeper and the moment is fine.
    put_helper(conn, 'B.jpg', [_f()])
    build_groups(conn)
    g = conn.execute("SELECT keeper_id, reasons_json FROM duplicate_groups WHERE category = 'near'").fetchone()
    assert g['keeper_id'] == _id(conn, 'B.jpg') and json.loads(g['reasons_json'])['all_bad'] is False

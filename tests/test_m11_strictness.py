"""M11: the owner's quality strictness moves the blur and closed-eye lines, applied when results are read."""
from app import settings
from app.quality import faces, strictness, subject


def _level(name):
    settings.save({'quality_strictness': name})


def test_normal_is_the_calibrated_behaviour():
    n = strictness.LEVELS['normal']
    assert (n['blur'], n['eye_closed'], n['rel_closed'], n['rel_max']) == \
        (1.0, faces.EYE_CLOSED, faces.REL_CLOSED, faces.REL_MAX)


def test_blur_lines_follow_the_setting():
    values = [6.7] * 10
    try:
        _level('normal')
        normal = subject.lines(values)
        _level('strict')
        strict = subject.lines(values)
        _level('lenient')
        lenient = subject.lines(values)
    finally:
        _level('normal')
    assert lenient[0] < normal[0] < strict[0] and lenient[1] < normal[1] < strict[1]
    row = {'sharpness': normal[1] * 1.05, 'anisotropy': 1.0, 'whole': 5.0}
    assert subject.verdict(row, *normal)[0] == 'sharp'
    assert subject.verdict(row, *strict)[0] == 'soft'      # the same photo is soft when strict


def test_closed_eye_line_follows_the_setting():
    face = {'box': [0.3, 0.3, 0.3, 0.3], 'left_eye': 0.10, 'right_eye': 0.11, 'pitch': 0.1,
            'landmarks_confidence': 0.9}
    try:
        _level('normal')
        assert faces.eye_state(face)[0] == 'closed'
        _level('lenient')
        assert faces.eye_state(face)[0] == 'unsure'       # 0.10 is not shut enough for lenient
        face2 = dict(face, left_eye=0.14, right_eye=0.14)
        _level('normal')
        assert faces.eye_state(face2)[0] == 'unsure'
        _level('strict')
        assert faces.eye_state(face2)[0] == 'closed'
    finally:
        _level('normal')


def test_unknown_level_in_the_file_falls_back_to_normal():
    import json
    p = settings._path()
    d = json.loads(p.read_text())
    d['quality_strictness'] = 'weird'
    p.write_text(json.dumps(d))
    try:
        assert strictness.current()['level'] == 'normal'
    finally:
        _level('normal')

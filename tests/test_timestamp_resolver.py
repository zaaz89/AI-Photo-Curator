"""Capture-time rules (app/metadata/timestamp_resolver.py), tags-only."""
from app.metadata.timestamp_resolver import parse_dt, resolve


def r(tags, **kw):
    return resolve(tags, kw.pop('filename', 'IMG_0001.JPG'), kw.pop('mtime', 1_700_000_000.0), **kw)


def test_dto_with_offset_and_subsec():
    x = r({'EXIF:DateTimeOriginal': '2026:10:23 18:14:32', 'EXIF:SubSecTimeOriginal': '25',
           'EXIF:OffsetTimeOriginal': '+02:00', 'EXIF:ModifyDate': '2026:11:06 18:24:55'})
    assert (x.rule, x.confidence) == ('exif_dto_offset', 'high')
    assert x.local_time == '2026-10-23T18:14:32.250000'
    assert x.utc_time == '2026-10-23T16:14:32.250000Z'


def test_modify_date_alone_is_never_used_as_capture_time():
    x = r({'EXIF:ModifyDate': '2026:11:06 18:24:55'}, filename='photo.jpg')
    assert x.rule == 'file_mtime' and x.confidence == 'unknown'


def test_offset_from_matching_xmp_date():
    x = r({'EXIF:DateTimeOriginal': '2026:10:23 18:10:42', 'XMP:CreateDate': '2026:10:23 18:10:42+02:00',
           'XMP:ModifyDate': '2026:11:06 18:24:55+01:00'})
    assert (x.rule, x.offset_minutes) == ('exif_dto_xmp_offset', 120)


def test_offset_derived_from_gps_utc():
    x = r({'EXIF:DateTimeOriginal': '2026:10:23 18:14:32', 'Composite:GPSDateTime': '2026:10:23 16:14:31Z'})
    assert (x.rule, x.offset_minutes, x.confidence) == ('exif_dto_gps', 120, 'high')


def test_assumed_offset_is_medium_and_explained():
    x = r({'EXIF:DateTimeOriginal': '2026:10:23 18:14:32'}, assumed_offset=120, assumed_from='same source')
    assert (x.rule, x.confidence) == ('exif_dto_assumed', 'medium')
    assert any('assumed' in n for n in x.notes)


def test_no_offset_no_assumption_is_low_and_local():
    x = r({'EXIF:DateTimeOriginal': '2026:10:23 18:14:32'})
    assert (x.rule, x.confidence, x.utc_time) == ('exif_dto_local', 'low', None)
    assert any('time zone unknown' in n for n in x.notes)


def test_createdate_fallback_is_one_level_lower():
    x = r({'EXIF:CreateDate': '2026:10:23 18:14:32', 'EXIF:OffsetTimeDigitized': '+02:00'})
    assert (x.rule, x.confidence) == ('exif_createdate_offset', 'medium')


def test_quicktime_creationdate_with_offset():
    x = r({'QuickTime:CreationDate': '2026:10:23 18:14:32+02:00', 'QuickTime:CreateDate': '2026:10:23 16:14:32'},
          kind='video')
    assert (x.rule, x.confidence, x.utc_time) == ('qt_creationdate', 'high', '2026-10-23T16:14:32Z')


def test_quicktime_createdate_is_utc_medium():
    x = r({'QuickTime:CreateDate': '2026:10:23 16:14:32'}, kind='video', assumed_offset=120, assumed_from='x')
    assert (x.rule, x.confidence, x.utc_time, x.local_time) == \
        ('qt_createdate_utc', 'medium', '2026-10-23T16:14:32Z', '2026-10-23T18:14:32')


def test_filename_pattern_is_low():
    x = r({}, filename='IMG_20261023_181432.jpg')
    assert (x.rule, x.confidence, x.local_time) == ('filename', 'low', '2026-10-23T18:14:32')


def test_zero_placeholder_dates_are_ignored():
    assert parse_dt('0000:00:00 00:00:00') == (None, None)
    x = r({'EXIF:DateTimeOriginal': '0000:00:00 00:00:00'}, filename='a.jpg')
    assert x.rule == 'file_mtime'


def test_dst_change_keeps_true_order():
    # 25 Oct 2026, Europe: 02:59:59 CEST (+02:00) is before 02:30:00 CET (+01:00).
    before = r({'EXIF:DateTimeOriginal': '2026:10:25 02:59:59', 'EXIF:OffsetTimeOriginal': '+02:00'})
    after = r({'EXIF:DateTimeOriginal': '2026:10:25 02:30:00', 'EXIF:OffsetTimeOriginal': '+01:00'})
    assert before.sort_key < after.sort_key

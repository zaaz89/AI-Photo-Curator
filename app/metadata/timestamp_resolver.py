"""Resolve the most trustworthy capture time for one file (brief section 4.2).

The resolver never invents a time. Each result says which rule produced it,
how confident it is, and what was assumed. Original metadata is not changed;
the caller stores this result separately.

Rules, strongest first:
  exif_dto_offset      DateTimeOriginal + OffsetTimeOriginal                 high
  exif_dto_xmp_offset  DateTimeOriginal + offset from an XMP date with the
                       same wall-clock time (Lightroom writes these)         high
  exif_dto_gps         DateTimeOriginal + offset derived from GPS UTC time   high/medium
  qt_creationdate      QuickTime CreationDate (local time with offset)       high
  exif_dto_assumed     DateTimeOriginal + offset assumed from the same
                       source's other files or the collection time zone      medium
  exif_dto_local       DateTimeOriginal, offset unknown                      low
  exif_createdate      EXIF CreateDate (digitized) used the same way         one step lower
  qt_createdate_utc    QuickTime CreateDate (UTC by spec, often wrong)       medium
  filename             date/time pattern in the file name                    low
  file_mtime           filesystem modification time                          unknown
EXIF ModifyDate / IFD0 DateTime (last edit or export) is never used.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Optional

from app.metadata.exif_reader import first

_DT_RE = re.compile(
    r'^(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2}):(\d{2})(\.\d+)?\s*(Z|[+\-]\d{2}:?\d{2})?$')
_FILENAME_RE = re.compile(r'(?<!\d)(20\d{2}|19\d{2})[-_]?(\d{2})[-_]?(\d{2})[-_ T]?(\d{2})[-_.]?(\d{2})[-_.]?(\d{2})(?!\d)')

LEVELS = ['high', 'medium', 'low', 'unknown']


@dataclass
class ResolvedTime:
    rule: str
    confidence: str
    local_time: Optional[str] = None       # ISO wall clock, no offset
    utc_time: Optional[str] = None         # ISO with Z
    offset_minutes: Optional[int] = None
    sort_key: float = 0.0
    notes: list = field(default_factory=list)


def parse_offset(s) -> Optional[int]:
    if s in (None, ''):
        return None
    s = str(s).strip()
    if s == 'Z':
        return 0
    m = re.match(r'^([+\-])(\d{2}):?(\d{2})$', s)
    if not m:
        return None
    mins = int(m.group(2)) * 60 + int(m.group(3))
    return mins if m.group(1) == '+' else -mins


def parse_dt(value) -> tuple[Optional[datetime], Optional[int]]:
    """'2026:10:23 18:14:32[.123][+02:00|Z]' -> (naive local datetime, offset minutes)."""
    if value in (None, ''):
        return None, None
    m = _DT_RE.match(str(value).strip())
    if not m:
        return None, None
    y, mo, d, h, mi, s = (int(x) for x in m.groups()[:6])
    if y < 1900 or mo == 0 or d == 0:          # '0000:00:00 00:00:00' placeholders
        return None, None
    try:
        dt = datetime(y, mo, d, h, mi, s)
    except ValueError:
        return None, None
    if m.group(7):
        dt += timedelta(microseconds=round(float(m.group(7)) * 1e6))
    return dt, parse_offset(m.group(8))


def _with_subsec(dt: datetime, subsec) -> datetime:
    if subsec in (None, '') or dt.microsecond:
        return dt
    digits = re.sub(r'\D', '', str(subsec))
    if not digits:
        return dt
    return dt + timedelta(microseconds=round(float('0.' + digits) * 1e6))


def _fmt_offset(mins: int) -> str:
    sign = '+' if mins >= 0 else '-'
    return f'{sign}{abs(mins) // 60:02d}:{abs(mins) % 60:02d}'


def _finish(r: ResolvedTime, local: datetime, offset: Optional[int]) -> ResolvedTime:
    r.local_time = local.isoformat()
    r.offset_minutes = offset
    if offset is not None:
        utc = (local - timedelta(minutes=offset)).replace(tzinfo=timezone.utc)
        r.utc_time = utc.isoformat().replace('+00:00', 'Z')
        r.sort_key = utc.timestamp()
    else:
        # Unknown offset: order by the recorded wall clock and say so.
        r.sort_key = local.replace(tzinfo=timezone.utc).timestamp()
        r.notes.append('time zone unknown: ordered by the camera clock as recorded')
    return r


def _lower(conf: str) -> str:
    return LEVELS[min(LEVELS.index(conf) + 1, len(LEVELS) - 1)]


def _offset_from_gps(local: datetime, gps_value) -> tuple[Optional[int], Optional[str], list]:
    gps, gps_off = parse_dt(gps_value)
    if gps is None:
        return None, None, []
    if gps_off not in (None, 0):
        gps = gps - timedelta(minutes=gps_off)
    diff_min = (local - gps).total_seconds() / 60
    offset = int(round(diff_min / 15.0) * 15)
    residual = abs(diff_min - offset) * 60
    if abs(offset) > 14 * 60:
        return None, None, [f'GPS time {gps_value} is not usable to derive an offset']
    conf = 'high' if residual <= 120 else 'medium'
    return offset, conf, [f'offset {_fmt_offset(offset)} derived from GPS UTC time '
                          f'(clock vs GPS residual {residual:.0f} s)']


def resolve(tags: dict, filename: str, mtime: Optional[float], kind: str = 'image',
            assumed_offset: Optional[int] = None, assumed_from: str = '') -> ResolvedTime:
    """Resolve the capture time for one file.

    assumed_offset: offset (minutes) to assume when the file itself has none,
    e.g. the most common offset of the same source. assumed_from explains it."""

    def from_exif_date(value, subsec, offset_tag, base_rule, base_conf_drop):
        local, inline_off = parse_dt(value)
        if local is None:
            return None
        local = _with_subsec(local, subsec)
        drop = (lambda c: _lower(c)) if base_conf_drop else (lambda c: c)
        off = inline_off if inline_off is not None else parse_offset(offset_tag)
        if off is not None:
            return _finish(ResolvedTime(f'{base_rule}_offset', drop('high'),
                                        notes=[f'offset {_fmt_offset(off)} from EXIF']), local, off)
        # Lightroom and other tools store the same wall clock with an offset in XMP.
        for xmp_key in ('XMP:DateTimeOriginal', 'XMP:CreateDate', 'XMP:DateCreated'):
            xl, xo = parse_dt(tags.get(xmp_key))
            if xl is not None and xo is not None and abs((xl - local.replace(microsecond=0)).total_seconds()) < 1:
                return _finish(ResolvedTime(f'{base_rule}_xmp_offset', drop('high'),
                                            notes=[f'offset {_fmt_offset(xo)} from {xmp_key}']), local, xo)
        g_off, g_conf, g_notes = _offset_from_gps(local, first(tags, 'Composite:GPSDateTime', 'GPSDateTime'))
        if g_off is not None:
            return _finish(ResolvedTime(f'{base_rule}_gps', drop(g_conf), notes=g_notes), local, g_off)
        if assumed_offset is not None:
            return _finish(ResolvedTime(f'{base_rule}_assumed', drop('medium'),
                                        notes=[f'offset {_fmt_offset(assumed_offset)} assumed: {assumed_from}']),
                           local, assumed_offset)
        return _finish(ResolvedTime(f'{base_rule}_local', drop('low')), local, None)

    r = from_exif_date(first(tags, 'EXIF:DateTimeOriginal', 'XMP:DateTimeOriginal'),
                       first(tags, 'EXIF:SubSecTimeOriginal'),
                       first(tags, 'EXIF:OffsetTimeOriginal'), 'exif_dto', False)
    if r:
        return r

    if kind == 'video':
        local, off = parse_dt(first(tags, 'QuickTime:CreationDate'))
        if local is not None and off is not None:
            return _finish(ResolvedTime('qt_creationdate', 'high',
                                        notes=['QuickTime CreationDate with offset']), local, off)
        utc, _ = parse_dt(first(tags, 'QuickTime:CreateDate'))
        if utc is not None:
            r = ResolvedTime('qt_createdate_utc', 'medium',
                             notes=['QuickTime CreateDate is UTC by spec; some cameras write local time'])
            if assumed_offset is not None:
                local = utc + timedelta(minutes=assumed_offset)
                r.notes.append(f'local time shown with offset {_fmt_offset(assumed_offset)} assumed: {assumed_from}')
                return _finish(r, local, assumed_offset)
            return _finish(r, utc, 0)

    r = from_exif_date(first(tags, 'EXIF:CreateDate'), first(tags, 'EXIF:SubSecTimeDigitized'),
                       first(tags, 'EXIF:OffsetTimeDigitized'), 'exif_createdate', True)
    if r:
        r.notes.append('DateTimeOriginal missing; used EXIF CreateDate (digitized)')
        return r

    m = _FILENAME_RE.search(filename or '')
    if m:
        try:
            local = datetime(*(int(x) for x in m.groups()))
        except ValueError:
            local = None
        if local is not None:
            r = ResolvedTime('filename', 'low', notes=[f'parsed from file name "{filename}"'])
            if assumed_offset is not None:
                r.notes.append(f'offset {_fmt_offset(assumed_offset)} assumed: {assumed_from}')
            return _finish(r, local, assumed_offset)

    if mtime:
        utc = datetime.fromtimestamp(mtime, tz=timezone.utc)
        r = ResolvedTime('file_mtime', 'unknown',
                         notes=['no capture metadata; filesystem modification time is usually the '
                                'copy or export time, not the capture time'])
        r.local_time = None
        r.utc_time = utc.isoformat().replace('+00:00', 'Z')
        r.sort_key = utc.timestamp()
        return r
    return ResolvedTime('none', 'unknown', notes=['no usable time found'], sort_key=0.0)


def explicit_offset(tags: dict) -> Optional[int]:
    """Offset the file states itself (EXIF/XMP/QuickTime), for building source defaults."""
    for key in ('EXIF:OffsetTimeOriginal', 'EXIF:OffsetTime'):
        off = parse_offset(tags.get(key))
        if off is not None:
            return off
    for key in ('EXIF:DateTimeOriginal', 'XMP:DateTimeOriginal', 'XMP:CreateDate', 'QuickTime:CreationDate'):
        _, off = parse_dt(tags.get(key))
        if off is not None:
            return off
    return None

"""Verified, non-destructive export of copies.

Rules (brief section 16):
- Originals are only ever opened for reading.
- Output goes to a new job folder inside a destination the user chose. The
  destination may not be inside a source folder, and a source folder may not
  be inside the destination.
- Files are created with exclusive mode, so nothing is ever overwritten.
- Every copy is verified by re-reading it and comparing SHA-256 checksums.
- A manifest (manifest.json) is written before copying (status "planned")
  and rewritten after (status "completed" or "failed").
- The export only reports success when every file verified.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Callable, Iterable, Optional

CHUNK = 1024 * 1024
MANIFEST_NAME = 'manifest.json'


class ExportError(Exception):
    """Raised when an export cannot start (bad destination, no space)."""


@dataclass
class ExportItem:
    source: str
    dest_name: str
    kind: str = 'copy'            # 'copy' = original bytes, 'derived' = generated file
    status: str = 'planned'       # planned | verified | failed | skipped
    dest: Optional[str] = None
    size: Optional[int] = None
    sha256_source: Optional[str] = None
    sha256_dest: Optional[str] = None
    error: Optional[str] = None


@dataclass
class ExportResult:
    ok: bool
    job_dir: str
    manifest: str
    verified: int = 0
    failed: int = 0
    skipped: int = 0
    items: list = field(default_factory=list)


def _is_within(child: str, parent: str) -> bool:
    child, parent = os.path.realpath(child), os.path.realpath(parent)
    return child == parent or child.startswith(parent.rstrip(os.sep) + os.sep)


def validate_destination(dest_root: str, source_roots: Iterable[str]) -> Path:
    """Return the resolved destination or raise ExportError."""
    if not dest_root:
        raise ExportError('No export destination chosen')
    dest = Path(os.path.realpath(dest_root))
    if not dest.is_dir():
        raise ExportError(f'Export destination does not exist: {dest}')
    for src in source_roots:
        if not src:
            continue
        if _is_within(str(dest), src):
            raise ExportError(f'Export destination is inside a source folder ({src}). '
                              'Choose a folder outside your photos.')
        if _is_within(src, str(dest)):
            raise ExportError(f'A source folder ({src}) is inside the export destination. '
                              'Choose a different destination.')
    return dest


def safe_name(name: str) -> str:
    """Strip path separators and characters that are invalid on macOS/Windows."""
    bad = '/\\:*?"<>|\x00'
    cleaned = ''.join('_' if c in bad or ord(c) < 32 else c for c in name).strip()
    cleaned = cleaned.lstrip('.') or 'file'
    return cleaned


def _unique_path(folder: Path, name: str, taken: set) -> Path:
    stem, suffix = os.path.splitext(name)
    candidate, n = name, 2
    while candidate.lower() in taken or (folder / candidate).exists():
        candidate = f'{stem}_{n}{suffix}'
        n += 1
    taken.add(candidate.lower())
    return folder / candidate


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(CHUNK), b''):
            h.update(chunk)
    return h.hexdigest()


def _copy_verified(src: str, dst: Path) -> tuple[str, str, int]:
    """Copy src to a NEW file dst (never overwrites). Returns (sha_src, sha_dst, size)."""
    h = hashlib.sha256()
    size = 0
    with open(src, 'rb') as fin, open(dst, 'xb') as fout:
        for chunk in iter(lambda: fin.read(CHUNK), b''):
            h.update(chunk)
            fout.write(chunk)
            size += len(chunk)
        fout.flush()
        os.fsync(fout.fileno())
    shutil.copystat(src, dst)            # keep timestamps; the source is only read
    return h.hexdigest(), sha256_file(str(dst)), size


def _write_manifest(path: Path, payload: dict) -> None:
    tmp = path.with_suffix('.json.tmp')
    tmp.write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    os.replace(tmp, path)               # atomic; inside the job folder only


def export_copies(items: list[ExportItem], dest_root: str, source_roots: Iterable[str],
                  job_name: str,
                  derive: Optional[Callable[[ExportItem, Path], None]] = None,
                  resume_dir: Optional[str] = None, extra: Optional[dict] = None,
                  progress: Optional[Callable[[str, int, int], None]] = None) -> ExportResult:
    """Copy (or derive) every item into a fresh job folder and verify it.

    derive(item, target_path) must create target_path for items of kind
    'derived' (e.g. a cropped wallpaper). It is never given the source path
    for writing.

    resume_dir: an earlier job folder of the same plan (interrupted export).
    Files already there with the source's checksum count as done; a file
    with other content is never overwritten (the copy gets a new name)."""
    source_roots = [s for s in source_roots if s]
    dest = validate_destination(dest_root, source_roots)

    stamp = time.strftime('%Y%m%d-%H%M%S')
    if resume_dir:
        job_dir = Path(os.path.realpath(resume_dir))
        if not _is_within(str(job_dir), str(dest)) or not (job_dir / MANIFEST_NAME).is_file():
            raise ExportError('Resume folder must be an earlier export (with manifest.json) inside the destination')
    else:
        job_dir = _unique_path(dest, safe_name(f'{job_name}_{stamp}'), set())
    manifest = job_dir / MANIFEST_NAME
    taken: set = {MANIFEST_NAME}

    # Plan: resolve every target name before touching anything.
    done_already = set()
    for idx, it in enumerate(items):
        sub = Path(it.dest_name)
        folder = job_dir.joinpath(*[safe_name(p) for p in sub.parts[:-1]]) if len(sub.parts) > 1 else job_dir
        planned = folder / safe_name(sub.name)
        if resume_dir and planned.is_file() and planned.name.lower() not in taken \
                and os.path.isfile(it.source) and sha256_file(str(planned)) == sha256_file(it.source):
            taken.add(planned.name.lower())
            it.dest = str(planned)
            done_already.add(idx)
            continue
        it.dest = str(_unique_path(folder, safe_name(sub.name), taken))

    needed = sum(os.path.getsize(i.source) for k, i in enumerate(items)
                 if i.kind == 'copy' and k not in done_already and os.path.isfile(i.source))
    free = shutil.disk_usage(dest).free
    if needed * 1.05 + 50 * 1024 * 1024 > free:
        raise ExportError(f'Not enough free space at {dest}: need about '
                          f'{needed / 1e9:.2f} GB, {free / 1e9:.2f} GB free')
    job_dir.mkdir(exist_ok=bool(resume_dir))

    header = {'tool': 'AI Photo Curator', 'job': job_name, 'created': stamp,
              'destination': str(job_dir), 'source_roots': source_roots,
              'resumed': bool(resume_dir), **(extra or {})}
    _write_manifest(manifest, {**header, 'status': 'planned',
                               'items': [asdict(i) for i in items]})

    for idx, it in enumerate(items):
        target = Path(it.dest)
        if progress:
            progress(f'Copying and verifying {Path(it.dest_name).name}', idx, len(items))
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            if idx in done_already:
                it.sha256_source = it.sha256_dest = sha256_file(str(target))
                it.size = target.stat().st_size
                it.status, it.error = 'verified', None
                continue
            if it.kind == 'copy':
                if not os.path.isfile(it.source):
                    it.status, it.error = 'skipped', 'source file missing'
                    continue
                it.sha256_source, it.sha256_dest, it.size = _copy_verified(it.source, target)
                if it.sha256_source != it.sha256_dest:
                    it.status, it.error = 'failed', 'checksum mismatch'
                    continue
            else:
                if derive is None:
                    raise ExportError('derived item without a derive function')
                derive(it, target)
                it.sha256_dest = sha256_file(str(target))
                it.size = target.stat().st_size
            it.status = 'verified'
        except Exception as e:                       # record and continue
            it.status, it.error = 'failed', str(e)

    verified = sum(i.status == 'verified' for i in items)
    failed = sum(i.status == 'failed' for i in items)
    skipped = sum(i.status == 'skipped' for i in items)
    ok = failed == 0 and skipped == 0 and verified == len(items)
    _write_manifest(manifest, {**header, 'status': 'completed' if ok else 'failed',
                               'verified': verified, 'failed': failed, 'skipped': skipped,
                               'items': [asdict(i) for i in items]})
    return ExportResult(ok=ok, job_dir=str(job_dir), manifest=str(manifest),
                        verified=verified, failed=failed, skipped=skipped,
                        items=[asdict(i) for i in items])

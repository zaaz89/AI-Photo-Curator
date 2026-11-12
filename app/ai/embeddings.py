"""Semantic image embeddings with SigLIP 2, computed locally (Metal/MPS on Apple Silicon).

Images and text share one vector space, so a text query can be ranked against
all photos. Vectors are cached per file content (SHA-256) and model.
"""
from __future__ import annotations

import threading
from typing import Callable, Iterable, Optional

import numpy as np
from PIL import Image, ImageOps

from app.ai.models import EMBED_MODEL, configure_hf_offline, models_dir
from app.collections import now_iso

BATCH = 16
_lock = threading.Lock()
_model = None


class ModelUnavailable(RuntimeError):
    pass


class Embedder:
    """Wraps SigLIP 2. Tests replace it with a fake via set_embedder()."""
    name = EMBED_MODEL

    def __init__(self):
        configure_hf_offline()
        if not (models_dir() / 'huggingface').exists():
            raise ModelUnavailable('SigLIP 2 is not downloaded. Run scripts/download-models.sh')
        try:
            import torch
            from transformers import AutoModel, AutoProcessor
        except ImportError as e:                               # pragma: no cover
            raise ModelUnavailable(f'PyTorch/transformers missing: {e}')
        self.torch = torch
        self.device = 'mps' if torch.backends.mps.is_available() else 'cpu'
        try:
            self.model = AutoModel.from_pretrained(EMBED_MODEL).to(self.device).eval()
            self.proc = AutoProcessor.from_pretrained(EMBED_MODEL)
        except Exception as e:
            raise ModelUnavailable(f'could not load {EMBED_MODEL}: {e}')

    def _norm(self, out):
        out = getattr(out, 'pooler_output', out)          # transformers 5 returns an output object
        out = self.torch.nn.functional.normalize(out, dim=-1)
        return out.float().cpu().numpy()

    def images(self, images: list) -> np.ndarray:
        with self.torch.no_grad():
            x = self.proc(images=images, return_tensors='pt').to(self.device)
            return self._norm(self.model.get_image_features(**x))

    def texts(self, texts: list) -> np.ndarray:
        with self.torch.no_grad():
            x = self.proc(text=texts, padding='max_length', max_length=64, return_tensors='pt').to(self.device)
            return self._norm(self.model.get_text_features(**x))


def get_embedder():
    global _model
    with _lock:
        if _model is None:
            _model = Embedder()
        return _model


def set_embedder(obj):
    """Testing hook."""
    global _model
    _model = obj


def load_image(path: str, side: int = 448) -> Optional[Image.Image]:
    try:
        from raw_loader import open_image_pil
        im = open_image_pil(path)
    except Exception:
        try:
            im = Image.open(path)
        except Exception:
            return None
    try:
        im.draft('RGB', (side, side))
    except Exception:
        pass
    return ImageOps.exif_transpose(im).convert('RGB')


def compute_embeddings(conn, progress: Optional[Callable] = None,
                       cancelled: Callable[[], bool] = lambda: False) -> dict:
    emb = get_embedder()
    rows = conn.execute(
        "SELECT DISTINCT a.sha256, s.path || '/' || a.rel_path AS path FROM assets a "
        "JOIN sources s ON s.id = a.source_id "
        "WHERE a.status = 'present' AND a.kind = 'image' AND a.sha256 != '' "
        "AND a.sha256 NOT IN (SELECT sha256 FROM image_embeddings WHERE model = ?) "
        "GROUP BY a.sha256", (emb.name,)).fetchall()
    done = failed = 0
    for i in range(0, len(rows), BATCH):
        if cancelled():
            break
        chunk = rows[i:i + BATCH]
        if progress:
            progress('Search index (SigLIP 2)', i, len(rows))
        ims, keep = [], []
        for r in chunk:
            im = load_image(r['path'])
            if im is None:
                failed += 1
                continue
            ims.append(im)
            keep.append(r['sha256'])
        if not ims:
            continue
        vecs = emb.images(ims)
        with conn:
            conn.executemany('INSERT OR REPLACE INTO image_embeddings (sha256, model, vec, computed_at) '
                             'VALUES (?, ?, ?, ?)',
                             [(s, emb.name, v.astype(np.float16).tobytes(), now_iso()) for s, v in zip(keep, vecs)])
        done += len(keep)
    return {'embedded': done, 'failed': failed}


def load_matrix(conn, model: str) -> tuple[list, np.ndarray]:
    rows = conn.execute('SELECT sha256, vec FROM image_embeddings WHERE model = ?', (model,)).fetchall()
    if not rows:
        return [], np.zeros((0, 1), np.float32)
    shas = [r['sha256'] for r in rows]
    mat = np.stack([np.frombuffer(r['vec'], np.float16) for r in rows]).astype(np.float32)
    return shas, mat

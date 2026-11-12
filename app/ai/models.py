"""Where local models live and which ones are used.

All model files stay inside the project (local-data/models/, ignored by git):
  - Hugging Face cache (SigLIP 2):  local-data/models/huggingface
  - Ollama models (Qwen3-VL instruct): local-data/models/ollama  (scripts/ollama-serve.sh)
Downloads only happen through scripts/download-models.sh. At runtime the
Hugging Face hub is put in offline mode, so nothing is fetched or reported.
"""
from __future__ import annotations

import os

from app.collections import REPO, data_dir

EMBED_MODEL = 'google/siglip2-base-patch16-224'
VLM_MODEL = os.environ.get('PHOTOCURATOR_VLM', 'qwen3-vl:4b-instruct')
OLLAMA_URL = os.environ.get('PHOTOCURATOR_OLLAMA', 'http://127.0.0.1:11434')
OLLAMA_SCRIPT = REPO / 'scripts' / 'ollama-serve.sh'


def models_dir():
    return data_dir() / 'models'


def configure_hf_offline():
    os.environ.setdefault('HF_HOME', str(models_dir() / 'huggingface'))
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
    os.environ['TRANSFORMERS_OFFLINE'] = '1'

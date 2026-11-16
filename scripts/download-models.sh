#!/bin/sh
# Download the local AI models into this project (local-data/models/, ignored by git).
#   SigLIP 2 base (google/siglip2-base-patch16-224, Apache 2.0, ~1.4 GB)  - search
# The Qwen3-VL description model was dropped on 2026-11-16 (no descriptions: Google Photos writes its own).
# Needs: uv. Run once per machine.
set -e
cd "$(dirname "$0")/.."
export HF_HOME="$PWD/local-data/models/huggingface"
export HF_HUB_DISABLE_TELEMETRY=1
uv run python -c "from huggingface_hub import snapshot_download; print(snapshot_download('google/siglip2-base-patch16-224', allow_patterns=['*.json','*.safetensors','*.model','*.txt','README.md']))"

echo "Models are in $PWD/local-data/models"

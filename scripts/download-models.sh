#!/bin/sh
# Download the local AI models into this project (local-data/models/, ignored by git).
#   SigLIP 2 base (google/siglip2-base-patch16-224, Apache 2.0, ~1.4 GB)  - search
#   Qwen3-VL 4B instruct (qwen3-vl:4b-instruct via Ollama, Apache 2.0, ~3.3 GB) - descriptions
# Needs: uv, Ollama (brew install ollama). Run once per machine.
set -e
cd "$(dirname "$0")/.."
export HF_HOME="$PWD/local-data/models/huggingface"
export HF_HUB_DISABLE_TELEMETRY=1
uv run python -c "from huggingface_hub import snapshot_download; print(snapshot_download('google/siglip2-base-patch16-224', allow_patterns=['*.json','*.safetensors','*.model','*.txt','README.md']))"

if ! curl -s http://127.0.0.1:11434/api/tags >/dev/null; then
  ./scripts/ollama-serve.sh >/dev/null 2>&1 &
  sleep 3
fi
OLLAMA_HOST=127.0.0.1:11434 ollama pull qwen3-vl:4b-instruct
echo "Models are in $PWD/local-data/models"

#!/bin/sh
# Start a local Ollama server that keeps its models inside this project
# (local-data/models/ollama, ignored by git) and listens on loopback only.
cd "$(dirname "$0")/.." || exit 1
export OLLAMA_MODELS="$PWD/local-data/models/ollama"
export OLLAMA_HOST="127.0.0.1:11434"
mkdir -p "$OLLAMA_MODELS"
exec ollama serve

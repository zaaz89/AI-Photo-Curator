#!/bin/sh
# Start a local Ollama server that keeps its models inside this project
# (local-data/models/ollama, ignored by git) and listens on loopback only.
# It runs with macOS background priority (taskpolicy -b) so the owner's own
# apps come first, handles one request at a time and unloads idle models
# after 2 minutes.
cd "$(dirname "$0")/.." || exit 1
export OLLAMA_MODELS="$PWD/local-data/models/ollama"
export OLLAMA_HOST="127.0.0.1:11434"
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_MAX_LOADED_MODELS=1
export OLLAMA_KEEP_ALIVE=2m
mkdir -p "$OLLAMA_MODELS"
exec /usr/sbin/taskpolicy -b ollama serve

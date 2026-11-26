#!/usr/bin/env bash
# M13 benchmark: the whole analysis of a bench set, headless through app.cli, into
# local-data/bench/results-<date>.json (wall time per stage, peak memory of engine and helper, photos/s,
# GPU share the throttle used). Plain bash 3.2 (macOS).
#
#   scripts/bench.sh [set folder] [--share 30] [--mode per-day|all-at-once] [--yes]
#
# The set comes from scripts/make-bench-set.py (default local-data/bench/bench-3000). Each run uses a fresh data
# folder (local-data/bench/data-<date>): its own album, settings (the share) and caches, so runs compare and the
# owner's albums and settings are never touched. The helper, places and models are linked in from local-data/.
# A long AI job (AGENTS.md): sets over 200 files need --yes, so ask the owner first.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

SET="local-data/bench/bench-3000"
SHARE=30
MODE="per-day"
YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --share) SHARE="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --yes) YES=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) SET="$1"; shift ;;
    esac
done
case "$MODE" in per-day|all-at-once) ;; *) echo "--mode must be per-day or all-at-once"; exit 2 ;; esac
case "$SHARE" in ''|*[!0-9]*) echo "--share must be a number from 10 to 100"; exit 2 ;; esac
if [ "$SHARE" -lt 10 ] || [ "$SHARE" -gt 100 ]; then echo "--share must be a number from 10 to 100"; exit 2; fi

SET_ABS="$(cd "$SET" 2>/dev/null && pwd)" || { echo "No bench set at $SET (run scripts/make-bench-set.py)"; exit 2; }
[ -f "$SET_ABS/bench-times.json" ] || { echo "$SET has no bench-times.json (not made by make-bench-set.py)"; exit 2; }
FILES=$(find "$SET_ABS" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.mp4' \) | wc -l | tr -d ' ')
if [ "$FILES" -gt 200 ] && [ "$YES" -ne 1 ]; then
    echo "$FILES files: this is a long AI job. Ask the owner, then run again with --yes."
    exit 3
fi

STAMP="$(date +%Y-%m-%d-%H%M%S)"
DATA="$REPO/local-data/bench/data-$STAMP"
OUT="$REPO/local-data/bench/results-$STAMP-$MODE-share$SHARE.json"
LOG="$REPO/local-data/bench/run-$STAMP.log"
mkdir -p "$DATA"
for d in bin geo models; do
    if [ -e "$REPO/local-data/$d" ]; then ln -s "$REPO/local-data/$d" "$DATA/$d"; fi
done
printf '{"ai_gpu_share": %s}\n' "$SHARE" > "$DATA/settings.json"

export PHOTOCURATOR_DATA_DIR="$DATA"
export PHOTOCURATOR_BENCH_TIMES="$SET_ABS/bench-times.json"
cli() { uv run --quiet python -m app.cli "$@"; }

echo "Bench: $FILES files, mode $MODE, share $SHARE %, data $DATA"
[ -e "$DATA/bin/pc-helper" ] || echo "NOTE: no helper (scripts/build-helper.sh): faces and videos are skipped"
SLUG="$(cli create "bench $STAMP")"
for d in "$SET_ABS"/*/; do
    d="${d%/}"
    cli add-source "$SLUG" "$d" --owner "$(basename "$d")" > /dev/null
done
cli bench "$SLUG" --out "$OUT" --mode "$MODE" 2> "$LOG"
echo "Results: $OUT"
echo "Log:     $LOG"

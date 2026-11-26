#!/usr/bin/env bash
# Design-token ratchet (M12b). Counts hardcoded values in the Mac app's SwiftUI code outside DesignSystem/
# and fails if any count is higher than in mac/design-tokens-baseline.txt. Counts may only go down:
# after migrating call sites to Space/Radius/TypeRole/Motion, run with --update to lower the baseline.
# Plain bash + grep, so it runs anywhere (no Swift toolchain needed).
#   scripts/check-design-tokens.sh            check
#   scripts/check-design-tokens.sh --update   write the current counts as the new baseline
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="mac/Sources/PhotoCurator"
BASELINE="mac/design-tokens-baseline.txt"

files() { find "$SRC" -name '*.swift' -not -path "$SRC/DesignSystem/*" | sort; }

# count <extended regex> [exclude regex]: number of matches (not lines) in the app sources.
count() {
    local pattern="$1" exclude="${2:-}"
    local out
    out=$(files | xargs grep -ohE "$pattern" 2>/dev/null || true)
    if [[ -n "$exclude" ]]; then out=$(printf '%s\n' "$out" | grep -vE "$exclude" || true); fi
    printf '%s\n' "$out" | grep -c . || true
}

# One variable per metric (now_padding, ...) instead of an associative array: macOS ships bash 3.2.
# .padding(8), .padding(.horizontal, 10), .padding(size * 0.07): any padding with a number in it.
now_padding=$(count '\.padding\([^)]*[0-9][^)]*\)')
# cornerRadius: 12 (RoundedRectangle, .rect(cornerRadius:)).
now_cornerRadius=$(count 'cornerRadius: *[0-9]')
# .font(.system(size: 34 ...)): fixed font sizes; use TypeRole.
now_fontSystemSize=$(count '\.font\(\.system\(size: *[0-9]')
# Raw animation curves and withAnimation without a Motion name.
now_animationCurve=$(( $(count '\.(snappy|spring|bouncy|smooth|easeIn|easeOut|easeInOut|linear|interactiveSpring|interpolatingSpring|timingCurve)\b(\(|[^A-Za-z(])' '\.linear[^A-Za-z(]') \
    + $(count 'withAnimation *(\([A-Za-z.]*|\{)' 'withAnimation *\(Motion\.') \
    + $(count '\.animation\(\.default') ))
now() { local v="now_$1"; echo "${!v}"; }

keys=(padding cornerRadius fontSystemSize animationCurve)

if [[ "${1:-}" == "--update" ]]; then
    {
        echo "# Design-token ratchet baseline (scripts/check-design-tokens.sh). Counts may only go down."
        for k in "${keys[@]}"; do echo "$k=$(now "$k")"; done
    } > "$BASELINE"
    echo "Baseline written to $BASELINE"
fi

[[ -f "$BASELINE" ]] || { echo "Missing $BASELINE (run with --update once)"; exit 1; }

fail=0
printf '%-16s %8s %8s\n' metric baseline now
for k in "${keys[@]}"; do
    base=$(grep -E "^$k=" "$BASELINE" | cut -d= -f2)
    base=${base:-0}
    mark=""; n=$(now "$k")
    if (( n > base )); then mark="  <-- grew: use the DesignSystem tokens"; fail=1
    elif (( n < base )); then mark="  (lower: run --update to ratchet down)"; fi
    printf '%-16s %8s %8s%s\n' "$k" "$base" "$n" "$mark"
done
if (( fail )); then echo "FAIL: hardcoded design values grew (see notes/m12b-design-system.md)"; exit 1; fi
echo "OK"

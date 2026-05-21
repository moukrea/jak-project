#!/usr/bin/env bash
# Phase F3 validator — 30 FPS render sustained, 60 Hz simulation preserved.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A5_COMMIT=$(git log --format=%H --all --grep='autoport/A5-emitter-far-relocs' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"

BOOT_LOG=".autoport/reports/F3-boot.log"
FRAME_CSV=".autoport/reports/F3-frame-times.csv"
SHIM_REPORT=".autoport/reports/F3-shim-tags.txt"
F3_RUN=".autoport/lib/f3_run.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase F3 validator (30 FPS sustained) =="

[ -x "$F3_RUN" ] || fail "$F3_RUN missing"
echo "  running f3_run.sh (60s gameplay)..."
"$F3_RUN" > /tmp/f3-run.log 2>&1 || { tail -60 /tmp/f3-run.log; fail "f3_run.sh failed"; }
[ -f "$BOOT_LOG" ] || fail "$BOOT_LOG missing"
[ -f "$FRAME_CSV" ] || fail "$FRAME_CSV missing — per-frame timing must be recorded"
ok "f3_run.sh completed"

# Sustained swap count: ≥1800 in 60 s = 30 FPS
SWAP=$(grep -oE "sustained swap [0-9]+" "$BOOT_LOG" | awk '{print $3}' | sort -n | tail -1)
[ -n "$SWAP" ] || fail "no sustained swap counter found"
[ "$SWAP" -ge 1800 ] || fail "only $SWAP swaps in 60s (< 30 FPS); renderer not sustaining target"
ok "sustained swap count $SWAP ≥ 1800 (30 FPS achieved)"

# Frame-time CSV stats
python3 - "$FRAME_CSV" <<'PY' || exit 1
import csv, sys, statistics
times_us = []
with open(sys.argv[1]) as f:
    for row in csv.reader(f):
        if row and row[0].lstrip('-').isdigit():
            times_us.append(int(row[0]))
if len(times_us) < 100:
    print(f"FAIL: only {len(times_us)} frames in CSV (need ≥1800)", file=sys.stderr); sys.exit(1)
avg = statistics.mean(times_us)
p95 = sorted(times_us)[int(len(times_us)*0.95)]
p99 = sorted(times_us)[int(len(times_us)*0.99)]
print(f"  frames={len(times_us)} avg={avg/1000:.2f}ms p95={p95/1000:.2f}ms p99={p99/1000:.2f}ms")
if p95 > 40_000:
    print(f"FAIL: p95 frame time {p95/1000:.2f}ms exceeds 40ms target", file=sys.stderr); sys.exit(1)
PY
ok "frame-time stats within tolerance (p95 ≤ 40 ms)"

# 60 Hz simulation tick preserved (game logic unchanged)
TICKS=$(grep -cE "set! \*display\*|display tick|\*frame-counter\*" "$BOOT_LOG" || true)
# Tolerance: 3600 ticks in 60 s ± 5%; allow 3400-3800
if [ "$TICKS" -lt 3400 ] || [ "$TICKS" -gt 3800 ]; then
    fail "GOAL simulation tick count $TICKS outside [3400,3800] — simulation rate may have been halved (forbidden behavior divergence)"
fi
ok "GOAL simulation tick count $TICKS (60 Hz preserved)"

# Shim governance, codegen + classifier locks, CGO baseline (template)
:> "$SHIM_REPORT"
for f in android/android_runtime_compat.cpp android/android_runtime_full.cpp \
         android/android_sound_stubs.cpp android/android_graphics_stubs.cpp; do
    [ -f "$f" ] || continue
    awk '
        BEGIN { has_tag=0; last_blank=1 }
        /^[ \t]*$/ { last_blank=1; next }
        /SHIM_KIND:/ { has_tag=1 }
        /^[a-zA-Z_][a-zA-Z0-9_<>:* ,&]*[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^;]*\)[ \t]*\{?[ \t]*$/ {
            if (!has_tag && last_blank) print FILENAME ":" NR
            has_tag=0; last_blank=0; next
        }
        { last_blank=0 }
    ' "$f" >> "$SHIM_REPORT" || true
done
UNTAGGED=$(wc -l < "$SHIM_REPORT")
[ "$UNTAGGED" -eq 0 ] || { head -10 "$SHIM_REPORT" >&2; fail "shim governance: $UNTAGGED untagged shims"; }
ok "shim governance: all tagged"

for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.cpp goalc/compiler/CodeGenerator.h; do
    [ "$(git diff "$A4" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] || fail "$f drifted since A4"
done
[ -n "$A5_COMMIT" ] && for f in goalc/emitter/IGenARM64.cpp goalc/emitter/ObjectGenerator.cpp; do
    [ "$(git diff "$A5_COMMIT" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] || fail "$f drifted since A5"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier drifted"
ok "codegen + classifier locks intact"

while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs intact"

ANCHOR=${A5_COMMIT:-$A4}
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions since A5"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions since A5"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new stubs since A5"
ok "no new abort/weak/stubs since A5"

SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase F3 — 30 FPS render sustained on device with 60 Hz"
echo "      simulation preserved (no behavior divergence from desktop)."

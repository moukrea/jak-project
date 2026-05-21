#!/usr/bin/env bash
# Phase F1 validator — Geyser Rock reached + game-state matches desktop.
# This is the north-star: identical gameplay behavior on device.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A5_COMMIT=$(git log --format=%H --all --grep='autoport/A5-emitter-far-relocs' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A5_BASELINE=".autoport/reports/A5-baseline-arm64-cgo-hashes.txt"

ORACLE=".autoport/oracle/jak1-desktop-trace.txt"
BOOT_LOG=".autoport/reports/F1-boot.log"
TRACE_DIFF=".autoport/reports/F1-trace-diff.txt"
STATE_DUMP=".autoport/reports/F1-state-frame-600.json"
STATE_REF=".autoport/reports/F1-desktop-state-frame-600.json"
SCREENCAP=".autoport/reports/F1-screencap-frame-600.png"
SCREENCAP_REF=".autoport/reports/F1-geyser-rock-frame-600.png"
SHIM_REPORT=".autoport/reports/F1-shim-tags.txt"
F1_RUN=".autoport/lib/f1_run.sh"

ADB=${ADB:-/home/emeric/Android/platform-tools/adb}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase F1 validator (Geyser Rock gameplay) =="

[ -x "$F1_RUN" ] || fail "$F1_RUN missing or not executable"
ok "f1_run.sh present"

echo "  running f1_run.sh (build → install → 120s gameplay capture)..."
"$F1_RUN" > /tmp/f1-run.log 2>&1 \
    || { tail -60 /tmp/f1-run.log; fail "f1_run.sh failed"; }
[ -f "$BOOT_LOG" ] || fail "$BOOT_LOG missing"
ok "f1_run.sh completed"

# Geyser Rock loaded
grep -qE "load 'geyser-rock|engine: state=in-game|geyser-rock.*loaded" "$BOOT_LOG" \
    || fail "Geyser Rock never loaded — title-to-gameplay transition broken"
ok "Geyser Rock loaded on device"

# Game-state probe at frame 600
[ -f "$STATE_DUMP" ] || fail "$STATE_DUMP missing — game-state dump at frame 600 must be produced"
[ -f "$STATE_REF" ] || fail "$STATE_REF missing — desktop x86 reference state required (run f1_run.sh on desktop build first)"

python3 - "$STATE_DUMP" "$STATE_REF" <<'PY' || fail "game-state divergence at frame 600 — device behavior differs from desktop x86_64"
import json, sys, math
with open(sys.argv[1]) as a, open(sys.argv[2]) as b:
    dev = json.load(a); ref = json.load(b)
EPS_POS = 0.1
def cmp(path, dv, rv):
    if isinstance(rv, list):
        for i,(d,r) in enumerate(zip(dv,rv)):
            cmp(f"{path}[{i}]", d, r)
    elif isinstance(rv, dict):
        for k in rv:
            cmp(f"{path}.{k}", dv.get(k), rv[k])
    elif isinstance(rv, float):
        if not math.isclose(dv, rv, abs_tol=EPS_POS):
            print(f"DIVERGE {path}: dev={dv} ref={rv} delta={abs(dv-rv)}", file=sys.stderr)
            sys.exit(1)
    else:
        if dv != rv:
            print(f"DIVERGE {path}: dev={dv} ref={rv}", file=sys.stderr)
            sys.exit(1)
cmp("$", dev, ref)
PY
ok "game-state at frame 600 matches desktop within position epsilon"

# Screencap phash check (optional but recommended)
if [ -f "$SCREENCAP" ] && [ -f "$SCREENCAP_REF" ]; then
    python3 - "$SCREENCAP" "$SCREENCAP_REF" <<'PY' || fail "screencap diverges from reference (phash distance too high)"
import sys
from PIL import Image
import imagehash
a = imagehash.phash(Image.open(sys.argv[1]))
b = imagehash.phash(Image.open(sys.argv[2]))
d = a - b
if d > 12:
    print(f"phash distance {d} exceeds tolerance 12", file=sys.stderr)
    sys.exit(1)
print(f"phash distance {d} (ok)")
PY
    ok "screencap phash within tolerance of reference"
else
    echo "  skip: screencap phash (no reference; F1 will record one on first pass)"
fi

# Trace-diff to oracle through in-game milestone
.autoport/lib/trace_diff.py \
    --oracle "$ORACLE" \
    --target "$BOOT_LOG" \
    --milestone 'engine: state=in-game' \
    --max-divergence-events 80 \
    > "$TRACE_DIFF" 2>&1 \
    || { cat "$TRACE_DIFF"; fail "trace-diff diverged through in-game milestone"; }
ok "trace-diff matches desktop oracle through in-game"

# Shim governance
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
ok "shim governance: all shims tagged"

# Codegen + classifier + CGO baselines (same template as E1/E2/E3)
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
echo "PASS: Phase F1 — Geyser Rock plays on device with game-state"
echo "      identical to desktop x86_64 reference (within float epsilon)."

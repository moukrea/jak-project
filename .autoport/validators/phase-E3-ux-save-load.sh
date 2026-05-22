#!/usr/bin/env bash
# Phase E3 validator — save file binary-identical to desktop x86_64.
# The whole point: saves are portable between platforms.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A5_COMMIT=$(git log --format=%H --all --grep='autoport/A5-emitter-far-relocs' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A5_BASELINE=".autoport/reports/A5-baseline-arm64-cgo-hashes.txt"

SAVE_REF=".autoport/reports/E3-desktop-save-reference.sha256"
SAVE_DEVICE="/tmp/E3-android-save.bin"
ROUND_TRIP_TRACE=".autoport/reports/E3-roundtrip-trace.txt"
ORACLE=".autoport/oracle/jak1-desktop-trace.txt"
SHIM_REPORT=".autoport/reports/E3-shim-tags.txt"
E3_RUN=".autoport/lib/e3_run.sh"

ADB=${ADB:-/home/emeric/Android/platform-tools/adb}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase E3 validator (save/load binary identity) =="

[ -x "$E3_RUN" ] || fail "$E3_RUN missing or not executable"
ok "e3_run.sh present"

# kmemcard symbols present in libgk.so (not stubbed). Dump nm to a file
# so `nm | grep -q` doesn't SIGPIPE-mask a matching grep — grep -q exits
# the pipe writer with EPIPE the moment it finds the first hit, which
# `set -o pipefail` then treats as a whole-pipeline failure even though
# the check actually passed (per feedback_validator_pipefail_grep_q).
LIBGK="build-android/lib/arm64-v8a/libgk.so"
[ -f "$LIBGK" ] || fail "$LIBGK missing (build must complete first)"
NM_DUMP=$(mktemp); trap "rm -f $NM_DUMP" EXIT
nm --defined-only "$LIBGK" >"$NM_DUMP" 2>/dev/null || true
grep -qE "kmemcard|McRead|McWrite|save_thread" "$NM_DUMP" \
    || fail "kmemcard symbols not present in libgk.so — cross-compile missing"
ok "kmemcard cross-compiled into libgk.so"

# Run device save flow
echo "  running e3_run.sh (save flow)..."
"$E3_RUN" > /tmp/e3-run.log 2>&1 \
    || { tail -60 /tmp/e3-run.log; fail "e3_run.sh failed"; }

# Save file pulled from device
[ -f "$SAVE_DEVICE" ] || fail "$SAVE_DEVICE missing — adb pull did not retrieve a save file"
ok "save file retrieved from device"

# Binary identity vs desktop reference
[ -f "$SAVE_REF" ] || fail "$SAVE_REF missing — desktop reference save hash must be produced first (run save flow on desktop x86 build)"
EXPECTED=$(cut -d' ' -f1 < "$SAVE_REF")
ACTUAL=$(sha256sum "$SAVE_DEVICE" | cut -d' ' -f1)
if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "  expected (desktop): $EXPECTED" >&2
    echo "  actual   (android): $ACTUAL"   >&2
    fail "save file NOT byte-identical to desktop — binary format diverges; saves are not portable"
fi
ok "save file byte-identical to desktop x86_64 reference"

# Round-trip: load Android save on desktop, capture trace, diff
echo "  round-trip: loading Android save on desktop x86_64..."
RT_LOG=$(mktemp); trap "rm -f $RT_LOG" EXIT
timeout 120 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso \
    -load-save "$SAVE_DEVICE" -- -boot -debug-mem > "$RT_LOG" 2>&1 || true
grep -q "link finish: logo$" "$RT_LOG" || { tail -20 "$RT_LOG"; fail "desktop failed to boot from Android-produced save"; }
ok "Android save loads on desktop x86_64 — boots through to title"

.autoport/lib/trace_diff.py \
    --oracle "$ORACLE" \
    --target "$RT_LOG" \
    --milestone 'link finish: logo' \
    --max-divergence-events 30 \
    > "$ROUND_TRIP_TRACE" 2>&1 \
    || { cat "$ROUND_TRIP_TRACE"; fail "round-trip trace diverged from oracle — Android save introduces state drift"; }
ok "round-trip trace matches oracle"

# Shim governance scan
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

# Codegen + classifier locks intact
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.cpp goalc/compiler/CodeGenerator.h; do
    [ "$(git diff "$A4" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] || fail "$f drifted since A4"
done
[ -n "$A5_COMMIT" ] && {
    for f in goalc/emitter/IGenARM64.cpp goalc/emitter/ObjectGenerator.cpp; do
        [ "$(git diff "$A5_COMMIT" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] || fail "$f drifted since A5"
    done
}
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier drifted"
ok "codegen + classifier locks intact"

# x86 + arm64 CGO baselines
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs intact"

[ -f "$A5_BASELINE" ] && {
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "arm64 CGO drift since A5: $path"
    done < "$A5_BASELINE"
    ok "arm64 CGOs intact"
}

# No new abort/weak/stubs since A5
ANCHOR=${A5_COMMIT:-$A4}
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions since A5"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions since A5"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new stubs since A5"
ok "no new abort/weak/stubs since A5"

# Desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase E3 — Android save file byte-identical to desktop x86_64,"
echo "      round-trips losslessly through trace-diff."

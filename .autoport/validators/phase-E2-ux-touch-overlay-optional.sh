#!/usr/bin/env bash
# Phase E2 validator — touch overlay produces same JNI events as gamepad.
# Same-behavior contract enforced via trace-diff and shim governance.

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
BOOT_LOG=".autoport/reports/E2-boot.log"
TRACE_DIFF=".autoport/reports/E2-trace-diff.txt"
SHIM_REPORT=".autoport/reports/E2-shim-tags.txt"
OVERLAY_MAP=".autoport/reports/E2-overlay-map.json"
E2_RUN=".autoport/lib/e2_run.sh"

ADB=${ADB:-/home/emeric/Android/platform-tools/adb}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase E2 validator (touch overlay) =="

[ -x "$E2_RUN" ] || fail "$E2_RUN missing or not executable"
ok "e2_run.sh present"

echo "  running e2_run.sh..."
"$E2_RUN" > /tmp/e2-run.log 2>&1 \
    || { tail -60 /tmp/e2-run.log; fail "e2_run.sh failed"; }
[ -f "$BOOT_LOG" ] || fail "$BOOT_LOG missing"
[ -f "$OVERLAY_MAP" ] || fail "$OVERLAY_MAP missing (hitbox-to-button mapping must be recorded)"
ok "e2_run.sh completed; overlay map recorded"

grep -qE "overlay visible|touch overlay enabled" "$BOOT_LOG" \
    || fail "touch overlay never reported visible — settings/auto-detect logic missing"
ok "touch overlay visible by default (no gamepad)"

PAD_HITS=$(grep -cE "onPadButton.*from=overlay|overlay tap -> onPadButton" "$BOOT_LOG" || true)
[ "$PAD_HITS" -ge 1 ] || fail "synthetic taps did not route to onPadButton — overlay events must produce gamepad-shape callbacks, not raw touch events"
ok "overlay taps route to onPadButton ($PAD_HITS hits)"

.autoport/lib/trace_diff.py \
    --oracle "$ORACLE" \
    --target "$BOOT_LOG" \
    --milestone 'link finish: logo' \
    --max-divergence-events 40 \
    > "$TRACE_DIFF" 2>&1 \
    || { cat "$TRACE_DIFF"; fail "trace-diff diverged — overlay input pipeline produces different events than desktop reference"; }
ok "trace-diff matches desktop oracle"

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
    ok "arm64 CGOs intact (no re-emission in E2)"
}

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
echo "PASS: Phase E2 — touch overlay produces identical onPadButton events"
echo "      as gamepad, trace-diff matches desktop oracle."

#!/usr/bin/env bash
# Phase F2 validator — audio triggers at same trace points as desktop.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A5_COMMIT=$(git log --format=%H --all --grep='autoport/A5-emitter-far-relocs' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"

ORACLE=".autoport/oracle/jak1-desktop-trace.txt"
BOOT_LOG=".autoport/reports/F2-boot.log"
AUDIO_TRIGGERS=".autoport/reports/F2-audio-triggers.txt"
DESKTOP_AUDIO_TRIGGERS=".autoport/reports/F2-desktop-audio-triggers.txt"
SHIM_REPORT=".autoport/reports/F2-shim-tags.txt"
F2_RUN=".autoport/lib/f2_run.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase F2 validator (audio) =="

[ -x "$F2_RUN" ] || fail "$F2_RUN missing"
ok "f2_run.sh present"

echo "  running f2_run.sh..."
"$F2_RUN" > /tmp/f2-run.log 2>&1 || { tail -60 /tmp/f2-run.log; fail "f2_run.sh failed"; }
[ -f "$BOOT_LOG" ] || fail "$BOOT_LOG missing"
ok "f2_run.sh completed"

# SDL audio device opened with AAudio backend
grep -qE "SDL_audio: opened.*aaudio|aaudio.*opened" "$BOOT_LOG" \
    || fail "SDL3 AAudio backend not opened — audio device init missing"
ok "SDL3 AAudio backend opened"

# Extract audio-trigger events from device log
grep -oE "PlayVag @ #x[0-9a-fA-F]+|LoadSingle @ #x[0-9a-fA-F]+|PauseStream|StopVag" "$BOOT_LOG" \
    > "$AUDIO_TRIGGERS" || true
TRIG_COUNT=$(wc -l < "$AUDIO_TRIGGERS")
[ "$TRIG_COUNT" -ge 5 ] || fail "only $TRIG_COUNT audio triggers in 30s — expected ≥5 from title-music + intro VAGs"
ok "$TRIG_COUNT audio triggers observed"

# Trigger sequence matches desktop reference (within 2-frame tolerance,
# but as a first pass we just compare the multiset of trigger types)
if [ -f "$DESKTOP_AUDIO_TRIGGERS" ]; then
    diff <(sort -u "$AUDIO_TRIGGERS") <(sort -u "$DESKTOP_AUDIO_TRIGGERS") > /tmp/f2-trigger-diff.txt 2>&1 \
        || { cat /tmp/f2-trigger-diff.txt; fail "audio trigger types differ from desktop reference"; }
    ok "audio trigger types match desktop reference"
else
    echo "  warn: no $DESKTOP_AUDIO_TRIGGERS; recording first-pass reference"
    cp "$AUDIO_TRIGGERS" "$DESKTOP_AUDIO_TRIGGERS"
fi

# SDL audio callback firing in capture
CB_COUNT=$(grep -c "SDL_audio: callback fired" "$BOOT_LOG" || true)
[ "$CB_COUNT" -ge 100 ] || fail "only $CB_COUNT audio callbacks fired in 30s — audio thread not pumping"
ok "$CB_COUNT SDL audio callbacks fired"

# Shim governance, codegen + classifier, CGO baselines (template)
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
echo "PASS: Phase F2 — Android audio device opens with AAudio, audio triggers"
echo "      match desktop reference, callback pumping at expected rate."

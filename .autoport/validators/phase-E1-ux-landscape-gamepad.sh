#!/usr/bin/env bash
# Phase E1 validator — landscape rendering + Bluetooth gamepad on device.
#
# Authored by the supervisor 2026-05-21 (replaces May-21 placeholder).
# Enforces the same-behavior contract: identical input pipeline shape to
# the desktop x86_64 port, verified via on-device install + trace-diff
# against the desktop oracle. NO log-string-only checks. NO synthetic
# stubs. The shim-governance scan begins here and applies to every
# later phase.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true

A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1_COMMIT=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A5_BASELINE=".autoport/reports/A5-baseline-arm64-cgo-hashes.txt"
A5_COMMIT=$(git log --format=%H --all --grep='autoport/A5-emitter-far-relocs' | head -1)

ORACLE=".autoport/oracle/jak1-desktop-trace.txt"
BOOT_LOG=".autoport/reports/E1-boot.log"
TRACE_DIFF=".autoport/reports/E1-trace-diff.txt"
SHIM_REPORT=".autoport/reports/E1-shim-tags.txt"
E1_RUN=".autoport/lib/e1_run.sh"

PACKAGE="org.opengoal.gk.jak1"
ADB=${ADB:-/home/emeric/Android/platform-tools/adb}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase E1 validator (landscape + Bluetooth gamepad) =="

# ---- 1. e1_run.sh exists + executable ----
[ -x "$E1_RUN" ] || fail "$E1_RUN missing or not executable"
ok "e1_run.sh present"

# ---- 2. Device attached ----
device_require_attached 2>/dev/null || {
    "$ADB" devices | grep -qE 'device$' || fail "no device attached"
}
ok "device attached"

# ---- 3. Build + install + capture via e1_run.sh ----
echo "  running e1_run.sh (build → install → launch → 60s capture)..."
"$E1_RUN" > /tmp/e1-run.log 2>&1 \
    || { tail -60 /tmp/e1-run.log; fail "e1_run.sh failed"; }
[ -f "$BOOT_LOG" ] || fail "$BOOT_LOG missing"
ok "e1_run.sh completed"

# ---- 4. Landscape orientation verified on device ----
ORIENT=$("$ADB" shell dumpsys window 2>&1 | grep -oE 'mCurrentRotation=ROTATION_[0-9]+' | head -1 || true)
case "$ORIENT" in
    *ROTATION_90*|*ROTATION_270*) ok "landscape orientation: $ORIENT" ;;
    *) fail "device not in landscape ($ORIENT) — manifest or activity orientation lock missing" ;;
esac

# Also verify SDL window has w > h
SDL_W=$(grep -oE "SDL_CreateWindow: [0-9]+x[0-9]+" "$BOOT_LOG" | head -1 | grep -oE "[0-9]+x[0-9]+" || true)
[ -n "$SDL_W" ] || fail "no SDL_CreateWindow size logged"
WIDTH=$(echo "$SDL_W" | cut -dx -f1)
HEIGHT=$(echo "$SDL_W" | cut -dx -f2)
[ "$WIDTH" -gt "$HEIGHT" ] || fail "SDL window not landscape ($SDL_W)"
ok "SDL window landscape: $SDL_W"

# ---- 5. Gamepad subsystem initialized ----
grep -qE "SDL_Init: gamepad subsystem OK|SDL_INIT_GAMEPAD|gamepad subsystem initialized" "$BOOT_LOG" \
    || fail "SDL gamepad subsystem never reported initialized in logcat"
ok "gamepad subsystem initialized"

# ---- 6. Bluetooth gamepad event fired ----
# Either SDL_EVENT_GAMEPAD_ADDED on real device, or an existing-pad open
# event (SDL_GAMEPAD: opened "<name>").
grep -qE "SDL_EVENT_GAMEPAD_ADDED|SDL_OpenGamepad|SDL_GAMEPAD: opened|Java_org_opengoal_gk_NativeGk_onPadButton" "$BOOT_LOG" \
    || fail "no gamepad event in 60s capture window — connect a Bluetooth pad and press a button DURING the run; e1_run.sh prints a 'press a button now' prompt that should be visible to the operator"
ok "gamepad event observed in capture"

# ---- 7. JNI onPadButton callback fired (proves event reached the runtime) ----
PADBTN_HITS=$(grep -cE "onPadButton|opengoal-gk: pad-state poll" "$BOOT_LOG" || true)
[ "$PADBTN_HITS" -ge 1 ] || fail "no onPadButton JNI callback observed — gamepad event didn't reach the GOAL runtime"
ok "pad event reached JNI/GOAL runtime ($PADBTN_HITS hits)"

# ---- 8. Trace-diff against desktop oracle through title-screen milestone ----
.autoport/lib/trace_diff.py \
    --oracle "$ORACLE" \
    --target "$BOOT_LOG" \
    --milestone 'link finish: logo' \
    --max-divergence-events 30 \
    > "$TRACE_DIFF" 2>&1 \
    || { cat "$TRACE_DIFF"; fail "trace-diff against desktop oracle DIVERGED — on-device event sequence is not a subsequence of the x86_64 reference; investigate the diff above"; }
ok "trace-diff matches desktop oracle through title-screen milestone"

# ---- 9. Shim governance: every function in android_runtime_compat.cpp +
#         android_runtime_full.cpp must carry a SHIM_KIND tag ----
mkdir -p .autoport/reports
:> "$SHIM_REPORT"
UNTAGGED=0
for f in android/android_runtime_compat.cpp android/android_runtime_full.cpp \
         android/android_sound_stubs.cpp android/android_graphics_stubs.cpp; do
    [ -f "$f" ] || continue
    # Find every function definition (heuristic: `<type> <name>(` at column 0
    # OR after a return type on the previous line — we approximate with
    # grep, accepting some false positives that the SHIM_KIND comment scan
    # then filters).
    awk '
        BEGIN { in_func=0; last_blank=1 }
        /^[ \t]*$/ { last_blank=1; next }
        /SHIM_KIND:/ { has_tag=1 }
        /^[a-zA-Z_][a-zA-Z0-9_<>:* ,&]*[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*\([^;]*\)[ \t]*\{?[ \t]*$/ {
            if (!has_tag && last_blank) {
                print FILENAME ":" NR ": " $0
            }
            has_tag=0; last_blank=0
            next
        }
        { last_blank=0 }
    ' "$f" >> "$SHIM_REPORT" || true
done
UNTAGGED=$(wc -l < "$SHIM_REPORT")
if [ "$UNTAGGED" -gt 0 ]; then
    echo "Untagged shim definitions found ($UNTAGGED):" >&2
    head -20 "$SHIM_REPORT" >&2
    fail "shim governance: $UNTAGGED function(s) lack a SHIM_KIND tag — every entry must declare BIONIC_ADAPTER / PS2_HW_EMULATION / PLATFORM_FEATURE / OPTIONAL_OFF or be removed as a DODGE shim"
fi
ok "shim governance: all shims carry SHIM_KIND tags"

# ---- 10. Codegen + classifier locks intact (A5-close anchors) ----
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.cpp goalc/compiler/CodeGenerator.h; do
    DIFF=$(git diff "$A4_COMMIT" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A4 (codegen-lock violation)"
done
[ -n "$A5_COMMIT" ] && {
    for f in goalc/emitter/IGenARM64.cpp goalc/emitter/ObjectGenerator.cpp; do
        DIFF=$(git diff "$A5_COMMIT" HEAD -- "$f" 2>/dev/null | wc -l)
        [ "$DIFF" -eq 0 ] || fail "$f changed since A5 (codegen-lock violation; A5 unlock was for A5 only)"
    done
}
CLF_DIFF=$(git diff "$A1_COMMIT" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)
[ "$CLF_DIFF" -eq 0 ] || fail "classifier modified since A1"
ok "codegen + classifier locks intact"

# ---- 11. x86 CGO baseline preserved ----
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == /* || "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# ---- 12. arm64 CGOs byte-identical to A5 baseline (E1 must not re-emit) ----
if [ -f "$A5_BASELINE" ]; then
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "arm64 CGO drift since A5: $path"
    done < "$A5_BASELINE"
    ok "arm64 CGOs byte-identical to A5 baseline"
fi

# ---- 13. No new abort/weak/stubs since A5-close ----
ANCHOR=${A5_COMMIT:-$A4_COMMIT}
ABORTS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
[ "$ABORTS" -eq 0 ] || fail "$ABORTS abort() additions since A5-close"
WEAK=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)
[ "$WEAK" -eq 0 ] || fail "$WEAK weak attribute additions since A5-close"
NEW_STUBS=$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)
[ -z "$NEW_STUBS" ] || fail "new *_stubs.cpp files since A5-close: $NEW_STUBS"
ok "no new abort/weak/stubs since A5-close"

# ---- 14. Desktop x86 smoke still works ----
SMOKE_LOG=$(mktemp); trap "rm -f $SMOKE_LOG" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE_LOG" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE_LOG" || { tail -25 "$SMOKE_LOG"; fail "desktop gk did not reach 'link finish: logo'"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase E1 — landscape orientation locked, Bluetooth gamepad"
echo "      reaches GOAL runtime, on-device trace matches desktop oracle"
echo "      through title-screen milestone, shim governance enforced."

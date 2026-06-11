#!/usr/bin/env bash
# Phase A41 validator — LEAN + physical renderer checks.
# Hard gates: no forbidden edits, x86 boots, qemu no regression, renderer
# symbols physically present in libgk.so, device screencap + report exist.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A40_CLOSE=$(git log --format=%H --all --grep='autoport/A40-android-hint-cursor-reset-goal-frame' | head -1)
A39_CLOSE=$(git log --format=%H --all --grep='autoport/A39-android-goal-frame-capture' | head -1)
ANCHOR=${A40_CLOSE:-${A39_CLOSE:-HEAD}}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A41 validator (renderer DMA→GLES bring-up) =="
echo "  anchor: $ANCHOR"

# 1. Forbidden edits (the only hard locks)
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
[ "$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)" -eq 0 ] || fail "goal_src/ edited (shared with x86)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra (lib/validators) edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
ok "no forbidden edits (IGenX86_64 / goal_src / infra all untouched)"

# 2. Anti-cheat patterns
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge pattern present"
WEAK=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)
[ "$WEAK" -eq 0 ] || fail "weak symbol additions ($WEAK)"
ABRT=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
[ "$ABRT" -eq 0 ] || fail "abort additions ($ABRT)"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp"
FAKE_LINK=$(git diff "$ANCHOR" HEAD -- 'game/**/*.cpp' 'game/**/*.s' 2>/dev/null | grep -cE '^\+.*printf.*link finish' || true)
[ "$FAKE_LINK" -eq 0 ] || fail "fake 'link finish' printf injected ($FAKE_LINK)"
# Renderer-specific cheat: hardcoded image blits pretending to be game content
FAKE_FRAME=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|test_pattern)' || true)
[ "$FAKE_FRAME" -eq 0 ] || fail "suspicious hardcoded-image/test-pattern additions ($FAKE_FRAME)"
ok "anti-cheat clean (no weak/abort/dodge/stubs/fake-link/fake-frame)"

# 3. Required report
REPORTS=$(find .autoport/reports -maxdepth 1 \( -name 'A41-fix-summary.md' -o -name 'A41-attempt-*-next-blocker.md' -o -name 'A41-attempt-*-progress.md' \) 2>/dev/null | wc -l)
[ "$REPORTS" -gt 0 ] || fail "no A41 report (fix-summary / next-blocker / progress)"
LATEST=$(ls -t .autoport/reports/A41-fix-summary.md .autoport/reports/A41-attempt-*-next-blocker.md .autoport/reports/A41-attempt-*-progress.md 2>/dev/null | head -1)
LINES=$(wc -l < "$LATEST")
[ "$LINES" -ge 80 ] || fail "$LATEST too short ($LINES lines, need >=80)"
ok "A41 report present: $(basename "$LATEST") ($LINES lines)"

# 4. x86 desktop smoke — the KEY gate
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -25 "$SMOKE"; fail "x86 desktop smoke regressed — x86 no longer reaches link finish: logo"; }
ok "x86 desktop smoke passes (link finish: logo)"

# 5. qemu boot count — no regression
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a41-qemu.log 2>&1 || true
    N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a41-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    LAST=$(grep -E "link finish:" /tmp/a41-qemu.log | tail -1 | sed 's/.*link finish: //' | head -c 40 || true)
    [ "$N" -ge 675 ] || fail "qemu link-finish regressed: $N (floor 675)"
    ok "qemu link-finish count $N (>=675, no regression; last='$LAST')"
fi

# 6. native-log routing preserved (gk_log_pipe)
ROUTING=$(grep -rlE "dup2|__android_log_write|__android_log_print|android_log_pipe|gk_log_pipe" android/ game/ 2>/dev/null | xargs grep -lE "STDOUT_FILENO|STDERR_FILENO|stdout|stderr|fileno" 2>/dev/null | head -1)
[ -n "$ROUTING" ] || fail "no native stdout/stderr → logcat routing found (gk_log_pipe lost)"
ok "native-log routing present ($ROUTING)"

# 7. PHYSICAL renderer artifact: DirectRenderer + DMA follower compiled into libgk.so
LIBGK=$(find build-android -name 'libgk.so' 2>/dev/null | head -1)
[ -n "$LIBGK" ] || fail "no libgk.so in build-android (renderer port must be compiled)"
NM_OUT_FILE=$(mktemp)
nm -C "$LIBGK" > "$NM_OUT_FILE" 2>/dev/null || llvm-nm -C "$LIBGK" > "$NM_OUT_FILE" 2>/dev/null || true
DIRECT_N=$(grep -c "DirectRenderer" "$NM_OUT_FILE" || true)
DMA_N=$(grep -cE "DmaFollower|send_chain" "$NM_OUT_FILE" || true)
rm -f "$NM_OUT_FILE"
[ "$DIRECT_N" -ge 5 ] || fail "DirectRenderer not compiled into libgk.so ($DIRECT_N symbols, need >=5) — the renderer port is the phase"
[ "$DMA_N" -ge 2 ] || fail "DMA chain consumption not compiled into libgk.so ($DMA_N DmaFollower/send_chain symbols, need >=2)"
ok "renderer physically present in libgk.so (DirectRenderer=$DIRECT_N, dma=$DMA_N symbols)"

# 8. Device screencap evidence
SHOT=$(ls .autoport/reports/A41-device-*.png 2>/dev/null | head -1)
[ -n "$SHOT" ] || fail "no A41-device-*.png screencap (device evidence required — a dark frame is still evidence)"
SHOT_SZ=$(stat -c %s "$SHOT" 2>/dev/null || echo 0)
[ "$SHOT_SZ" -gt 1000 ] || fail "screencap $SHOT looks empty ($SHOT_SZ bytes)"
ok "device screencap present: $(basename "$SHOT") ($SHOT_SZ bytes)"

# 9. Sustained-loop evidence: frame counter must reach 300+ in the newest A36 logcat
NEWLOG=$(ls -t .autoport/reports/A41-routed-logcat-*.log 2>/dev/null | head -1)
[ -n "$NEWLOG" ] || fail "no A41 routed logcat (device run evidence required)"
FRAME_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1)
FRAME_MAX=${FRAME_MAX:-0}
[ "$FRAME_MAX" -ge 300 ] || fail "kernel/display loop not sustained: max frame=$FRAME_MAX in $(basename "$NEWLOG") (need >=300)"
ok "display loop sustained: frame counter reached $FRAME_MAX"
TRIS_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "tris=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1)
TRIS_MAX=${TRIS_MAX:-0}
[ "$TRIS_MAX" -gt 0 ] || fail "renderer draws nothing: max tris=$TRIS_MAX (need >0)"
ok "renderer drawing: max tris=$TRIS_MAX"

# Note: whether any screencap shows REAL GAME CONTENT is judged by the
# supervisor (vision) independently. A fix-summary claiming a render is
# cross-checked by the supervisor's own multi-frame capture.

echo ""
echo "PASS: Phase A41 — renderer DMA→GLES bring-up (lean gates). qemu=$N. Supervisor judges the frames."

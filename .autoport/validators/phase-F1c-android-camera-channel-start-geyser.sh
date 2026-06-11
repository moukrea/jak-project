#!/usr/bin/env bash
# Phase F1c validator — LEAN + physical renderer checks.
# Hard gates: no forbidden edits, x86 boots, qemu no regression, renderer
# symbols physically present in libgk.so, device screencap + report exist.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

F1B_CLOSE=$(git log --format=%H --all --grep='autoport/F1b-android-joint-decompress-start-geyser' | head -1)
F1A_CLOSE=$(git log --format=%H --all --grep='autoport/F1a-android-camera-merc-title-correct' | head -1)
ANCHOR=${F1B_CLOSE:-${F1A_CLOSE:-HEAD}}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase F1c validator (renderer DMA→GLES bring-up) =="
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
# STRICT (supervisor 2026-06-11, post-F1b false-green): PASS requires a real
# F1c-fix-summary.md. A progress/next-blocker report does NOT satisfy this gate
# — it triggers retry, then an honest BLOCK the supervisor carries forward.
[ -f .autoport/reports/F1c-fix-summary.md ] || fail "no F1c-fix-summary.md — progress/next-blocker reports do NOT pass this phase (honest block, not false-green)"
LATEST=.autoport/reports/F1c-fix-summary.md
LINES=$(wc -l < "$LATEST")
[ "$LINES" -ge 80 ] || fail "$LATEST too short ($LINES lines, need >=80)"
ok "F1c report present: $(basename "$LATEST") ($LINES lines)"

# 4. x86 desktop smoke — the KEY gate
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -25 "$SMOKE"; fail "x86 desktop smoke regressed — x86 no longer reaches link finish: logo"; }
ok "x86 desktop smoke passes (link finish: logo)"

# 5. qemu boot count — no regression
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/f1c-qemu.log 2>&1 || true
    N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/f1c-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    LAST=$(grep -E "link finish:" /tmp/f1c-qemu.log | tail -1 | sed 's/.*link finish: //' | head -c 40 || true)
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
MERC_N=$(grep -ciE "MercRenderer|Merc2" "$NM_OUT_FILE" || true)
rm -f "$NM_OUT_FILE"
[ "$DIRECT_N" -ge 5 ] || fail "DirectRenderer not compiled into libgk.so ($DIRECT_N symbols, need >=5) — the renderer port is the phase"
[ "$DMA_N" -ge 2 ] || fail "DMA chain consumption not compiled into libgk.so ($DMA_N DmaFollower/send_chain symbols, need >=2)"
ok "renderer physically present in libgk.so (DirectRenderer=$DIRECT_N, dma=$DMA_N symbols)"
[ "${MERC_N:-0}" -ge 5 ] || fail "MercRenderer not compiled into libgk.so (merc syms=$MERC_N, need >=5) — the merc port is half the phase"
ok "merc renderer physically present (syms=$MERC_N)"

# 8. Device screencap evidence
SHOT=$(ls .autoport/reports/F1c-device-*.png 2>/dev/null | head -1)
[ -n "$SHOT" ] || fail "no F1c-device-*.png screencap (device evidence required — a dark frame is still evidence)"
SHOT_SZ=$(stat -c %s "$SHOT" 2>/dev/null || echo 0)
[ "$SHOT_SZ" -gt 1000 ] || fail "screencap $SHOT looks empty ($SHOT_SZ bytes)"
ok "device screencap present: $(basename "$SHOT") ($SHOT_SZ bytes)"

# 9. Sustained-loop evidence: frame counter must reach 300+ in the newest A36 logcat
NEWLOG=$(ls -t .autoport/reports/F1c-routed-logcat-*.log 2>/dev/null | head -1)
[ -n "$NEWLOG" ] || fail "no F1b routed logcat (device run evidence required)"
FRAME_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1)
FRAME_MAX=${FRAME_MAX:-0}
[ "$FRAME_MAX" -ge 300 ] || fail "kernel/display loop not sustained: max frame=$FRAME_MAX in $(basename "$NEWLOG") (need >=300)"
ok "display loop sustained: frame counter reached $FRAME_MAX"
TRIS_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "tris=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1)
TRIS_MAX=${TRIS_MAX:-0}
[ "$TRIS_MAX" -gt 0 ] || fail "renderer draws nothing: max tris=$TRIS_MAX (need >0)"
ok "renderer drawing: max tris=$TRIS_MAX"

# Camera-flight / level marker — defeats stale village-render false-green.
# Require evidence the title course actually progressed OR a level loaded.
FLIGHT=$(grep -acE "A37-CAM.*(fly|flight|pose-delta|moving)|F1C-CAMFLY|link finish: (training|geyser)|level.*(training|geyser).*(load|stream)" "$NEWLOG" 2>/dev/null || true)
[ "${FLIGHT:-0}" -ge 1 ] || fail "no camera-flight / level-load marker in newest F1c logcat — village rendering alone is the PRE-EXISTING state, not this phase's deliverable"
ok "camera-flight / level marker present ($FLIGHT lines)"

# Note: whether any screencap shows REAL GAME CONTENT is judged by the
# supervisor (vision) independently. A fix-summary claiming a render is
# cross-checked by the supervisor's own multi-frame capture.

echo ""
echo "PASS: Phase F1c — renderer DMA→GLES bring-up (lean gates). qemu=$N. Supervisor judges the frames."

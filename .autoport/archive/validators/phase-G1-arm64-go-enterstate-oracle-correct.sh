#!/usr/bin/env bash
# Phase G1 validator — STRICT, TITLE-REGRESSION GATE (supervisor 2026-06-13).
# Floor deliverable: the title is STABLE again (crash-free flying title) after
# F1f regressed it (sig=11 fault=0x7effffffec = control-transfer-to-garbage in
# the arm64 enter-state/go path). Fix must be oracle-grounded, not guesswork.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

# Baseline = last verified-stable title (F1e close).
F1E_CLOSE=$(git log --format=%H --all --grep='F1e-android-reveal-crash-fix' | head -1)
ANCHOR=${F1E_CLOSE:-HEAD}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase G1 validator (arm64 go/enter-state oracle-correct; title-regression gate) =="
echo "  anchor (stable-title baseline): $ANCHOR"

# 1. Forbidden edits — x86 oracle and shared source must stay untouched.
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited — the oracle is ground truth, never edit it"
[ "$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)" -eq 0 ] || fail "goal_src/ edited (shared with x86; the .gc is correct — fix the arm64 mechanism)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra (lib/validators/agents) edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
ok "no forbidden edits"

# 2. Anti-cheat
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge pattern present"
WEAK=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)
[ "$WEAK" -eq 0 ] || fail "weak symbol additions ($WEAK)"
ABRT=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
[ "$ABRT" -eq 0 ] || fail "abort additions ($ABRT)"
SIGSWALLOW=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(sigsetjmp|siglongjmp)' || true)
[ "$SIGSWALLOW" -eq 0 ] || fail "sigsetjmp/siglongjmp fault-swallow added — fix the control transfer, don't catch the crash"
ok "anti-cheat clean"

# 3. Required report — must engage the mechanism AND show oracle work
[ -f .autoport/reports/G1-fix-summary.md ] || fail "no G1-fix-summary.md — progress/next-blocker reports do NOT pass (honest block, not false-green)"
LATEST=.autoport/reports/G1-fix-summary.md
LINES=$(wc -l < "$LATEST")
[ "$LINES" -ge 80 ] || fail "$LATEST too short ($LINES lines, need >=80)"
grep -qiE 'enter-state|enter_state|\bgo\b|control.transfer|\.jr' "$LATEST" || fail "fix-summary never engages the enter-state/go mechanism"
grep -qiE 'oracle|x86.*arm64|disasm|objdump|addr2line' "$LATEST" || fail "fix-summary shows no x86-oracle diff — this phase REQUIRES oracle grounding, not device guesswork"
grep -qiE '0x7effffffec|7effffffec|control.transfer|return address|RA' "$LATEST" || fail "fix-summary never engages the actual crash (fault=0x7effffffec / corrupted return address)"
ok "G1 fix-summary present ($LINES lines; engages mechanism + oracle + the real crash)"

# 4. x86 desktop smoke — oracle must still boot
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -25 "$SMOKE"; fail "x86 desktop smoke regressed"; }
ok "x86 desktop smoke passes (link finish: logo)"

# 5. qemu boot count — no regression
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/g1-qemu.log 2>&1 || true
    N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/g1-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    [ "$N" -ge 675 ] || fail "qemu link-finish regressed: $N (floor 675)"
    ok "qemu link-finish count $N (>=675)"
fi

# 6. native-log routing
ROUTING=$(grep -rlE "dup2|__android_log_write|__android_log_print|android_log_pipe|gk_log_pipe" android/ game/ 2>/dev/null | xargs grep -lE "STDOUT_FILENO|STDERR_FILENO|stdout|stderr|fileno" 2>/dev/null | head -1)
[ -n "$ROUTING" ] || fail "no native stdout/stderr -> logcat routing (gk_log_pipe lost)"
ok "native-log routing present"

# 7. Renderer physically present
LIBGK=$(find build-android -name 'libgk.so' 2>/dev/null | head -1)
[ -n "$LIBGK" ] || fail "no libgk.so in build-android"
NM_OUT_FILE=$(mktemp)
nm -C "$LIBGK" > "$NM_OUT_FILE" 2>/dev/null || llvm-nm -C "$LIBGK" > "$NM_OUT_FILE" 2>/dev/null || true
DIRECT_N=$(grep -c "DirectRenderer" "$NM_OUT_FILE" || true); MERC_N=$(grep -ciE "MercRenderer|Merc2" "$NM_OUT_FILE" || true)
rm -f "$NM_OUT_FILE"
[ "$DIRECT_N" -ge 5 ] || fail "DirectRenderer missing ($DIRECT_N)"
[ "${MERC_N:-0}" -ge 5 ] || fail "MercRenderer missing ($MERC_N)"
ok "renderer present (DirectRenderer=$DIRECT_N, merc=$MERC_N)"

# 8. Device screencap
SHOT=$(ls .autoport/reports/G1-device-*.png 2>/dev/null | head -1)
[ -n "$SHOT" ] || fail "no G1-device-*.png"
[ "$(stat -c %s "$SHOT" 2>/dev/null || echo 0)" -gt 1000 ] || fail "screencap $SHOT looks empty"
ok "device screencap present: $(basename "$SHOT")"

# 9. THE TITLE-REGRESSION GATE — newest G1 boot must be crash-free + sustained
NEWLOG=$(ls -t .autoport/reports/G1-routed-logcat-*.log 2>/dev/null | head -1)
[ -n "$NEWLOG" ] || fail "no G1 routed logcat"
CRASHES=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true)
[ "${CRASHES:-0}" -eq 0 ] || fail "TITLE STILL CRASHES: $CRASHES sig=11 lines in $(basename "$NEWLOG") — the regression is not fixed (floor not met)"
MODE=$(grep -ac "set-master-mode" "$NEWLOG" 2>/dev/null || true)
[ "${MODE:-0}" -ge 1 ] || fail "boot never reached set-master-mode"
FRAME_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1); FRAME_MAX=${FRAME_MAX:-0}
[ "$FRAME_MAX" -ge 300 ] || fail "title loop not sustained: max frame=$FRAME_MAX (need >=300, crash-free)"
TRIS_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "tris=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1); TRIS_MAX=${TRIS_MAX:-0}
[ "$TRIS_MAX" -gt 0 ] || fail "renderer draws nothing (tris=$TRIS_MAX)"
ok "title stable: ZERO sig=11, set-master-mode reached, frame=$FRAME_MAX, tris=$TRIS_MAX"

# 10. Focus held
NEWFOCUS=$(ls -t .autoport/reports/G1-focus-*.txt 2>/dev/null | head -1)
[ -n "$NEWFOCUS" ] || fail "no G1-focus-*.txt"
echo "$(grep -a . "$NEWFOCUS" | tail -1)" | grep -q "org.opengoal.gk.jak1" || fail "final focus is NOT the app (title crashed/backgrounded)"
ok "final focus still org.opengoal.gk.jak1"

echo ""
echo "PASS: Phase G1 — title stable (0 crashes, frame=$FRAME_MAX) on an oracle-grounded enter-state/go fix. Supervisor judges the flying title + whether the cinematic still plays."

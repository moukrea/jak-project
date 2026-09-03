#!/usr/bin/env bash
# Phase F1f validator — STRICT, hardened against the F1d false-green.
# F1d's play-marker was satisfied by BOOT-TIME attract telemetry (master-mode
# 'game + static target at f=15). F1f requires what only a SPAWNED, MOVING Jak
# produces: many DISTINCT non-nan target positions and a non-nan tail.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

F1E_CLOSE=$(git log --format=%H --all --grep='autoport/F1e-android-reveal-crash-fix' | head -1)
ANCHOR=${F1E_CLOSE:-HEAD}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase F1f validator (go control-transfer -> Jak spawns and moves) =="
echo "  anchor: $ANCHOR"

# 1. Forbidden edits (hard locks)
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
[ "$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)" -eq 0 ] || fail "goal_src/ edited (shared with x86 — the .gc code is correct, fix the arm64 mechanism)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra (lib/validators/agents) edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
ok "no forbidden edits"

# 2. Anti-cheat patterns
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge pattern present"
WEAK=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)
[ "$WEAK" -eq 0 ] || fail "weak symbol additions ($WEAK)"
ABRT=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
[ "$ABRT" -eq 0 ] || fail "abort additions ($ABRT)"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp"
# F1f-specific cheat: synthesized target positions. The diag print must keep
# reading the live *target* object — adding code that fabricates target-pos
# lines or feeds fake vectors into the print is a cheat.
FAKE_POS=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*F1D target-pos.*%f.*%f.*%f.*(rand|\+\+|frame \*|fake|synthetic)' || true)
[ "$FAKE_POS" -eq 0 ] || fail "suspicious synthetic target-pos generation"
ok "anti-cheat clean"

# 3. Required report — must engage the named mechanisms
[ -f .autoport/reports/F1f-fix-summary.md ] || fail "no F1f-fix-summary.md — progress/next-blocker reports do NOT pass (honest block, not false-green)"
LATEST=.autoport/reports/F1f-fix-summary.md
LINES=$(wc -l < "$LATEST")
[ "$LINES" -ge 80 ] || fail "$LATEST too short ($LINES lines, need >=80)"
grep -qiE '\bgo\b.*(return|transfer)|control.transfer|throw|catch' "$LATEST" || fail "fix-summary never engages the go/control-transfer mechanism"
grep -qiE 'master slot|evaluate-joint-control|art-joint-anim|spool' "$LATEST" || fail "fix-summary never engages the spool/master-slot mechanism"
ok "F1f fix-summary present ($LINES lines, engages both named mechanisms)"

# 4. x86 desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -25 "$SMOKE"; fail "x86 desktop smoke regressed"; }
ok "x86 desktop smoke passes (link finish: logo)"

# 5. qemu boot count — no regression
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/f1f-qemu.log 2>&1 || true
    N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/f1f-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    [ "$N" -ge 675 ] || fail "qemu link-finish regressed: $N (floor 675)"
    ok "qemu link-finish count $N (>=675)"
fi

# 6. native-log routing preserved
ROUTING=$(grep -rlE "dup2|__android_log_write|__android_log_print|android_log_pipe|gk_log_pipe" android/ game/ 2>/dev/null | xargs grep -lE "STDOUT_FILENO|STDERR_FILENO|stdout|stderr|fileno" 2>/dev/null | head -1)
[ -n "$ROUTING" ] || fail "no native stdout/stderr -> logcat routing (gk_log_pipe lost)"
ok "native-log routing present"

# 7. Renderer physically present
LIBGK=$(find build-android -name 'libgk.so' 2>/dev/null | head -1)
[ -n "$LIBGK" ] || fail "no libgk.so in build-android"
NM_OUT_FILE=$(mktemp)
nm -C "$LIBGK" > "$NM_OUT_FILE" 2>/dev/null || llvm-nm -C "$LIBGK" > "$NM_OUT_FILE" 2>/dev/null || true
DIRECT_N=$(grep -c "DirectRenderer" "$NM_OUT_FILE" || true)
MERC_N=$(grep -ciE "MercRenderer|Merc2" "$NM_OUT_FILE" || true)
rm -f "$NM_OUT_FILE"
[ "$DIRECT_N" -ge 5 ] || fail "DirectRenderer missing ($DIRECT_N syms)"
[ "${MERC_N:-0}" -ge 5 ] || fail "MercRenderer missing ($MERC_N syms)"
ok "renderer physically present (DirectRenderer=$DIRECT_N, merc=$MERC_N)"

# 8. Device screencap evidence
SHOT=$(ls .autoport/reports/F1f-device-*.png 2>/dev/null | head -1)
[ -n "$SHOT" ] || fail "no F1f-device-*.png screencap"
SHOT_SZ=$(stat -c %s "$SHOT" 2>/dev/null || echo 0)
[ "$SHOT_SZ" -gt 1000 ] || fail "screencap $SHOT looks empty ($SHOT_SZ bytes)"
ok "device screencap present: $(basename "$SHOT")"

# 9. THE PHASE GATE — newest F1f logcat: alive, crash-free, Jak MOVING
NEWLOG=$(ls -t .autoport/reports/F1f-routed-logcat-*.log 2>/dev/null | head -1)
[ -n "$NEWLOG" ] || fail "no F1f routed logcat"
CRASHES=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true)
[ "${CRASHES:-0}" -eq 0 ] || fail "sig=11 present ($CRASHES lines) in $(basename "$NEWLOG")"
FRAME_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1)
FRAME_MAX=${FRAME_MAX:-0}
[ "$FRAME_MAX" -ge 300 ] || fail "loop not sustained: max frame=$FRAME_MAX"
TRIS_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "tris=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1)
TRIS_MAX=${TRIS_MAX:-0}
[ "$TRIS_MAX" -gt 0 ] || fail "renderer draws nothing (tris=$TRIS_MAX)"
# Jak-moves gate: >=10 DISTINCT non-nan positions, non-nan last position.
# Boot attract telemetry cannot satisfy this (static pos, then nan after the
# F1d-era crash) — only a spawned, moving target can.
POS_FILE=$(mktemp)
grep -a "F1D target-pos" "$NEWLOG" | grep -oE '=\([^)]*\)' > "$POS_FILE" || true
DISTINCT=$(grep -v 'nan' "$POS_FILE" | sort -u | wc -l)
LAST_POS=$(tail -1 "$POS_FILE")
TOTAL_POS=$(wc -l < "$POS_FILE")
rm -f "$POS_FILE"
[ "${TOTAL_POS:-0}" -ge 1 ] || fail "no target-pos telemetry at all in newest logcat"
echo "$LAST_POS" | grep -qv 'nan' || fail "LAST target-pos is nan ($LAST_POS) — target state corrupt at end of run"
[ "${DISTINCT:-0}" -ge 10 ] || fail "only $DISTINCT distinct non-nan target positions (need >=10) — a static/boot-attract target does NOT pass; Jak must MOVE"
ok "Jak telemetry: $DISTINCT distinct non-nan positions, non-nan tail, frame=$FRAME_MAX, 0 crashes"

# 10. Focus bracket: app foreground at the final bracket
NEWFOCUS=$(ls -t .autoport/reports/F1f-focus-*.txt 2>/dev/null | head -1)
[ -n "$NEWFOCUS" ] || fail "no F1f-focus-*.txt"
LASTFOCUS=$(grep -a . "$NEWFOCUS" | tail -1)
echo "$LASTFOCUS" | grep -q "org.opengoal.gk.jak1" || fail "final focus is NOT the app: '$LASTFOCUS'"
ok "final focus bracket still org.opengoal.gk.jak1"

echo ""
echo "PASS: Phase F1f — go transfers, Jak spawned and moved ($DISTINCT distinct positions). Supervisor judges the frames."

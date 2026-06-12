#!/usr/bin/env bash
# Phase F1e validator — STRICT (supervisor 2026-06-12).
# Deliverable: the title-reveal crash (sig=11 fault=0x28 pc=0x7610d56414) is
# FIXED — the freshly-built device boot survives well past the reveal with the
# app still foreground — and the fix-summary names the symbolized crash site.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

F1C_CLOSE=$(git log --format=%H --all --grep='autoport/F1c-android-camera-channel-start-geyser' | head -1)
ANCHOR=${F1C_CLOSE:-HEAD}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase F1e validator (title-reveal crash fix) =="
echo "  anchor: $ANCHOR"

# 1. Forbidden edits (hard locks)
[ "$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h 2>/dev/null | wc -l)" -eq 0 ] || fail "IGenX86_64 (x86 oracle) edited"
[ "$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)" -eq 0 ] || fail "goal_src/ edited (shared with x86)"
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
[ "$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra (lib/validators/agents) edited"
[ "$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' '.claude/agents/*.md' 2>/dev/null | wc -l)" -eq 0 ] || fail "infra edited (unstaged)"
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
FAKE_FRAME=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(stb_image|loadPNG|decodePng|hardcoded_frame|test_pattern)' || true)
[ "$FAKE_FRAME" -eq 0 ] || fail "suspicious hardcoded-image/test-pattern additions ($FAKE_FRAME)"
# F1e-specific dodge: a SIGSEGV handler that swallows the fault and longjmps on
# is NOT a fix — the crash must not fire at all.
SIGSWALLOW=$(git diff "$ANCHOR" HEAD -- 'android/*.cpp' 'game/**/*.cpp' 2>/dev/null | grep -cE '^\+.*(sigsetjmp|siglongjmp).*' || true)
[ "$SIGSWALLOW" -eq 0 ] || fail "sigsetjmp/siglongjmp fault-swallow added ($SIGSWALLOW) — fix the null deref, don't catch it"
ok "anti-cheat clean (no weak/abort/dodge/stubs/fake-link/fake-frame/sig-swallow)"

# 3. Required report — STRICT: fix-summary only; must engage the actual crash
[ -f .autoport/reports/F1e-fix-summary.md ] || fail "no F1e-fix-summary.md — progress/next-blocker reports do NOT pass this phase (honest block, not false-green)"
LATEST=.autoport/reports/F1e-fix-summary.md
LINES=$(wc -l < "$LATEST")
[ "$LINES" -ge 80 ] || fail "$LATEST too short ($LINES lines, need >=80)"
grep -qiE '0x7610d56414|fault=0x28' "$LATEST" || fail "fix-summary never references the actual crash (pc=0x7610d56414 / fault=0x28) — symbolize THE crash, not a story"
grep -qiE 'addr2line|symboliz|llvm-symbolizer' "$LATEST" || fail "fix-summary has no symbolization evidence (addr2line/llvm-symbolizer) — the crash site must be NAMED"
ok "F1e fix-summary present ($LINES lines, references the real crash + symbolization)"

# 4. x86 desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -25 "$SMOKE"; fail "x86 desktop smoke regressed — x86 no longer reaches link finish: logo"; }
ok "x86 desktop smoke passes (link finish: logo)"

# 5. qemu boot count — no regression
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/f1e-qemu.log 2>&1 || true
    N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/f1e-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    [ "$N" -ge 675 ] || fail "qemu link-finish regressed: $N (floor 675)"
    ok "qemu link-finish count $N (>=675, no regression)"
fi

# 6. native-log routing preserved
ROUTING=$(grep -rlE "dup2|__android_log_write|__android_log_print|android_log_pipe|gk_log_pipe" android/ game/ 2>/dev/null | xargs grep -lE "STDOUT_FILENO|STDERR_FILENO|stdout|stderr|fileno" 2>/dev/null | head -1)
[ -n "$ROUTING" ] || fail "no native stdout/stderr -> logcat routing found (gk_log_pipe lost)"
ok "native-log routing present ($ROUTING)"

# 7. Renderer physically present in libgk.so
LIBGK=$(find build-android -name 'libgk.so' 2>/dev/null | head -1)
[ -n "$LIBGK" ] || fail "no libgk.so in build-android"
NM_OUT_FILE=$(mktemp)
nm -C "$LIBGK" > "$NM_OUT_FILE" 2>/dev/null || llvm-nm -C "$LIBGK" > "$NM_OUT_FILE" 2>/dev/null || true
DIRECT_N=$(grep -c "DirectRenderer" "$NM_OUT_FILE" || true)
MERC_N=$(grep -ciE "MercRenderer|Merc2" "$NM_OUT_FILE" || true)
rm -f "$NM_OUT_FILE"
[ "$DIRECT_N" -ge 5 ] || fail "DirectRenderer not compiled into libgk.so ($DIRECT_N symbols, need >=5)"
[ "${MERC_N:-0}" -ge 5 ] || fail "MercRenderer not compiled into libgk.so (merc syms=$MERC_N, need >=5) — disabling merc is a forbidden dodge"
ok "renderer physically present (DirectRenderer=$DIRECT_N, merc=$MERC_N)"

# 8. Device screencap evidence
SHOT=$(ls .autoport/reports/F1e-device-*.png 2>/dev/null | head -1)
[ -n "$SHOT" ] || fail "no F1e-device-*.png screencap"
SHOT_SZ=$(stat -c %s "$SHOT" 2>/dev/null || echo 0)
[ "$SHOT_SZ" -gt 1000 ] || fail "screencap $SHOT looks empty ($SHOT_SZ bytes)"
ok "device screencap present: $(basename "$SHOT") ($SHOT_SZ bytes)"

# 9. THE PHASE GATE — newest F1e logcat: reveal reached, loop sustained, ZERO crashes
NEWLOG=$(ls -t .autoport/reports/F1e-routed-logcat-*.log 2>/dev/null | head -1)
[ -n "$NEWLOG" ] || fail "no F1e routed logcat (device run evidence required)"
# grep -a: routed logcats contain binary bytes; plain grep hides matches.
MODE_GAME=$(grep -ac "set-master-mode" "$NEWLOG" 2>/dev/null || true)
[ "${MODE_GAME:-0}" -ge 1 ] || fail "newest logcat never reaches set-master-mode — the boot did not get to the title intro"
CRASHES=$(grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$NEWLOG" 2>/dev/null || true)
[ "${CRASHES:-0}" -eq 0 ] || fail "the reveal crash is NOT fixed: $CRASHES sig=11 lines in $(basename "$NEWLOG")"
FRAME_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1)
FRAME_MAX=${FRAME_MAX:-0}
[ "$FRAME_MAX" -ge 300 ] || fail "loop not sustained past the reveal: max frame=$FRAME_MAX (crash was at f~15; need >=300)"
TRIS_MAX=$(grep -a "A35-RENDER frame=" "$NEWLOG" | grep -oE "tris=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1)
TRIS_MAX=${TRIS_MAX:-0}
[ "$TRIS_MAX" -gt 0 ] || fail "renderer draws nothing: max tris=$TRIS_MAX (need >0) — blanking the screen is not a fix"
ok "newest logcat: set-master-mode reached, ZERO sig=11, frame=$FRAME_MAX, tris=$TRIS_MAX"

# 10. Focus bracket: the app must STILL be foreground at the final bracket
NEWFOCUS=$(ls -t .autoport/reports/F1e-focus-*.txt 2>/dev/null | head -1)
[ -n "$NEWFOCUS" ] || fail "no F1e-focus-*.txt (mCurrentFocus brackets required)"
LASTFOCUS=$(grep -a . "$NEWFOCUS" | tail -1)
echo "$LASTFOCUS" | grep -q "org.opengoal.gk.jak1" || fail "final focus bracket is NOT the app: '$LASTFOCUS' — the app died/backgrounded (the F1d failure mode)"
ok "final focus bracket still org.opengoal.gk.jak1"

# Note: whether the island reveal actually RENDERS (vs a frozen/black frame)
# is judged by the supervisor's own vision on independently-captured frames.

echo ""
echo "PASS: Phase F1e — reveal crash fixed on a fresh build (frame=$FRAME_MAX, 0 crashes). Supervisor judges the island by eye."

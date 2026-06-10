#!/usr/bin/env bash
# Phase A30 validator — LEAN. Wide-scope codegen fix sprint.
# Only hard gates: no forbidden edits, x86 still boots, qemu no regression, a report exists.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A29_CLOSE=$(git log --format=%H --all --grep='autoport/A29-arm64-gsound-iop-rpc-sprint' | head -1)
A28_CLOSE=$(git log --format=%H --all --grep='autoport/A28-arm64-codegen-fix-sprint' | head -1)
ANCHOR=${A29_CLOSE:-${A28_CLOSE:-HEAD}}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A30 validator (lean codegen fix sprint) =="
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
# No fake link-finish printf injected into the kernel
FAKE_LINK=$(git diff "$ANCHOR" HEAD -- 'game/**/*.cpp' 'game/**/*.s' 2>/dev/null | grep -cE '^\+.*printf.*link finish' || true)
[ "$FAKE_LINK" -eq 0 ] || fail "fake 'link finish' printf injected ($FAKE_LINK)"
ok "anti-cheat clean (no weak/abort/dodge/stubs/fake-link)"

# 3. Required report
REPORTS=$(find .autoport/reports -maxdepth 1 \( -name 'A30-fix-summary.md' -o -name 'A30-attempt-*-next-blocker.md' -o -name 'A30-attempt-*-progress.md' \) 2>/dev/null | wc -l)
[ "$REPORTS" -gt 0 ] || fail "no A30 report (fix-summary / next-blocker / progress)"
LATEST=$(ls -t .autoport/reports/A30-fix-summary.md .autoport/reports/A30-attempt-*-next-blocker.md .autoport/reports/A30-attempt-*-progress.md 2>/dev/null | head -1)
LINES=$(wc -l < "$LATEST")
[ "$LINES" -ge 80 ] || fail "$LATEST too short ($LINES lines, need >=80)"
ok "A30 report present: $(basename "$LATEST") ($LINES lines)"

FIX_PATH=0
[ -f .autoport/reports/A30-fix-summary.md ] && FIX_PATH=1

# 4. x86 desktop smoke — the KEY gate (replaces byte-identity)
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -25 "$SMOKE"; fail "x86 desktop smoke regressed — x86 no longer reaches link finish: logo"; }
ok "x86 desktop smoke passes (link finish: logo) — x86 still boots even if CGO bytes changed"

# 5. qemu boot count — A30 is Android-only, so qemu must NOT regress (codegen untouched).
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a30-qemu.log 2>&1 || true
    N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a30-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    LAST=$(grep -E "link finish:" /tmp/a30-qemu.log | tail -1 | sed 's/.*link finish: //' | head -c 40 || true)
    [ "$N" -ge 660 ] || fail "qemu link-finish regressed: $N (was 660) — A30 Android changes shouldn't touch codegen"
    ok "qemu link-finish count $N (>=660, no regression; last='$LAST')"
fi

# 6. A30-specific: native-log routing landed (so on-device boot is visible)
ROUTING=$(grep -rlE "dup2|__android_log_write|__android_log_print|android_log_pipe|gk_log_pipe" android/ game/ 2>/dev/null | xargs grep -lE "STDOUT_FILENO|STDERR_FILENO|stdout|stderr|fileno" 2>/dev/null | head -1)
[ -n "$ROUTING" ] || fail "no native stdout/stderr → logcat routing found (the first A30 deliverable; device boot is invisible without it)"
ok "native-log routing present ($ROUTING)"

# 7. A30-specific: at least one device screencap captured (evidence over prose)
SHOT=$(ls .autoport/reports/A30-device-*.png 2>/dev/null | head -1)
[ -n "$SHOT" ] || fail "no A30-device-*.png screencap (device evidence required — a black screen is still evidence, capture it)"
SHOT_SZ=$(stat -c %s "$SHOT" 2>/dev/null || echo 0)
[ "$SHOT_SZ" -gt 1000 ] || fail "screencap $SHOT looks empty ($SHOT_SZ bytes)"
ok "device screencap present: $(basename "$SHOT") ($SHOT_SZ bytes)"

# Note: whether the screencap shows the TITLE SCREEN vs black is judged by the
# supervisor (vision) independently — the validator only confirms evidence exists.
# A fix-summary CLAIMING a render is cross-checked by the supervisor's own screencap.

echo ""
echo "PASS: Phase A30 — Android runtime bring-up (lean gates). qemu=$N (no regression). Supervisor verifies the screencap renders."

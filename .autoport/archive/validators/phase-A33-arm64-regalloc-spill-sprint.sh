#!/usr/bin/env bash
# Phase A33 validator — LEAN. Wide-scope codegen fix sprint.
# Only hard gates: no forbidden edits, x86 still boots, qemu no regression, a report exists.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A32_CLOSE=$(git log --format=%H --all --grep='autoport/A32-android-renderer-path-bringup' | head -1)
A31_CLOSE=$(git log --format=%H --all --grep='autoport/A31-android-boot-to-titlescreen' | head -1)
ANCHOR=${A32_CLOSE:-${A31_CLOSE:-HEAD}}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A33 validator (lean codegen fix sprint) =="
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
REPORTS=$(find .autoport/reports -maxdepth 1 \( -name 'A33-fix-summary.md' -o -name 'A33-attempt-*-next-blocker.md' -o -name 'A33-attempt-*-progress.md' \) 2>/dev/null | wc -l)
[ "$REPORTS" -gt 0 ] || fail "no A33 report (fix-summary / next-blocker / progress)"
LATEST=$(ls -t .autoport/reports/A33-fix-summary.md .autoport/reports/A33-attempt-*-next-blocker.md .autoport/reports/A33-attempt-*-progress.md 2>/dev/null | head -1)
LINES=$(wc -l < "$LATEST")
[ "$LINES" -ge 80 ] || fail "$LATEST too short ($LINES lines, need >=80)"
ok "A33 report present: $(basename "$LATEST") ($LINES lines)"

FIX_PATH=0
[ -f .autoport/reports/A33-fix-summary.md ] && FIX_PATH=1

# 4. x86 desktop smoke — the KEY gate (replaces byte-identity)
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 90 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -25 "$SMOKE"; fail "x86 desktop smoke regressed — x86 no longer reaches link finish: logo"; }
ok "x86 desktop smoke passes (link finish: logo) — x86 still boots even if CGO bytes changed"

# 5. qemu boot count
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a33-qemu.log 2>&1 || true
    N=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a33-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    LAST=$(grep -E "link finish:" /tmp/a33-qemu.log | tail -1 | sed 's/.*link finish: //' | head -c 40 || true)
    [ "$N" -ge 660 ] || fail "qemu link-finish regressed: $N (was 660)"
    if [ "$N" -gt 660 ]; then
        echo "  ok: *** qemu link-finish count $N — ADVANCE past 660! last='$LAST' ***"
    else
        echo "  ok: qemu link-finish count $N (no regression; ceiling unchanged; last='$LAST')"
    fi
    if [ "$FIX_PATH" -eq 1 ]; then
        [ "$N" -ge 661 ] || fail "A33-fix-summary.md present but qemu count $N <= 660 (fix path requires advance)"
        [ -f .autoport/reports/A33-baseline-arm64-cgo-hashes.txt ] || fail "fix-summary present but no A33-baseline file"
        # Verify the baseline matches actual
        while read -r expected path; do
            [ -z "$expected" ] && continue
            actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
            [ "$expected" = "$actual" ] || fail "A33-baseline mismatch: $path"
        done < .autoport/reports/A33-baseline-arm64-cgo-hashes.txt
        ok "A33-baseline matches actual CGOs (real fix shipped)"
    fi
fi

echo ""
echo "PASS: Phase A33 — codegen fix sprint (lean gates). qemu=$N."

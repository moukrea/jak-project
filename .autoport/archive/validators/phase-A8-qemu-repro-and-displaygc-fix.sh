#!/usr/bin/env bash
# Phase A8 validator — qemu-aarch64 reproduction + display.gc NULL fn-ptr fix.
# Authored by supervisor 2026-05-23 after A7 unit-test harness landed but
# the extended display-fix scope wasn't validator-gated.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A6_CLOSE=$(git log --format=%H --all --grep='attempt 4 blocker analysis' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A8 validator (qemu repro + display.gc fix) =="

# ---- 1. qemu_repro.sh exists + executable ----
[ -x .autoport/lib/qemu_repro.sh ] || fail ".autoport/lib/qemu_repro.sh missing or not executable"
ok "qemu_repro.sh present"

# ---- 2. Linux-arm64 build extended ----
grep -qE "ENGINE\.CGO|GAME\.CGO" game/linux-arm64/linux_arm64_main.cpp \
    || fail "game/linux-arm64/linux_arm64_main.cpp not extended to load ENGINE/GAME.CGO"
ok "linux-arm64 driver extended for ENGINE.CGO + GAME.CGO"

# ---- 3. Root-cause report present + names a symbol ----
RCR=".autoport/reports/A8-displaygc-root-cause.md"
[ -f "$RCR" ] || fail "$RCR missing"
grep -qE "^##|root cause:|failing symbol:|the bug is in" "$RCR" \
    || fail "$RCR doesn't appear to name a root cause (no headers/keywords)"
ok "root-cause report present"

# ---- 4. Anti-cheat: no dodge re-introductions ----
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "fault-recovery dodge re-introduced ($DODGES files)"
ok "no fault-recovery dodge in source"

# ---- 5. No new abort/weak/stubs since A6 close ----
ANCHOR=${A6_CLOSE:-$A4}
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort() additions since A6 close"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak attribute additions since A6 close"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp since A6 close"
ok "no new abort/weak/stubs since A6 close"

# ---- 6. Codegen locks (sans A8-authorized changes) ----
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.cpp goalc/compiler/CodeGenerator.h; do
    [ "$(git diff "$A4" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] || fail "$f changed since A4 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "non-unlocked codegen + classifier locks intact"

# ---- 7. x86 CGOs preserved ----
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# ---- 8. D4 device validator passes (the actual test of whether the fix works) ----
echo "  re-running D4 device validator on A8 fix..."
if [ -x .autoport/validators/phase-D4-android-apk-title.sh ]; then
    bash .autoport/validators/phase-D4-android-apk-title.sh > /tmp/a8-d4.log 2>&1 \
        || { tail -40 /tmp/a8-d4.log; fail "D4 device validator failed on A8 fix"; }
    ok "D4 device validator passes — display.gc fix verified end-to-end"
else
    fail "D4 validator script missing"
fi

# ---- 9. Desktop x86 smoke ----
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A8 — qemu repro infrastructure in place, display.gc"
echo "      NULL fn-ptr fix landed, D4 device validator clean,"
echo "      no dodge re-introductions, all locks intact."

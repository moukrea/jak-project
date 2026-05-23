#!/usr/bin/env bash
# Phase A10 validator — callee no longer corrupts caller's save-area.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A10 validator (caller's-save-area preservation) =="

# 1. IR.cpp changed (the unlock target)
IR_DIFF=$(git diff "$A4" HEAD -- goalc/compiler/IR.cpp 2>/dev/null | wc -l)
[ "$IR_DIFF" -gt 5 ] || fail "goalc/compiler/IR.cpp barely changed ($IR_DIFF lines) — fix not landed"
ok "IR.cpp has $IR_DIFF lines diff from A4"

# 2. Other goalc locks intact
for f in goalc/emitter/IGenARM64.h goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.h goalc/compiler/IR.h; do
    DIFF=$(git diff "$A4" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A4 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "non-A10-unlocked goalc + classifier locks intact"

# 3. Fix summary report
[ -f .autoport/reports/A10-fix-summary.md ] || fail "A10-fix-summary.md missing"
ok "fix summary present"

# 4. arm64 CGOs regenerated
[ -f .autoport/reports/A10-baseline-arm64-cgo-hashes.txt ] || fail "A10 baseline missing"
ok "A10 arm64 baseline saved"

# 5. Anti-cheat
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced ($DODGES files)"
ok "no dodge in source"

ANCHOR=$(git log --format=%H --all --grep='\[autoport/A9-codegen-spill-ops\] update fix summary' | head -1)
ANCHOR=${ANCHOR:-$A4}
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions since A9 close"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak attribute additions since A9 close"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp since A9 close"
ok "no new abort/weak/stubs since A9 close"

# 6. x86 CGOs preserved
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# 7. qemu repro progresses past knuth-rand
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a10-qemu.log 2>&1 || true
    # Want to see one of these later markers
    grep -qE "link finish: (logo|level-info|main-h|engine)|engine: state=" /tmp/a10-qemu.log \
        || { tail -30 /tmp/a10-qemu.log; fail "qemu repro shows no post-A10 progression past knuth-rand"; }
    ok "qemu repro progresses past knuth-rand"
fi

# 8. D4 device validator passes
bash .autoport/validators/phase-D4-android-apk-title.sh > /tmp/a10-d4.log 2>&1 \
    || { tail -40 /tmp/a10-d4.log; fail "D4 device validator failed on A10 fix"; }
ok "D4 device validator passes end-to-end"

# 9. Desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A10 — caller's-save-area fix landed, boot progresses"
echo "      past knuth-rand, D4 device validator passes end-to-end."

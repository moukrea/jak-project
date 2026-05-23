#!/usr/bin/env bash
# Phase A11 validator — texture-CGO sym=0 SIGILL closed via sym-MEM binding.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A10_CLOSE=$(git log --format=%H --all --grep='autoport/A10-callee-save-area' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A11 validator (texture-sym binding) =="

# 1. At least one of the unlocked targets actually changed
TOTAL_DIFF=0
for f in android/gk_android_main.cpp game/linux-arm64/linux_arm64_main.cpp \
         game/kernel/common/klink.cpp game/kernel/common/kmachine.cpp \
         game/kernel/common/symbol.cpp; do
    D=$(git diff "$A10_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l)
    TOTAL_DIFF=$((TOTAL_DIFF + D))
done
[ "$TOTAL_DIFF" -gt 5 ] || fail "no A11 unlocked file changed since A10 close ($TOTAL_DIFF lines) — no diagnostic+fix landed"
ok "A11-unlocked files have $TOTAL_DIFF total lines diff from A10"

# 2. Codegen locks intact (everything closed by prior phases)
for f in goalc/emitter/IGenARM64.h goalc/emitter/IGenARM64.cpp \
         goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp \
         goalc/compiler/CodeGenerator.h goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/IR.h goalc/compiler/IR.cpp; do
    DIFF=$(git diff "$A10_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A10 (codegen lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "all codegen locks intact since A10"

# 3. Anti-cheat: no dodges
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced ($DODGES files)"
ok "no dodge in source"

# 4. No new abort/weak/stubs since A10 close
ANCHOR=${A10_CLOSE:-$A4}
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions since A10 close"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions since A10 close"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp since A10 close"
ok "no new abort/weak/stubs since A10 close"

# 5. Diagnostic-print evidence in source (the sym-name discovery step)
DIAG_PRESENT=$(grep -rE 'texture-sym-zero|sym-mem-zero|A11-DIAG|sym-bind-trace' \
    android/gk_android_main.cpp game/linux-arm64/linux_arm64_main.cpp \
    game/kernel/common/klink.cpp game/kernel/common/kmachine.cpp \
    game/kernel/common/symbol.cpp 2>/dev/null | wc -l)
[ "$DIAG_PRESENT" -gt 0 ] || fail "no A11 diagnostic print in unlocked files — bug evidence not captured"
ok "diagnostic print present"

# 6. Fix summary
[ -f .autoport/reports/A11-fix-summary.md ] || fail "A11-fix-summary.md missing"
ok "fix summary present"

# 7. x86 CGOs byte-identical to A2 baseline
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# 8. qemu repro progresses past texture
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a11-qemu.log 2>&1 || true
    grep -qE "link finish: (logo|level-info|main-h|loader|kernel-h|game-info)|engine: state=" /tmp/a11-qemu.log \
        || { tail -30 /tmp/a11-qemu.log; fail "qemu repro shows no post-A11 progression past texture"; }
    ok "qemu repro progresses past texture"
fi

# 9. D4 device validator passes
bash .autoport/validators/phase-D4-android-apk-title.sh > /tmp/a11-d4.log 2>&1 \
    || { tail -40 /tmp/a11-d4.log; fail "D4 device validator failed on A11 fix"; }
ok "D4 device validator passes end-to-end"

# 10. Desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A11 — texture sym-MEM binding closed, boot progresses past"
echo "      texture, D4 device validator passes end-to-end."

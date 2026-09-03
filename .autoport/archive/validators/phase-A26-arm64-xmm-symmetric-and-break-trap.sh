#!/usr/bin/env bash
# Phase A26 validator — widen IR_RegSet dispatch + IDIV-by-zero trap.
# Four exit paths: A) fix-summary (qemu>=217), B) next-blocker, C) partial-fix, D) regression.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A17_CLOSE=$(git log --format=%H --all --grep='autoport/A17-idiv-emitter-spill' | head -1)
A19_CLOSE=$(git log --format=%H --all --grep='autoport/A19-goalc-arm64-codegen-fixes' | head -1)
A20_CLOSE=$(git log --format=%H --all --grep='autoport/A20-goalc-arm64-field-offset' | head -1)
A21_CLOSE=$(git log --format=%H --all --grep='autoport/A21-arm64-codegen-deeper-investigation' | head -1)
A22_CLOSE=$(git log --format=%H --all --grep='autoport/A22-arm64-codegen-h2-fix' | head -1)
A23_CLOSE=$(git log --format=%H --all --grep='autoport/A23-arm64-blr-target-tracer' | head -1)
A24_CLOSE=$(git log --format=%H --all --grep='autoport/A24-arm64-epilogue-x30-tracer' | head -1)
A25_CLOSE=$(git log --format=%H --all --grep='autoport/A25-arm64-ir-regset-fpr-dispatch' | head -1)
ANCHOR=${A25_CLOSE:-${A24_CLOSE:-${A23_CLOSE:-${A22_CLOSE:-${A21_CLOSE:-${A20_CLOSE:-${A19_CLOSE:-${A17_CLOSE:-$A4}}}}}}}}
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A25_BASELINE=".autoport/reports/A25-baseline-arm64-cgo-hashes.txt"
A26_BASELINE=".autoport/reports/A26-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A26 validator (widen XMM dispatch + IDIV trap) =="
echo "  anchor: $ANCHOR"

# 1. Lock check
LOCKED=(
    goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h
    goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp
    goalc/compiler/Compiler.cpp
    goalc/compiler/Val.cpp goalc/compiler/Val.h
    goalc/compiler/compilation/Type.cpp
    goalc/regalloc/Allocator.cpp goalc/regalloc/allocate_common.cpp
    common/type_system/Type.cpp common/type_system/Type.h
    game/kernel/common/kscheme.cpp
    game/kernel/common/kmachine.cpp
    game/system/IOP_Kernel.cpp game/system/IOP_Kernel.h
    game/linux-arm64/linux_arm64_runtime_compat.cpp
    android/android_runtime_compat.cpp
)
for f in "${LOCKED[@]}"; do
    [ -f "$f" ] || continue
    DIFF=$(git diff "$ANCHOR" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A25 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
# Goal source must NOT be edited (would break x86 byte-identity)
GOAL_DIFF=$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)
[ "$GOAL_DIFF" -eq 0 ] || fail "goal_src/ modified — would break x86 byte-identity"
ok "all locked files unchanged since A25"

# 2. Anti-cheat
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge"
ok "no dodge"

WEAK_ADDS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)
[ "$WEAK_ADDS" -eq 0 ] || fail "weak additions"
ABORT_ADDS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
[ "$ABORT_ADDS" -eq 0 ] || fail "abort additions"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "_stubs.cpp"
INLINE_STUBS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' 2>/dev/null | grep -cE '^\+.*\w+_stub\s*\(' || true)
[ "$INLINE_STUBS" -eq 0 ] || fail "inline _stub additions"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
INFRA_DIFF=$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
INFRA_UNSTAGED=$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
[ "$INFRA_DIFF" -eq 0 ] && [ "$INFRA_UNSTAGED" -eq 0 ] || fail "infra modified"
ok "anti-cheat clean"

# 3. Invariants
TRAP_BODY=$(grep -nE "_Exit\(13\)" game/kernel/common/klink.cpp 2>/dev/null | wc -l)
[ "$TRAP_BODY" -gt 0 ] || fail "A18 trap missing"
ok "A18 preserved"

X12_FIX=$(grep -cE "kStpX12X23Push|0xA9BF5FEC" goalc/emitter/IGenARM64.cpp 2>/dev/null)
[ "${X12_FIX:-0}" -gt 0 ] || fail "A19 X12 fix missing"
ok "A19 preserved"

OFFSET_TRACE=$(grep -cE "OG_OFFSET_TRACE" goalc/compiler/IR.cpp 2>/dev/null)
[ "${OFFSET_TRACE:-0}" -ge 4 ] || fail "A20 OG_OFFSET_TRACE missing"
ok "A20 preserved ($OFFSET_TRACE sites)"

A21_DIAGS=0
for pair in \
    "game/kernel/common/klink.cpp:OG_KLINK_IMM19_TRACE" \
    "game/linux-arm64/linux_arm64_main.cpp:OG_REG_BYTE_DUMP" \
    "goalc/regalloc/Allocator_v2.cpp:OG_REGALLOC_TRACE" \
    "game/kernel/jak1/kscheme.cpp:OG_CALLGOAL_TRACE"; do
    F="${pair%%:*}"; V="${pair##*:}"
    HITS=$(grep -c "$V" "$F" 2>/dev/null || true)
    [ "${HITS:-0}" -gt 0 ] && A21_DIAGS=$((A21_DIAGS + 1)) || fail "A21 diag $V missing"
done
[ "$A21_DIAGS" -eq 4 ] || fail "A21 diags incomplete"
ok "A21 preserved"

A23_EMIT=$(grep -cE "OG_BLR_TARGET_TRACE|blr_target_trace_emit_enabled" goalc/emitter/IGenARM64.cpp 2>/dev/null || echo 0)
[ "${A23_EMIT:-0}" -gt 0 ] || fail "A23 emit missing"
A23_DEC=$(grep -cE "0x1EE0|BLR-TARGET-STACK" game/linux-arm64/linux_arm64_main.cpp 2>/dev/null || echo 0)
[ "${A23_DEC:-0}" -gt 0 ] || fail "A23 decoder missing"
ok "A23 preserved"

A24_EMIT=$(grep -cE "OG_X30_TRACE_EMIT|epilogue_x30_trace_emit_enabled|0x1EF0" goalc/compiler/CodeGenerator.cpp 2>/dev/null || echo 0)
[ "${A24_EMIT:-0}" -gt 0 ] || fail "A24 emit missing"
A24_DEC=$(grep -cE "0x1EF0|EPILOGUE-X30-STACK" game/linux-arm64/linux_arm64_main.cpp 2>/dev/null || echo 0)
[ "${A24_DEC:-0}" -gt 0 ] || fail "A24 decoder missing"
ok "A24 preserved"

# A25 helpers
A25_HELPER=$(grep -cE "emit_arm64_reg_to_reg_mov|fmov_d_d" goalc/compiler/IR.cpp goalc/emitter/IGenARM64.cpp goalc/emitter/IGenARM64.h 2>/dev/null | awk -F: '{s+=$2}END{print s}')
[ "${A25_HELPER:-0}" -gt 0 ] || fail "A25 helpers missing"
ok "A25 helpers preserved"

# 4. x86 CGOs match A2
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs match A2 baseline"

# 5. Required reports
FIX_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A26-fix-summary.md' 2>/dev/null | wc -l)
NEXT_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A26-attempt-*-next-blocker.md' 2>/dev/null | wc -l)
PARTIAL_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A26-attempt-*-partial-fix.md' 2>/dev/null | wc -l)
REGRESSION_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A26-attempt-*-regression.md' 2>/dev/null | wc -l)
TOTAL_EXIT=$((FIX_REPORTS + NEXT_REPORTS + PARTIAL_REPORTS + REGRESSION_REPORTS))
[ "$TOTAL_EXIT" -gt 0 ] || fail "no A26 exit report"

[ -f .autoport/reports/A26-investigation-trace.md ] || fail "A26-investigation-trace.md missing"
INV_LINES=$(wc -l < .autoport/reports/A26-investigation-trace.md)
[ "$INV_LINES" -ge 200 ] || fail "A26-investigation-trace.md too short ($INV_LINES)"
ok "A26-investigation-trace.md present ($INV_LINES lines)"

# 6. Per-path
EXIT_PATH=""
if [ "$FIX_REPORTS" -gt 0 ]; then
    EXIT_PATH="fix"
    L=$(wc -l < .autoport/reports/A26-fix-summary.md)
    [ "$L" -ge 250 ] || fail "A26-fix-summary.md too short ($L)"
    REFS=$(grep -cE '(emit_arm64_reg_to_reg_mov|movq_gpr64_xmm64|movq_xmm64_gpr64|mov_vf_vf|UDF #0xBEEF|0xBEEF|BREAK-MACRO-TRAP|cpu-thread-suspend|new-catch-frame)' .autoport/reports/A26-fix-summary.md 2>/dev/null || true)
    [ "${REFS:-0}" -ge 3 ] || fail "A26-fix-summary lacks A26-specific refs (got $REFS)"
    ok "A26-fix-summary.md present ($L lines)"
fi
if [ "$PARTIAL_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}partial"
    LATEST=$(ls -t .autoport/reports/A26-attempt-*-partial-fix.md | head -1)
    L=$(wc -l < "$LATEST")
    [ "$L" -ge 250 ] || fail "$LATEST too short ($L)"
    ok "$LATEST present ($L lines)"
fi
if [ "$NEXT_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}next-blocker"
    LATEST=$(ls -t .autoport/reports/A26-attempt-*-next-blocker.md | head -1)
    L=$(wc -l < "$LATEST")
    [ "$L" -ge 250 ] || fail "$LATEST too short ($L)"
    ok "$LATEST present ($L lines)"
fi
if [ "$REGRESSION_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}regression"
    LATEST=$(ls -t .autoport/reports/A26-attempt-*-regression.md | head -1)
    L=$(wc -l < "$LATEST")
    [ "$L" -ge 250 ] || fail "$LATEST too short ($L)"
    ok "$LATEST present ($L lines)"
fi

# 7. CGO drift
ARM64_VS_A25_DRIFT=0
ARM64_VS_A25_TOTAL=0
while read -r expected path; do
    [ -z "$expected" ] && continue
    ARM64_VS_A25_TOTAL=$((ARM64_VS_A25_TOTAL + 1))
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || ARM64_VS_A25_DRIFT=$((ARM64_VS_A25_DRIFT + 1))
done < "$A25_BASELINE"

if [ "$FIX_REPORTS" -gt 0 ] || [ "$PARTIAL_REPORTS" -gt 0 ]; then
    [ -f "$A26_BASELINE" ] || fail "A26-baseline missing"
    [ "$ARM64_VS_A25_DRIFT" -gt 0 ] || fail "CGOs match A25 but fix/partial claims fix shipped"
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "A26-baseline mismatch: $path"
    done < "$A26_BASELINE"
    ok "arm64 CGOs drifted from A25 ($ARM64_VS_A25_DRIFT/$ARM64_VS_A25_TOTAL) + match A26-baseline"
else
    [ "$ARM64_VS_A25_DRIFT" -eq 0 ] || fail "CGOs drifted from A25 but no fix/partial report"
    ok "arm64 CGOs match A25 baseline (next-blocker or regression path)"
fi

# 8. qemu boot count
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a26-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a26-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    if [ "$FIX_REPORTS" -gt 0 ]; then
        [ "$SUM_COUNT" -ge 217 ] || fail "qemu link-finish $SUM_COUNT — fix path needs >=217"
        ok "qemu link-finish $SUM_COUNT (>=217, REAL ADVANCE)"
    else
        [ "$SUM_COUNT" -ge 200 ] || fail "qemu regressed: $SUM_COUNT"
        ok "qemu link-finish $SUM_COUNT (>=200)"
    fi
fi

# 9. Desktop x86 smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop x86 smoke regressed"; }
ok "desktop x86 smoke passes"

echo ""
echo "PASS: Phase A26 — widen XMM dispatch + IDIV trap, exit path: $EXIT_PATH"

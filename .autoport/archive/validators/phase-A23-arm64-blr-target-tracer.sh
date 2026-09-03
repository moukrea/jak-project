#!/usr/bin/env bash
# Phase A23 validator — runtime BLR-target tracer + Val.cpp/Type.cpp audit.
# Four valid exit paths: A) fix landed, B) next-blocker, C) bug-located-named-source, D) no-source-located.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A17_CLOSE=$(git log --format=%H --all --grep='autoport/A17-idiv-emitter-spill' | head -1)
A19_CLOSE=$(git log --format=%H --all --grep='autoport/A19-goalc-arm64-codegen-fixes' | head -1)
A20_CLOSE=$(git log --format=%H --all --grep='autoport/A20-goalc-arm64-field-offset' | head -1)
A21_CLOSE=$(git log --format=%H --all --grep='autoport/A21-arm64-codegen-deeper-investigation' | head -1)
A22_CLOSE=$(git log --format=%H --all --grep='autoport/A22-arm64-codegen-h2-fix' | head -1)
ANCHOR=${A22_CLOSE:-${A21_CLOSE:-${A20_CLOSE:-${A19_CLOSE:-${A17_CLOSE:-$A4}}}}}
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A19_BASELINE=".autoport/reports/A19-baseline-arm64-cgo-hashes.txt"
A21_BASELINE=".autoport/reports/A21-baseline-arm64-cgo-hashes.txt"
A23_BASELINE=".autoport/reports/A23-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A23 validator (arm64 runtime BLR-target tracer + Val/Type audit) =="
echo "  anchor: $ANCHOR"

# 1. Lock check — only A23's unlocked files may have diffs
LOCKED=(
    goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h
    goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp
    goalc/compiler/CodeGenerator.h goalc/compiler/CodeGenerator.cpp
    goalc/compiler/Compiler.cpp
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
    [ "$DIFF" -eq 0 ] || fail "$f changed since A22 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "all locked files unchanged since A22"

# 2. Anti-cheat
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced"
ok "no dodge in source"

WEAK_ADDS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)
[ "$WEAK_ADDS" -eq 0 ] || fail "weak symbol additions ($WEAK_ADDS)"
ABORT_ADDS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
[ "$ABORT_ADDS" -eq 0 ] || fail "abort additions ($ABORT_ADDS)"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp"
INLINE_STUBS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' 2>/dev/null | grep -cE '^\+.*\w+_stub\s*\(' || true)
[ "$INLINE_STUBS" -eq 0 ] || fail "inline _stub additions ($INLINE_STUBS)"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
INFRA_DIFF=$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
INFRA_UNSTAGED=$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
[ "$INFRA_DIFF" -eq 0 ] && [ "$INFRA_UNSTAGED" -eq 0 ] || fail "infra modified"
ok "anti-cheat checks all pass"

# 3. A18/A19/A20/A21 invariants still in place
TRAP_BODY=$(grep -nE "_Exit\(13\)|_Exit\s*\(13\)" game/kernel/common/klink.cpp 2>/dev/null | wc -l)
[ "$TRAP_BODY" -gt 0 ] || fail "a18_method_zero_trap no longer calls _Exit(13)"
ok "a18 method-zero trap body still _Exit(13)"

X12_FIX=$(grep -cE "kStpX12X23Push|0xA9BF5FEC" goalc/emitter/IGenARM64.cpp 2>/dev/null)
[ "${X12_FIX:-0}" -gt 0 ] || fail "A19's X12 fix missing"
ok "A19 X12 fix preserved"

OFFSET_TRACE_PATCHES=$(grep -cE "OG_OFFSET_TRACE" goalc/compiler/IR.cpp 2>/dev/null)
[ "${OFFSET_TRACE_PATCHES:-0}" -ge 4 ] || fail "A20 OG_OFFSET_TRACE missing (got $OFFSET_TRACE_PATCHES, need >=4)"
ok "A20 OG_OFFSET_TRACE preserved ($OFFSET_TRACE_PATCHES sites)"

A21_DIAGS=0
for pair in \
    "game/kernel/common/klink.cpp:OG_KLINK_IMM19_TRACE" \
    "game/linux-arm64/linux_arm64_main.cpp:OG_REG_BYTE_DUMP" \
    "goalc/regalloc/Allocator_v2.cpp:OG_REGALLOC_TRACE" \
    "game/kernel/jak1/kscheme.cpp:OG_CALLGOAL_TRACE"; do
    F="${pair%%:*}"
    V="${pair##*:}"
    HITS=$(grep -c "$V" "$F" 2>/dev/null || true)
    if [ "${HITS:-0}" -gt 0 ]; then
        A21_DIAGS=$((A21_DIAGS + 1))
    else
        fail "A21 diag $V missing from $F"
    fi
done
[ "$A21_DIAGS" -eq 4 ] || fail "expected 4 A21 diags (got $A21_DIAGS)"
ok "all 4 A21 diags preserved"

# 4. x86 CGOs byte-identical to A2 baseline (HARD)
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path — A23 broke shared code"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# 5. Required reports
FIX_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A23-fix-summary.md' 2>/dev/null | wc -l)
NEXT_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A23-attempt-*-next-blocker.md' 2>/dev/null | wc -l)
BUGLOC_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A23-attempt-*-bug-located-named-source.md' 2>/dev/null | wc -l)
NOSRC_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A23-attempt-*-no-source-located.md' 2>/dev/null | wc -l)
TOTAL_EXIT=$((FIX_REPORTS + NEXT_REPORTS + BUGLOC_REPORTS + NOSRC_REPORTS))
[ "$TOTAL_EXIT" -gt 0 ] || fail "no A23 exit report (need ONE of fix-summary / next-blocker / bug-located-named-source / no-source-located)"

[ -f .autoport/reports/A23-investigation-trace.md ] || fail "A23-investigation-trace.md missing (required for all paths)"
INV_LINES=$(wc -l < .autoport/reports/A23-investigation-trace.md)
[ "$INV_LINES" -ge 200 ] || fail "A23-investigation-trace.md too short ($INV_LINES lines, need >=200)"
ok "A23-investigation-trace.md present ($INV_LINES lines)"

# 6. Per-path checks
EXIT_PATH=""
if [ "$FIX_REPORTS" -gt 0 ]; then
    EXIT_PATH="fix"
    FIX_LINES=$(wc -l < .autoport/reports/A23-fix-summary.md)
    [ "$FIX_LINES" -ge 250 ] || fail "A23-fix-summary.md too short ($FIX_LINES lines, need >=250)"
    NAMED_REFS=$(grep -cE '(Val\.cpp|MemoryDerefVal|StackVarAddrVal|compilation/Type\.cpp|IR_FunctionCall|m_func|emit_pc|BLR-TARGET-STACK|OG_BLR_TARGET_TRACE)' .autoport/reports/A23-fix-summary.md 2>/dev/null || true)
    [ "${NAMED_REFS:-0}" -ge 3 ] || fail "A23-fix-summary.md doesn't reference enough A23-specific symbols (got $NAMED_REFS, need >=3)"
    ok "A23-fix-summary.md present ($FIX_LINES lines, references A23 symbols)"
fi
if [ "$BUGLOC_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}bug-located-named-source"
    LATEST_BUG=$(ls -t .autoport/reports/A23-attempt-*-bug-located-named-source.md | head -1)
    BUG_LINES=$(wc -l < "$LATEST_BUG")
    [ "$BUG_LINES" -ge 250 ] || fail "$LATEST_BUG too short ($BUG_LINES lines, need >=250)"
    # Must reference emit_pc / BLR-TARGET-STACK output
    NAMED_REFS=$(grep -cE '(emit_pc|BLR-TARGET-STACK|freg|UDF|0x[a-f0-9]{6,}|GOAL function|method dispatch)' "$LATEST_BUG" 2>/dev/null || true)
    [ "${NAMED_REFS:-0}" -ge 3 ] || fail "$LATEST_BUG doesn't reference tracer output specifics (got $NAMED_REFS, need >=3)"
    ok "$LATEST_BUG present ($BUG_LINES lines, references tracer output)"
fi
if [ "$NEXT_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}next-blocker"
    LATEST_NEXT=$(ls -t .autoport/reports/A23-attempt-*-next-blocker.md | head -1)
    NEXT_LINES=$(wc -l < "$LATEST_NEXT")
    [ "$NEXT_LINES" -ge 250 ] || fail "$LATEST_NEXT too short ($NEXT_LINES lines, need >=250)"
    ok "$LATEST_NEXT present ($NEXT_LINES lines)"
fi
if [ "$NOSRC_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}no-source-located"
    LATEST_NOSRC=$(ls -t .autoport/reports/A23-attempt-*-no-source-located.md | head -1)
    NOSRC_LINES=$(wc -l < "$LATEST_NOSRC")
    [ "$NOSRC_LINES" -ge 250 ] || fail "$LATEST_NOSRC too short ($NOSRC_LINES lines, need >=250)"
    ok "$LATEST_NOSRC present ($NOSRC_LINES lines)"
fi

# 7. CGO drift check
ARM64_VS_A21_DRIFT=0
ARM64_VS_A21_TOTAL=0
while read -r expected path; do
    [ -z "$expected" ] && continue
    ARM64_VS_A21_TOTAL=$((ARM64_VS_A21_TOTAL + 1))
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || ARM64_VS_A21_DRIFT=$((ARM64_VS_A21_DRIFT + 1))
done < "$A21_BASELINE"

if [ "$FIX_REPORTS" -gt 0 ]; then
    [ -f "$A23_BASELINE" ] || fail "A23-baseline-arm64-cgo-hashes.txt missing (required when fix-summary present)"
    [ "$ARM64_VS_A21_DRIFT" -gt 0 ] || fail "arm64 CGOs unchanged from A21 baseline but fix-summary claims fix landed"
    # Verify A23 baseline matches actual
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "A23-baseline mismatch: $path (declared $expected, actual $actual)"
    done < "$A23_BASELINE"
    ok "arm64 CGOs drifted from A21 ($ARM64_VS_A21_DRIFT/$ARM64_VS_A21_TOTAL) + match A23-baseline (real fix)"
elif [ "$BUGLOC_REPORTS" -gt 0 ]; then
    # bug-located may or may not have shipped tracer emit. If A23-baseline exists, must match.
    if [ -f "$A23_BASELINE" ]; then
        while read -r expected path; do
            [ -z "$expected" ] && continue
            actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
            [ "$expected" = "$actual" ] || fail "A23-baseline mismatch: $path"
        done < "$A23_BASELINE"
        ok "arm64 CGOs match A23 baseline (tracer emit shipped, $ARM64_VS_A21_DRIFT/$ARM64_VS_A21_TOTAL drifted from A21)"
    else
        [ "$ARM64_VS_A21_DRIFT" -eq 0 ] || fail "arm64 CGOs drifted from A21 but no A23-baseline and no fix-summary"
        ok "arm64 CGOs match A21 baseline (bug-located via runtime probe without changing emit)"
    fi
else
    [ "$ARM64_VS_A21_DRIFT" -eq 0 ] || fail "arm64 CGOs drifted from A21 but no fix-summary and no A23-baseline — code changed without claimed fix"
    ok "arm64 CGOs match A21 baseline (honest-exit path)"
fi

# 8. qemu boot count
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a23-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a23-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    if [ "$FIX_REPORTS" -gt 0 ]; then
        [ "$SUM_COUNT" -ge 217 ] || fail "qemu link-finish count $SUM_COUNT (fix-summary claims advance but still <=216)"
        ok "qemu link-finish count $SUM_COUNT (>=217, real advance)"
    else
        [ "$SUM_COUNT" -ge 200 ] || fail "qemu link-finish count regressed: $SUM_COUNT"
        ok "qemu link-finish count $SUM_COUNT (>=200, no regression)"
    fi
fi

# 9. Tracer infrastructure landed (required for fix and bug-located paths)
if [ "$FIX_REPORTS" -gt 0 ] || [ "$BUGLOC_REPORTS" -gt 0 ]; then
    TRACER_HITS_EMIT=$(grep -c "OG_BLR_TARGET_TRACE" goalc/emitter/IGenARM64.cpp 2>/dev/null || echo 0)
    TRACER_HITS_HANDLER=$(grep -c "OG_BLR_TARGET_TRACE\|0x1ee2\|BLR-TARGET-STACK" game/linux-arm64/linux_arm64_main.cpp 2>/dev/null || echo 0)
    [ "${TRACER_HITS_EMIT:-0}" -gt 0 ] || fail "OG_BLR_TARGET_TRACE missing from IGenARM64.cpp"
    [ "${TRACER_HITS_HANDLER:-0}" -gt 0 ] || fail "OG_BLR_TARGET_TRACE / UDF tag decoder missing from linux_arm64_main.cpp"
    ok "tracer infra: emit ($TRACER_HITS_EMIT hits in IGenARM64.cpp) + handler ($TRACER_HITS_HANDLER hits in linux_arm64_main.cpp)"
fi

# 10. Desktop x86 smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop x86 smoke regressed"; }
ok "desktop x86 smoke still passes"

echo ""
echo "PASS: Phase A23 — runtime BLR-target tracer, exit path: $EXIT_PATH"

#!/usr/bin/env bash
# Phase A24 validator — arm64 epilogue X30 stack-range tracer + CodeGenerator.cpp audit.
# Five exit paths: A) fix landed, B) next-blocker, C) bug-located-named-source, D) no-source-located, E) tracer-doesnt-fire.
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
ANCHOR=${A23_CLOSE:-${A22_CLOSE:-${A21_CLOSE:-${A20_CLOSE:-${A19_CLOSE:-${A17_CLOSE:-$A4}}}}}}
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A21_BASELINE=".autoport/reports/A21-baseline-arm64-cgo-hashes.txt"
A23_BASELINE=".autoport/reports/A23-baseline-arm64-cgo-hashes.txt"
A24_BASELINE=".autoport/reports/A24-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A24 validator (arm64 epilogue X30 tracer + CodeGenerator audit) =="
echo "  anchor: $ANCHOR"

# 1. Lock check — only A24's unlocked files may have diffs
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
    [ "$DIFF" -eq 0 ] || fail "$f changed since A23 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "all locked files unchanged since A23"

# 2. Anti-cheat
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced"
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

# 3. A18/A19/A20/A21/A23 invariants
TRAP_BODY=$(grep -nE "_Exit\(13\)|_Exit\s*\(13\)" game/kernel/common/klink.cpp 2>/dev/null | wc -l)
[ "$TRAP_BODY" -gt 0 ] || fail "a18 _Exit(13) missing"
ok "a18 trap preserved"

X12_FIX=$(grep -cE "kStpX12X23Push|0xA9BF5FEC" goalc/emitter/IGenARM64.cpp 2>/dev/null)
[ "${X12_FIX:-0}" -gt 0 ] || fail "A19 X12 fix missing"
ok "A19 X12 fix preserved"

OFFSET_TRACE_PATCHES=$(grep -cE "OG_OFFSET_TRACE" goalc/compiler/IR.cpp 2>/dev/null)
[ "${OFFSET_TRACE_PATCHES:-0}" -ge 4 ] || fail "A20 OG_OFFSET_TRACE missing"
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
[ "$A21_DIAGS" -eq 4 ] || fail "A21 diags missing"
ok "A21 4 diags preserved"

# A23 invariant: tracer in IGenARM64.cpp + decoder in linux_arm64_main.cpp
A23_EMIT=$(grep -cE "OG_BLR_TARGET_TRACE|blr_target_trace_emit_enabled" goalc/emitter/IGenARM64.cpp 2>/dev/null || echo 0)
[ "${A23_EMIT:-0}" -gt 0 ] || fail "A23 OG_BLR_TARGET_TRACE missing from IGenARM64.cpp"
A23_DEC=$(grep -cE "0x1EE0|0x1ee0|BLR-TARGET-STACK" game/linux-arm64/linux_arm64_main.cpp 2>/dev/null || echo 0)
[ "${A23_DEC:-0}" -gt 0 ] || fail "A23 UDF 0x1EE0 decoder missing from linux_arm64_main.cpp"
ok "A23 tracer infra preserved (emit: $A23_EMIT hits; decoder: $A23_DEC hits)"

# 4. x86 CGOs match A2 baseline (HARD)
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs match A2 baseline"

# 5. Required reports
FIX_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A24-fix-summary.md' 2>/dev/null | wc -l)
NEXT_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A24-attempt-*-next-blocker.md' 2>/dev/null | wc -l)
BUGLOC_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A24-attempt-*-bug-located-named-source.md' 2>/dev/null | wc -l)
NOSRC_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A24-attempt-*-no-source-located.md' 2>/dev/null | wc -l)
NOFIRE_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A24-attempt-*-tracer-doesnt-fire.md' 2>/dev/null | wc -l)
TOTAL_EXIT=$((FIX_REPORTS + NEXT_REPORTS + BUGLOC_REPORTS + NOSRC_REPORTS + NOFIRE_REPORTS))
[ "$TOTAL_EXIT" -gt 0 ] || fail "no A24 exit report"

[ -f .autoport/reports/A24-investigation-trace.md ] || fail "A24-investigation-trace.md missing"
INV_LINES=$(wc -l < .autoport/reports/A24-investigation-trace.md)
[ "$INV_LINES" -ge 200 ] || fail "A24-investigation-trace.md too short ($INV_LINES lines, need >=200)"
ok "A24-investigation-trace.md present ($INV_LINES lines)"

# 6. Per-path checks
EXIT_PATH=""
if [ "$FIX_REPORTS" -gt 0 ]; then
    EXIT_PATH="fix"
    L=$(wc -l < .autoport/reports/A24-fix-summary.md)
    [ "$L" -ge 250 ] || fail "A24-fix-summary.md too short ($L lines)"
    REFS=$(grep -cE '(CodeGenerator|do_goal_function_arm64|epilogue|LDP X29|0x1EF0|EPILOGUE-X30-STACK|OG_X30_TRACE_EMIT|emit_pc|GOAL function)' .autoport/reports/A24-fix-summary.md 2>/dev/null || true)
    [ "${REFS:-0}" -ge 3 ] || fail "fix-summary doesn't reference A24-specific symbols (got $REFS, need >=3)"
    ok "A24-fix-summary.md present ($L lines)"
fi
if [ "$BUGLOC_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}bug-located"
    LATEST=$(ls -t .autoport/reports/A24-attempt-*-bug-located-named-source.md | head -1)
    L=$(wc -l < "$LATEST")
    [ "$L" -ge 250 ] || fail "$LATEST too short ($L lines)"
    REFS=$(grep -cE '(EPILOGUE-X30-STACK|emit_pc|GOAL function|0x1EF0|do_goal_function_arm64|LDP X29)' "$LATEST" 2>/dev/null || true)
    [ "${REFS:-0}" -ge 3 ] || fail "$LATEST doesn't reference tracer output (got $REFS)"
    ok "$LATEST present ($L lines, references tracer output)"
fi
if [ "$NEXT_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}next-blocker"
    LATEST=$(ls -t .autoport/reports/A24-attempt-*-next-blocker.md | head -1)
    L=$(wc -l < "$LATEST")
    [ "$L" -ge 250 ] || fail "$LATEST too short ($L lines)"
    ok "$LATEST present ($L lines)"
fi
if [ "$NOSRC_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}no-source-located"
    LATEST=$(ls -t .autoport/reports/A24-attempt-*-no-source-located.md | head -1)
    L=$(wc -l < "$LATEST")
    [ "$L" -ge 250 ] || fail "$LATEST too short ($L lines)"
    ok "$LATEST present ($L lines)"
fi
if [ "$NOFIRE_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}tracer-doesnt-fire"
    LATEST=$(ls -t .autoport/reports/A24-attempt-*-tracer-doesnt-fire.md | head -1)
    L=$(wc -l < "$LATEST")
    [ "$L" -ge 250 ] || fail "$LATEST too short ($L lines)"
    ok "$LATEST present ($L lines)"
fi

# 7. CGO drift check
ARM64_VS_A23_DRIFT=0
ARM64_VS_A23_TOTAL=0
while read -r expected path; do
    [ -z "$expected" ] && continue
    ARM64_VS_A23_TOTAL=$((ARM64_VS_A23_TOTAL + 1))
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || ARM64_VS_A23_DRIFT=$((ARM64_VS_A23_DRIFT + 1))
done < "$A23_BASELINE"

if [ "$FIX_REPORTS" -gt 0 ] || [ "$BUGLOC_REPORTS" -gt 0 ]; then
    [ -f "$A24_BASELINE" ] || fail "A24-baseline-arm64-cgo-hashes.txt missing"
    [ "$ARM64_VS_A23_DRIFT" -gt 0 ] || fail "arm64 CGOs match A23 baseline but A24 claims tracer or fix shipped"
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "A24-baseline mismatch: $path"
    done < "$A24_BASELINE"
    ok "arm64 CGOs match A24-baseline (drift from A23: $ARM64_VS_A23_DRIFT/$ARM64_VS_A23_TOTAL)"
else
    if [ "$ARM64_VS_A23_DRIFT" -ne 0 ]; then
        # next-blocker/no-source/tracer-doesnt-fire CAN have new tracer emit if A24-baseline ships
        if [ -f "$A24_BASELINE" ]; then
            while read -r expected path; do
                [ -z "$expected" ] && continue
                actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
                [ "$expected" = "$actual" ] || fail "A24-baseline mismatch: $path"
            done < "$A24_BASELINE"
            ok "arm64 CGOs match A24-baseline (alternate path with tracer ship)"
        else
            fail "arm64 CGOs drifted from A23 but no A24-baseline file"
        fi
    else
        ok "arm64 CGOs match A23 baseline (no fix shipped, no new tracer)"
    fi
fi

# 8. qemu boot count
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a24-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a24-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    if [ "$FIX_REPORTS" -gt 0 ]; then
        [ "$SUM_COUNT" -ge 217 ] || fail "qemu link-finish $SUM_COUNT (fix path needs >=217)"
        ok "qemu link-finish $SUM_COUNT (>=217, real advance)"
    else
        [ "$SUM_COUNT" -ge 200 ] || fail "qemu link-finish regressed: $SUM_COUNT"
        ok "qemu link-finish $SUM_COUNT (>=200, no regression)"
    fi
fi

# 9. A24 tracer infra (required on fix or bug-located paths)
if [ "$FIX_REPORTS" -gt 0 ] || [ "$BUGLOC_REPORTS" -gt 0 ]; then
    EMIT_HITS_CG=$(grep -cE "OG_X30_TRACE_EMIT|epilogue_x30_trace|0x1EF0" goalc/compiler/CodeGenerator.cpp 2>/dev/null || echo 0)
    EMIT_HITS_IGEN=$(grep -cE "OG_X30_TRACE_EMIT|epilogue_x30_trace|0x1EF0" goalc/emitter/IGenARM64.cpp 2>/dev/null || echo 0)
    EMIT_HITS=$((EMIT_HITS_CG + EMIT_HITS_IGEN))
    DEC_HITS=$(grep -cE "0x1EF0|0x1ef0|EPILOGUE-X30-STACK" game/linux-arm64/linux_arm64_main.cpp 2>/dev/null || echo 0)
    [ "${EMIT_HITS:-0}" -gt 0 ] || fail "A24 X30 tracer emit missing from CodeGenerator.cpp/IGenARM64.cpp"
    [ "${DEC_HITS:-0}" -gt 0 ] || fail "A24 UDF 0x1EF0 decoder missing from linux_arm64_main.cpp"
    ok "A24 tracer infra: emit ($EMIT_HITS hits) + decoder ($DEC_HITS hits)"
fi

# 10. Desktop x86 smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop x86 smoke regressed"; }
ok "desktop x86 smoke passes"

echo ""
echo "PASS: Phase A24 — arm64 epilogue X30 tracer, exit path: $EXIT_PATH"

#!/usr/bin/env bash
# Phase A22 validator — arm64 codegen H2 fix (find + patch source of stack-addr corruption).
# Three valid exit paths: A) fix landed + qemu boot >216, B) honest next-blocker, C) no-source-located.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A17_CLOSE=$(git log --format=%H --all --grep='autoport/A17-idiv-emitter-spill' | head -1)
A19_CLOSE=$(git log --format=%H --all --grep='autoport/A19-goalc-arm64-codegen-fixes' | head -1)
A20_CLOSE=$(git log --format=%H --all --grep='autoport/A20-goalc-arm64-field-offset' | head -1)
A21_CLOSE=$(git log --format=%H --all --grep='autoport/A21-arm64-codegen-deeper-investigation' | head -1)
ANCHOR=${A21_CLOSE:-${A20_CLOSE:-${A19_CLOSE:-${A17_CLOSE:-$A4}}}}
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A19_BASELINE=".autoport/reports/A19-baseline-arm64-cgo-hashes.txt"
A21_BASELINE=".autoport/reports/A21-baseline-arm64-cgo-hashes.txt"
A22_BASELINE=".autoport/reports/A22-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A22 validator (arm64 codegen H2 fix) =="
echo "  anchor: $ANCHOR"

# 1. Lock check — only A22's unlocked files may have diffs
LOCKED=(
    goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h
    goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp
    goalc/compiler/CodeGenerator.h goalc/compiler/CodeGenerator.cpp
    goalc/compiler/Compiler.cpp
    goalc/compiler/Val.cpp goalc/compiler/Val.h
    goalc/compiler/compilation/Type.cpp
    goalc/regalloc/Allocator.cpp goalc/regalloc/allocate_common.cpp
    goalc/regalloc/Allocator_v2.cpp
    common/type_system/Type.cpp common/type_system/Type.h
    game/kernel/common/klink.cpp
    game/kernel/common/kscheme.cpp
    game/kernel/common/kmachine.cpp
    game/kernel/jak1/kscheme.cpp
    game/system/IOP_Kernel.cpp game/system/IOP_Kernel.h
    game/linux-arm64/linux_arm64_main.cpp
    game/linux-arm64/linux_arm64_runtime_compat.cpp
    android/android_runtime_compat.cpp
)
for f in "${LOCKED[@]}"; do
    [ -f "$f" ] || continue
    DIFF=$(git diff "$ANCHOR" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A21 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "all locked files unchanged since A21"

# 2. Anti-cheat (shared with A20/A21)
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
[ "${X12_FIX:-0}" -gt 0 ] || fail "A19's X12 fix (kStpX12X23Push) missing from IGenARM64.cpp"
ok "A19 X12 fix preserved in HEAD"

OFFSET_TRACE_PATCHES=$(grep -cE "OG_OFFSET_TRACE" goalc/compiler/IR.cpp 2>/dev/null)
[ "${OFFSET_TRACE_PATCHES:-0}" -ge 4 ] || fail "A20's OG_OFFSET_TRACE diag missing from IR.cpp (got $OFFSET_TRACE_PATCHES sites, need >=4)"
ok "A20 OG_OFFSET_TRACE diag preserved in HEAD ($OFFSET_TRACE_PATCHES sites)"

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
[ "$A21_DIAGS" -eq 4 ] || fail "expected all 4 A21 diags preserved (got $A21_DIAGS)"
ok "all 4 A21 diags preserved in HEAD"

# 4. x86 CGOs byte-identical to A2 baseline (HARD REGRESSION CHECK)
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path — A22 broke shared code"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline (x86 untouched)"

# 5. Required reports present — at least ONE of fix-summary / next-blocker / no-source-located
FIX_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A22-fix-summary.md' 2>/dev/null | wc -l)
NEXT_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A22-attempt-*-next-blocker.md' 2>/dev/null | wc -l)
NOSRC_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A22-attempt-*-no-source-located.md' 2>/dev/null | wc -l)
TOTAL_EXIT_REPORTS=$((FIX_REPORTS + NEXT_REPORTS + NOSRC_REPORTS))
[ "$TOTAL_EXIT_REPORTS" -gt 0 ] || fail "no A22 exit report (need ONE of fix-summary / attempt-N-next-blocker / attempt-N-no-source-located)"

# Investigation trace required regardless of exit path
[ -f .autoport/reports/A22-investigation-trace.md ] || fail "A22-investigation-trace.md missing (required for all exit paths)"
INV_LINES=$(wc -l < .autoport/reports/A22-investigation-trace.md)
[ "$INV_LINES" -ge 150 ] || fail "A22-investigation-trace.md too short ($INV_LINES lines, need >=150)"
ok "A22-investigation-trace.md present ($INV_LINES lines)"

# 6. Path-specific checks
EXIT_PATH=""
if [ "$FIX_REPORTS" -gt 0 ]; then
    EXIT_PATH="fix"
    FIX_LINES=$(wc -l < .autoport/reports/A22-fix-summary.md)
    [ "$FIX_LINES" -ge 200 ] || fail "A22-fix-summary.md too short ($FIX_LINES lines, need >=200)"
    # Fix summary must NAME the specific emit sequence (not just generic claims)
    NAMED_SEQ=$(grep -cE '(IR_FunctionCall|IGenARM64|call_r64|_call_goal_asm|X16|kA6OffRegScratchRegId|do_codegen_arm64|asm_funcs_arm64)' .autoport/reports/A22-fix-summary.md 2>/dev/null || true)
    [ "${NAMED_SEQ:-0}" -ge 3 ] || fail "A22-fix-summary.md doesn't name specific emit-sequence symbols (got $NAMED_SEQ refs, need >=3 of: IR_FunctionCall, IGenARM64, call_r64, _call_goal_asm, X16, kA6OffRegScratchRegId, do_codegen_arm64, asm_funcs_arm64)"
    ok "A22-fix-summary.md present ($FIX_LINES lines, names specific emit surfaces)"
fi
if [ "$NEXT_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}next-blocker"
    LATEST_NEXT=$(ls -t .autoport/reports/A22-attempt-*-next-blocker.md | head -1)
    NEXT_LINES=$(wc -l < "$LATEST_NEXT")
    [ "$NEXT_LINES" -ge 200 ] || fail "$LATEST_NEXT too short ($NEXT_LINES lines, need >=200)"
    ok "$LATEST_NEXT present ($NEXT_LINES lines)"
fi
if [ "$NOSRC_REPORTS" -gt 0 ]; then
    EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}no-source-located"
    LATEST_NOSRC=$(ls -t .autoport/reports/A22-attempt-*-no-source-located.md | head -1)
    NOSRC_LINES=$(wc -l < "$LATEST_NOSRC")
    [ "$NOSRC_LINES" -ge 200 ] || fail "$LATEST_NOSRC too short ($NOSRC_LINES lines, need >=200)"
    ok "$LATEST_NOSRC present ($NOSRC_LINES lines)"
fi

# 7. CGO drift check — depends on exit path
if [ "$FIX_REPORTS" -gt 0 ]; then
    # Fix landed → arm64 CGOs MUST differ from A21 baseline
    [ -f "$A22_BASELINE" ] || fail "A22-baseline-arm64-cgo-hashes.txt missing (required when fix-summary.md present)"
    DRIFT=0
    TOTAL=0
    while read -r expected path; do
        [ -z "$expected" ] && continue
        TOTAL=$((TOTAL + 1))
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || DRIFT=$((DRIFT + 1))
    done < "$A21_BASELINE"
    [ "$DRIFT" -gt 0 ] || fail "arm64 CGOs byte-identical to A21 baseline but fix-summary.md present — fix didn't change any emit"
    ok "arm64 CGOs drifted from A21 baseline ($DRIFT/$TOTAL CGOs changed — fix shipped real codegen change)"
else
    # No fix → arm64 CGOs SHOULD match A21 baseline (diag-only paths)
    DRIFT=0
    TOTAL=0
    while read -r expected path; do
        [ -z "$expected" ] && continue
        TOTAL=$((TOTAL + 1))
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || DRIFT=$((DRIFT + 1))
    done < "$A21_BASELINE"
    [ "$DRIFT" -eq 0 ] || fail "arm64 CGOs drifted from A21 baseline ($DRIFT/$TOTAL) but no fix-summary.md — code changed without claimed fix"
    ok "arm64 CGOs byte-identical to A21 baseline (honest-exit path, as expected)"
fi

# 8. qemu boot count check
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a22-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a22-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    if [ "$FIX_REPORTS" -gt 0 ]; then
        # Fix path → STRICT: must advance past 216
        [ "$SUM_COUNT" -ge 217 ] || fail "qemu link-finish count $SUM_COUNT — fix-summary.md claims advance but ceiling still $SUM_COUNT (A19 was 216; need >=217)"
        ok "qemu link-finish count $SUM_COUNT (>=217 — real advance past A19 ceiling)"
    else
        # No-fix path → no regression: must not drop below ~200
        [ "$SUM_COUNT" -ge 200 ] || fail "qemu link-finish count regressed: $SUM_COUNT (A19 ceiling was 216; tolerance is 200)"
        ok "qemu link-finish count $SUM_COUNT (>=200 — no regression, honest-exit path)"
    fi
fi

# 9. Desktop x86 smoke — must still reach link finish: logo
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop x86 smoke regressed — A22 broke x86 boot"; }
ok "desktop x86 smoke still passes (link finish: logo reached)"

echo ""
echo "PASS: Phase A22 — arm64 codegen H2 fix exit path: $EXIT_PATH"

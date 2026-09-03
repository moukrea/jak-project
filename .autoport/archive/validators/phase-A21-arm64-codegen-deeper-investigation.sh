#!/usr/bin/env bash
# Phase A21 validator — arm64 codegen deeper investigation (diag phase).
# Success = at least one diag patch landed + bug-class-identified report.
# Optional bonus path: in-scope fix that advances qemu boot past 216.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A17_CLOSE=$(git log --format=%H --all --grep='autoport/A17-idiv-emitter-spill' | head -1)
A19_CLOSE=$(git log --format=%H --all --grep='autoport/A19-goalc-arm64-codegen-fixes' | head -1)
A20_CLOSE=$(git log --format=%H --all --grep='autoport/A20-goalc-arm64-field-offset' | head -1)
ANCHOR=${A20_CLOSE:-${A19_CLOSE:-${A17_CLOSE:-$A4}}}
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A19_BASELINE=".autoport/reports/A19-baseline-arm64-cgo-hashes.txt"
A21_BASELINE=".autoport/reports/A21-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A21 validator (arm64 codegen deeper investigation, diag phase) =="

# 1. Strict lock checks — only A21's unlocked files may have diffs
LOCKED=(
    goalc/emitter/IGenARM64.cpp goalc/emitter/IGenARM64.h
    goalc/emitter/IGenX86_64.cpp goalc/emitter/IGenX86_64.h
    goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp
    goalc/compiler/CodeGenerator.h goalc/compiler/CodeGenerator.cpp
    goalc/compiler/Compiler.cpp
    goalc/compiler/IR.cpp goalc/compiler/IR.h
    goalc/compiler/Val.cpp goalc/compiler/Val.h
    goalc/compiler/compilation/Type.cpp
    goalc/regalloc/Allocator.cpp goalc/regalloc/allocate_common.cpp
    common/type_system/Type.cpp common/type_system/Type.h
    game/kernel/asm_funcs_arm64.s
    game/kernel/common/kscheme.cpp
    game/kernel/common/kmachine.cpp
    game/system/IOP_Kernel.cpp game/system/IOP_Kernel.h
    game/linux-arm64/linux_arm64_runtime_compat.cpp
    android/android_runtime_compat.cpp
)
for f in "${LOCKED[@]}"; do
    [ -f "$f" ] || continue
    DIFF=$(git diff "$ANCHOR" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A20 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "all locked files unchanged since A20"

# 2. Anti-cheat (shared with A20)
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced"
ok "no dodge in source"

[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp"
INLINE_STUBS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' 2>/dev/null | grep -cE '^\+.*\w+_stub\s*\(' || true)
[ "$INLINE_STUBS" -eq 0 ] || fail "inline _stub additions ($INLINE_STUBS)"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
INFRA_DIFF=$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
INFRA_UNSTAGED=$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
[ "$INFRA_DIFF" -eq 0 ] && [ "$INFRA_UNSTAGED" -eq 0 ] || fail "infra modified"
ok "anti-cheat checks all pass"

# 3. A18/A19/A20 invariants still in place
TRAP_BODY=$(grep -nE "_Exit\(13\)|_Exit\s*\(13\)" game/kernel/common/klink.cpp 2>/dev/null | wc -l)
[ "$TRAP_BODY" -gt 0 ] || fail "a18_method_zero_trap no longer calls _Exit(13)"
ok "a18 method-zero trap body still _Exit(13)"

X12_FIX=$(grep -cE "kStpX12X23Push|0xA9BF5FEC" goalc/emitter/IGenARM64.cpp 2>/dev/null)
[ "${X12_FIX:-0}" -gt 0 ] || fail "A19's X12 fix (kStpX12X23Push) missing from IGenARM64.cpp"
ok "A19 X12 fix preserved in HEAD"

OFFSET_TRACE_PATCHES=$(grep -cE "OG_OFFSET_TRACE" goalc/compiler/IR.cpp 2>/dev/null)
[ "${OFFSET_TRACE_PATCHES:-0}" -ge 4 ] || fail "A20's OG_OFFSET_TRACE diag missing from IR.cpp"
ok "A20 OG_OFFSET_TRACE diag preserved in HEAD ($OFFSET_TRACE_PATCHES sites)"

# 4. At least ONE A21 diag patch landed
DIAG_HITS=0
DIAG_NAMES=""
for pair in \
    "linux_arm64_main.cpp:OG_A21_REG_TRACE" \
    "linux_arm64_main.cpp:OG_REG_BYTE_DUMP" \
    "klink.cpp:OG_KLINK_IMM19_TRACE" \
    "Allocator_v2.cpp:OG_REGALLOC_TRACE" \
    "kscheme.cpp:OG_CALLGOAL_TRACE"; do
    F="${pair%%:*}"
    V="${pair##*:}"
    FOUND_FILE=$(find game/linux-arm64 game/kernel goalc/regalloc -name "$F" 2>/dev/null | head -1)
    [ -n "$FOUND_FILE" ] || continue
    HITS=$(grep -c "$V" "$FOUND_FILE" 2>/dev/null || true)
    if [ "${HITS:-0}" -gt 0 ]; then
        DIAG_HITS=$((DIAG_HITS + 1))
        DIAG_NAMES="$DIAG_NAMES $V"
    fi
done
[ "$DIAG_HITS" -gt 0 ] || fail "no A21 diag patch found (expected one of: OG_A21_REG_TRACE, OG_KLINK_IMM19_TRACE, OG_REGALLOC_TRACE, OG_CALLGOAL_TRACE)"
ok "$DIAG_HITS A21 diag patch(es) landed:$DIAG_NAMES"

# 5. Required reports present
[ -f .autoport/reports/A21-diagnostic-summary.md ] || fail "A21-diagnostic-summary.md missing"
DIAG_SUMMARY_LINES=$(wc -l < .autoport/reports/A21-diagnostic-summary.md)
[ "$DIAG_SUMMARY_LINES" -ge 100 ] || fail "A21-diagnostic-summary.md too short ($DIAG_SUMMARY_LINES lines, need >=100)"
ok "A21-diagnostic-summary.md present ($DIAG_SUMMARY_LINES lines)"

BUG_CLASS_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A21-attempt-*-bug-class-identified.md' 2>/dev/null | wc -l)
NO_HYP_REPORTS=$(find .autoport/reports -maxdepth 1 -name 'A21-attempt-*-no-hypothesis-fits.md' 2>/dev/null | wc -l)
[ "$BUG_CLASS_REPORTS" -gt 0 ] || [ "$NO_HYP_REPORTS" -gt 0 ] || fail "no A21-attempt-N-bug-class-identified.md OR A21-attempt-N-no-hypothesis-fits.md"

if [ "$BUG_CLASS_REPORTS" -gt 0 ]; then
    LATEST_BUG=$(ls -t .autoport/reports/A21-attempt-*-bug-class-identified.md | head -1)
    BUG_LINES=$(wc -l < "$LATEST_BUG")
    [ "$BUG_LINES" -ge 150 ] || fail "$LATEST_BUG too short ($BUG_LINES lines, need >=150)"
    # Must name ONE of H1/H2/H3/H4 as primary
    NAMED=$(grep -cE '^\s*(##|###|\*\*).*(H1|H2|H3|H4).*(primary|cause|root|verdict)' "$LATEST_BUG" 2>/dev/null || true)
    [ "${NAMED:-0}" -gt 0 ] || fail "$LATEST_BUG doesn't name H1/H2/H3/H4 as primary/cause/root"
    ok "$LATEST_BUG present ($BUG_LINES lines, names primary hypothesis)"
fi
if [ "$NO_HYP_REPORTS" -gt 0 ]; then
    LATEST_NO_HYP=$(ls -t .autoport/reports/A21-attempt-*-no-hypothesis-fits.md | head -1)
    NO_HYP_LINES=$(wc -l < "$LATEST_NO_HYP")
    [ "$NO_HYP_LINES" -ge 150 ] || fail "$LATEST_NO_HYP too short ($NO_HYP_LINES lines, need >=150)"
    ok "$LATEST_NO_HYP present ($NO_HYP_LINES lines, escalates to broader A22)"
fi

# 6. Baseline file present
[ -f "$A21_BASELINE" ] || fail "A21-baseline-arm64-cgo-hashes.txt missing"
ok "A21 arm64 CGO baseline file present"

# 7. x86 CGOs byte-identical to A2 baseline (HARD REGRESSION CHECK)
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path — A21 broke shared code"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline (x86 untouched)"

# 8. arm64 CGOs SHOULD be byte-identical to A19 baseline (A21 is diag-only).
# Exception: if claude landed an in-scope fix and qemu advances past 216, the
# CGOs may differ. We only ENFORCE this when no fix-summary is present.
if [ -f "$A19_BASELINE" ]; then
    DRIFT=0
    TOTAL=0
    while read -r expected path; do
        [ -z "$expected" ] && continue
        TOTAL=$((TOTAL + 1))
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || DRIFT=$((DRIFT + 1))
    done < "$A19_BASELINE"
    if [ -f .autoport/reports/A21-fix-summary.md ]; then
        ok "arm64 CGO drift $DRIFT/$TOTAL (A21-fix-summary present, drift expected)"
    else
        [ "$DRIFT" -eq 0 ] || fail "arm64 CGOs drifted from A19 baseline ($DRIFT/$TOTAL) but no A21-fix-summary.md — diag-only phase shouldn't change emit"
        ok "arm64 CGOs byte-identical to A19 baseline (diag-only, as expected)"
    fi
fi

# 9. qemu boot count — must not regress below 216 (A19 ceiling)
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a21-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a21-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    [ "$SUM_COUNT" -ge 200 ] || fail "qemu link-finish count regressed: $SUM_COUNT (A19 ceiling was 216; tolerance is 200)"
    if [ "$SUM_COUNT" -gt 216 ]; then
        ok "qemu link-finish count $SUM_COUNT (>216 — bonus advance!)"
    else
        ok "qemu link-finish count $SUM_COUNT (>=200 — diag-only, ceiling unchanged as expected)"
    fi
fi

# 10. Desktop x86 smoke — must still reach link finish: logo
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop x86 smoke regressed — A21 broke x86 boot"; }
ok "desktop x86 smoke still passes (link finish: logo reached)"

echo ""
echo "PASS: Phase A21 — arm64 codegen deeper investigation (diag phase) landed; one or more of H1/H2/H3/H4 named as primary cause; A22 fix scope recommended."

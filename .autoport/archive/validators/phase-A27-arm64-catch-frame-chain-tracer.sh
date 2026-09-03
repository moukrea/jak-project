#!/usr/bin/env bash
# Phase A27 validator — catch-frame chain tracer to discriminate H1/H2/H3/H5.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A19_CLOSE=$(git log --format=%H --all --grep='autoport/A19-goalc-arm64-codegen-fixes' | head -1)
A20_CLOSE=$(git log --format=%H --all --grep='autoport/A20-goalc-arm64-field-offset' | head -1)
A21_CLOSE=$(git log --format=%H --all --grep='autoport/A21-arm64-codegen-deeper-investigation' | head -1)
A22_CLOSE=$(git log --format=%H --all --grep='autoport/A22-arm64-codegen-h2-fix' | head -1)
A23_CLOSE=$(git log --format=%H --all --grep='autoport/A23-arm64-blr-target-tracer' | head -1)
A24_CLOSE=$(git log --format=%H --all --grep='autoport/A24-arm64-epilogue-x30-tracer' | head -1)
A25_CLOSE=$(git log --format=%H --all --grep='autoport/A25-arm64-ir-regset-fpr-dispatch' | head -1)
A26_CLOSE=$(git log --format=%H --all --grep='autoport/A26-arm64-xmm-symmetric-and-break-trap' | head -1)
ANCHOR=${A26_CLOSE:-${A25_CLOSE:-${A24_CLOSE:-${A23_CLOSE:-${A22_CLOSE:-${A21_CLOSE:-${A20_CLOSE:-${A19_CLOSE:-$A4}}}}}}}}
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A26_BASELINE=".autoport/reports/A26-baseline-arm64-cgo-hashes.txt"
A27_BASELINE=".autoport/reports/A27-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A27 validator (catch-frame chain tracer) =="
echo "  anchor: $ANCHOR"

# 1. Lock check (Allocator.cpp explicitly locked — H4 deferred)
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
    [ "$DIFF" -eq 0 ] || fail "$f changed since A26 (lock violation)"
done
GOAL_DIFF=$(git diff "$ANCHOR" HEAD -- 'goal_src/' 2>/dev/null | wc -l)
[ "$GOAL_DIFF" -eq 0 ] || fail "goal_src/ modified — would break x86 byte-identity"
ok "all locked files unchanged since A26"

# 2. Anti-cheat
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge"
ok "no dodge"

WEAK_ADDS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)
[ "$WEAK_ADDS" -eq 0 ] || fail "weak additions"
ABORT_ADDS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
[ "$ABORT_ADDS" -eq 0 ] || fail "abort additions"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "_stubs.cpp"

SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
INFRA_DIFF=$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
INFRA_UNSTAGED=$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
[ "$INFRA_DIFF" -eq 0 ] && [ "$INFRA_UNSTAGED" -eq 0 ] || fail "infra modified"
ok "anti-cheat clean"

# 3. Invariants
grep -nE "_Exit\(13\)" game/kernel/common/klink.cpp >/dev/null || fail "A18 trap missing"
ok "A18 preserved"
grep -cE "kStpX12X23Push|0xA9BF5FEC" goalc/emitter/IGenARM64.cpp | head -1 | grep -qE '^[1-9]' || fail "A19 X12 fix missing"
ok "A19 preserved"
[ "$(grep -cE 'OG_OFFSET_TRACE' goalc/compiler/IR.cpp)" -ge 4 ] || fail "A20 missing"
ok "A20 preserved"
for pair in "game/kernel/common/klink.cpp:OG_KLINK_IMM19_TRACE" \
            "game/linux-arm64/linux_arm64_main.cpp:OG_REG_BYTE_DUMP" \
            "goalc/regalloc/Allocator_v2.cpp:OG_REGALLOC_TRACE" \
            "game/kernel/jak1/kscheme.cpp:OG_CALLGOAL_TRACE"; do
    F="${pair%%:*}"; V="${pair##*:}"
    grep -q "$V" "$F" || fail "A21 diag $V missing"
done
ok "A21 preserved"
grep -qE "OG_BLR_TARGET_TRACE|blr_target_trace_emit_enabled" goalc/emitter/IGenARM64.cpp || fail "A23 emit missing"
grep -qE "0x1EE0|BLR-TARGET-STACK" game/linux-arm64/linux_arm64_main.cpp || fail "A23 decoder missing"
ok "A23 preserved"
grep -qE "OG_X30_TRACE_EMIT|epilogue_x30_trace_emit_enabled|0x1EF0" goalc/compiler/CodeGenerator.cpp || fail "A24 emit missing"
grep -qE "0x1EF0|EPILOGUE-X30-STACK" game/linux-arm64/linux_arm64_main.cpp || fail "A24 decoder missing"
ok "A24 preserved"
grep -qE "emit_arm64_reg_to_reg_mov|fmov_d_d" goalc/compiler/IR.cpp goalc/emitter/IGenARM64.cpp goalc/emitter/IGenARM64.h || fail "A25 helpers missing"
ok "A25 helpers preserved"
grep -qE "cbnz_x_imm|udf_imm16|0xBEEF|0xbeef" goalc/emitter/IGenARM64.cpp goalc/compiler/IR.cpp || fail "A26 helpers missing"
grep -qE "0xBEEF|0xbeef|BREAK-MACRO-TRAP" game/linux-arm64/linux_arm64_main.cpp || fail "A26 decoder missing"
ok "A26 helpers preserved"

# 4. x86 CGOs
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs match A2"

# 5. Required reports
FIX=$(find .autoport/reports -maxdepth 1 -name 'A27-fix-summary.md' 2>/dev/null | wc -l)
NEXT=$(find .autoport/reports -maxdepth 1 -name 'A27-attempt-*-next-blocker.md' 2>/dev/null | wc -l)
BUGLOC=$(find .autoport/reports -maxdepth 1 -name 'A27-attempt-*-bug-located-named-source.md' 2>/dev/null | wc -l)
NOSRC=$(find .autoport/reports -maxdepth 1 -name 'A27-attempt-*-no-source-located.md' 2>/dev/null | wc -l)
TOTAL=$((FIX + NEXT + BUGLOC + NOSRC))
[ "$TOTAL" -gt 0 ] || fail "no A27 exit report"

[ -f .autoport/reports/A27-investigation-trace.md ] || fail "A27-investigation-trace.md missing"
INV_LINES=$(wc -l < .autoport/reports/A27-investigation-trace.md)
[ "$INV_LINES" -ge 200 ] || fail "investigation-trace too short ($INV_LINES)"
ok "A27 reports present (investigation-trace: $INV_LINES lines)"

EXIT_PATH=""
for tag in fix next bug nosrc; do
  case $tag in
    fix) RFILE=.autoport/reports/A27-fix-summary.md; LBL="fix";;
    next) RFILE=$(ls -t .autoport/reports/A27-attempt-*-next-blocker.md 2>/dev/null | head -1); LBL="next-blocker";;
    bug) RFILE=$(ls -t .autoport/reports/A27-attempt-*-bug-located-named-source.md 2>/dev/null | head -1); LBL="bug-located";;
    nosrc) RFILE=$(ls -t .autoport/reports/A27-attempt-*-no-source-located.md 2>/dev/null | head -1); LBL="no-source-located";;
  esac
  [ -n "$RFILE" ] && [ -f "$RFILE" ] || continue
  L=$(wc -l < "$RFILE")
  [ "$L" -ge 250 ] || fail "$RFILE too short ($L)"
  EXIT_PATH="${EXIT_PATH:+$EXIT_PATH+}$LBL"
done

# 6. A27 chain dumper landed
A27_DEC=$(grep -cE "A27-DIAG|catch-frame chain|chain dump" game/linux-arm64/linux_arm64_main.cpp 2>/dev/null || echo 0)
[ "${A27_DEC:-0}" -gt 0 ] || fail "A27 chain dumper missing from linux_arm64_main.cpp"
ok "A27 chain dumper present ($A27_DEC hits)"

# 7. CGO drift (A27 may or may not change CGOs)
ARM64_VS_A26_DRIFT=0
ARM64_VS_A26_TOTAL=0
while read -r expected path; do
    [ -z "$expected" ] && continue
    ARM64_VS_A26_TOTAL=$((ARM64_VS_A26_TOTAL + 1))
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || ARM64_VS_A26_DRIFT=$((ARM64_VS_A26_DRIFT + 1))
done < "$A26_BASELINE"

if [ "$FIX" -gt 0 ]; then
    [ -f "$A27_BASELINE" ] || fail "A27-baseline missing (required when fix landed)"
    [ "$ARM64_VS_A26_DRIFT" -gt 0 ] || fail "CGOs match A26 but fix-summary claims fix landed"
    ok "arm64 CGOs drifted from A26 (real fix)"
elif [ "$ARM64_VS_A26_DRIFT" -eq 0 ]; then
    ok "arm64 CGOs match A26 baseline (no emit change — diag-only)"
else
    # CGOs drifted but no fix-summary; allow if A27-baseline matches
    [ -f "$A27_BASELINE" ] || fail "CGOs drifted from A26 without A27-baseline file"
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "A27-baseline mismatch: $path"
    done < "$A27_BASELINE"
    ok "arm64 CGOs drifted from A26 + match A27-baseline (some emit-influencing diag landed)"
fi

# 8. qemu boot count
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a27-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a27-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    if [ "$FIX" -gt 0 ]; then
        [ "$SUM_COUNT" -ge 217 ] || fail "qemu $SUM_COUNT — fix path needs >=217"
        ok "qemu $SUM_COUNT (>=217, ADVANCE)"
    else
        [ "$SUM_COUNT" -ge 200 ] || fail "qemu regressed: $SUM_COUNT"
        ok "qemu $SUM_COUNT (>=200)"
    fi
fi

# 9. Desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop x86 smoke regressed"; }
ok "desktop x86 smoke passes"

echo ""
echo "PASS: Phase A27 — catch-frame chain tracer, exit path: $EXIT_PATH"

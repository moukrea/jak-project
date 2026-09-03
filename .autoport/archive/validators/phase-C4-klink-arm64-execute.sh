#!/usr/bin/env bash
# Phase C4 validator — klink arm64 ADRP+ADD fixups + bytecode execute.
# Authored by the supervisor 2026-05-21.
#
# C4 inherits all C3 invariants (the 39 checks from
# phase-C3-linux-arm64-title.sh's full output) and adds C4-specific:
#   - LINK_FLAG_EXECUTE enabled (inverse of C3's check)
#   - No SIGILL/SIGSEGV in the EXECUTE-enabled run
#   - NumSymbols rises by 200-2000 post-execute
#   - klink.cpp diff shows real ADRP/imm12-aware patching code
#   - codegen / classifier / desktop-oracle still locked

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

C3_VALIDATOR=".autoport/validators/phase-C3-linux-arm64-title.sh"
C4_RUN_SCRIPT=".autoport/lib/c4_run.sh"
C4_BOOT_LOG=".autoport/reports/C4-boot.log"
C4_EXIT_TXT=".autoport/reports/C4-exit.txt"
C4_REPORT_MD=".autoport/reports/C4-execute.md"
LINUX_ARM64_MAIN="game/linux-arm64/linux_arm64_main.cpp"
KLINK_CPP="game/kernel/common/klink.cpp"
CLASSIFIER=".autoport/lib/classify_ir_arm64.py"
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase C4 validator =="

# ---- 1. C3 invariants must still pass ----
# Run C3's validator end-to-end; if anything regresses, C4 fails.
echo "  re-running C3 validator (inherited invariants)..."
[ -x "$C3_VALIDATOR" ] || fail "$C3_VALIDATOR missing"
"$C3_VALIDATOR" > /tmp/c4-c3-validator.log 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "C3 validator regressed; tail of its output:"
    tail -30 /tmp/c4-c3-validator.log
    fail "C3 invariants no longer hold"
fi
ok "C3 invariants all still hold"

# ---- 2. Required C4 files ----
[ -f "$C4_BOOT_LOG" ] || fail "$C4_BOOT_LOG missing"
[ -f "$C4_EXIT_TXT" ] || fail "$C4_EXIT_TXT missing"
[ -f "$C4_REPORT_MD" ] || fail "$C4_REPORT_MD missing"
[ -x "$C4_RUN_SCRIPT" ] || fail "$C4_RUN_SCRIPT missing or not executable"
ok "C4 required files present"

# ---- 3. LINK_FLAG_EXECUTE enabled in linux_arm64_main.cpp ----
if ! grep -qE 'LINK_FLAG_EXECUTE' "$LINUX_ARM64_MAIN"; then
    fail "$LINUX_ARM64_MAIN does not enable LINK_FLAG_EXECUTE"
fi
# It should be in the flags constant, not just a comment
if ! grep -qE '^[^/]*LINK_FLAG_(OUTPUT_LOAD|EXECUTE|PRINT_LOGIN).*\|.*LINK_FLAG_EXECUTE|^[^/]*LINK_FLAG_EXECUTE.*\|.*LINK_FLAG_' "$LINUX_ARM64_MAIN"; then
    # Less strict: just confirm a non-comment line contains LINK_FLAG_EXECUTE
    if ! grep -nE '^[[:space:]]*[^/].*LINK_FLAG_EXECUTE' "$LINUX_ARM64_MAIN" >/dev/null; then
        fail "LINK_FLAG_EXECUTE only present in comments, not in active code"
    fi
fi
ok "LINK_FLAG_EXECUTE enabled in active code"

# ---- 4. No SIGILL/SIGSEGV/abort/UDF in C4 boot log ----
if grep -qE 'Illegal instruction|SIGILL|SIGSEGV|signal 4|signal 11|terminate called|Aborted|qemu: uncaught|UDF #' "$C4_BOOT_LOG"; then
    echo "C4 boot log shows a fault:"
    grep -nE 'Illegal instruction|SIGILL|SIGSEGV|signal 4|signal 11|terminate|Aborted|qemu: uncaught|UDF #' "$C4_BOOT_LOG" | head -5
    fail "C4 EXECUTE-enabled run hit a fault — klink patching is still wrong"
fi
ok "C4 boot log free of fault markers"

# ---- 5. C4 exit code is 0 ----
EXIT_CODE=$(cat "$C4_EXIT_TXT")
[ "$EXIT_CODE" = "0" ] || fail "qemu C4 exit code = $EXIT_CODE (expected 0)"
ok "qemu C4 exit code = 0"

# ---- 6. All 8 link-finish markers present ----
EXPECTED_LINKS=(gcommon gstring-h gkernel-h gkernel pskernel gstring dgo-h gstate)
for name in "${EXPECTED_LINKS[@]}"; do
    grep -qE "link finish: ${name}\$|link finish: ${name}[[:space:]]" "$C4_BOOT_LOG" \
        || fail "C4 boot log missing 'link finish: $name'"
done
ok "all 8 KERNEL.CGO objects relinked under C4"

# ---- 7. Post-execute marker with NumSymbols floor ----
POST_LINE=$(grep -E "C4 KERNEL.CGO execute complete \(NumSymbols=[0-9]+, post-execute-delta=\+[0-9]+\)" "$C4_BOOT_LOG" | tail -1)
[ -n "$POST_LINE" ] || fail "C4 boot log missing 'C4 KERNEL.CGO execute complete (NumSymbols=N, post-execute-delta=+M)'"
N=$(echo "$POST_LINE" | grep -oE 'NumSymbols=[0-9]+' | grep -oE '[0-9]+')
M=$(echo "$POST_LINE" | grep -oE 'post-execute-delta=\+[0-9]+' | grep -oE '[0-9]+')
[ "$N" -ge 517 ] || fail "NumSymbols=$N below floor 517 (C3 was 317; need ≥200 post-execute delta)"
[ "$M" -ge 200 ] || fail "post-execute-delta=$M below 200 (gcommon top-level should intern ≥200 symbols)"
[ "$M" -le 2000 ] || fail "post-execute-delta=$M above cap 2000 (symbol table looks like it's being spammed)"
ok "NumSymbols=$N (+$M post-execute) within expected bounds"

# ---- 8. No signal-handler trickery for SIGILL ----
if grep -qE 'signal\([^)]*SIGILL|sigaction[^;]*SIGILL' "$LINUX_ARM64_MAIN"; then
    fail "$LINUX_ARM64_MAIN installs a SIGILL handler — execution under signal-suppression forbidden"
fi
ok "no SIGILL handler in linux_arm64_main"

# ---- 9. NumSymbols= literal appears exactly once in linux_arm64_main ----
NS_COUNT=$(grep -cE 'NumSymbols=' "$LINUX_ARM64_MAIN")
[ "$NS_COUNT" -eq 1 ] || fail "linux_arm64_main has 'NumSymbols=' literal $NS_COUNT times (must be exactly 1)"
ok "NumSymbols= literal present once (in the live-runtime print)"

# ---- 10. klink.cpp diff vs A4 shows real ADRP/imm12 awareness ----
A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
[ -n "$A4_COMMIT" ] || fail "could not locate A4 commit"
KLINK_DIFF_LINES=$(git diff "$A4_COMMIT" -- "$KLINK_CPP" 2>/dev/null | wc -l)
[ "$KLINK_DIFF_LINES" -ge 30 ] || fail "$KLINK_CPP diff vs A4 is $KLINK_DIFF_LINES lines (<30, too small to be real arm64 patching)"
if ! git diff "$A4_COMMIT" -- "$KLINK_CPP" | grep -qiE "ADRP|adrp"; then
    fail "$KLINK_CPP diff doesn't mention ADRP — A4 widened ObjectGenerator the same way, C4 should mirror"
fi
if ! git diff "$A4_COMMIT" -- "$KLINK_CPP" | grep -qiE "imm12"; then
    fail "$KLINK_CPP diff doesn't reference imm12 — partial fix?"
fi
ok "klink.cpp shows arm64-aware patching code"

# ---- 11. Codegen still locked since A4 ----
# Phase A5 explicitly unlocks goalc/emitter/IGenARM64.cpp +
# ObjectGenerator.cpp for the far-reloc sym-mem expansion that closes
# C4's 691-NOP gap. The A5 validator enforces its own narrow lock on
# those two files; C4 only needs to guard the still-locked files.
for f in goalc/compiler/IR.cpp \
         goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/CodeGenerator.h; do
    if [ -f "$f" ]; then
        DIFF=$(git diff "$A4_COMMIT" -- "$f" 2>/dev/null | wc -l)
        [ "$DIFF" -eq 0 ] || fail "$f changed since A4 (still-locked file after A5 narrow unlock)"
    fi
done
ok "still-locked codegen files byte-identical to A4 (IGenARM64.cpp + ObjectGenerator.cpp unlocked by A5)"

# ---- 12. Classifier still locked since A1 ----
A1_COMMIT=$(git log --format=%H --all --grep="\[autoport/A1-emitter-enumerate\] enumerate" | head -1)
CLF_DIFF=$(git diff "$A1_COMMIT" -- "$CLASSIFIER" 2>/dev/null | wc -l)
[ "$CLF_DIFF" -eq 0 ] || fail "$CLASSIFIER modified since A1"
ok "classifier still locked"

# ---- 13. x86 CGOs untouched ----
while read -r expected_hash path; do
    [ -z "$expected_hash" ] && continue
    # Handle either "HASH  PATH" or "HASH  filename" formats
    [[ "$path" == /* || "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected_hash" = "$actual" ] \
        || fail "x86 CGO drift: $path (expected $expected_hash, got $actual)"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# ---- 14. No conditional LINK_FLAG_EXECUTE references ----
# Anti-cheat: must not selectively disable EXECUTE per object
COND_COUNT=$(grep -cE 'if[^{]*LINK_FLAG_EXECUTE|LINK_FLAG_EXECUTE.*?:|\?[^?]*LINK_FLAG_EXECUTE' "$LINUX_ARM64_MAIN" || true)
[ "$COND_COUNT" -eq 0 ] || fail "linux_arm64_main has conditional LINK_FLAG_EXECUTE references — must be a single constant"
ok "LINK_FLAG_EXECUTE applied uniformly"

# ---- 15. C4-execute.md headline ----
if ! grep -qiE 'ADRP|NumSymbols' "$C4_REPORT_MD"; then
    fail "$C4_REPORT_MD missing ADRP or NumSymbols keyword"
fi
ok "C4-execute.md headline present"

# ---- 16. Instruction-kind histogram in C4-execute.md sums to ≥ 100 ----
HIST_SUM=$(grep -oE '(ADRP|ADD[[:space:]]*imm12|LDR[[:space:]]*imm12|STR[[:space:]]*imm12)[[:space:]]*:?[[:space:]]*[0-9]+' "$C4_REPORT_MD" | grep -oE '[0-9]+$' | python3 -c "import sys; print(sum(int(x) for x in sys.stdin))" 2>/dev/null || echo 0)
[ "$HIST_SUM" -ge 100 ] || fail "klink instruction-kind histogram sum=$HIST_SUM (<100, suggests very few patches actually happened)"
ok "klink handled $HIST_SUM arm64 instruction patches"

echo ""
echo "PASS: Phase C4 — klink arm64-aware; gcommon executes under qemu without SIGILL."

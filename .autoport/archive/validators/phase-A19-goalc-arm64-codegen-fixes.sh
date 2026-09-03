#!/usr/bin/env bash
# Phase A19 validator — arm64 goalc codegen fixes (X12 regalloc + field-offset off-by-4).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A17_CLOSE=$(git log --format=%H --all --grep='autoport/A17-idiv-emitter-spill' | head -1)
A18_CLOSE=$(git log --format=%H --all --grep='autoport/A18-type-method-zero-bind' | head -1)
ANCHOR=${A18_CLOSE:-${A17_CLOSE:-$A4}}
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A19_BASELINE=".autoport/reports/A19-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A19 validator (arm64 goalc codegen fixes) =="

# 1. A19-unlocked targets changed (regalloc + emitter must both have real edits)
ALLOC_DIFF=$(git diff "$ANCHOR" HEAD -- goalc/regalloc/Allocator_v2.cpp goalc/regalloc/Allocator_v2.h 2>/dev/null | wc -l)
[ "$ALLOC_DIFF" -gt 5 ] || fail "Allocator_v2.cpp/h not modified since A18 ($ALLOC_DIFF lines) — X12 fix not landed"
ok "Allocator_v2 has $ALLOC_DIFF lines diff from A18"

IGEN_DIFF=$(git diff "$ANCHOR" HEAD -- goalc/emitter/IGenARM64.cpp goalc/emitter/IGenARM64.h 2>/dev/null | wc -l)
[ "$IGEN_DIFF" -gt 5 ] || fail "IGenARM64.cpp/h not modified since A18 ($IGEN_DIFF lines) — off-by-4 fix not landed"
ok "IGenARM64 has $IGEN_DIFF lines diff from A18"

# 2. NO changes to x86 emitter / shared IR / shared regalloc / shared codegen
for f in goalc/emitter/IGenX86_64.h goalc/emitter/IGenX86_64.cpp \
         goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp \
         goalc/compiler/CodeGenerator.h goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/IR.h goalc/compiler/IR.cpp \
         goalc/compiler/Compiler.cpp \
         goalc/regalloc/Allocator.cpp goalc/regalloc/allocate_common.cpp \
         game/kernel/asm_funcs_arm64.s \
         game/kernel/common/kscheme.cpp \
         game/kernel/common/kmachine.cpp \
         game/system/IOP_Kernel.cpp game/system/IOP_Kernel.h \
         game/linux-arm64/linux_arm64_runtime_compat.cpp \
         android/android_runtime_compat.cpp; do
    [ -f "$f" ] || continue
    DIFF=$(git diff "$ANCHOR" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A18 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "all locked files unchanged since A18"

# 3. Anti-cheat (shared)
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced"
ok "no dodge in source"

[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp"
INLINE_STUBS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' 2>/dev/null | grep -cE '^\+.*\w+_stub\s*\(' || true)
[ "$INLINE_STUBS" -eq 0 ] || fail "inline _stub additions ($INLINE_STUBS)"

DIFF_FILE=$(mktemp); trap "rm -f $DIFF_FILE" EXIT
git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' > "$DIFF_FILE" 2>/dev/null || true
STUB_SHAPED=$(DIFF_FILE="$DIFF_FILE" python3 - <<'PY' || true
import re, os
diff = open(os.environ['DIFF_FILE']).read()
added_blocks = []
cur = []
for line in diff.splitlines():
    if line.startswith('+') and not line.startswith('+++'):
        cur.append(line[1:])
    else:
        if cur: added_blocks.append('\n'.join(cur))
        cur = []
if cur: added_blocks.append('\n'.join(cur))
hits = 0
fn_re = re.compile(
    r'\b(?:u64|u32|s64|s32|uint64_t|uint32_t|int64_t|int32_t|void)\s+'
    r'(\w+_(?:impl|bridge|shim|trampoline|proxy|bound|hook))\s*\([^{;]*\)\s*'
    r'\{([^{}]*)\}', re.M)
for blk in added_blocks:
    for m in fn_re.finditer(blk):
        body = m.group(2)
        clean = re.sub(r'//[^\n]*', '', body)
        clean = re.sub(r'/\*.*?\*/', '', clean, flags=re.S)
        clean = re.sub(r'(?:std::)?(?:fprintf|printf|fputs|puts|lg::\w+)\([^;]*\);', '', clean)
        clean = clean.strip()
        if re.match(r'^\s*return\s+0\s*;\s*$', clean):
            hits += 1
            print(f"STUB-SHAPED: {m.group(1)}")
print(f"hits={hits}")
PY
)
RENAME_STUBS=$(echo "$STUB_SHAPED" | grep -oE "hits=[0-9]+" | tail -1 | cut -d= -f2)
[ "${RENAME_STUBS:-0}" -eq 0 ] || { echo "$STUB_SHAPED" | head -10; fail "rename-evasion stub-shaped functions added ($RENAME_STUBS)"; }
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
INFRA_DIFF=$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
INFRA_UNSTAGED=$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
[ "$INFRA_DIFF" -eq 0 ] && [ "$INFRA_UNSTAGED" -eq 0 ] || fail "infra modified"
ok "anti-cheat checks all pass"

# 4. A18 anti-cheat invariants still in place
TRAP_BODY=$(grep -nE "_Exit\(13\)|_Exit\s*\(13\)" game/kernel/common/klink.cpp 2>/dev/null | wc -l)
[ "$TRAP_BODY" -gt 0 ] || fail "a18_method_zero_trap no longer calls _Exit(13)"
ok "a18 method-zero trap body still _Exit(13)"

# 5. Fix summary + baseline present
[ -f .autoport/reports/A19-fix-summary.md ] || fail "A19-fix-summary.md missing"
ok "A19 fix summary present"

[ -f "$A19_BASELINE" ] || fail "A19-baseline-arm64-cgo-hashes.txt missing — orchestrator must produce fresh arm64 CGO baseline"
ok "A19 arm64 CGO baseline file present"

# 6. x86 CGOs byte-identical to A2 baseline (HARD REGRESSION CHECK)
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path — A19 broke shared code"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline (x86 untouched)"

# 7. arm64 CGOs MUST differ from A17 baseline (proves emit changed)
A17_BASELINE=".autoport/reports/A17-baseline-arm64-cgo-hashes.txt"
if [ -f "$A17_BASELINE" ]; then
    CHANGED=0
    TOTAL=0
    while read -r expected path; do
        [ -z "$expected" ] && continue
        TOTAL=$((TOTAL + 1))
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || CHANGED=$((CHANGED + 1))
    done < "$A17_BASELINE"
    [ "$CHANGED" -gt 0 ] || fail "no arm64 CGO changed since A17 — codegen fix didn't ripple (regalloc + emit fix would change every CGO)"
    ok "$CHANGED / $TOTAL arm64 CGOs differ from A17 baseline (codegen fix landed)"
fi

# 8. arm64 CGOs match A19 baseline (proves reproducibility)
A19_MATCH=0
A19_TOTAL=0
while read -r expected path; do
    [ -z "$expected" ] && continue
    A19_TOTAL=$((A19_TOTAL + 1))
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] && A19_MATCH=$((A19_MATCH + 1))
done < "$A19_BASELINE"
[ "$A19_MATCH" -eq "$A19_TOTAL" ] && [ "$A19_TOTAL" -gt 0 ] || fail "arm64 CGOs don't match A19 baseline ($A19_MATCH/$A19_TOTAL match)"
ok "arm64 CGOs match A19 baseline ($A19_MATCH/$A19_TOTAL)"

# 9. The specific diagnostic bug: find-gap-by-size's first LDR must encode offset 0x34 (52), not 0x30 (48)
# Build a tiny disasm probe: scan KERNEL.CGO for the byte pattern that decodes to LDR Wt, [Xn, #0x34]
KERNEL_ARM64="out/jak1-arm64/iso/KERNEL.CGO"
if [ -f "$KERNEL_ARM64" ]; then
    # Look for "0xb9403403" (LDR W3,[X16,#0x34]) or any "0xb940 34xx" (LDR Wt,[Xn,#0x34])
    # The encoding is 1011_1001_0100_0000_0011_01xx_xxxx_xxxx for offset 0x34
    # In LE bytes that's the pattern: ?? 34 40 b9 (last 3 bytes fixed, first byte = Rt|(Rn<<5))
    # Looser check: simply that the kernel CGO bytes have at least one such pattern
    OFFSET_34_HITS=$(python3 - "$KERNEL_ARM64" <<'PY' || true
import sys
data = open(sys.argv[1], 'rb').read()
# LDR-32 unsigned imm12 = 0x34 / 4 = 13 = 0x0D
# Encoding: 1011 1001 01 00 0000 0011 01_RRRR_RRRR_R
# Top 22 bits = 0xB940_0D (where 0x0D = imm12)
# Bytes [3:0] = b9 4d 03 xy — no wait, let me redo this:
# 32-bit little-endian:
#   byte 3 (MSB): 1011_1001 = 0xb9
#   byte 2     : 01_RR_RRRR or simpler: bits 15-22 of instruction
#   byte 1     : bits 7-14
#   byte 0     : bits 0-6
# imm12=0x0D, opcode 0xb940XXXX where XXXX encodes imm12<<10 | Rn<<5 | Rt
# imm12 bits in big-endian-int positions: bits 21-10
# 0x0D << 10 = 0x3400, so 0xb940XXXX has high nibble 3, second nibble 4..7 for varying Rn high bit
# Let me just grep for the LE bytes pattern 0x?? 0x?? 0x40 0xb9 with bit 21-10 encoding 0x0D
# Equivalent: bytes[2] in {0x34, 0x35, 0x36, 0x37} and bytes[3] = 0xb9
hits = 0
sample = []
for i in range(0, len(data) - 4):
    if data[i+3] == 0xb9 and (data[i+2] & 0xfc) == 0x34:
        hits += 1
        if len(sample) < 3:
            instr = int.from_bytes(data[i:i+4], 'little')
            sample.append(f"0x{instr:08x}@{i}")
print(f"hits={hits}")
if sample:
    print("sample:", " ".join(sample))
PY
)
    LDR_34_COUNT=$(echo "$OFFSET_34_HITS" | grep -oE "hits=[0-9]+" | cut -d= -f2)
    [ "${LDR_34_COUNT:-0}" -gt 0 ] || fail "no LDR Wt,[Xn,#0x34] pattern in KERNEL.CGO — off-by-4 fix did not land in arm64 emit"
    ok "arm64 KERNEL.CGO contains $LDR_34_COUNT LDR-at-offset-0x34 patterns (off-by-4 fix shipped)"
fi

# 10. qemu repro strict advance past A18 ceiling (216) by ≥30 link-finishes
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a19-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a19-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    [ "$SUM_COUNT" -ge 216 ] || fail "qemu link-finish count regressed: $SUM_COUNT (A18 ceiling was 216)"
    [ "$SUM_COUNT" -ge 246 ] || fail "qemu link-finish count $SUM_COUNT not >= 246 — A19's fix did not unblock the post-time-of-day chain"
    ok "qemu repro link-finish count $SUM_COUNT (>=246)"
fi

# 11. Device advance check (relaxed per A17 lesson: link count > 216, eventual crash OK)
if [ -x .autoport/lib/d4_run.sh ]; then
    bash .autoport/lib/d4_run.sh > /tmp/a19-d4-launch.log 2>&1 || true
fi
DEVICE_LINKS=$(grep -c "link finish:" .autoport/reports/D4-boot.log 2>/dev/null || echo 0)
[ "$DEVICE_LINKS" -gt 216 ] || fail "device link-finish count $DEVICE_LINKS not > 216"
ok "device link-finish count $DEVICE_LINKS (>216)"

# 12. Desktop x86 smoke — must still reach link finish: logo
SMOKE=$(mktemp); trap "rm -f $SMOKE $DIFF_FILE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop x86 smoke regressed — A19 broke x86 boot"; }
ok "desktop x86 smoke still passes (link finish: logo reached)"

echo ""
echo "PASS: Phase A19 — arm64 goalc codegen fixes landed; qemu advances ≥246 link-finishes."

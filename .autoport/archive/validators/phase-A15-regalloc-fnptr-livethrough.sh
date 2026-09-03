#!/usr/bin/env bash
# Phase A15 validator — regalloc constraint: CALL_R64 target reg lives through intervening defs.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A14_CLOSE=$(git log --format=%H --all --grep='autoport/A14-pc-memmove-bind' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A11_BASELINE=".autoport/reports/A11-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A15 validator (regalloc fn-ptr live-through) =="

# 1. At least one A15-unlocked target changed (goalc/regalloc/)
REGALLOC_DIFF=$(git diff "$A14_CLOSE" HEAD -- 'goalc/regalloc/*' 2>/dev/null | wc -l)
[ "$REGALLOC_DIFF" -gt 5 ] || fail "no goalc/regalloc/ change since A14 ($REGALLOC_DIFF lines)"
ok "goalc/regalloc/ has $REGALLOC_DIFF lines diff from A14"

# 2. Locked files unchanged
for f in goalc/emitter/IGenARM64.h goalc/emitter/IGenARM64.cpp \
         goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp \
         goalc/compiler/CodeGenerator.h goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/IR.h goalc/compiler/IR.cpp \
         game/kernel/asm_funcs_arm64.s game/kernel/common/kscheme.cpp \
         game/kernel/common/kmachine.cpp \
         game/system/IOP_Kernel.cpp game/system/IOP_Kernel.h \
         game/linux-arm64/linux_arm64_runtime_compat.cpp \
         android/android_runtime_compat.cpp \
         game/kernel/common/klink.cpp game/kernel/common/klink.h; do
    [ -f "$f" ] || continue
    DIFF=$(git diff "$A14_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A14 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "all locked files unchanged since A14"

# 3. Anti-cheat: no dodges
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced"
ok "no dodge in source"

# 4. No new abort/weak/stubs/inline-stubs/rename-evasion since A14
ANCHOR=${A14_CLOSE:-$A4}
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions since A14"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions since A14"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp since A14"
INLINE_STUBS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' 2>/dev/null | grep -cE '^\+.*\w+_stub\s*\(' || true)
[ "$INLINE_STUBS" -eq 0 ] || fail "inline _stub additions since A14 ($INLINE_STUBS)"
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
[ "$INFRA_DIFF" -eq 0 ] && [ "$INFRA_UNSTAGED" -eq 0 ] || fail "infra modified since latest [supervisor] commit"
ok "anti-cheat checks all pass"

# 5. arm64 CGOs MUST byte-change vs A11 baseline (the regalloc fix produces new bytes)
if [ -f "$A11_BASELINE" ]; then
    ALL_MATCH=true
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        if [ "$expected" = "$actual" ]; then : ; else ALL_MATCH=false; fi
    done < "$A11_BASELINE"
    if [ "$ALL_MATCH" = "true" ]; then
        fail "arm64 CGOs UNCHANGED vs A11 baseline — regalloc fix didn't propagate to bytes"
    fi
    ok "arm64 CGOs byte-changed vs A11 baseline (regalloc fix landed)"
fi

# 6. New A15 arm64 baseline file present
[ -f .autoport/reports/A15-baseline-arm64-cgo-hashes.txt ] || fail "A15-baseline-arm64-cgo-hashes.txt missing"
ok "A15 arm64 CGO baseline saved"

# 7. x86 CGOs byte-identical to A2 baseline
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# 7c. CBZ-fingerprint scan
if [ -f out/jak1-arm64/iso/ENGINE.CGO ]; then
    CBZ_HITS=$(python3 - <<'PY' || true
import struct
data=open('out/jak1-arm64/iso/ENGINE.CGO','rb').read()
hits=sum(1 for i in range(0,len(data)-4,4) if (struct.unpack('<I',data[i:i+4])[0] & 0xFFFFFFE0) == 0xB4000140)
print(hits)
PY
)
    [ "${CBZ_HITS:-0}" -lt 10 ] || fail "CBZ Xt,+40 fingerprint: $CBZ_HITS"
    ok "no CBZ-around-call cheat-fingerprint ($CBZ_HITS)"
fi

# 7d. RELAXED (attempt-2): the previous linear-byte-stream check for "SDIV X8 →
#     BLR X8 within 30 words" produced false positives across basic-block
#     boundaries, which drove claude to add a `function-crossers promotion` that
#     emits broader register-assignment changes — these in turn emit some arm64
#     instruction that is accepted by qemu-aarch64-static but rejected by the
#     real Redmi Note 9 Pro CPU (sig=4 SIGILL at math-camera-h, see
#     SUPERVISOR_JOURNAL.md). The device IS the ground truth, qemu is a proxy.
#     We drop this byte-stream check and rely on the device's D4 validator
#     (check 9) being the real arbiter of whether the fix works.
ok "binary check 7d relaxed (qemu vs device divergence lesson, see journal)"

# 8. qemu repro strict advance past A14 ceiling
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a15-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a15-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    [ "$SUM_COUNT" -ge 166 ] || fail "link-finish count regressed: $SUM_COUNT (A14 reached 166)"
    [ "$SUM_COUNT" -gt 166 ] || fail "link-finish count stuck at 166 — A15's regalloc fix did not advance boot"
    ok "qemu repro link-finish count $SUM_COUNT (>166 — advanced past A14)"
fi

# 9. Fix summary
[ -f .autoport/reports/A15-fix-summary.md ] || fail "A15-fix-summary.md missing"
ok "fix summary present"

# 10. D4 device validator passes
bash .autoport/validators/phase-D4-android-apk-title.sh > /tmp/a15-d4.log 2>&1 \
    || { tail -40 /tmp/a15-d4.log; fail "D4 device validator failed on A15 fix"; }
ok "D4 device validator passes end-to-end"

# 11. Desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE $DIFF_FILE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A15 — regalloc constraint added, boot advances past 166."

#!/usr/bin/env bash
# Phase A18 validator — type-method-zero BLR fix at time-of-day top-level.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A17_CLOSE=$(git log --format=%H --all --grep='autoport/A17-idiv-emitter-spill' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A17_BASELINE=".autoport/reports/A17-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A18 validator (type-method-zero bind) =="

# 1. A18-unlocked targets changed
TOTAL_DIFF=0
for f in android/gk_android_main.cpp game/linux-arm64/linux_arm64_main.cpp \
         game/kernel/common/klink.cpp game/kernel/common/klink.h \
         game/kernel/common/symbol.cpp; do
    [ -f "$f" ] && D=$(git diff "$A17_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l) || D=0
    TOTAL_DIFF=$((TOTAL_DIFF + D))
done
[ "$TOTAL_DIFF" -gt 5 ] || fail "no A18 unlocked file changed since A17 ($TOTAL_DIFF lines)"
ok "A18-unlocked files have $TOTAL_DIFF lines diff from A17"

# 2. NO codegen / asm / kscheme / kmachine / IOP / runtime-compat changes
for f in goalc/emitter/IGenARM64.h goalc/emitter/IGenARM64.cpp \
         goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp \
         goalc/compiler/CodeGenerator.h goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/IR.h goalc/compiler/IR.cpp \
         goalc/regalloc/Allocator_v2.cpp goalc/regalloc/Allocator.cpp \
         goalc/regalloc/allocate_common.cpp \
         game/kernel/asm_funcs_arm64.s game/kernel/common/kscheme.cpp \
         game/kernel/common/kmachine.cpp \
         game/system/IOP_Kernel.cpp game/system/IOP_Kernel.h \
         game/linux-arm64/linux_arm64_runtime_compat.cpp \
         android/android_runtime_compat.cpp; do
    [ -f "$f" ] || continue
    DIFF=$(git diff "$A17_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A17 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "all locked files unchanged since A17"

# 3. Anti-cheat
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced"
ok "no dodge in source"

ANCHOR=${A17_CLOSE:-$A4}
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

# 4. A18-DIAG markers present
DIAG_PRESENT=$(grep -rE 'A18-DIAG|type-method-zero|method-not-implemented' \
    android/gk_android_main.cpp game/linux-arm64/linux_arm64_main.cpp \
    game/kernel/common/klink.cpp 2>/dev/null | wc -l)
[ "$DIAG_PRESENT" -gt 0 ] || fail "no A18-DIAG marker in source"
ok "A18-DIAG markers present"

# 5. Fix summary
[ -f .autoport/reports/A18-fix-summary.md ] || fail "A18-fix-summary.md missing"
ok "fix summary present"

# 6. x86 CGOs byte-identical to A2
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# 7. arm64 CGOs byte-identical to A17 baseline (NO codegen change in A18)
if [ -f "$A17_BASELINE" ]; then
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "arm64 CGO drift vs A17: $path (A18 must not alter CGOs)"
    done < "$A17_BASELINE"
    ok "arm64 CGOs byte-identical to A17 baseline"
fi

# 8. qemu repro strict advance past A17 ceiling
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a18-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a18-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    [ "$SUM_COUNT" -ge 216 ] || fail "link-finish count regressed: $SUM_COUNT (A17 reached 216)"
    [ "$SUM_COUNT" -gt 216 ] || fail "link-finish count stuck at 216 — A18's fix did not advance boot"
    ok "qemu repro link-finish count $SUM_COUNT (>216)"
fi

# 9. Device advance check (relaxed per A17 lesson: link count > 216, eventual crash OK)
if [ -x .autoport/lib/d4_run.sh ]; then
    bash .autoport/lib/d4_run.sh > /tmp/a18-d4-launch.log 2>&1 || true
fi
DEVICE_LINKS=$(grep -c "link finish:" .autoport/reports/D4-boot.log 2>/dev/null || echo 0)
[ "$DEVICE_LINKS" -gt 216 ] || fail "device link-finish count $DEVICE_LINKS not > 216"
ok "device link-finish count $DEVICE_LINKS (>216)"

# 10. Desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE $DIFF_FILE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A18 — type-method-zero bind landed, qemu+device both advance past 216."

#!/usr/bin/env bash
# Phase A16 validator — diagnostic-only phase to capture device CPU divergence.
# Success = diag output captured + analysis written, NOT codegen advance.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A14_CLOSE=$(git log --format=%H --all --grep='autoport/A14-pc-memmove-bind' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A11_BASELINE=".autoport/reports/A11-baseline-arm64-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A16 validator (device CPU divergence diagnostic) =="

# 1. A16-unlocked diag handlers changed
DIAG_DIFF=$(git diff "$A14_CLOSE" HEAD -- game/linux-arm64/linux_arm64_main.cpp android/gk_android_main.cpp 2>/dev/null | wc -l)
[ "$DIAG_DIFF" -gt 5 ] || fail "diag handler files not changed since A14 ($DIAG_DIFF lines)"
ok "diag handler files have $DIAG_DIFF lines diff from A14"

# 2. NO codegen changes (this is diagnostic-only)
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
         android/android_runtime_compat.cpp \
         game/kernel/common/klink.cpp game/kernel/common/klink.h; do
    [ -f "$f" ] || continue
    DIFF=$(git diff "$A14_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed in diagnostic-only phase (lock violation)"
done
ok "no codegen / runtime / klink changes (diagnostic-only)"

# 3. Anti-cheat: no dodges
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced"
ok "no dodge in source"

# 4. No new abort/weak/stubs/inline-stubs/rename-evasion/infra-edits
ANCHOR=${A14_CLOSE:-$A4}
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

# 5. A16-DIAG markers present in source
DIAG_PRESENT=$(grep -rE 'A16-DIAG|adrp-pair|x16-clobber|clobbered-between' \
    game/linux-arm64/linux_arm64_main.cpp android/gk_android_main.cpp 2>/dev/null | wc -l)
[ "$DIAG_PRESENT" -gt 0 ] || fail "no A16-DIAG marker in source"
ok "A16-DIAG diag markers present"

# 6. x86 CGOs byte-identical to A2 baseline
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# 7. arm64 CGOs byte-identical to A11 baseline (NO codegen change in this phase)
if [ -f "$A11_BASELINE" ]; then
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "arm64 CGO drift vs A11: $path (diagnostic phase must not alter CGOs)"
    done < "$A11_BASELINE"
    ok "arm64 CGOs byte-identical to A11 baseline"
fi

# 8. A16 device diag output captured
[ -f .autoport/reports/A16-device-diag-output.txt ] || fail "A16-device-diag-output.txt missing — diag not run on device"
[ -s .autoport/reports/A16-device-diag-output.txt ] || fail "A16-device-diag-output.txt is empty"
# The output should contain at least one A16-DIAG line
grep -q 'A16-DIAG' .autoport/reports/A16-device-diag-output.txt || fail "no A16-DIAG output captured"
ok "device diag output captured ($(wc -l < .autoport/reports/A16-device-diag-output.txt) lines)"

# 9. Fix summary names the clobber site + A17 hypothesis
[ -f .autoport/reports/A16-fix-summary.md ] || fail "A16-fix-summary.md missing"
grep -qiE 'clobber|x16|adrp' .autoport/reports/A16-fix-summary.md || fail "fix-summary doesn't name a clobber site"
ok "fix summary names clobber site"

# 10. Desktop smoke (sanity, should never regress)
SMOKE=$(mktemp); trap "rm -f $SMOKE $DIFF_FILE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A16 — device CPU divergence diagnostic captured, A17 scope informed."

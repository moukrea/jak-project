#!/usr/bin/env bash
# Phase A13 validator — IOP_Kernel mutex pre-init on arm64.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A12_CLOSE=$(git log --format=%H --all --grep='autoport/A12-gsound-stack-fnptr' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A13 validator (IOP_Kernel mutex init) =="

# 1. At least one A13-unlocked target changed
TOTAL_DIFF=0
for f in game/linux-arm64/linux_arm64_runtime_compat.cpp \
         android/android_runtime_compat.cpp \
         game/linux-arm64/linux_arm64_main.cpp \
         android/gk_android_main.cpp \
         game/kernel/common/klink.cpp; do
    [ -f "$f" ] && D=$(git diff "$A12_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l) || D=0
    TOTAL_DIFF=$((TOTAL_DIFF + D))
done
[ "$TOTAL_DIFF" -gt 5 ] || fail "no A13 unlocked file changed since A12 close ($TOTAL_DIFF lines) — no init landed"
ok "A13-unlocked files have $TOTAL_DIFF total lines diff from A12"

# 2. Codegen + asm + kscheme + klink.h + IOP_Kernel locks intact
for f in goalc/emitter/IGenARM64.h goalc/emitter/IGenARM64.cpp \
         goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp \
         goalc/compiler/CodeGenerator.h goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/IR.h goalc/compiler/IR.cpp \
         game/kernel/asm_funcs_arm64.s game/kernel/common/kscheme.cpp \
         game/kernel/common/klink.h \
         game/system/IOP_Kernel.cpp game/system/IOP_Kernel.h; do
    [ -f "$f" ] || continue
    DIFF=$(git diff "$A12_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A12 (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "codegen + asm + kscheme + klink.h + IOP_Kernel locks intact since A12"

# 3. Anti-cheat: no dodges
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced ($DODGES files)"
ok "no dodge in source"

# 4. No new abort/weak/stubs/inline-stubs since A12 close
ANCHOR=${A12_CLOSE:-$A4}
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions since A12 close"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions since A12 close"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp since A12 close"
INLINE_STUBS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' 2>/dev/null | grep -cE '^\+.*\w+_stub\s*\(' || true)
[ "$INLINE_STUBS" -eq 0 ] || fail "inline _stub function additions since A12 close ($INLINE_STUBS)"
# 4b'. Rename-evasion
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
# 4c. Infra lock
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$ANCHOR}
INFRA_DIFF=$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
INFRA_UNSTAGED=$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
[ "$INFRA_DIFF" -eq 0 ] && [ "$INFRA_UNSTAGED" -eq 0 ] || fail "infra modified since latest [supervisor] commit (diff=$INFRA_DIFF, unstaged=$INFRA_UNSTAGED)"
ok "anti-cheat checks all pass"

# 5. pthread_mutex_init call present in the diff (the actual fix)
MUTEX_INIT=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' 2>/dev/null | grep -cE '^\+.*pthread_mutex_init\s*\(' || true)
[ "$MUTEX_INIT" -gt 0 ] || fail "no pthread_mutex_init() call added in the diff — fix not landed"
ok "pthread_mutex_init() call present ($MUTEX_INIT)"

# 6. Fix summary
[ -f .autoport/reports/A13-fix-summary.md ] || fail "A13-fix-summary.md missing"
ok "fix summary present"

# 7. x86 CGOs byte-identical to A2 baseline
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# 7b. arm64 CGOs byte-identical to A11 baseline
A11_ARM64_BASELINE=".autoport/reports/A11-baseline-arm64-cgo-hashes.txt"
A10_ARM64_BASELINE=".autoport/reports/A10-baseline-arm64-cgo-hashes.txt"
ARM_BASELINE=""
[ -f "$A11_ARM64_BASELINE" ] && ARM_BASELINE=$A11_ARM64_BASELINE
[ -z "$ARM_BASELINE" ] && [ -f "$A10_ARM64_BASELINE" ] && ARM_BASELINE=$A10_ARM64_BASELINE
if [ -n "$ARM_BASELINE" ]; then
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "arm64 CGO drift vs $(basename "$ARM_BASELINE"): $path"
    done < "$ARM_BASELINE"
    ok "arm64 CGOs byte-identical to $(basename "$ARM_BASELINE")"
fi

# 7c. CBZ-fingerprint scan
if [ -f out/jak1-arm64/iso/ENGINE.CGO ]; then
    CBZ_HITS=$(python3 - <<'PY' || true
import struct
data=open('out/jak1-arm64/iso/ENGINE.CGO','rb').read()
hits=sum(1 for i in range(0,len(data)-4,4) if (struct.unpack('<I',data[i:i+4])[0] & 0xFFFFFFE0) == 0xB4000140)
print(hits)
PY
)
    [ "${CBZ_HITS:-0}" -lt 10 ] || fail "CBZ Xt,+40 fingerprint: $CBZ_HITS in ENGINE.CGO (>=10)"
    ok "no CBZ-around-call cheat-fingerprint in ENGINE.CGO ($CBZ_HITS)"
fi

# 8. qemu repro progresses past gsound and advances link count
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a13-qemu.log 2>&1 || true
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a13-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    [ "$SUM_COUNT" -ge 156 ] || fail "link-finish count regressed: $SUM_COUNT (A11/A12 reached 156)"
    [ "$SUM_COUNT" -gt 156 ] || fail "link-finish count stuck at 156 — A13's mutex init did not advance boot"
    ok "qemu repro link-finish count $SUM_COUNT (>156 — boot advanced past A12 ceiling)"
fi

# 9. D4 device validator passes
bash .autoport/validators/phase-D4-android-apk-title.sh > /tmp/a13-d4.log 2>&1 \
    || { tail -40 /tmp/a13-d4.log; fail "D4 device validator failed on A13 fix"; }
ok "D4 device validator passes end-to-end"

# 10. Desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE $DIFF_FILE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A13 — IOP_Kernel mutex initialised, boot advances past 156."

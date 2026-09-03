#!/usr/bin/env bash
# Phase A11 validator — texture-CGO sym=0 SIGILL closed via sym-MEM binding.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A10_CLOSE=$(git log --format=%H --all --grep='autoport/A10-callee-save-area' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A11 validator (texture-sym binding) =="

# 1. At least one of the unlocked targets actually changed
TOTAL_DIFF=0
for f in android/gk_android_main.cpp game/linux-arm64/linux_arm64_main.cpp \
         game/kernel/common/klink.cpp game/kernel/common/kmachine.cpp \
         game/kernel/common/symbol.cpp; do
    D=$(git diff "$A10_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l)
    TOTAL_DIFF=$((TOTAL_DIFF + D))
done
[ "$TOTAL_DIFF" -gt 5 ] || fail "no A11 unlocked file changed since A10 close ($TOTAL_DIFF lines) — no diagnostic+fix landed"
ok "A11-unlocked files have $TOTAL_DIFF total lines diff from A10"

# 2. Codegen locks intact (everything closed by prior phases)
for f in goalc/emitter/IGenARM64.h goalc/emitter/IGenARM64.cpp \
         goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp \
         goalc/compiler/CodeGenerator.h goalc/compiler/CodeGenerator.cpp \
         goalc/compiler/IR.h goalc/compiler/IR.cpp; do
    DIFF=$(git diff "$A10_CLOSE" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since A10 (codegen lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "all codegen locks intact since A10"

# 3. Anti-cheat: no dodges
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "dodge re-introduced ($DODGES files)"
ok "no dodge in source"

# 4. No new abort/weak/stubs since A10 close
ANCHOR=${A10_CLOSE:-$A4}
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions since A10 close"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions since A10 close"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp since A10 close"
# 4b. Inline-stub detection (the A11 attempt-2 cheat pattern): function
#     definitions whose name ends in `_stub` and bodies that just `return 0;`.
INLINE_STUBS=$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' 2>/dev/null | grep -cE '^\+.*\w+_stub\s*\(' || true)
[ "$INLINE_STUBS" -eq 0 ] || fail "inline _stub function additions since A10 close ($INLINE_STUBS) — silent-return cheat"
# 4c. Test/validator infrastructure must NOT change during a phase —
#     test infra is supervisor-owned (caught the qemu_repro.sh marker
#     injection cheat). Anchor on the LATEST [autoport/supervisor]
#     commit so the validator does not self-reference its own
#     supervisor-author edits.
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1)
SUP_ANCHOR=${SUP_ANCHOR:-$A10_CLOSE}
INFRA_DIFF=$(git diff "$SUP_ANCHOR" HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
INFRA_UNSTAGED=$(git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' 2>/dev/null | wc -l)
[ "$INFRA_DIFF" -eq 0 ] && [ "$INFRA_UNSTAGED" -eq 0 ] || fail "test infrastructure modified since latest [autoport/supervisor] commit (diff=$INFRA_DIFF, unstaged=$INFRA_UNSTAGED) — phase must not edit .autoport/lib/* or validators/*"
# 4d. FFI trampoline lock — asm_funcs_arm64.s is owned by codegen phases
#     (A6 unlocked it). Runtime phases (A11+) must not touch it.
ASM_TRAMPOLINE_DIFF=$(git diff "$ANCHOR" HEAD -- game/kernel/asm_funcs_arm64.s 2>/dev/null | wc -l)
[ "$ASM_TRAMPOLINE_DIFF" -eq 0 ] || fail "asm_funcs_arm64.s changed since A10 close ($ASM_TRAMPOLINE_DIFF lines) — codegen file, locked in A11"
ok "no abort/weak/stubs/inline-stubs/infra-edit/asm-trampoline since A10 close"

# 5. Diagnostic-print evidence in source (the sym-name discovery step)
DIAG_PRESENT=$(grep -rE 'texture-sym-zero|sym-mem-zero|A11-DIAG|sym-bind-trace' \
    android/gk_android_main.cpp game/linux-arm64/linux_arm64_main.cpp \
    game/kernel/common/klink.cpp game/kernel/common/kmachine.cpp \
    game/kernel/common/symbol.cpp 2>/dev/null | wc -l)
[ "$DIAG_PRESENT" -gt 0 ] || fail "no A11 diagnostic print in unlocked files — bug evidence not captured"
ok "diagnostic print present"

# 6. Fix summary
[ -f .autoport/reports/A11-fix-summary.md ] || fail "A11-fix-summary.md missing"
ok "fix summary present"

# 7. x86 CGOs byte-identical to A2 baseline
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# 7b. arm64 CGOs byte-identical to A10 baseline (A11 unlocks NO compiler code,
#     so a CGO byte change implies an unauthorized goalc edit — incl. the
#     CBZ-around-call cheat reverted at 13c9ee334).
A10_ARM64_BASELINE=".autoport/reports/A10-baseline-arm64-cgo-hashes.txt"
if [ -f "$A10_ARM64_BASELINE" ]; then
    while read -r expected path; do
        [ -z "$expected" ] && continue
        actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
        [ "$expected" = "$actual" ] || fail "arm64 CGO drift vs A10 baseline: $path (compiler likely modified)"
    done < "$A10_ARM64_BASELINE"
    ok "arm64 CGOs byte-identical to A10 baseline (no unauthorized goalc edit)"
fi

# 7c. Binary-level cheat-pattern scan: CBZ Xt, +40 (encoded 0xB400014X) appearing
#     immediately before a call_r64 sequence is the fingerprint of the
#     IR_FunctionCall null-ptr-guard cheat (commit 3c2d0ad8, reverted at 13c9ee334).
#     Honest arm64 ENGINE.CGO has 0 such patterns.
if [ -f out/jak1-arm64/iso/ENGINE.CGO ]; then
    CBZ_HITS=$(python3 - <<'PY' || true
import struct,sys
data=open('out/jak1-arm64/iso/ENGINE.CGO','rb').read()
hits=0
for i in range(0,len(data)-4,4):
    w=struct.unpack('<I',data[i:i+4])[0]
    # CBZ Xt, +40  →  base 0xB4000000 | (10 << 5) | rt[0..30]
    if (w & 0xFFFFFFE0) == 0xB4000140:
        hits+=1
print(hits)
PY
)
    [ "${CBZ_HITS:-0}" -lt 10 ] || fail "binary cheat-fingerprint: $CBZ_HITS CBZ Xt,+40 in ENGINE.CGO (>=10) — null-ptr-guard cheat returned"
    ok "no CBZ-around-call cheat-fingerprint in ENGINE.CGO ($CBZ_HITS, <10)"
fi

# 8. qemu repro progresses past texture
if [ -x .autoport/lib/qemu_repro.sh ]; then
    bash .autoport/lib/qemu_repro.sh > /tmp/a11-qemu.log 2>&1 || true
    # 8a. Count regression check — link-finish total must NOT drop vs A10 (104).
    LF_COUNT=$(grep -cE "^link finish:|^[[:space:]]+link finish:" /tmp/a11-qemu.log || true)
    # Alternative source: the qemu_repro.sh summary line "N 'link finish:' lines captured"
    SUM_COUNT=$(grep -oE "([0-9]+) 'link finish:' lines captured" /tmp/a11-qemu.log | head -1 | grep -oE "^[0-9]+" || echo 0)
    EFF_COUNT=$LF_COUNT; [ "$SUM_COUNT" -gt "$EFF_COUNT" ] && EFF_COUNT=$SUM_COUNT
    [ "$EFF_COUNT" -ge 100 ] || fail "link-finish count regressed: $EFF_COUNT (A10 reached 104) — fix broke prior progress"
    ok "qemu repro link-finish count $EFF_COUNT (≥100 — no regression vs A10)"
    # 8b. Progression-past-texture marker.
    grep -qE "link finish: (logo|level-info|main-h|loader|kernel-h|game-info)|engine: state=" /tmp/a11-qemu.log \
        || { tail -30 /tmp/a11-qemu.log; fail "qemu repro shows no post-A11 progression past texture"; }
    ok "qemu repro progresses past texture"
fi

# 9. D4 device validator passes
bash .autoport/validators/phase-D4-android-apk-title.sh > /tmp/a11-d4.log 2>&1 \
    || { tail -40 /tmp/a11-d4.log; fail "D4 device validator failed on A11 fix"; }
ok "D4 device validator passes end-to-end"

# 10. Desktop smoke
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A11 — texture sym-MEM binding closed, boot progresses past"
echo "      texture, D4 device validator passes end-to-end."

#!/usr/bin/env bash
# Phase A6 validator — off-register fix lands; skip-flag dodge REMOVED entirely;
# real GOAL dispatcher runs on device. The deferred bug from A5's shim-audit.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A5_COMMIT=$(git log --format=%H --all --grep='autoport/A5-emitter-far-relocs' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"
A6_BASELINE=".autoport/reports/A6-baseline-arm64-cgo-hashes.txt"
NOP_REPORT=".autoport/reports/A6-nop-report.txt"
LIBGK="build-android/lib/arm64-v8a/libgk.so"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A6 validator (off-register fix + skip-flag REMOVED) =="

# ---- 1. Codegen unlock narrow: only IGenARM64.cpp may differ from A5,
#         everything else locked ----
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.h \
         goalc/compiler/CodeGenerator.cpp goalc/compiler/CodeGenerator.h; do
    [ "$(git diff "$A4" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] || fail "$f drifted since A4"
done
[ "$(git diff "$A5_COMMIT" HEAD -- goalc/emitter/ObjectGenerator.cpp 2>/dev/null | wc -l)" -eq 0 ] \
    || fail "goalc/emitter/ObjectGenerator.cpp drifted since A5 (A6 unlock is IGenARM64.cpp only)"
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier drifted"
ok "locks intact (IGenARM64.cpp is the only goalc/ file allowed to move)"

# ---- 2. IGenARM64.cpp actually changed (otherwise no fix landed) ----
IGEN_DIFF=$(git diff "$A5_COMMIT" HEAD -- goalc/emitter/IGenARM64.cpp 2>/dev/null | wc -l)
[ "$IGEN_DIFF" -gt 20 ] || fail "goalc/emitter/IGenARM64.cpp barely changed ($IGEN_DIFF lines) — fix not landed"
ok "IGenARM64.cpp has $IGEN_DIFF lines diff from A5"

# ---- 3. Skip-flag dodge completely removed from source ----
GREP_HITS=$(grep -rn 'g_android_skip_goal_call\|skip-flag armed' android/ game/ 2>/dev/null | wc -l)
if [ "$GREP_HITS" -gt 0 ]; then
    grep -rn 'g_android_skip_goal_call\|skip-flag armed' android/ game/ 2>/dev/null | head -10 >&2
    fail "skip-flag dodge still present in source ($GREP_HITS references) — A6 must REMOVE the dodge entirely"
fi
ok "skip-flag dodge completely removed from source tree"

# ---- 4. Skip-flag symbol not in libgk.so ----
[ -f "$LIBGK" ] || fail "$LIBGK missing (build must complete first)"
NM_DUMP=$(mktemp); trap "rm -f $NM_DUMP" EXIT
nm --defined-only "$LIBGK" >"$NM_DUMP" 2>/dev/null || true
nm --undefined-only "$LIBGK" >>"$NM_DUMP" 2>/dev/null || true
if grep -q "skip_goal_call" "$NM_DUMP"; then
    grep "skip_goal_call" "$NM_DUMP" >&2
    fail "g_android_skip_goal_call symbol still in libgk.so — header decl or extern still references it"
fi
ok "skip-flag symbol not present in libgk.so"

# ---- 5. NOP count stays at 0 (A5 invariant continues) ----
[ -f "$NOP_REPORT" ] || fail "$NOP_REPORT missing — A6 must re-run the patcher and produce a fresh NOP count"
NOPS=$(awk '/^TOTAL_NOPS:/ {print $2}' "$NOP_REPORT")
[ "$NOPS" = "0" ] || fail "NOPs = $NOPS (must remain 0; A5 invariant)"
ok "0 NOPs in A6 patcher report (A5 invariant preserved)"

# ---- 6. arm64 CGOs regenerated; new baseline saved ----
[ -f "$A6_BASELINE" ] || fail "$A6_BASELINE missing (A6 must save the regenerated CGO hashes)"
ok "A6 arm64 CGO baseline file present"

# ---- 7. x86 CGOs byte-identical to A2 baseline ----
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# ---- 8. D4 validator re-passes WITH dispatcher actually running ----
D4_VALIDATOR=".autoport/validators/phase-D4-android-apk-title.sh"
echo "  re-running D4 validator on A6 bytecode..."
"$D4_VALIDATOR" > /tmp/a6-d4.log 2>&1 \
    || { tail -50 /tmp/a6-d4.log; fail "D4 validator failed on A6-regenerated CGOs"; }
ok "D4 still passes on A6 bytecode"

# ---- 9. The boot log shows the dispatcher actually executing ----
BOOT_LOG=".autoport/reports/D4-boot.log"
if grep -q "skip-flag armed" "$BOOT_LOG"; then
    fail "boot log still contains 'skip-flag armed' marker — dodge still runtime-active"
fi
DISPATCHER_HITS=$(grep -cE "KernelCheckAndDispatch|jak1::KernelCheckAndDispatch|kernel-dispatcher" "$BOOT_LOG" || true)
[ "$DISPATCHER_HITS" -ge 1 ] || fail "no jak1::KernelCheckAndDispatch markers in boot log — dispatcher not invoked"
ok "dispatcher runs ($DISPATCHER_HITS markers in boot log; skip-flag marker absent)"

# ---- 10. No new abort/weak/stubs since A5 ----
ANCHOR=$A5_COMMIT
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions since A5"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions since A5"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new stubs since A5"
ok "no new abort/weak/stubs since A5"

# ---- 11. Desktop x86 smoke ----
SMOKE=$(mktemp); trap "rm -f $SMOKE $NM_DUMP" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A6 — off-register bug fixed, skip-flag dodge removed"
echo "      entirely, real GOAL dispatcher runs on device, A5's 0-NOP"
echo "      invariant preserved."

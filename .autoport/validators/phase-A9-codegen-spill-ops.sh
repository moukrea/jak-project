#!/usr/bin/env bash
# Phase A9 validator — real spill ops in CodeGenerator::do_goal_function_arm64.
# Authored by supervisor 2026-05-23 after A8 delivered the diagnosis.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A8_CLOSE=$(git log --format=%H --all --grep='autoport/A8-qemu-repro-and-displaygc-fix' | head -1)
A2_BASELINE=".autoport/reports/A2-baseline-x86-cgo-hashes.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A9 validator (codegen spill ops) =="

# ---- 1. CodeGenerator.cpp actually changed (the whole point) ----
CG_DIFF=$(git diff "$A4" HEAD -- goalc/compiler/CodeGenerator.cpp 2>/dev/null | wc -l)
[ "$CG_DIFF" -gt 20 ] || fail "goalc/compiler/CodeGenerator.cpp barely changed ($CG_DIFF lines from A4) — spill ops not implemented"
ok "CodeGenerator.cpp has $CG_DIFF lines diff from A4 (spill ops implementation)"

# ---- 2. Other locked codegen files untouched ----
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h goalc/emitter/IGenARM64.cpp \
         goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp \
         goalc/compiler/CodeGenerator.h; do
    BASE=$A4
    # IGenARM64.cpp was unlocked in A5/A6/A8 — anchor is A8-close for it
    if [ "$f" = "goalc/emitter/IGenARM64.cpp" ] && [ -n "$A8_CLOSE" ]; then
        BASE=$A8_CLOSE
    fi
    if [ "$f" = "goalc/emitter/ObjectGenerator.cpp" ] && [ -n "$A8_CLOSE" ]; then
        BASE=$A8_CLOSE
    fi
    DIFF=$(git diff "$BASE" HEAD -- "$f" 2>/dev/null | wc -l)
    [ "$DIFF" -eq 0 ] || fail "$f changed since anchor (lock violation)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] || fail "classifier modified since A1"
ok "non-A9-unlocked codegen + classifier locks intact"

# ---- 3. Spill emit patterns present (LDR/STR + SP-relative) ----
grep -qE "0x[Ff]9[0-9A-Fa-f]{6}|str.*sp|ldr.*sp|SP, #" goalc/compiler/CodeGenerator.cpp \
    || fail "goalc/compiler/CodeGenerator.cpp has no SP-relative LDR/STR pattern (spill ops not landed)"
ok "spill ops present in CodeGenerator.cpp"

# ---- 4. arm64 CGOs regenerated; new baseline saved ----
[ -f .autoport/reports/A9-baseline-arm64-cgo-hashes.txt ] || fail "A9-baseline-arm64-cgo-hashes.txt missing"
ok "A9 arm64 CGO baseline saved"

# ---- 5. Fix summary report ----
[ -f .autoport/reports/A9-fix-summary.md ] || fail ".autoport/reports/A9-fix-summary.md missing"
ok "fix summary report present"

# ---- 6. Anti-cheat: no dodges ----
DODGES=$(grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/ 2>/dev/null | wc -l)
[ "$DODGES" -eq 0 ] || fail "fault-recovery dodge re-introduced ($DODGES files)"
ok "no fault-recovery dodge in source"

# ---- 7. No new abort/weak/stubs since A8 close ----
ANCHOR=${A8_CLOSE:-$A4}
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)" -eq 0 ] || fail "abort additions since A8 close"
[ "$(git diff "$ANCHOR" HEAD -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)" -eq 0 ] || fail "weak additions since A8 close"
[ -z "$(git diff --name-only --diff-filter=A "$ANCHOR" HEAD 2>/dev/null | grep -E '_stubs\.cpp$' || true)" ] || fail "new *_stubs.cpp since A8 close"
ok "no new abort/weak/stubs since A8 close"

# ---- 8. x86 CGOs preserved ----
while read -r expected path; do
    [ -z "$expected" ] && continue
    [[ "$path" == out/* ]] || path="out/jak1/iso/$path"
    actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
    [ "$expected" = "$actual" ] || fail "x86 CGO drift: $path"
done < "$A2_BASELINE"
ok "x86 CGOs byte-identical to A2 baseline"

# ---- 9. qemu repro must show post-fix progress ----
if [ -x .autoport/lib/qemu_repro.sh ]; then
    echo "  running qemu_repro.sh to verify post-fix progress..."
    bash .autoport/lib/qemu_repro.sh > /tmp/a9-qemu.log 2>&1 || true
    grep -qE "FIRST POST-FIX CGO LINKED|link finish:.*(connect|engine|game-info)" /tmp/a9-qemu.log \
        || { tail -30 /tmp/a9-qemu.log; fail "qemu repro shows no post-fix progress past display.gc"; }
    ok "qemu repro shows boot progressing past display.gc"
fi

# ---- 10. D4 device validator passes ----
echo "  re-running D4 device validator on A9 fix..."
bash .autoport/validators/phase-D4-android-apk-title.sh > /tmp/a9-d4.log 2>&1 \
    || { tail -40 /tmp/a9-d4.log; fail "D4 device validator failed on A9 fix"; }
ok "D4 device validator passes end-to-end with hardened SDL/GL marker check"

# ---- 11. Desktop x86 smoke ----
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A9 — real spill ops in CodeGenerator::do_goal_function_arm64,"
echo "      qemu repro past display.gc, D4 device validator end-to-end clean."

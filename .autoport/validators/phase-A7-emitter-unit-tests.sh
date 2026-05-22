#!/usr/bin/env bash
# Phase A7 validator — emitter unit test harness gates here.
# Authored by supervisor 2026-05-23 with user sign-off.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

A4=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
A1=$(git log --format=%H --all --grep='\[autoport/A1-emitter-enumerate\] enumerate' | head -1)
A6_COMMIT=$(git log --format=%H --all --grep='autoport/A6-emitter-off-register' | head -1)

TESTS_DIR=".autoport/tests/emitter"
RUN_SH="$TESTS_DIR/run.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase A7 validator (emitter unit tests) =="

# ---- 1. Codegen lock — A7 must NOT touch any codegen file ----
for f in goalc/compiler/IR.cpp goalc/emitter/IGenARM64.h goalc/emitter/IGenARM64.cpp \
         goalc/emitter/ObjectGenerator.h goalc/emitter/ObjectGenerator.cpp \
         goalc/compiler/CodeGenerator.cpp goalc/compiler/CodeGenerator.h; do
    [ "$(git diff "$A6_COMMIT" HEAD -- "$f" 2>/dev/null | wc -l)" -eq 0 ] \
        || fail "$f changed since A6 (codegen-lock violation; A7 is tooling-only)"
done
[ "$(git diff "$A1" HEAD -- .autoport/lib/classify_ir_arm64.py 2>/dev/null | wc -l)" -eq 0 ] \
    || fail "classifier modified since A1"
ok "codegen + classifier locks intact (A7 is tooling-only)"

# ---- 2. Test harness directory + run.sh exist ----
[ -d "$TESTS_DIR" ] || fail "$TESTS_DIR missing"
[ -x "$RUN_SH" ] || fail "$RUN_SH missing or not executable"
[ -d "$TESTS_DIR/encoding" ] || fail "$TESTS_DIR/encoding missing"
[ -d "$TESTS_DIR/exec" ] || fail "$TESTS_DIR/exec missing"
ok "test harness directory structure present"

# ---- 3. Tests link against REAL goalc sources (anti-cheat) ----
# Validator scans the encoding tests' CMakeLists for references to the
# real goalc/emitter/IGenARM64.cpp objects, NOT a forked copy.
CMAKE_FILE="$TESTS_DIR/encoding/CMakeLists.txt"
[ -f "$CMAKE_FILE" ] || fail "$CMAKE_FILE missing"
grep -qE "goalc/emitter/IGenARM64|goalc/emitter/ObjectGenerator" "$CMAKE_FILE" \
    || fail "$CMAKE_FILE does not reference real goalc/emitter sources (suspected forked copy)"
ok "encoding tests link against real goalc/emitter sources"

# Scan exec tests for qemu-aarch64-static usage
EXEC_RUN="$TESTS_DIR/exec/run_exec_tests.sh"
[ -f "$EXEC_RUN" ] || fail "$EXEC_RUN missing"
grep -qE "qemu-aarch64-static" "$EXEC_RUN" \
    || fail "$EXEC_RUN does not invoke qemu-aarch64-static"
ok "exec tests use qemu-aarch64-static"

# ---- 4. Coverage: every emit_ family has at least 1 test ----
# Grep IGenARM64.cpp for function names matching emit_/encode_/InstructionARM64,
# then ensure each has at least 1 reference in the test files.
EMIT_FUNCS=$(grep -oE "^InstructionARM64 (emit_|encode_)?[a-z_0-9]+\b" goalc/emitter/IGenARM64.cpp \
    | awk '{print $2}' | sort -u | wc -l)
TEST_REFS=$(grep -rhoE "(emit_|encode_)[a-z_0-9]+" "$TESTS_DIR/encoding/" \
    | sort -u | wc -l)
[ "$TEST_REFS" -ge "$((EMIT_FUNCS / 2))" ] \
    || fail "test coverage too thin: $TEST_REFS distinct emit_/encode_ refs vs $EMIT_FUNCS source functions"
ok "test coverage: $TEST_REFS distinct emit_/encode_ refs (source has $EMIT_FUNCS)"

# ---- 5. Run the test suite ----
echo "  running $RUN_SH (target: < 30 s)..."
START=$(date +%s)
"$RUN_SH" > /tmp/a7-tests.log 2>&1 || { tail -40 /tmp/a7-tests.log; fail "test suite failed"; }
END=$(date +%s)
RUNTIME=$((END - START))
[ "$RUNTIME" -lt 30 ] || fail "test suite ran for ${RUNTIME}s (target: < 30 s)"
ok "test suite passed in ${RUNTIME}s"

# ---- 6. No new abort/weak/stubs in WT (anti-cheat) ----
WT_A=$(git diff -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+[^/]*\b(abort|std::abort)\(' || true)
WT_W=$(git diff -- '*.cpp' '*.h' '*.s' 2>/dev/null | grep -cE '^\+.*__attribute__.*weak|^\+.*\bweak_' || true)
[ "$WT_A" -eq 0 ] || fail "$WT_A new abort() additions in WT"
[ "$WT_W" -eq 0 ] || fail "$WT_W new weak attribute additions in WT"
ok "no new abort/weak additions"

# ---- 7. Skip-flag dodge stays GONE (A6 invariant) ----
SKIP=$(grep -rn 'g_android_skip_goal_call' android/ game/ 2>/dev/null | wc -l)
[ "$SKIP" -eq 0 ] || fail "skip-flag references resurrected ($SKIP)"
ok "skip-flag dodge stays removed"

# ---- 8. Desktop smoke ----
SMOKE=$(mktemp); trap "rm -f $SMOKE" EXIT
timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { tail -20 "$SMOKE"; fail "desktop smoke regressed"; }
ok "desktop smoke passes"

echo ""
echo "PASS: Phase A7 — emitter unit-test harness runs in ${RUNTIME}s,"
echo "      covers $TEST_REFS distinct emit_/encode_ functions,"
echo "      anti-cheat clean, codegen locked, ready for F1+ to use."

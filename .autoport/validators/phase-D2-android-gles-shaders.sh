#!/usr/bin/env bash
# Phase D2 validator — Real GLES shader port. Authored by the
# orchestrator session 2026-05-21 (no supervisor available in headless
# mode; see SUPERVISOR_JOURNAL.md for the rationale and supervisor-
# equivalent commit).
#
# Enforces (in roughly increasing strictness):
#   1.  Required files present: rewritten preprocess.py, the
#       strict_fixer helper, the D2-shaders.md report.
#   2.  Shader source directory has the expected pair count
#       (>=45 pairs, the canonical jak1 set).
#   3.  preprocess.py is the new thin form (no phase-21 int→float
#       regex). Anti-cheat grep.
#   4.  preprocess.py runs and emits the expected blob header +
#       N android.vert / N android.frag files (N == pair count).
#   5.  Every preprocessed shader compiles under glslc
#       --target-env=opengl --target-spv=spv1.0. No exceptions.
#   6.  Every output file is at least 80 bytes (anti-stub floor — a
#       shader file shorter than the GLES 3.20 boilerplate header
#       can't be honest).
#   7.  Blob header kShaderCount == discovered pair count.
#   8.  No solid-color cheat .frag files (anti-phase-29 pattern).
#   9.  No __attribute__((weak)) / kStateSeq introduced since A4 in
#       any tracked source.
#  10.  Codegen + classifier files byte-identical to A4.
#  11.  C4 + D1 validators still pass.
#  12.  Desktop gk smoke test still reaches `link finish: logo`.
#  13.  D2-shaders.md headline mentions "GLES 3.20" + "compile".

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

# ---- Paths ----
SHADERS_SRC_DIR="game/graphics/opengl_renderer/shaders"
PREPROCESS_PY="${SHADERS_SRC_DIR}/preprocess.py"
FIXER_PY=".autoport/lib/d2_shader_strict_fixer.py"
REPORT_MD=".autoport/reports/D2-shaders.md"
GLSLC_DEFAULT="${ANDROID_NDK_HOME:-/home/emeric/Android/android-ndk-r27c}/shader-tools/linux-x86_64/glslc"
GLSLC="${GLSLC:-$GLSLC_DEFAULT}"
GK_DESKTOP="build-x86/game/gk"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "== Phase D2 validator =="

# ---- 1. Required files ----
[ -f "$PREPROCESS_PY" ]        || fail "$PREPROCESS_PY missing — D2 deliverable"
[ -f "$FIXER_PY" ]             || fail "$FIXER_PY missing — D2 deliverable"
[ -f "$REPORT_MD" ]            || fail "$REPORT_MD missing — D2 deliverable"
[ -x "$GLSLC" ] || fail "glslc not found at $GLSLC (NDK shader-tools)"
ok "required files present"

# ---- 2. Shader source directory has the expected pair count ----
VERT_COUNT=$(ls "$SHADERS_SRC_DIR"/*.vert 2>/dev/null | wc -l)
FRAG_COUNT=$(ls "$SHADERS_SRC_DIR"/*.frag 2>/dev/null | wc -l)
[ "$VERT_COUNT" -ge 45 ] \
    || fail "only $VERT_COUNT .vert files; expected >=45 jak1 shaders"
[ "$FRAG_COUNT" -ge 45 ] \
    || fail "only $FRAG_COUNT .frag files; expected >=45 jak1 shaders"
# Pair count: shaders with BOTH .vert and .frag.
PAIRS=0
while IFS= read -r v; do
    name=$(basename "$v" .vert)
    [ -f "$SHADERS_SRC_DIR/$name.frag" ] && PAIRS=$((PAIRS + 1))
done < <(ls "$SHADERS_SRC_DIR"/*.vert)
[ "$PAIRS" -ge 45 ] \
    || fail "only $PAIRS shader pairs (.vert + .frag); expected >=45"
ok "shader directory: $PAIRS pairs ($VERT_COUNT vert + $FRAG_COUNT frag)"

# ---- 3. preprocess.py is the new thin form (no phase-21 cheat regex) ----
# Phase 21's brittle int→float regex appended `.0` or `u` to bare
# integer literals via patterns like:
#     re.sub(r"(\*=?|/=?|\+=|-=)(\s*)(\d+)...", r"\1\2\3.0", src)
# We reject any of these patterns. The legitimate D2 preprocess.py
# does no literal promotion at all.
if grep -nE 'r"\\?\(?[*/+-]\\?=\?[)?\][^"]*\\d\+[^"]*\.0' "$PREPROCESS_PY" >/dev/null \
   || grep -nE 'r"\([<>]=?\\?[^"]*\\d\+[^"]*\.0' "$PREPROCESS_PY" >/dev/null \
   || grep -nE 'r"\\?\([0-9][^"]*\\d\+\\?\\?\)[^"]*\.0' "$PREPROCESS_PY" >/dev/null \
   ; then
    echo "preprocess.py contains a phase-21-style int→float regex:" >&2
    grep -nE 'r"[^"]*\\d\+[^"]*\.0|r"[^"]*\\d\+[^"]*u' "$PREPROCESS_PY" >&2
    fail "preprocess.py must not contain literal-promotion regexes (phase 21 cheat)"
fi
# Be doubly explicit: forbid the exact phase-21 source lines if they
# ever return verbatim.
if grep -qE 'phase 29.*autoport.*promote bare integer literals' "$PREPROCESS_PY"; then
    fail "preprocess.py still has the phase 29 comment for int-to-float promotion"
fi
ok "preprocess.py is the thin form (no phase-21 literal-promotion regex)"

# ---- 4. preprocess.py runs and emits the expected outputs ----
PP_OUT=$(mktemp -d --suffix=-d2-pp)
trap "rm -rf $PP_OUT /tmp/d2-validator-*.log" EXIT
python3 "$PREPROCESS_PY" "$SHADERS_SRC_DIR" "$PP_OUT" > /tmp/d2-validator-pp.log 2>&1 \
    || { tail -20 /tmp/d2-validator-pp.log; fail "preprocess.py failed"; }
GENERATED_VERT=$(ls "$PP_OUT"/*.android.vert 2>/dev/null | wc -l)
GENERATED_FRAG=$(ls "$PP_OUT"/*.android.frag 2>/dev/null | wc -l)
[ "$GENERATED_VERT" -eq "$PAIRS" ] \
    || fail "preprocess.py emitted $GENERATED_VERT android.vert files; expected $PAIRS"
[ "$GENERATED_FRAG" -eq "$PAIRS" ] \
    || fail "preprocess.py emitted $GENERATED_FRAG android.frag files; expected $PAIRS"
[ -f "$PP_OUT/shaders_android_blob.h" ] \
    || fail "preprocess.py did not emit shaders_android_blob.h"
ok "preprocess.py emitted $PAIRS pairs + blob header"

# ---- 5. Every preprocessed shader compiles under glslc ----
COMPILE_FAILURES=0
COMPILE_FAILS_FILE=$(mktemp --suffix=-d2-compile-fails)
trap "rm -rf $PP_OUT /tmp/d2-validator-*.log $COMPILE_FAILS_FILE" EXIT
for v in "$PP_OUT"/*.android.vert; do
    name=$(basename "$v" .android.vert)
    if ! "$GLSLC" -fauto-map-locations -fauto-bind-uniforms \
                  -fshader-stage=vert --target-env=opengl --target-spv=spv1.0 \
                  -o /dev/null "$v" 2>>"$COMPILE_FAILS_FILE"; then
        COMPILE_FAILURES=$((COMPILE_FAILURES + 1))
        echo "FAIL: $name.vert" >> "$COMPILE_FAILS_FILE"
    fi
done
for f in "$PP_OUT"/*.android.frag; do
    name=$(basename "$f" .android.frag)
    if ! "$GLSLC" -fauto-map-locations -fauto-bind-uniforms \
                  -fshader-stage=frag --target-env=opengl --target-spv=spv1.0 \
                  -o /dev/null "$f" 2>>"$COMPILE_FAILS_FILE"; then
        COMPILE_FAILURES=$((COMPILE_FAILURES + 1))
        echo "FAIL: $name.frag" >> "$COMPILE_FAILS_FILE"
    fi
done
if [ "$COMPILE_FAILURES" -gt 0 ]; then
    echo "" >&2
    echo "glslc rejected $COMPILE_FAILURES shaders (tail of error output):" >&2
    tail -40 "$COMPILE_FAILS_FILE" >&2
    fail "$COMPILE_FAILURES preprocessed shaders did not compile under GLES 3.20"
fi
ok "all $((PAIRS * 2)) preprocessed shader units compile under glslc --target-env=opengl"

# ---- 6. No stub shaders (anti-empty-file cheat) ----
SHORT_SHADERS=$(find "$PP_OUT" -name "*.android.vert" -size -80c -o -name "*.android.frag" -size -80c)
if [ -n "$SHORT_SHADERS" ]; then
    echo "Shaders shorter than 80 bytes (suspicious; below GLES boilerplate floor):" >&2
    echo "$SHORT_SHADERS" >&2
    fail "anti-stub floor violation: at least one preprocessed shader is <80 bytes"
fi
ok "no preprocessed shader below 80-byte anti-stub floor"

# ---- 7. Blob header kShaderCount matches discovered pair count ----
# The blob header defines `kShaderCount = sizeof(kShaders) / ...`. We
# can't evaluate sizeof from bash, but we can count the entries in the
# kShaders array — each entry starts with a `    {` line followed by
# `        "name",`. Counting the name lines is robust against the
# auto-generated formatting.
BLOB_COUNT=$(grep -cE '^        "[A-Za-z][A-Za-z0-9_]*",$' "$PP_OUT/shaders_android_blob.h")
[ "$BLOB_COUNT" -eq "$PAIRS" ] \
    || fail "shaders_android_blob.h has $BLOB_COUNT entries; expected $PAIRS"
ok "shaders_android_blob.h has $BLOB_COUNT entries (matches pair count)"

# ---- 8. No solid-color cheat shaders introduced since A4 ----
# A solid-color cheat is a fragment shader that ignores its inputs and
# emits one constant rgba. The phase-29 cheat shipped such shaders
# wholesale; pre-existing upstream debug shaders (e.g.
# glow_probe_read_debug.frag, which outputs vec4(0,0.5,1,1) by design)
# are legitimate and untouched since A4. We only flag NEW or
# RECENTLY-EDITED shaders that look like solid-color stand-ins.
A4_COMMIT_SHADERS=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
SOLID_CHEATS=0
for f in "$SHADERS_SRC_DIR"/*.frag; do
    SZ=$(stat -c %s "$f")
    if [ "$SZ" -ge 200 ]; then continue; fi
    if ! grep -qE '(gl_FragColor|color|out_color|frag_out|fragment_color)\s*=\s*vec4\s*\(\s*[0-9.f-]+\s*,\s*[0-9.f-]+\s*,\s*[0-9.f-]+\s*,\s*[0-9.f-]+\s*\)\s*;' "$f"; then
        continue
    fi
    if grep -qE '(\bin\s+(vec|float|int|uint|sampler)|texture\s*\(|texelFetch)' "$f"; then
        continue
    fi
    # Solid-color shape — check whether the file changed since A4. If
    # not, it's a pre-existing upstream debug shader, not a D2 cheat.
    if [ -n "$A4_COMMIT_SHADERS" ]; then
        DIFF_LINES=$(git diff "$A4_COMMIT_SHADERS" -- "$f" 2>/dev/null | wc -l)
        if [ "$DIFF_LINES" -eq 0 ]; then
            continue
        fi
    fi
    echo "Suspected solid-color cheat (introduced/modified since A4): $f" >&2
    SOLID_CHEATS=$((SOLID_CHEATS + 1))
done
[ "$SOLID_CHEATS" -eq 0 ] \
    || fail "$SOLID_CHEATS suspected solid-color cheat fragment shader(s)"
ok "no solid-color cheat fragment shaders introduced since A4"

# ---- 9. No synthetic-state patterns introduced since A4 ----
A4_COMMIT=$(git log --format=%H --all --grep="autoport/A4-linker-fixups" | head -1)
[ -n "$A4_COMMIT" ] || fail "could not locate A4 commit"
FORBIDDEN_PATTERNS='kStateSeq|kSyntheticBootSequence|weak_jak1_|synthetic.{0,3}gradient|engine: state=(boot|load|title)|placeholder render|kSolidColorOnly'
if git diff "$A4_COMMIT" -- ':(exclude).autoport/' ':(exclude)build*' \
   | grep -E "^\+.*($FORBIDDEN_PATTERNS)" >/dev/null; then
    echo "Forbidden synthetic-state patterns introduced since A4:" >&2
    git diff "$A4_COMMIT" -- ':(exclude).autoport/' ':(exclude)build*' \
        | grep -nE "^\+.*($FORBIDDEN_PATTERNS)" | head -10 >&2
    fail "synthetic-state cheat detected since A4"
fi
ok "no synthetic-state patterns introduced since A4"

# ---- 10. Codegen + classifier files byte-identical to A4 ----
for f in goalc/compiler/IR.cpp \
         goalc/emitter/IGenARM64.cpp \
         goalc/emitter/IGenARM64.h \
         goalc/emitter/ObjectGenerator.cpp \
         goalc/emitter/ObjectGenerator.h \
         goalc/emitter/CodeGenerator.cpp \
         goalc/emitter/CodeGenerator.h \
         .autoport/lib/classify_ir_arm64.py; do
    if [ -f "$f" ]; then
        DIFF_LINES=$(git diff "$A4_COMMIT" -- "$f" 2>/dev/null | wc -l)
        [ "$DIFF_LINES" -eq 0 ] \
            || fail "$f changed since A4 (D2 must not touch codegen/classifier)"
    fi
done
ok "codegen + classifier files byte-identical to A4"

# ---- 11. C4 + D1 validators still pass ----
C4_VALIDATOR=".autoport/validators/phase-C4-klink-arm64-execute.sh"
D1_VALIDATOR=".autoport/validators/phase-D1-android-bionic-shims.sh"
if [ -x "$C4_VALIDATOR" ]; then
    echo "  re-running C4 validator..."
    "$C4_VALIDATOR" > /tmp/d2-validator-c4.log 2>&1 \
        || { tail -25 /tmp/d2-validator-c4.log >&2; fail "C4 validator regressed"; }
    ok "C4 validator still passes"
fi
if [ -x "$D1_VALIDATOR" ]; then
    echo "  re-running D1 validator (this rebuilds android-arm64 gk; ~2-3 min)..."
    "$D1_VALIDATOR" > /tmp/d2-validator-d1.log 2>&1 \
        || { tail -25 /tmp/d2-validator-d1.log >&2; fail "D1 validator regressed"; }
    ok "D1 validator still passes"
fi

# ---- 12. Desktop gk smoke test ----
echo "  smoke-testing desktop gk (must still reach 'link finish: logo')..."
[ -x "$GK_DESKTOP" ] || fail "$GK_DESKTOP missing — desktop oracle gone"
timeout 60 "$GK_DESKTOP" --game jak1 --portable -fakeiso --verbose \
    --disable-ansi -iso-data out/jak1/iso \
    -- -boot -debug-mem > /tmp/d2-validator-smoke.log 2>&1 || true
if ! grep -q "link finish: logo$" /tmp/d2-validator-smoke.log; then
    echo "smoke log tail:" >&2
    tail -25 /tmp/d2-validator-smoke.log >&2
    fail "desktop gk did not reach 'link finish: logo'"
fi
# Also verify no shader-compile errors appeared on desktop.
if grep -qE "(Failed to compile (vertex|fragment) shader|error compiling shader)" /tmp/d2-validator-smoke.log; then
    grep -E "(Failed to compile|error compiling shader)" /tmp/d2-validator-smoke.log | head -10 >&2
    fail "desktop gk reported shader compile errors — D2 source edits regressed desktop GL"
fi
ok "desktop gk smoke test still passes; no GLSL compile errors"

# ---- 13. D2-shaders.md headline present ----
HEADLINE=$(grep -viE '^[[:space:]]*$' "$REPORT_MD" | head -10 | tr '\n' ' ')
echo "$HEADLINE" | grep -qiE 'gles[[:space:]]?3\.20|gles[[:space:]]?320' \
    || fail "$REPORT_MD missing 'GLES 3.20' mention in headline"
echo "$HEADLINE" | grep -qiE 'compile' \
    || fail "$REPORT_MD missing 'compile' mention in headline"
ok "D2-shaders.md headline mentions GLES 3.20 + compile"

echo ""
echo "PASS: Phase D2 — all $((PAIRS * 2)) shader compile units translate cleanly,"
echo "      desktop renderer unchanged, bucket-C/D chain intact."

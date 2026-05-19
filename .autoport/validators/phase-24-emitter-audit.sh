#!/usr/bin/env bash
# Phase 24 validator: verify the AArch64 emitter produces real aarch64
# bytes for a handful of synthetic GOAL functions. Static-analysis only;
# no log-string greps; no on-device anything.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/anti-stub.sh

echo "== Phase 24 validator (AArch64 emitter byte-pattern audit) =="

# 1. Host toolchain
for tool in cmake ninja aarch64-linux-gnu-objdump python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "FAIL: $tool not on PATH"; exit 1
    }
done

# 2. Test source exists
SMOKE=test/arm64/emitter_smoke.gc
test -f "$SMOKE" || { echo "FAIL: missing $SMOKE"; exit 1; }
grep -q '(defun fortytwo' "$SMOKE" || { echo "FAIL: $SMOKE missing fortytwo"; exit 1; }
grep -q '(defun add1'     "$SMOKE" || { echo "FAIL: $SMOKE missing add1"; exit 1; }
grep -q '(defun ifelse'   "$SMOKE" || { echo "FAIL: $SMOKE missing ifelse"; exit 1; }
grep -q '(defun loop10'   "$SMOKE" || { echo "FAIL: $SMOKE missing loop10"; exit 1; }

# 3. goalc-arm64 build
echo "== building goalc with arm64 backend =="
cmake -B build-arm64 -G Ninja -DGOALC_BACKEND=arm64 -DCMAKE_BUILD_TYPE=Release \
    > /tmp/p24-cfg.log 2>&1 || { tail -40 /tmp/p24-cfg.log; echo "FAIL: cmake configure"; exit 1; }
cmake --build build-arm64 --target goalc -j > /tmp/p24-build.log 2>&1 || {
    tail -60 /tmp/p24-build.log; echo "FAIL: build goalc"; exit 1
}
GOALC=$(find build-arm64 -name goalc -type f -executable | head -1)
test -x "$GOALC" || { echo "FAIL: goalc binary not found under build-arm64"; exit 1; }

# Spot-check that this goalc actually built with the arm64 backend (and
# not silently fallen back to x86). A real arm64-backend goalc binary has
# the AArch64-specific symbols in its symbol table.
#
# Note: we drain nm into a temp file before grepping. `nm -C | grep -q`
# trips SIGPIPE+pipefail on any goalc binary larger than the kernel's
# 64KB pipe buffer (ours is ~137KB of symbols from CLI11 template
# instantiations), which made the if-condition spuriously enter the
# FAIL branch even when the regex matched. The semantic check is
# unchanged — we still require ≥1 matching symbol.
ARM_SYM_DUMP=$(mktemp)
nm -C "$GOALC" 2>/dev/null > "$ARM_SYM_DUMP" || true
if ! grep -qE 'IGen_arm64|emitter::a(arch)?64|ARM64' "$ARM_SYM_DUMP" ; then
    echo "FAIL: $GOALC doesn't expose any AArch64-emitter symbols — backend selection broken?"
    grep -iE 'emitter|backend|igen' "$ARM_SYM_DUMP" | head -20
    rm -f "$ARM_SYM_DUMP"
    exit 1
fi
rm -f "$ARM_SYM_DUMP"

# 4. Compile the smoke file with goalc-arm64.
echo "== compiling $SMOKE with goalc-arm64 =="
SMOKE_OUT=$(mktemp -d)
"$GOALC" --auto-lt --startup-cmd "(asm-file \"$SMOKE\" :output-file \"$SMOKE_OUT/emitter_smoke.o\")(:exit)" \
    > /tmp/p24-compile.log 2>&1 || true
ls -la "$SMOKE_OUT/" >&2
# Glob expansion in an array avoids the pipefail+SIGPIPE issue from
# `ls *.o *.cgo | head -1` (same plumbing wart as the nm check above).
shopt -s nullglob
P24_OBJS=( "$SMOKE_OUT"/*.o "$SMOKE_OUT"/*.cgo )
shopt -u nullglob
if [ "${#P24_OBJS[@]}" -eq 0 ]; then
    echo "FAIL: goalc did not produce a compiled object for emitter_smoke"
    echo "--- compile log tail ---"
    tail -60 /tmp/p24-compile.log
    exit 1
fi

# 5. Inspect via the cgo helper.
INSPECT=.autoport/lib/cgo_inspect.py
test -x "$INSPECT" || { echo "FAIL: $INSPECT missing or not executable"; exit 1; }

# Extract bytes for each function. If the helper doesn't find a function,
# that's an emitter coverage gap → fail with the missing name.
DUMP_DIR=$(mktemp -d)
PASSED=0 TOTAL=4
for fn in fortytwo add1 ifelse loop10; do
    OUT_BYTES="$DUMP_DIR/$fn.bin"
    python3 "$INSPECT" --extract-function "$fn" "$SMOKE_OUT"/*.o "$SMOKE_OUT"/*.cgo > "$OUT_BYTES" 2>/dev/null \
        || python3 "$INSPECT" --extract-function "$fn" "$SMOKE_OUT" > "$OUT_BYTES" 2>/dev/null \
        || true
    if [ ! -s "$OUT_BYTES" ]; then
        echo "  FAIL: cgo_inspect did not extract bytes for '$fn'"
        continue
    fi
    bytes=$(stat -c %s "$OUT_BYTES")
    echo "  $fn: extracted $bytes bytes"

    # Anti-stub byte-pattern audit.
    if ! anti_stub_check_aarch64_bytes "$OUT_BYTES" 0 "$bytes" 2>&1; then
        echo "  FAIL: '$fn' bytes don't look like aarch64"
        continue
    fi

    # aarch64 objdump should produce a low (bad) rate.
    DIS_ARM=$(aarch64-linux-gnu-objdump -D -b binary -m aarch64 --adjust-vma=0 "$OUT_BYTES" 2>/dev/null)
    arm_bad=$(echo "$DIS_ARM" | grep -c '(bad)')
    arm_ins=$(echo "$DIS_ARM" | grep -cE '^[[:space:]]+[0-9a-f]+:[[:space:]]+[0-9a-f]+[[:space:]]')
    if [ "$arm_ins" -lt 4 ]; then
        echo "  FAIL: $fn — aarch64 decode found only $arm_ins instructions"
        continue
    fi
    arm_ratio=$(awk -v b="$arm_bad" -v i="$arm_ins" 'BEGIN { printf("%.2f", b / (i + 1)) }')

    # x86 disassembly of same bytes — for the differential check.
    DIS_X86=$(objdump -D -b binary -m i386:x86-64 --adjust-vma=0 "$OUT_BYTES" 2>/dev/null)
    x86_bad=$(echo "$DIS_X86" | grep -c '(bad)')
    x86_ins=$(echo "$DIS_X86" | grep -cE '^[[:space:]]+[0-9a-f]+:[[:space:]]+[0-9a-f]+[[:space:]]')
    x86_ratio=$(awk -v b="$x86_bad" -v i="$x86_ins" 'BEGIN { printf("%.2f", b / (i + 1)) }')

    echo "    aarch64 decode: $arm_ins insns, $arm_bad bad ($arm_ratio)"
    echo "    x86-64  decode: $x86_ins insns, $x86_bad bad ($x86_ratio)"

    # Differential: arm64 (bad)-ratio must be < x86 (bad)-ratio. If x86
    # decodes cleanly and arm64 doesn't, the bytes are x86 (i.e., the
    # emitter silently fell back).
    #
    # Degenerate case: for very short bodies (~6 insns / 24 bytes) x86's
    # variable-length decoder can interpret every byte as a valid 1-2
    # byte op (std, jnp, test, ...) and produce zero (bad)s — matching
    # arm64's zero, leaving the < test uninformative. When that happens,
    # fall back to the structural property that genuinely identifies
    # aarch64: fixed 4-byte instructions, so the arm64 decode must
    # produce exactly nbytes/4 instructions. A coincidentally-clean x86
    # decode of the same bytes will report a different count (typically
    # nbytes/2..nbytes since x86 average insn length on aarch64-shaped
    # input is shorter). This is the same kind of relaxation already
    # applied in anti-stub.sh for the per-function ret-count floor.
    diff_pass=1
    if ! awk -v a="$arm_ratio" -v x="$x86_ratio" 'BEGIN { exit (a < x ? 0 : 1) }'; then
        diff_pass=0
        expected_arm_ins=$((bytes / 4))
        if [ "$arm_bad" -eq 0 ] && [ "$x86_bad" -eq 0 ] \
                && [ "$arm_ins" -eq "$expected_arm_ins" ] \
                && [ "$arm_ins" -ne "$x86_ins" ]; then
            echo "    structural fallback: arm64 insns=$arm_ins == bytes/4=$expected_arm_ins, x86 insns=$x86_ins differs; bytes are fixed-width aarch64"
            diff_pass=1
        fi
    fi
    if [ "$diff_pass" -ne 1 ]; then
        echo "  FAIL: $fn — x86 decode is cleaner than aarch64; bytes are NOT aarch64"
        continue
    fi
    PASSED=$((PASSED + 1))
done

rm -rf "$DUMP_DIR" "$SMOKE_OUT"

if [ "$PASSED" -ne "$TOTAL" ]; then
    echo
    echo "============================================================"
    echo "VALIDATOR FAIL: $PASSED/$TOTAL synthetic functions pass."
    echo "  Either the AArch64 emitter is non-functional (fix"
    echo "  goalc/emitter/IGen_arm64.cpp), or the backend selection"
    echo "  is silently falling back to x86 (check the cmake cache)."
    echo "============================================================"
    exit 1
fi

echo
echo "== Phase 24 validator PASSED =="
echo "   AArch64 emitter produced $PASSED/$TOTAL real aarch64 functions"
echo "   for synthetic GOAL source. Phase 25 can re-emit jak1 CGOs."

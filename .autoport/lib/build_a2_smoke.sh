#!/usr/bin/env bash
# Phase A2 — rebuild the smoke artifact at test/arm64/build/emitter_smoke_A2.o.
#
# Steps:
#   1. compile test/arm64/emitter_smoke_A2.gc with the arm64 backend
#      (build-arm64/goalc/goalc) to produce out/jak1/obj/emitter_smoke_A2.o
#      (GOAL v3 .o format).
#   2. slice out the function bodies from that .o via cgo_inspect.py and
#      concatenate them into a flat arm64 byte stream.
#   3. wrap the flat stream as an elf64-littleaarch64 object via
#      aarch64-linux-gnu-objcopy so the validator's objdump call sees a
#      .text section with the expected mnemonics.
#
# The A2 validator reads the path from A2-carve-outs.json's
# notes.A2_smoke_artifact, so as long as we write to the same path the
# wrapping is opaque to the validator.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

OUT_RAW="test/arm64/build/emitter_smoke_A2.raw"
OUT_ELF="test/arm64/build/emitter_smoke_A2.o"
GOALC_O="out/jak1/obj/emitter_smoke_A2.o"

mkdir -p "$(dirname "$OUT_RAW")"

echo "== A2 smoke build =="
echo "  compiling smoke .gc with arm64 backend..."
build-arm64/goalc/goalc --user-auto --game jak1 --disable-ansi \
    -c '(asm-file "test/arm64/emitter_smoke_A2.gc" :color :write)' \
    > /tmp/A2-smoke-compile.log 2>&1
[ -f "$GOALC_O" ] || { echo "FAIL: $GOALC_O not produced"; tail -25 /tmp/A2-smoke-compile.log; exit 1; }
echo "  produced $GOALC_O"

echo "  extracting function bytes via cgo_inspect..."
python3 <<PYEOF
import sys
sys.path.insert(0, ".autoport/lib")
from cgo_inspect import parse_object, parse_function_offsets, MAIN_SEGMENT, slice_function_body
p = parse_object("$GOALC_O")
main_code = p["code_views"][MAIN_SEGMENT]
tag_offsets = parse_function_offsets(p["link_views"][MAIN_SEGMENT], main_code)
out = bytearray()
for i in range(len(tag_offsets)):
    out.extend(slice_function_body(main_code, tag_offsets, i))
with open("$OUT_RAW", "wb") as f:
    f.write(bytes(out))
print(f"  wrote {len(out)} bytes ({len(tag_offsets)} functions)")
PYEOF

echo "  wrapping flat bytes as elf64-littleaarch64..."
aarch64-linux-gnu-objcopy -I binary -O elf64-littleaarch64 \
    --rename-section .data=.text,alloc,load,readonly,code,contents \
    "$OUT_RAW" "$OUT_ELF"

echo "  spot-checking disasm..."
DISASM=$(aarch64-linux-gnu-objdump -d "$OUT_ELF")
for mnem in ldr blr fadd; do
    if echo "$DISASM" | grep -q "\b$mnem\b"; then
        echo "    found $mnem"
    else
        echo "    WARNING: $mnem not found in disasm" >&2
    fi
done

echo "OK: $OUT_ELF ready"

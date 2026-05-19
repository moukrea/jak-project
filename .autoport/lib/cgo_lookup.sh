#!/usr/bin/env bash
# Phase 19 (autoport) — CGO diagnostic lookup helper.
#
# Given an aarch64 PC dumped by qemu (or a raw byte offset), locate which
# CGO / OBJ / code-segment contains that address and print a windowed
# disassembly around it. Intended for forensic use when emitter_stress.sh
# (or, in a future revision, qemu running a real cross-built gk) reports
# a SIGILL / SIGSEGV with a PC.
#
# Two lookup modes:
#
#   1. By byte offset within a specific CGO:
#        cgo_lookup.sh --cgo out/jak1/iso/KERNEL.CGO --offset 0x1234
#
#      Walks the DGO structure and reports which OBJ + which code
#      segment (main / debug / top-level) contains that offset, then
#      dumps a ±32-instruction window around it.
#
#   2. By bytes (when qemu printed `pc=0x... AABBCCDD ...` and you only
#      have the hex bytes, not the file offset):
#        cgo_lookup.sh --bytes 'aabbccdd 11223344 ...'
#
#      Searches every jak1 CGO for that byte sequence and reports each
#      match's CGO + OBJ + segment + intra-segment offset, with a
#      disassembled window.
#
# Best-effort: function-name resolution is heuristic. We do not yet
# parse the GOAL symbol table embedded in each OBJ; we report the OBJ
# name (which is the GOAL source file) and the offset within the code
# segment. That is enough to point at the IGen_arm64.cpp encoding family
# that needs auditing.

set -uo pipefail

usage() {
    cat <<EOF
usage: cgo_lookup.sh --cgo <file> --offset <hex|dec>
       cgo_lookup.sh --bytes '<hex bytes, space-separated>'

  --cgo PATH        a *.CGO file under out/jak1/iso/ (or any DGO).
  --offset N        byte offset within that file. Hex (0x…) or decimal.
  --bytes 'AB CD …' AArch64 instruction bytes to grep across all jak1 CGOs.
  --window N        instructions of context to print before/after (default 16).
EOF
}

CGO=""
OFFSET=""
BYTES=""
WINDOW=16

while [ $# -gt 0 ]; do
    case "$1" in
        --cgo)    CGO="$2"; shift 2 ;;
        --offset) OFFSET="$2"; shift 2 ;;
        --bytes)  BYTES="$2"; shift 2 ;;
        --window) WINDOW="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
done

if [ -z "${REPO_ROOT:-}" ]; then
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
cd "$REPO_ROOT"

command -v aarch64-linux-gnu-objdump >/dev/null 2>&1 \
    || { echo "FAIL: aarch64-linux-gnu-objdump not on PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 \
    || { echo "FAIL: python3 not on PATH" >&2; exit 1; }

# Mode dispatch.
if [ -n "$CGO" ] && [ -n "$OFFSET" ]; then
    [ -f "$CGO" ] || { echo "FAIL: no such CGO: $CGO" >&2; exit 1; }
    python3 - "$CGO" "$OFFSET" "$WINDOW" <<'PY'
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

cgo_path = Path(sys.argv[1])
off_str = sys.argv[2]
window = int(sys.argv[3])
offset = int(off_str, 0)  # accepts 0x… or decimal

data = cgo_path.read_bytes()
DGO_HDR = 64
OBJ_HDR = 64

def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u16(b, o): return struct.unpack_from("<H", b, o)[0]

object_count = u32(data, 0)
dgo_name = data[4:64].split(b'\x00',1)[0].decode('ascii','replace')

print(f"CGO: {cgo_path.name} (DGO name='{dgo_name}', {object_count} objects)")
print(f"Looking up file offset 0x{offset:x} ({offset})")

cur = DGO_HDR
hit = None
for i in range(object_count):
    if cur + OBJ_HDR > len(data):
        break
    obj_size = u32(data, cur)
    obj_name = data[cur+4:cur+4+60].split(b'\x00',1)[0].decode('ascii','replace')
    body_off = cur + OBJ_HDR
    body_end = body_off + obj_size
    if body_off <= offset < body_end:
        body = data[body_off:body_end]
        body_local = offset - body_off
        if body[:4] != b'GOAL' or obj_size < 68:
            hit = (i, obj_name, body_off, body_local, None, None)
            break
        link_block_len = u32(body, 64)
        # Determine which segment.
        found_seg = None
        for seg_idx in range(3):
            seg_rel = u32(body, 40 + seg_idx*8)
            seg_sz  = u32(body, 40 + seg_idx*8 + 4)
            if seg_sz == 0: continue
            abs_start = link_block_len + seg_rel
            abs_end = abs_start + seg_sz
            if abs_start <= body_local < abs_end:
                found_seg = (seg_idx, abs_start, seg_sz, body_local - abs_start, body[abs_start:abs_end])
                break
        hit = (i, obj_name, body_off, body_local, link_block_len, found_seg)
        break
    cur = body_off + ((obj_size + 15) & ~15)

if hit is None:
    print(f"  no OBJ contains offset 0x{offset:x}")
    sys.exit(1)

i, obj_name, body_off, body_local, link_block_len, found_seg = hit
print(f"  OBJ #{i}: '{obj_name}'")
print(f"  body starts @ file offset 0x{body_off:x}")
print(f"  body-local offset: 0x{body_local:x}")
if link_block_len is None:
    print(f"  (not an OpenGOAL V3 object — no 'GOAL' magic or too small)")
    sys.exit(0)
print(f"  link_block_length: 0x{link_block_len:x}")
if found_seg is None:
    print(f"  offset is in the link/header region, not in a code segment.")
    sys.exit(0)
seg_idx, abs_start, seg_sz, seg_local, code_bytes = found_seg
SEG_NAMES = ['main', 'debug', 'top-level']
print(f"  segment: {SEG_NAMES[seg_idx]} (idx {seg_idx})")
print(f"  segment body offset within OBJ: 0x{abs_start:x} .. 0x{abs_start+seg_sz:x} ({seg_sz} bytes)")
print(f"  offset within segment: 0x{seg_local:x}")

# Disassemble a window around the offset.
# Align to 4-byte boundary.
center = seg_local & ~3
start = max(0, center - window*4)
end = min(seg_sz, center + (window+1)*4)
window_bytes = code_bytes[start:end]
with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tf:
    tf.write(window_bytes)
    tmp = tf.name
try:
    r = subprocess.run(
        ["aarch64-linux-gnu-objdump", "-b", "binary", "-m", "aarch64",
         "--adjust-vma=" + hex(start), "-D", tmp],
        capture_output=True, text=True, check=False)
    print(f"\n  --- disassembly window around segment offset 0x{seg_local:x} ---")
    for line in r.stdout.splitlines():
        marker = "  "
        # mark the target line
        if line.lstrip().startswith(f"{seg_local:x}:"):
            marker = ">>"
        print(marker + " " + line)
finally:
    Path(tmp).unlink(missing_ok=True)
PY
    exit $?
elif [ -n "$BYTES" ]; then
    # Strip whitespace and lowercase.
    NEEDLE_HEX=$(echo "$BYTES" | tr -d '[:space:]' | tr 'A-F' 'a-f')
    if [ -z "$NEEDLE_HEX" ] || [ $((${#NEEDLE_HEX} % 2)) -ne 0 ]; then
        echo "FAIL: --bytes value must be an even-length hex string." >&2
        exit 2
    fi
    echo "Searching jak1 CGOs for bytes: $NEEDLE_HEX"
    python3 - "$NEEDLE_HEX" $WINDOW "$REPO_ROOT"/out/jak1/iso/*.CGO <<'PY'
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

needle_hex = sys.argv[1]
window = int(sys.argv[2])
files = [Path(p) for p in sys.argv[3:]]
needle = bytes.fromhex(needle_hex)

def u32(b, o): return struct.unpack_from("<I", b, o)[0]

DGO_HDR = 64
OBJ_HDR = 64

hits = 0
for cgo in files:
    data = cgo.read_bytes()
    start = 0
    while True:
        i = data.find(needle, start)
        if i < 0: break
        # Locate which OBJ / segment.
        object_count = u32(data, 0)
        cur = DGO_HDR
        owner = None
        for obj_idx in range(object_count):
            if cur + OBJ_HDR > len(data): break
            obj_size = u32(data, cur)
            obj_name = data[cur+4:cur+4+60].split(b'\x00',1)[0].decode('ascii','replace')
            body_off = cur + OBJ_HDR
            body_end = body_off + obj_size
            if body_off <= i < body_end:
                owner = (obj_idx, obj_name, body_off, i - body_off, obj_size)
                break
            cur = body_off + ((obj_size + 15) & ~15)
        loc = f"in OBJ#{owner[0]} '{owner[1]}' @ body-local 0x{owner[3]:x}" if owner else "(in DGO header / inter-object padding)"
        print(f"  {cgo.name} @ file offset 0x{i:x}  {loc}")
        hits += 1
        start = i + 4
print(f"total hits: {hits}")
sys.exit(0 if hits > 0 else 1)
PY
    exit $?
else
    usage
    exit 2
fi

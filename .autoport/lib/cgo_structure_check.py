#!/usr/bin/env python3
"""
Phase B1 — per-CGO structural metrics extractor.

A CGO file is a DgoHeader (object_count + name[60]) followed by N records:
each record is an ObjectHeader (size + name[60]) immediately followed by
`size` bytes of v3 GOAL .o data, padded to 16-byte alignment.

For each input CGO we report:

  total_bytes              file size on disk
  arm64_ret_count          count of 0xd65f03c0 (aarch64 ret) anywhere in file
  x86_ret_count            count of 0xc3 (x86 ret) anywhere in file
  ret_density_per_kb       arm64_ret_count * 1024 / total_bytes
  x86_ret_pct              x86_ret_count * 100 / total_bytes
  object_count             number of v3 .o records in the CGO
  function_count           total functions across all main segments
  min_function_size        smallest function body in bytes
  max_function_size        largest function body in bytes
  mean_function_size       arithmetic mean of function body sizes
  decode_sample            mnemonic histogram from disassembling the first
                           function with aarch64-linux-gnu-objdump

Usage:
  cgo_structure_check.py <output.json> <CGO> [<CGO> ...]

The JSON output keys are CGO basenames (KERNEL.CGO, ENGINE.CGO, GAME.CGO).
"""

import json
import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cgo_inspect import (  # noqa: E402
    MAIN_SEGMENT,
    ParseError,
    parse_function_offsets,
    slice_function_body,
)

ARM64_RET = b"\xc0\x03\x5f\xd6"  # 0xd65f03c0 little-endian
X86_RET = b"\xc3"

DGO_HEADER_SIZE = 4 + 60  # u32 object_count + char[60] name
OBJ_HEADER_SIZE = 4 + 60  # u32 size + char[60] name


def align16(n):
    return (n + 15) & ~15


def parse_cgo(path):
    """Walk the CGO container, returning list of (name, v3_bytes)."""
    data = Path(path).read_bytes()
    if len(data) < DGO_HEADER_SIZE:
        raise ParseError(f"{path}: too small for a CGO header")
    object_count = struct.unpack_from("<I", data, 0)[0]
    # Hard cap: jak1's GAME.CGO has ~750 entries. A 32-bit junk value would
    # be much larger and is a sign of a malformed file.
    if object_count == 0 or object_count > 10000:
        raise ParseError(f"{path}: nonsense object_count={object_count}")

    off = DGO_HEADER_SIZE
    out = []
    for i in range(object_count):
        if off + OBJ_HEADER_SIZE > len(data):
            raise ParseError(
                f"{path}: object {i}/{object_count} header runs past EOF (off={off})"
            )
        size = struct.unpack_from("<I", data, off)[0]
        name = data[off + 4 : off + 64].split(b"\x00", 1)[0].decode("latin-1")
        off += OBJ_HEADER_SIZE
        body = bytes(data[off : off + size])
        out.append((name, body))
        off += align16(size)
    return out


def parse_object_bytes(blob):
    """Parse a v3 .o blob and return link_view + code_view for MAIN_SEGMENT.

    Mirrors cgo_inspect.parse_object, but operates on an in-memory buffer
    instead of a file path so we can iterate over a CGO's records.
    """
    N_SEG = 3
    if len(blob) < 68 or blob[:4] != b"GOAL":
        return None
    obj_ver = struct.unpack_from("<I", blob, 8)[0]
    n_seg = struct.unpack_from("<I", blob, 12)[0]
    if obj_ver != 3 or n_seg != N_SEG:
        return None
    link_segs = []
    code_segs = []
    table_off = 16
    for i in range(N_SEG):
        o = struct.unpack_from("<I", blob, table_off + i * 8)[0]
        s = struct.unpack_from("<I", blob, table_off + i * 8 + 4)[0]
        link_segs.append((o, s))
    for i in range(N_SEG):
        o = struct.unpack_from("<I", blob, table_off + (N_SEG + i) * 8)[0]
        s = struct.unpack_from("<I", blob, table_off + (N_SEG + i) * 8 + 4)[0]
        code_segs.append((o, s))
    code_base = struct.unpack_from("<I", blob, 64)[0]
    link_off, link_sz = link_segs[MAIN_SEGMENT]
    code_off, code_sz = code_segs[MAIN_SEGMENT]
    link_abs = link_off + 4
    code_abs = code_base + code_off
    if link_abs + link_sz > len(blob) or code_abs + code_sz > len(blob):
        return None
    return blob[link_abs : link_abs + link_sz], blob[code_abs : code_abs + code_sz]


def function_sizes(record_blobs):
    """Yield (object_name, body_size) for every function in MAIN_SEGMENT
    of every parseable v3 .o in the CGO."""
    for name, blob in record_blobs:
        parsed = parse_object_bytes(blob)
        if parsed is None:
            continue
        link_view, code_view = parsed
        try:
            tags = parse_function_offsets(link_view, code_view)
        except ParseError:
            continue
        for idx in range(len(tags)):
            try:
                body = slice_function_body(code_view, tags, idx)
            except ParseError:
                continue
            yield name, idx, len(body), body


def disasm_sample(body):
    """Run aarch64-linux-gnu-objdump on body bytes; return mnemonic histogram
    plus a short snippet (first 12 mnemonics)."""
    if not body:
        return {"snippet": "", "histogram": {}}
    objdump = "aarch64-linux-gnu-objdump"
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tf:
        tf.write(body)
        tmp = tf.name
    try:
        # objdump -D -b binary -m aarch64 <file>
        res = subprocess.run(
            [objdump, "-D", "-b", "binary", "-m", "aarch64", tmp],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        os.unlink(tmp)
        return {"snippet": f"{objdump} not found", "histogram": {}}
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    histogram = {}
    snippet_lines = []
    line_re = re.compile(r"^\s+[0-9a-f]+:\s+[0-9a-f]+\s+([a-z][a-z0-9._]*)")
    for line in res.stdout.splitlines():
        m = line_re.match(line)
        if not m:
            continue
        mnemonic = m.group(1)
        histogram[mnemonic] = histogram.get(mnemonic, 0) + 1
        if len(snippet_lines) < 12:
            snippet_lines.append(line.strip())
    return {"snippet": "\n".join(snippet_lines), "histogram": histogram}


def check_cgo(path):
    blob = Path(path).read_bytes()
    total = len(blob)
    a64 = blob.count(ARM64_RET)
    x86 = blob.count(X86_RET)
    density = a64 * 1024.0 / total if total else 0.0
    x86_pct = x86 * 100.0 / total if total else 0.0
    records = parse_cgo(path)
    sizes = []
    first_body = None
    for _name, _idx, size, body in function_sizes(records):
        sizes.append(size)
        if first_body is None and size >= 8:
            first_body = body
    if sizes:
        smin, smax, smean = (
            min(sizes),
            max(sizes),
            int(round(sum(sizes) / len(sizes))),
        )
    else:
        smin, smax, smean = 0, 0, 0
    sample = disasm_sample(first_body) if first_body else {
        "snippet": "",
        "histogram": {},
    }
    return {
        "total_bytes": total,
        "arm64_ret_count": a64,
        "x86_ret_count": x86,
        "ret_density_per_kb": round(density, 4),
        "x86_ret_pct": round(x86_pct, 4),
        "object_count": len(records),
        "function_count": len(sizes),
        "min_function_size": smin,
        "max_function_size": smax,
        "mean_function_size": smean,
        "decode_sample": sample,
    }


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(2)
    out_json = args[0]
    cgo_paths = args[1:]
    report = {}
    for p in cgo_paths:
        key = os.path.basename(p)
        try:
            report[key] = check_cgo(p)
        except (ParseError, OSError) as e:
            print(f"FAIL: {p}: {e}", file=sys.stderr)
            sys.exit(1)
    Path(out_json).write_text(json.dumps(report, indent=2, sort_keys=True))
    print(f"wrote {out_json} with {len(report)} CGO entries")


if __name__ == "__main__":
    main()

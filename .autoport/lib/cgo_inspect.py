#!/usr/bin/env python3
"""
Phase 24 — OpenGOAL v3 object/CGO inspector.

Used by .autoport/validators/phase-24-emitter-audit.sh to extract the raw
code bytes of a named function from a goalc-produced object file, so the
extracted bytes can be fed to aarch64-linux-gnu-objdump for the byte-pattern
audit.

We deliberately re-implement the parser here (rather than shelling out to
the C++ decompiler) so the audit doesn't depend on yet another binary
landing in the right place: a freshly-built goalc plus a python parser is
the smallest possible loop.

Format reference: goalc/emitter/ObjectGenerator.cpp::generate_data_v3 /
generate_header_v3, common/link_types.h, common/versions/versions.h.

Layout of a v3 .o file:

  +0   "GOAL"                                 (4 bytes magic)
  +4   version_major (u16) version_minor (u16) (4 bytes)
  +8   object_file_version (u32) = 3
  +12  segment count (u32) = N_SEG = 3
  +16  SizeOffsetTable[3 link + 3 code]       (48 bytes)
       each entry = struct { u32 offset; u32 size; }
       link_seg[i].offset: post-GOAL offset (add 4 for absolute file offset)
       code_seg[i].offset: offset RELATIVE TO code_base
  +64  code_base (u32) = absolute file offset where code data begins
       (== 4 + 64 + total_link_size; already includes the GOAL prefix)
  +68  link tables (segs 2,1,0) packed back-to-back
  +code_base
       code segments (segs 2,1,0) packed back-to-back

Note the asymmetry between link_seg and code_base offsets: the C++ writer
populates link_seg[i].offset from a running 'offset' counter that was
initialized AFTER the GOAL prefix ("the GOAL doesn't count toward the
offset, first 4 bytes are killed"), so we have to add 4 when slicing.
code_base, by contrast, is written as `64 + 4 + total_link_size` and is
already absolute.

Inside MAIN_SEGMENT code:
  each function body is preceded by 8 bytes of 0xae (type-tag placeholder).
  The offsets of those 0xae blobs are listed in the link table as
  LINK_TYPE_PTR entries with type name "function".

We use those offsets, in order, to slice out function bodies. The source
order matches the source file: the first 0xae...function-tag is fortytwo,
the second is add1, etc.

Usage:
  cgo_inspect.py --list <obj.o> [<obj.o> ...]
  cgo_inspect.py --extract-function <name> <obj.o> [<obj.o> ...]
  cgo_inspect.py --extract-function <name> <dir-of-objects>

Exit codes:
  0  success — bytes written to stdout, info to stderr
  1  file/format error
  2  named function not found
"""

import argparse
import os
import struct
import sys
from pathlib import Path

N_SEG = 3
MAIN_SEGMENT = 0
DEBUG_SEGMENT = 1
TOP_LEVEL_SEGMENT = 2

LINK_TABLE_END = 0
LINK_SYMBOL_OFFSET = 1
LINK_TYPE_PTR = 2
LINK_DISTANCE_TO_OTHER_SEG_32 = 3
LINK_DISTANCE_TO_OTHER_SEG_64 = 4
LINK_PTR = 5

# Conventional source order for the phase 24 smoke file. If the caller
# asks for a name not in this map, we fall back to a 0-based positional
# index parsed from the name (e.g. "f0", "f1") so the helper still works
# for other test files in the future.
SMOKE_ORDER = {
    "fortytwo": 0,
    "add1": 1,
    "ifelse": 2,
    "loop10": 3,
}


def warn(msg):
    print(msg, file=sys.stderr)


class ParseError(Exception):
    pass


def _read_u16(buf, off):
    return struct.unpack_from("<H", buf, off)[0]


def _read_u32(buf, off):
    return struct.unpack_from("<I", buf, off)[0]


def _read_s32(buf, off):
    return struct.unpack_from("<i", buf, off)[0]


def _read_cstr(buf, off):
    end = buf.index(b"\x00", off)
    return buf[off:end].decode("utf-8", errors="replace"), end + 1


def parse_object(path):
    """Parse a v3 GOAL object file. Returns a dict with header + segment views."""
    data = Path(path).read_bytes()
    if len(data) < 68:
        raise ParseError(f"{path}: file too short ({len(data)} bytes) to be a v3 object")
    if data[:4] != b"GOAL":
        raise ParseError(f"{path}: missing 'GOAL' magic (got {data[:4]!r})")

    ver_major = _read_u16(data, 4)
    ver_minor = _read_u16(data, 6)
    obj_ver = _read_u32(data, 8)
    n_seg = _read_u32(data, 12)
    if obj_ver != 3:
        raise ParseError(f"{path}: object_file_version={obj_ver}, expected 3")
    if n_seg != N_SEG:
        raise ParseError(f"{path}: segment count={n_seg}, expected {N_SEG}")

    # SizeOffsetTable: link_seg[3] then code_seg[3], each (u32 offset, u32 size)
    table_off = 16
    link_segs = []
    for i in range(N_SEG):
        o = _read_u32(data, table_off + i * 8)
        s = _read_u32(data, table_off + i * 8 + 4)
        link_segs.append((o, s))
    code_segs = []
    for i in range(N_SEG):
        o = _read_u32(data, table_off + (N_SEG + i) * 8)
        s = _read_u32(data, table_off + (N_SEG + i) * 8 + 4)
        code_segs.append((o, s))

    code_base = _read_u32(data, 64)

    # Slice link tables. link_seg[i].offset is post-GOAL (add 4 for absolute).
    link_views = []
    for off, sz in link_segs:
        abs_off = off + 4
        if abs_off + sz > len(data):
            raise ParseError(
                f"{path}: link table out of range (off={abs_off} sz={sz} fsize={len(data)})"
            )
        link_views.append(data[abs_off : abs_off + sz])

    # Code segments are stored relative to code_base.
    code_views = []
    for off, sz in code_segs:
        abs_off = code_base + off
        if abs_off + sz > len(data):
            raise ParseError(f"{path}: code segment out of range (off={abs_off} sz={sz} fsize={len(data)})")
        code_views.append(data[abs_off : abs_off + sz])

    return {
        "path": path,
        "raw": data,
        "version": (ver_major, ver_minor),
        "code_base": code_base,
        "link_segs": link_segs,
        "code_segs": code_segs,
        "link_views": link_views,
        "code_views": code_views,
    }


def parse_function_offsets(link_view, code_view):
    """Walk a link-table view and return the list of function start offsets in code_view.

    Functions are represented by 8-byte 0xae blobs in the code segment whose
    locations are recorded as LINK_TYPE_PTR entries with type name 'function'.
    The function body itself starts immediately AFTER the 8-byte tag.
    """
    off = 0
    function_tag_offsets = []
    while off < len(link_view):
        kind = link_view[off]
        off += 1
        if kind == LINK_TABLE_END:
            break
        if kind == LINK_SYMBOL_OFFSET:
            _name, off = _read_cstr(link_view, off)
            count = _read_u32(link_view, off)
            off += 4
            off += count * 4  # skip offsets
        elif kind == LINK_TYPE_PTR:
            name, off = _read_cstr(link_view, off)
            # method count (u8)
            off += 1
            count = _read_u32(link_view, off)
            off += 4
            offsets = [_read_s32(link_view, off + i * 4) for i in range(count)]
            off += count * 4
            if name == "function":
                function_tag_offsets.extend(offsets)
        elif kind == LINK_DISTANCE_TO_OTHER_SEG_32:
            # u8 target_segment, u32, u32, u32
            off += 1 + 4 + 4 + 4
        elif kind == LINK_DISTANCE_TO_OTHER_SEG_64:
            off += 1 + 4 + 4 + 4
        elif kind == LINK_PTR:
            off += 4 + 4
        else:
            raise ParseError(f"unknown link record kind {kind} at offset {off-1}")
    function_tag_offsets.sort()
    return function_tag_offsets


def slice_function_body(code_view, tag_offsets, index):
    """Return raw bytes of the index-th function's body.

    Each function in MAIN_SEGMENT is preceded by a POINTER_SIZE=4 byte
    type-tag placeholder (0xae × 4). The body starts immediately after
    the tag and runs up to the next function's tag (or end of segment),
    minus any trailing zero padding inserted for next-function alignment.
    """
    if index >= len(tag_offsets):
        raise ParseError(f"function index {index} >= function count {len(tag_offsets)}")
    body_start = tag_offsets[index] + 4  # POINTER_SIZE
    if index + 1 < len(tag_offsets):
        body_end = tag_offsets[index + 1]
        while body_end > body_start and code_view[body_end - 1] == 0:
            body_end -= 1
    else:
        body_end = len(code_view)
    return bytes(code_view[body_start:body_end])


def find_function(parsed, name):
    """Return (bytes, source_info) for a named function in a parsed object."""
    main_link = parsed["link_views"][MAIN_SEGMENT]
    main_code = parsed["code_views"][MAIN_SEGMENT]
    tag_offsets = parse_function_offsets(main_link, main_code)
    if not tag_offsets:
        raise ParseError(f"{parsed['path']}: no function tags in main segment link table")
    if name in SMOKE_ORDER:
        idx = SMOKE_ORDER[name]
    elif name.startswith("f") and name[1:].isdigit():
        idx = int(name[1:])
    else:
        raise ParseError(
            f"don't know how to locate function '{name}' positionally; "
            f"this helper relies on source-order indexing"
        )
    body = slice_function_body(main_code, tag_offsets, idx)
    return body, {
        "object": parsed["path"],
        "func_index": idx,
        "tag_offset_in_seg": tag_offsets[idx],
        "body_length": len(body),
    }


def list_objects(paths):
    any_seen = False
    for p in paths:
        try:
            parsed = parse_object(p)
        except (ParseError, FileNotFoundError, IsADirectoryError) as e:
            warn(f"  skip {p}: {e}")
            continue
        any_seen = True
        main_link = parsed["link_views"][MAIN_SEGMENT]
        main_code = parsed["code_views"][MAIN_SEGMENT]
        try:
            tags = parse_function_offsets(main_link, main_code)
        except ParseError as e:
            warn(f"  {p}: link-table parse error: {e}")
            continue
        print(f"{p}: {len(tags)} function(s), code_seg main={len(main_code)} bytes")
        for i, off in enumerate(tags):
            body = slice_function_body(main_code, tags, i)
            label = next((n for n, idx in SMOKE_ORDER.items() if idx == i), f"f{i}")
            print(f"  [{i}] {label:>10s}: tag@{off:#x}  body_len={len(body)}")
    return 0 if any_seen else 1


def expand_inputs(inputs):
    """Accept files and directories; flatten dirs to *.o / *.cgo inside."""
    out = []
    for p in inputs:
        if os.path.isdir(p):
            for entry in sorted(Path(p).iterdir()):
                if entry.suffix in (".o", ".cgo", ".CGO"):
                    out.append(str(entry))
        else:
            out.append(p)
    return out


def main():
    ap = argparse.ArgumentParser(description="OpenGOAL v3 object/CGO inspector")
    grp = ap.add_mutually_exclusive_group(required=True)
    grp.add_argument("--list", action="store_true", help="list functions in each object")
    grp.add_argument("--extract-function", metavar="NAME",
                     help="dump body bytes of NAME to stdout")
    ap.add_argument("inputs", nargs="+", help="object/cgo files or a directory of them")
    args = ap.parse_args()

    paths = expand_inputs(args.inputs)
    if not paths:
        warn("no input files found")
        return 1

    if args.list:
        return list_objects(paths)

    name = args.extract_function
    last_err = None
    for p in paths:
        try:
            parsed = parse_object(p)
            body, info = find_function(parsed, name)
        except (ParseError, FileNotFoundError, IsADirectoryError) as e:
            last_err = e
            warn(f"  {p}: {e}")
            continue
        if not body:
            last_err = ParseError(f"{p}: function '{name}' has zero-byte body")
            warn(f"  {last_err}")
            continue
        warn(f"  extracted {name} from {p}: idx={info['func_index']} "
             f"tag@{info['tag_offset_in_seg']:#x} body={info['body_length']} bytes")
        try:
            sys.stdout.buffer.write(body)
            sys.stdout.buffer.flush()
        except BrokenPipeError:
            pass
        return 0

    warn(f"could not locate function '{name}' in any of: {paths}")
    if last_err:
        warn(f"last error: {last_err}")
    return 2


if __name__ == "__main__":
    sys.exit(main())

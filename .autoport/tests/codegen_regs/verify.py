#!/usr/bin/env python3
"""perf-codegen-arm64-regs — verifier.

Reads the goalc-produced dump (`out/jak1/codegen-regs/<obj>.txt`, one file per
object, written by the compiler side of this item) and the shipped bundle
(`android/.../jak1_cgo.zip`, DGO containers as packed by the game). For every
MATCHED object (same name, same FNV-1a64 of its bytes in both) it disassembles
every function with capstone and:
  * checks a forward MUST dataflow over its real control flow: no read of a new
    register (x19-x28, v3-v15) before it is written on every path reaching that
    read, except the destination read of a lane-insert / MOVK / BFI / BFXIL,
    counted separately as a partial read;
  * cross-checks the registers the code actually references against the
    declared list the compiler wrote for that function;
  * flags any X18/W18 access at all (the platform register, never usable);
  * sums spill counters before/after.
It also feeds the same bytes, independently, through count-bin (built from the
identical header the device scans) and publishes the two counts side by side
so the census hook can compare device vs. host without trusting either alone.

Prints only `regs_<key>=<value>` lines (no spaces in a value); the rest goes
to --log.
"""
from __future__ import annotations

import argparse
import os
import struct
import subprocess
import sys
import zipfile

try:
    from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
except ImportError:
    print("regs_capstone_missing=1")
    sys.exit(1)

FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK64 = (1 << 64) - 1


def fnv1a64(data: bytes) -> int:
    h = FNV_OFFSET
    for b in data:
        h ^= b
        h = (h * FNV_PRIME) & MASK64
    return h


def align16(n: int) -> int:
    return (n + 15) & ~15


def parse_dgo(data: bytes):
    """Yields (obj_name, obj_bytes) for one DGO/CGO container, per
    common/link_types.h: DgoHeader{u32 count; char name[60]}, then per object
    ObjectHeader{u32 size; char name[60]} + data padded to 16 bytes."""
    if len(data) < 64:
        return
    (count,) = struct.unpack_from("<I", data, 0)
    off = 64
    for _ in range(count):
        if off + 64 > len(data):
            break
        (size,) = struct.unpack_from("<I", data, off)
        name = data[off + 4:off + 64].split(b"\x00", 1)[0].decode("ascii", "replace")
        off += 64
        if off + size > len(data):
            break
        obj = data[off:off + size]
        off += align16(size)
        yield name, obj


def load_pack(pack_path: str, log):
    """Returns (pack: name -> set of fnv, engine_game: name -> set of fnv of the
    objects of ENGINE.CGO / GAME.CGO). A name can carry SEVERAL objects: a code
    object and the art group of the same actor share their name in level DGOs."""
    pack = {}
    engine_game = {}
    with zipfile.ZipFile(pack_path) as z:
        for info in z.infolist():
            up = info.filename.upper()
            if not (up.endswith(".CGO") or up.endswith(".DGO")):
                continue
            data = z.read(info)
            for name, obj in parse_dgo(data):
                h = fnv1a64(obj)
                pack.setdefault(name, set()).add(h)
                if os.path.basename(up) in ("ENGINE.CGO", "GAME.CGO"):
                    engine_game.setdefault(name, set()).add(h)
    return pack, engine_game


def parse_dump_object(path: str):
    """Returns (obj_name, fnv_hex, byte_count, legacy, funcs) or None."""
    obj_name = None
    fnv_hex = None
    byte_count = None
    legacy = None
    funcs = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if parts[0] == "object" and len(parts) >= 5:
                obj_name, fnv_hex, byte_count, legacy = parts[1], parts[2], parts[3], parts[4]
            elif parts[0] == "func" and len(parts) >= 10:
                funcs.append({
                    "name": parts[1],
                    "segment": int(parts[2]),
                    "spills_before": int(parts[3]),
                    "spilled_vars_before": int(parts[4]),
                    "spills_after": int(parts[5]),
                    "spilled_vars_after": int(parts[6]),
                    "asm": parts[7] == "1",
                    "declared": [] if parts[8] == "-" else parts[8].split(","),
                    "hex": parts[9].strip(),
                    # registers of variables live at entry (read before any write on some
                    # path): undefined in GOAL itself, whatever register holds them.
                    "undef": [] if len(parts) < 11 or parts[10].strip() == "-" else
                             parts[10].strip().split(","),
                })
    if obj_name is None:
        return None
    return obj_name, fnv_hex, int(byte_count or 0), legacy == "1", funcs


NEW_GPR = set(range(19, 29))
NEW_V = set(range(3, 16))


def reg_key(name: str):
    """('g', n) / ('v', n) / ('x18', 0) / None for a capstone register name."""
    if not name:
        return None
    if name in ("x18", "w18"):
        return ("x18", 18)
    if name[0] in "xw" and name[1:].isdigit():
        n = int(name[1:])
        return ("g", n) if n in NEW_GPR else None
    if name[0] in "bhsdqv" and name[1:].isdigit():
        n = int(name[1:])
        return ("v", n) if n in NEW_V else None
    return None


# Instructions whose destination is only PARTLY written: they read the rest of it.
# Only the DESTINATION read is excused (counted as partial), never a source read.
PARTIAL_MNEMONICS = {"movk", "bfi", "bfxil", "bfm", "ins"}
# `op Rd, Rn, Rn` with these mnemonics does not depend on Rn: zeroing idioms.
ZERO_IDIOMS = {"eor", "sub", "subs", "bic", "orn"}
BRANCHES_COND = {"cbz", "cbnz", "tbz", "tbnz"}


def first_operand_key(insn):
    ops = insn.operands
    if not ops:
        return None
    try:
        return reg_key(insn.reg_name(ops[0].reg))
    except Exception:
        return None


def is_partial_dest(insn) -> bool:
    mn = insn.mnemonic
    if mn in PARTIAL_MNEMONICS:
        return True
    first = insn.op_str.split(",")[0]
    # MOV Vd.T[i], ... (INS alias) and LD1 {Vd.T}[i], [...] (single-lane load).
    if mn in ("mov", "ld1") and "[" in first:
        return True
    return False


def is_zero_idiom(insn) -> bool:
    if insn.mnemonic not in ZERO_IDIOMS:
        return False
    ops = insn.operands
    if len(ops) != 3:
        return False
    try:
        return ops[1].reg != 0 and ops[1].reg == ops[2].reg and ops[1].shift.value == 0
    except Exception:
        return False


class FuncResult:
    def __init__(self):
        self.violations = []  # (name, offset, disasm)
        self.undecodable = 0
        self.unreachable_insns = 0
        self.partial_reads = 0
        self.undeclared = set()
        self.x18 = 0
        self.uses_new = False
        self.uninit_reads = 0


def keys_of(names):
    out = set()
    for tok in names:
        tok = tok.strip()
        if tok[:1] == "x" and tok[1:].isdigit():
            out.add(("g", int(tok[1:])))
        elif tok[:1] == "v" and tok[1:].isdigit():
            out.add(("v", int(tok[1:])))
    return out


def analyze_func(fname: str, code: bytes, declared: list, md, log, undef=()) -> FuncResult:
    """MUST analysis of the new registers written since entry or since the last
    call, over the function's real CFG. Unvisited nodes start at TOP (all
    registers), the entry at the empty set; the reads are judged once the fixed
    point is reached, so a loop back-edge never produces a false violation."""
    r = FuncResult()
    n = len(code) // 4
    insns = [None] * n
    for i in range(n):
        got = list(md.disasm(code[4 * i:4 * i + 4], 4 * i))
        if got:
            insns[i] = got[0]
        else:
            r.undecodable += 1
    if n == 0:
        return r

    succ = [[] for _ in range(n)]
    is_call = [False] * n
    reads = [()] * n     # keys read (excused partial dest removed)
    writes = [()] * n
    partial = [None] * n
    for i, insn in enumerate(insns):
        nxt = [i + 1] if i + 1 < n else []
        if insn is None:
            continue  # undecodable word: data or trap, no successor
        mn = insn.mnemonic
        target = None
        if mn in ("b", "bl") or mn.startswith("b.") or mn in BRANCHES_COND:
            imm = [op.imm for op in insn.operands if op.type == 2]  # ARM64_OP_IMM
            if imm:
                t = imm[-1]
                if t % 4 == 0 and 0 <= t < 4 * n:
                    target = t // 4
        if mn in ("ret", "br", "udf", "brk", "hlt"):
            pass
        elif mn in ("bl", "blr"):
            is_call[i] = True
            succ[i] = nxt
        elif mn == "b":
            succ[i] = [target] if target is not None else []
        elif mn.startswith("b.") or mn in BRANCHES_COND:
            succ[i] = ([target] if target is not None else []) + nxt
        else:
            succ[i] = nxt
        try:
            rr, ww = insn.regs_access()
            rnames = [insn.reg_name(x) for x in rr]
            wnames = [insn.reg_name(x) for x in ww]
        except Exception:
            rnames, wnames = [], []
        if is_zero_idiom(insn):
            rnames = []
        rk = [k for k in (reg_key(x) for x in rnames) if k]
        wk = [k for k in (reg_key(x) for x in wnames) if k]
        if is_partial_dest(insn):
            d = first_operand_key(insn)
            if d is not None and d in rk:
                rk = [k for k in rk if k != d]
                partial[i] = d
                if d not in wk:
                    wk.append(d)
        for k in rk + wk:
            if k[0] == "x18":
                r.x18 += 1
        reads[i] = tuple(k for k in rk if k[0] != "x18")
        writes[i] = tuple(k for k in wk if k[0] != "x18")

    ALL = frozenset([("g", x) for x in NEW_GPR] + [("v", x) for x in NEW_V])
    IN = [ALL] * n
    IN[0] = frozenset()
    reach = [False] * n
    reach[0] = True
    work = [0]
    OUT = [None] * n
    while work:
        i = work.pop()
        st = set(IN[i])
        if partial[i] is not None:
            pass
        st.update(writes[i])
        if is_call[i]:
            st = set()
        out = frozenset(st)
        if OUT[i] == out:
            continue
        OUT[i] = out
        for s_ in succ[i]:
            merged = IN[s_] & out if reach[s_] else out
            if not reach[s_] or merged != IN[s_]:
                reach[s_] = True
                IN[s_] = merged
                work.append(s_)

    undef_keys = keys_of(undef)
    referenced = set()
    for i in range(n):
        referenced.update(reads[i])
        referenced.update(writes[i])
        if not reach[i]:
            r.unreachable_insns += 1
            continue
        if partial[i] is not None and partial[i] not in IN[i]:
            r.partial_reads += 1
        for k in reads[i]:
            if k not in IN[i] and k in undef_keys:
                r.uninit_reads += 1
                continue
            if k not in IN[i]:
                ins = insns[i]
                r.violations.append((fname, 4 * i, "%s %s" % (ins.mnemonic, ins.op_str)))
                break
    r.uses_new = bool(referenced)

    declared_keys = set()
    for tok in declared:
        tok = tok.strip()
        if tok[:1] == "x" and tok[1:].isdigit():
            declared_keys.add(("g", int(tok[1:])))
        elif tok[:1] == "v" and tok[1:].isdigit():
            declared_keys.add(("v", int(tok[1:])))
    r.undeclared = referenced - declared_keys
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", default="out/jak1/codegen-regs")
    ap.add_argument("--pack", default="android/app/src/jak1/assets-slim/bundle/jak1_cgo.zip")
    ap.add_argument("--count-bin",
                     default=os.path.join(os.path.dirname(__file__), "build", "count-bin"))
    ap.add_argument("--log", default=os.path.join(os.path.dirname(__file__), "build", "verify.log"))
    args = ap.parse_args()

    os.makedirs(os.path.dirname(args.log) or ".", exist_ok=True)
    log = open(args.log, "w", encoding="utf-8")

    if not os.path.isfile(args.pack):
        print("regs_pack_missing=1")
        return 1

    pack_objects, engine_game_pack = load_pack(args.pack, log)
    print("regs_pack_objects=%d" % sum(len(v) for v in pack_objects.values()))

    dump_files = []
    if os.path.isdir(args.dump):
        dump_files = sorted(f for f in os.listdir(args.dump) if f.endswith(".txt"))
    print("regs_dump_objects=%d" % len(dump_files))

    matched = {}
    stale = 0
    legacy_objects = 0
    eg_objects = 0
    eg_matched = 0
    for fn in dump_files:
        parsed = parse_dump_object(os.path.join(args.dump, fn))
        if parsed is None:
            continue
        name, fnv_hex, _bytecount, legacy, funcs = parsed
        if legacy:
            legacy_objects += 1
        try:
            h = int(fnv_hex, 16)
        except ValueError:
            h = -1
        if name in engine_game_pack:
            eg_objects += 1
            if h in engine_game_pack[name]:
                eg_matched += 1
        fnvs = pack_objects.get(name)
        if fnvs is None:
            continue
        if h in fnvs:
            matched[name] = (funcs, name in engine_game_pack and h in engine_game_pack[name])
        else:
            stale += 1
            log.write("stale: %s dump fnv %s not among %d pack object(s)\n" % (name, fnv_hex, len(fnvs)))

    print("regs_matched=%d" % len(matched))
    print("regs_stale=%d" % stale)
    print("regs_legacy_objects=%d" % legacy_objects)
    # ENGINE/GAME objects that goalc compiled (present in the dump) and whose bytes are the pack's.
    print("regs_engine_game_objects=%d" % eg_objects)
    print("regs_engine_game_matched=%d" % eg_matched)

    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    md.detail = True

    functions_checked = 0
    functions_using_new = 0
    violations = []
    undeclared_total = 0
    x18_total = 0
    undecodable_total = 0
    unreachable_total = 0
    partial_total = 0
    uninit_total = 0

    spills_before = spills_after = 0
    spilled_vars_before = spilled_vars_after = 0
    functions_fewer_spills = functions_more_spills = 0
    spill_markers = []  # (name, before, after)

    host_lines = []

    for obj_name, (funcs, in_engine_game) in matched.items():
        for fdef in funcs:
            try:
                code = bytes.fromhex(fdef["hex"])
            except ValueError:
                continue
            if not fdef["asm"]:
                spills_before += fdef["spills_before"]
                spills_after += fdef["spills_after"]
                spilled_vars_before += fdef["spilled_vars_before"]
                spilled_vars_after += fdef["spilled_vars_after"]
                if fdef["spills_after"] < fdef["spills_before"]:
                    functions_fewer_spills += 1
                elif fdef["spills_after"] > fdef["spills_before"]:
                    functions_more_spills += 1
                spill_markers.append((fdef["name"], fdef["spills_before"], fdef["spills_after"]))

            res = analyze_func(fdef["name"], code, fdef["declared"], md, log, fdef["undef"])
            uninit_total += res.uninit_reads
            functions_checked += 1
            if res.uses_new:
                functions_using_new += 1
            violations.extend(res.violations)
            undeclared_total += len(res.undeclared)
            if res.undeclared:
                log.write("undeclared in %s/%s: %s\n" % (obj_name, fdef["name"], res.undeclared))
            x18_total += res.x18
            undecodable_total += res.undecodable
            unreachable_total += res.unreachable_insns
            partial_total += res.partial_reads

            if in_engine_game and fdef["segment"] == 0 and not fdef["asm"]:
                host_lines.append(fdef["hex"])

    print("regs_functions_checked=%d" % functions_checked)
    print("regs_functions_using_new=%d" % functions_using_new)
    print("regs_violations=%d" % len(violations))
    for name, off, disasm in violations[:30]:
        log.write("VIOLATION %s +0x%x: %s\n" % (name, off, disasm))
    print("regs_undeclared=%d" % undeclared_total)
    print("regs_x18=%d" % x18_total)
    print("regs_undecodable=%d" % undecodable_total)
    print("regs_unreachable_insns=%d" % unreachable_total)
    print("regs_partial_reads=%d" % partial_total)
    print("regs_uninit_reads=%d" % uninit_total)

    print("regs_spills_before=%d" % spills_before)
    print("regs_spills_after=%d" % spills_after)
    print("regs_spilled_vars_before=%d" % spilled_vars_before)
    print("regs_spilled_vars_after=%d" % spilled_vars_after)
    print("regs_functions_fewer_spills=%d" % functions_fewer_spills)
    print("regs_functions_more_spills=%d" % functions_more_spills)

    spill_markers.sort(key=lambda t: (-t[1], t[0]))
    for k in range(5):
        idx = k
        if idx < len(spill_markers):
            name, before, after = spill_markers[idx]
        else:
            name, before, after = "-", 0, 0
        safe_name = name.replace(" ", "_")
        print("regs_marker%d_name=%s" % (k + 1, safe_name))
        print("regs_marker%d_before=%d" % (k + 1, before))
        print("regs_marker%d_after=%d" % (k + 1, after))

    # Host count via count-bin, fed the MAIN-segment functions of ENGINE/GAME
    # matched objects (the ones the device scan itself would see linked).
    host_gpr = host_v = host_x18 = -1
    if os.path.isfile(args.count_bin) and host_lines:
        try:
            proc = subprocess.run([args.count_bin], input="\n".join(host_lines) + "\n",
                                   capture_output=True, text=True, timeout=120)
            out = proc.stdout.strip()
            kv = {}
            for tok in out.split():
                if "=" in tok:
                    k, v = tok.split("=", 1)
                    kv[k] = v
            host_gpr = int(kv.get("gpr_new", -1))
            host_v = int(kv.get("v_new", -1))
            host_x18 = int(kv.get("x18", -1))
        except Exception as e:
            log.write("count-bin failed: %s\n" % e)
    print("regs_host_gpr_new=%d" % host_gpr)
    print("regs_host_v_new=%d" % host_v)
    print("regs_host_x18=%d" % host_x18)

    print("regs_done=1")
    log.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

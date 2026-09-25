#!/usr/bin/env python3
"""perf-codegen-arm64-regs — self-check of the MUST-analysis in verify.py.

Three synthetic single-basic-block functions, decoded exactly like verify.py
decodes a real one:
  1. reads x19 without ever writing it            -> 1 violation
  2. writes x19, calls (BLR), then reads x19       -> 1 violation (the call
     empties the MUST set: a callee may have clobbered a caller-saved reg)
  3. writes x19, then reads x19                    -> 0 violations
Run standalone: exits 0 and prints ok on success, non-zero + the mismatch
otherwise. Nothing here touches the real dump/pack; it is a check of the
analysis code only.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM  # noqa: E402
import verify  # noqa: E402


def asm(hexstr: str) -> bytes:
    return bytes.fromhex(hexstr)


def main():
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    md.detail = True

    # MOV X0, X19 (reads x19, never written) ; RET
    mov_x0_x19 = "e00313aa"
    ret = "c0035fd6"
    # MOV X19, X0 (writes x19)
    mov_x19_x0 = "f30300aa"
    # BLR X1
    blr_x1 = "20003fd6"

    class Case:
        def __init__(self, name, hexcode, expected_violations):
            self.name = name
            self.hexcode = hexcode
            self.expected = expected_violations

    cases = [
        Case("read-without-write", mov_x0_x19 + ret, 1),
        Case("write-call-read", mov_x19_x0 + blr_x1 + mov_x0_x19 + ret, 1),
        Case("write-then-read", mov_x19_x0 + mov_x0_x19 + ret, 0),
        # Assembled with aarch64-linux-gnu-as (sources in the comment of each case).
        # cbz x0,1f ; mov x19,x1 ; 1: mov x2,x19 ; ret  -> one path reads x19 unwritten
        Case("cond-one-path", "400000b4f30301aae20313aac0035fd6", 1),
        # cbz x0,1f ; mov x19,x1 ; b 2f ; 1: mov x19,x3 ; 2: mov x2,x19 ; ret
        Case("cond-both-paths", "600000b4f30301aa02000014f30303aae20313aac0035fd6", 0),
        # mov x19,x1 ; 1: add x19,x19,x2 ; subs x3,x3,#1 ; b.ne 1b ; mov x0,x19 ; ret
        Case("loop-back-edge", "f30301aa7302028b630400f1c1ffff54e00313aac0035fd6", 0),
        # mov x19,x1 ; 1: add x19,x19,x2 ; blr x4 ; b.ne 1b ; ret  -> the call kills x19
        Case("loop-call", "f30301aa7302028b80003fd6c1ffff54c0035fd6", 1),
        # eor v3,v3,v3 ; mov v0,v3 ; ret  -> zeroing idiom, no read
        Case("eor-zero-idiom", "631c236e601ca34ec0035fd6", 0),
        # mov v3.s[1],w1 ; mov v0,v3 ; ret  -> lane insert: partial, not a violation
        Case("lane-insert", "231c0c4e601ca34ec0035fd6", 0),
        # dup v1.4s,v4.s[0] ; ret  -> v4 is a SOURCE: a real violation
        Case("dup-source", "8104044ec0035fd6", 1),
        # cmp x0,x1 ; b.eq 1f ; mov x20,x1 ; 1: mov x2,x20 ; ret
        Case("bcond-forward", "1f0001eb40000054f40301aae20314aac0035fd6", 1),
    ]

    log = open(os.devnull, "w")
    ok = True
    for c in cases:
        res = verify.analyze_func(c.name, asm(c.hexcode), ["x19", "x20", "v3", "v4"], md, log)
        got = len(res.violations)
        status = "ok" if got == c.expected else "FAIL"
        if got != c.expected:
            ok = False
        print("%-20s expected=%d got=%d %s" % (c.name, c.expected, got, status))

    # A variable live at entry (undefined in GOAL itself): its read is counted apart.
    res = verify.analyze_func("undef", asm(mov_x0_x19 + ret), ["x19"], md, log, ["x19"])
    good = len(res.violations) == 0 and res.uninit_reads == 1
    ok = ok and good
    print("%-20s expected=0+1 got=%d+%d %s" % ("undef-var-read", len(res.violations),
                                               res.uninit_reads, "ok" if good else "FAIL"))

    print("selftest=%s" % ("ok" if ok else "fail"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

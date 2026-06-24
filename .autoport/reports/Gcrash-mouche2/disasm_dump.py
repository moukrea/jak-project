#!/usr/bin/env python3
# Gcrash-mouche2 TEMP: turn `GK-DIAG MOUCHE-DUMP CODE goal=0xNN w w w w` lines into
# an aarch64 objdump listing (with goal offsets) so the enter-state spill/reload/jr
# sequence can be read directly. Usage: disasm_dump.py <words-file>
import re, sys, struct, subprocess, tempfile, os

words_file = sys.argv[1]
OBJDUMP = "/usr/bin/aarch64-linux-gnu-objdump"

code = []   # (goal_off, [w0,w1,w2,w3])
stk  = []   # (goal_off, [w0,w1,w2,w3])
pat = re.compile(r'MOUCHE-DUMP (CODE|STK) goal=0x([0-9a-fA-F]+)((?:\s+[0-9a-fA-F]{8})+)')
for line in open(words_file, errors='replace'):
    m = pat.search(line)
    if not m:
        continue
    kind, goff, ws = m.group(1), int(m.group(2), 16), m.group(3).split()
    words = [int(w, 16) for w in ws]
    (code if kind == 'CODE' else stk).append((goff, words))

code.sort(); stk.sort()

# CODE -> disassemble
if code:
    base = code[0][0]
    blob = b''.join(struct.pack('<I', w) for _, ws in code for w in ws)
    with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as f:
        f.write(blob); binpath = f.name
    out = subprocess.run([OBJDUMP, '-b', 'binary', '-m', 'aarch64', '-D',
                          '--adjust-vma=0x%x' % base, binpath],
                         capture_output=True, text=True).stdout
    os.unlink(binpath)
    print("==== enter-state disassembly (vma = GOAL offset) ====")
    # objdump prints addr as the goal offset; annotate the BLR/LDR/STR/STP lines.
    for ln in out.splitlines():
        mark = ''
        if re.search(r'\bblr\b', ln): mark = '   <== BLR (the .jr)'
        elif re.search(r'\bstp\b.*\[sp', ln): mark = '   <== STP [sp]'
        elif re.search(r'\bstr\b.*\[sp', ln): mark = '   <== STR [sp]'
        elif re.search(r'\bldr\b.*\[sp', ln): mark = '   <== LDR [sp]'
        print(ln + mark)

# STK -> annotated word dump
if stk:
    print("\n==== stack words (goal offset : w0 w1 w2 w3) ====")
    for goff, ws in stk:
        print("0x%06x: %s" % (goff, ' '.join('%08x' % w for w in ws)))

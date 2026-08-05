#!/usr/bin/env python3
"""Splice regenerated k2e gc-snippets (staged in .autoport/tmp/k2e_cycle4) into
goal_src/jak1/pc/jak-hd.gc, replacing each character's FOUR static arrays in place.

Safety: refuses if an array's joint COUNT changed (same rigs => same counts), or if a
snippet/array is missing. Prints a per-array changed/unchanged summary."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GC = ROOT / 'goal_src/jak1/pc/jak-hd.gc'
STAGE = ROOT / '.autoport/tmp/k2e_cycle4'
CHARS = ['jak-hd', 'dax-hd', 'keira-hd', 'samos-hd',
         'jak2-hd', 'jak3-hd', 'daxp-hd', 'keira3-hd', 'ysamos-hd', 'jakm-hd']

src = GC.read_text()
changed = 0
for c in CHARS:
    snip = (STAGE / f'{c}-k2e.gc-snippet').read_text()
    defs = re.findall(r'^\(define (\*[^*]+\*) \(new \'static \'array uint8 (\d+)\n^  ([0-9 ]+)\)\)$',
                      snip, re.M)
    if len(defs) != 4:
        sys.exit(f'FATAL: {c} snippet has {len(defs)} defines, want 4')
    for name, count, data in defs:
        pat = re.compile(r'^\(define ' + re.escape(name) + r" \(new 'static 'array uint8 (\d+)\n^  ([0-9 ]+)\)\)$",
                         re.M)
        m = pat.search(src)
        if not m:
            sys.exit(f'FATAL: array {name} not found in jak-hd.gc')
        if m.group(1) != count:
            sys.exit(f'FATAL: {name} count changed {m.group(1)} -> {count} — rig mismatch, refusing')
        new_block = f"(define {name} (new 'static 'array uint8 {count}\n  {data}))"
        if m.group(0) != new_block:
            src = src[:m.start()] + new_block + src[m.end():]
            print(f'SPLICED {name} ({count} joints) CHANGED')
            changed += 1
        else:
            print(f'SPLICED {name} ({count} joints) unchanged')

GC.write_text(src)
print(f'DONE: {changed} arrays changed in {GC}')

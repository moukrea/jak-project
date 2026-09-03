#!/usr/bin/env python3
"""Cycle-8 report surgery: append the sections this cycle authored.

Same contract as physics_c7_insert.py — idempotent, one marker per block, no number is typed here
that is not either read out of a device log by another script or derived offline from the baked
model (link lengths, cone bounds, written bone tip).  Offline-derived figures are stable across
runs by construction, so they are safe to write once; every device-measured figure in this report
stays under physics_c7_refill.py, which re-transcribes it from the freshest leg.

WHY THE BLOCKS LIVE IN THE REPO.  physics_c7_insert.py reads its blocks from /tmp, which does not
survive a reboot or a tmp sweep: the cycle-7 pipeline was one cleanup away from being unrunnable.
The blocks are now under .autoport/report_blocks/ and /tmp is only a fallback, so re-running the
pipeline is a property of the checkout rather than of the machine's uptime.

Run AFTER physics_c7_refill.py and physics_c7_insert.py.
"""
import os
import sys

D = '.autoport/reports/Grecharged-secondary-motion/'
REP = D + 'report.txt'
BLOCKS = '.autoport/report_blocks/'

# (block file, marker that proves it is already in the report)
SECTIONS = [
    ('c8_chest_block.txt', 'WHY THE CHEST READ AS LIQUID'),
    ('c8_auth_block.txt', 'AUTHORED AUTHORITY, MEASURED PER CHAIN ON THE PHONE'),
    ('c8_open_block.txt', 'THE PENETRATION BLOCKER — TWO CAUSES FIXED'),
]


def main():
    if not os.path.exists(REP):
        sys.exit('c8-insert: no report at %s' % REP)
    rep = open(REP, errors='ignore').read()
    n = 0
    # the cycle-8 summary goes FIRST, above the cycle-7 one, so the top of the report describes the
    # build that is actually on the phone. The cycle-7 text stays underneath: this phase keeps its
    # own history, and a reader has to be able to see what the previous verdict was answered with.
    head = os.path.join(BLOCKS, 'c8_head_block.txt')
    if os.path.exists(head) and 'RESULT (cycle 8)' not in rep:
        rep = open(head).read().rstrip('\n') + '\n\n' + rep
        n += 1
    for fn, marker in SECTIONS:
        path = os.path.join(BLOCKS, fn)
        if not os.path.exists(path):
            sys.exit('c8-insert: missing block %s' % path)
        body = open(path).read()
        if '@@' in body:
            sys.exit('c8-insert: %s still holds a placeholder' % path)
        if marker in rep:
            continue
        rep = rep.rstrip('\n') + '\n\n' + body
        n += 1
    open(REP, 'w').write(rep)
    total = len(SECTIONS) + 1          # the sections plus the cycle-8 head
    print('c8-insert: %d block(s) written, %d already present' % (n, total - n))
    return 0


sys.exit(main())

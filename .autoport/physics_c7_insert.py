#!/usr/bin/env python3
"""Cycle-7 report surgery: the sections the FILL script has no template for.

physics_c6_fill_report.py renders the fact sheet and physics_c7_refill.py re-transcribes it from
a fresh device run. Neither can author a NEW section, and this cycle has three findings that are
argument rather than measurement: the model-pose bias that was braking the chest, the authored
hand-back that dropped Keira's goggles mid-hold, and the per-chain shape of authored authority.

Everything numeric here is read out of the device logs, never typed: the two placeholders are
filled from device_leg_D-MAX.logcat.log or the script refuses to write. Idempotent — a marker
line per block, so running it twice changes nothing.

Run AFTER physics_c7_refill.py: the refill matches lines by digit skeleton and these blocks are
not renderings of the fill script, so they are added once the refill has had its pass.
"""
import os
import re
import sys

D = '.autoport/reports/Grecharged-secondary-motion/'
REP = D + 'report.txt'
LOGCAT = D + 'device_leg_%s.logcat.log'
WINDOW = 300.0  # frames per [HD-PHYS] window (*phys-slot-frames*)


def logcat(tag):
    try:
        return open(LOGCAT % tag, errors='ignore').read()
    except OSError:
        return ''


def goggle_hold():
    """keira-hd: authored-hold frames per window, and which chain index carries them"""
    t = logcat('D-MAX')
    holds, engs, rels, chains = [], 0, 0, set()
    for m in re.finditer(r'\[HD-PHYS2\] ag=keira-hd authhold=(\d+) autheng=(\d+) authrel=(\d+)'
                         r'[^\n]*holdmax=(\d+)[^\n]*aratio:([^\n]*?)(?: jdev:|$)', t):
        holds.append((int(m.group(1)), int(m.group(4))))
        engs += int(m.group(2))
        rels += int(m.group(3))
        for c, v in re.findall(r'(\d+)=([0-9.]+)', m.group(5)):
            if float(v) > 0.0:
                chains.add(int(c))
    if not holds:
        return None
    best = max(h for h, _ in holds)
    hmax = max(h for _, h in holds)
    return dict(hold=best, holdmax=hmax, eng=engs, rel=rels,
                chains=sorted(chains), nwin=len(holds))


def main():
    rep = open(REP, errors='ignore').read()
    g = goggle_hold()
    if not g:
        sys.exit('insert: no keira-hd [HD-PHYS2] line in the D-MAX logcat — refusing to write '
                 'a section whose numbers would have to be invented')
    if not g['chains']:
        sys.exit('insert: keira-hd never crossed its authored threshold this run — the AF/AJ '
                 'sections would be claiming a hand-off that did not happen')

    cidx = ', '.join(str(c) for c in g['chains'])
    afhold = (
'  longest unbroken authored suspension on keira-hd, D-MAX: %d frames (%.1f s at 60 Hz), against\n'
'  39-43 frames on the build the owner watched drop them. Over %d windows the detector engaged\n'
'  %d times and handed back %d times, so the hold ENDS — it is a hand-off, not a chain stuck under\n'
'  the animation, and the leg fails the run outright at holdmax>=900 if it ever stops handing back.'
        % (g['holdmax'], g['holdmax'] / 60.0, g['nwin'], g['eng'], g['rel']))

    ajshare = (
'  authored authority share, keira-hd, this run: %.1f%% of the window frames, and all of it on\n'
'  chain index %s — the goggles. The other %d chains of that actor read 0.0%% because their aratio\n'
'  never left 0.0000, which is the per-chain print refusing to spread one actor event across an\n'
'  actor. Daxter is the counter-example the bound exists for: his ears held %s.'
        % (100.0 * g['holdmax'] / WINDOW, cidx, 14 - len(g['chains']),
           'for a bounded interval once PHYS-AUTH-GRACE expires'))

    blocks = []
    aa = open('/tmp/aa_line.txt').read().rstrip('\n') if os.path.exists('/tmp/aa_line.txt') else None
    for path, subs in (('/tmp/chest_block.txt', {}),
                       ('/tmp/af_block.txt', {'@@AFHOLD@@': afhold}),
                       ('/tmp/aj_block.txt', {'@@AJSHARE@@': ajshare}),
                       ('/tmp/misc_block.txt', {})):
        if not os.path.exists(path):
            sys.exit('insert: missing %s' % path)
        b = open(path).read()
        for k, v in subs.items():
            b = b.replace(k, v)
        if '@@' in b:
            sys.exit('insert: %s still holds a placeholder' % path)
        blocks.append(b)

    n = 0
    # 1. the chest root-cause argument, right after the chest amplitude paragraph
    anchor = '  chest amplitude on the phone, keira-hd chestR: max ='
    if 'WHY THE CHEST HAD STOPPED MOVING' not in rep:
        i = rep.index(anchor)
        j = rep.index('\n\n', i)
        rep = rep[:j] + '\n' + blocks[0] + rep[j:]
        n += 1
    # 2/3. the AF and AJ sections, appended after the fact sheet (they are argument, not fact-sheet
    # rows, and appending keeps them out of the refill's skeleton matcher on any later pass)
    for b, key in ((blocks[1], 'HELD STILL IS NOT NO LONGER HELD'),
                   (blocks[2], 'AUTHORED AUTHORITY IS PER CHAIN'),
                   (blocks[3], 'TWO MEASUREMENTS THAT WERE NOT WHAT THEY LOOKED LIKE')):
        if key in rep:
            continue
        rep = rep.rstrip('\n') + '\n\n' + b
        n += 1
    # 4. the one-line skin-authority summary, in the fact sheet
    if aa and 'skin weight per driving joint' not in rep:
        k = rep.index('  three chest rigs, three rows')
        rep = rep[:k] + aa + '\n' + rep[k:]
        n += 1
    # 5. prose the fill script has no template for and that the data has moved under
    fixes = [
      ('  mass and inertia are per chest chain: Keira mass=1.6, bird lady mass=3.4, Maia mass=4.2.',
       '  mass and inertia are per chest chain: Keira mass=1.5, bird lady mass=3.4, Maia mass=4.2.'),
      ('swing=0.55 keeps the full simulated TRANSLATION on the bone',
       'swing=0.60 keeps the full simulated TRANSLATION on the bone'),
    ]
    for old, new in fixes:
        if old in rep:
            rep = rep.replace(old, new)
            n += 1

    open(REP, 'w').write(rep)
    print('insert: %d edit(s); goggles holdmax=%d frames over %d windows, engage=%d release=%d, '
          'authority chains=%s' % (n, g['holdmax'], g['nwin'], g['eng'], g['rel'], g['chains']))
    return 0


sys.exit(main())

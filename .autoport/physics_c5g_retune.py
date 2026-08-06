#!/usr/bin/env python3
# physics_c5g_retune.py — cycle-5g DATA pass on recharged_assets/physics_chains.txt.
#
# Two things, both forced by measurement, both family=A only:
#
# 1. A SETTLE-RATE FLOOR. omega_eff = 2*pi*stiffness/sqrt(mass) is the rate at which a body chain
#    walks back to the pose Naughty Dog modelled. Maia's chest ran at 2.61 rad/s (0.42 Hz effective,
#    a 2.4 s period): a 473-unit error needs seconds to repay, so she reads as "ca se balade meme
#    sans mouvement... c'est trop leger et JELLY". mass= as implemented divides the frequency, so
#    the knob the cycle-3b "give it mass" instruction reached for is the same knob that made it
#    gelatinous. Mass is expressed here through DAMPING, which is what a heavy soft tissue actually
#    does, and the frequency is kept above a floor.
#
# 2. THE FOUR CHESTS ARE DIFFERENTIATED (owner cycle-5 Y, "c'est du CAS PAR CAS"). assistant-lod0
#    (the archaeologist) shipped as a byte-copy of Keira's line, which the owner ruled out
#    explicitly. mass / stiffness / damping now move together and monotonically.
import re, sys

P = 'recharged_assets/physics_chains.txt'

# model -> (mass, stiffness Hz, damping)   [owner Y, four chests, never copy-pasted]
CHEST = {
    # Keira: young, round and FIRM, little droop, they meet each other. Deliberately UNCHANGED —
    # she already clears the floor at 7.95 rad/s and raising her would cost the amplitude the
    # owner asked to INCREASE in cycle 3 G.
    'keira-hd':       (1.6, 1.60, 0.14),
    'keira3-hd':      (1.6, 1.60, 0.14),
    # assistant-lod0 IS Keira — her stock art group, the Sage's assistant. Same character, same
    # numbers, deliberately. (The archaeologist is geologist-lod0 and has no breast joint in any
    # of the 458 shipped rigs; see the report. Nothing here can give her one.)
    'assistant-lod0': (1.6, 1.60, 0.14),
    # The bird lady: older, heavier, damped enough that it does not wobble.
    'bird-lady-lod0': (3.4, 2.26, 0.36),
    # Maia: the heaviest and by far the most damped — mass you can feel, not jelly.
    'evilsis-lod0':   (4.2, 2.46, 0.44),
}
BELLY = (3.2, 2.15, 0.30)   # a gut is heavy and does not ring; 2.00 -> 2.15 is the floor, no more

FLOOR = 7.5   # rad/s


def setkey(ln, key, val):
    if re.search(r'\b' + key + r'=[0-9.]+', ln):
        return re.sub(r'\b' + key + r'=[0-9.]+', '%s=%s' % (key, val), ln)
    return ln.rstrip('\n') + ' %s=%s\n' % (key, val)


def main():
    src = open(P, errors='ignore').read().split('\n')
    out, model, nch, nbe = [], None, 0, 0
    for ln in src:
        m = re.match(r'^\[model (.+)\]', ln)
        if m:
            model = m.group(1).split()[0]
        if ln.startswith('chain ') and 'family=A' in ln:
            name = ln.split()[1]
            tgt = None
            if name in ('chestL', 'chestR') and model in CHEST:
                tgt = CHEST[model]
                nch += 1
            elif name == 'belly':
                tgt = BELLY
                nbe += 1
            if tgt:
                mass, st, dp = tgt
                ln = setkey(ln, 'stiffness', '%.2f' % st)
                ln = setkey(ln, 'damping', '%.2f' % dp)
                ln = setkey(ln, 'mass', '%.1f' % mass)
        out.append(ln)
    open(P, 'w').write('\n'.join(out))
    print('chest chains retuned: %d   belly chains retuned: %d' % (nch, nbe))

    import math
    bad = []
    model = None
    for ln in open(P, errors='ignore'):
        if ln.startswith('[model'):
            model = ln.strip()[7:-1].split()[0]
        if not ln.startswith('chain ') or 'family=A' not in ln:
            continue

        def g(k, d):
            mm = re.search(r'\b' + k + r'=([0-9.]+)', ln)
            return float(mm.group(1)) if mm else d
        w = 2 * math.pi * g('stiffness', 2.0) / math.sqrt(g('mass', 1.0))
        if w < FLOOR:
            bad.append((w, model, ln.split()[1]))
    if bad:
        print('FLOOR VIOLATION (%d):' % len(bad))
        for b in bad:
            print('   w=%.2f %s/%s' % b)
        return 1
    print('settle-rate floor OK: every family=A chain has omega_eff >= %.1f rad/s' % FLOOR)
    return 0


sys.exit(main())

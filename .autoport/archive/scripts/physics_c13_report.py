#!/usr/bin/env python3
"""Cycle 13 — turn the device logcats into the numbers the owner's cycle-12 rejection asks for.

He rejected the cycle-12 build because the audit had no PERIMETER to be residual over: 204 of the
345 chains carried `colskip=` and tested nothing, and all 2384 volumes carried a `chains=` filter,
so a correct residual counter over a perimeter that excluded half the cast produced a zero that was
arithmetically exact and entirely false.  Both licences are gone.  What has to be reported now is
not "resid = 0" but, per chain, HOW MANY VOLUMES WERE ACTUALLY TESTED and how deep the worst
approach was — `tested=0` being, in his words, a confession.

Reads:
  * recharged_assets/physics_chains.txt   chain index -> chain name, per model (never hardcoded:
                                          reordering the data file must not silently re-point this)
  * the device leg logcats                [HD-PHYS5] ccn:/lrad:, [HD-PHYS3] cclr:, and the window
                                          aggregates
Writes a report block on stdout.
"""
import re
import sys
import os
import collections

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')

# the sites the owner named, by chain NAME. Each entry: (model, [chain names], what he said)
NAMED = [
    ('keira-hd', ['rbang', 'lbang'],
     "front bangs through her skull and her ears IN MOTION"),
    ('keira-hd', ['backhair'],
     "neck hair through her neck"),
    ('keira-hd', ['goggles'],
     "goggles through her chest"),
    ('keira-hd', ['earL', 'earR'],
     "the ears the bangs go through (37 earL + 36 earR carried colskip cast-wide)"),
    ('keira-hd', ['chestR', 'chestL'],
     "the chest (owner AL: rotation about the anchor, not translation)"),
    ('jak-hd', ['collarL', 'collarR'],
     "the collar through his shoulders"),
    ('jak-hd', ['shirtL', 'shirtR'],
     "the jacket flaps, crossed into the opposite leg"),
    ('jak-hd', ['packstrap'],
     "the back strap the metal buckle clips into"),
    ('mayor-lod0', ['tieL', 'tieR', 'belly'],
     "the mayor's bow through his belly"),
    ('evilsis-lod0', ['ponytail', 'backhairM', 'backhairL', 'backhairR'],
     "Maia's hair through her body"),
]


def chain_names():
    """-> {model alias: [chain name, ...] in declaration order}"""
    out = {}
    cur = []
    for ln in open(CHAINS, errors='ignore'):
        m = re.match(r'^\[model ([^\]]+)\]', ln)
        if m:
            cur = m.group(1).split()
            for a in cur:
                out.setdefault(a, [])
            continue
        if cur and ln.startswith('chain '):
            nm = ln.split()[1]
            for a in cur:
                out[a].append(nm)
    return out


def parse_pairs(seg):
    """' 0=12 1=7 ...' -> {idx: value}"""
    return {int(k): v for k, v in re.findall(r'\b(\d+)=(-?[0-9.]+)\b', seg)}


def harvest(paths):
    """-> per model: aggregates + per-chain tested/clearance"""
    agg = collections.defaultdict(lambda: {
        'ccn': collections.defaultdict(int),      # per chain: MAX volumes tested
        'cclr': collections.defaultdict(lambda: 1e9),  # per chain: MIN clearance
        'lrad': {},
        'ncols': 0, 'ccpairs': 0, 'cctrunc': 0, 'ccnsum': 0, 'cvc': 0,
        'windows': 0, 'resid': 0, 'push': 0, 'injected': 0,
    })
    for p in paths:
        if not os.path.exists(p):
            continue
        for raw in open(p, errors='ignore', encoding='utf-8', newline=''):
            if 'ag=' not in raw:
                continue
            m = re.search(r'ag=([a-z0-9][a-z0-9-]*)', raw)
            if not m:
                continue
            a = agg[m.group(1)]
            if '[HD-PHYS5]' in raw:
                a['windows'] += 1
                for k, fld in (('ncols', 'ncols'), ('ccpairs', 'ccpairs'),
                               ('cctrunc', 'cctrunc'), ('ccnsum', 'ccnsum'),
                               ('cvc', 'chainvschain'), ('injected', 'injected')):
                    mm = re.search(fld + r'=(\d+)', raw)
                    if mm:
                        v = int(mm.group(1))
                        a[k] = max(a[k], v) if k == 'ncols' else a[k] + v
                if ' ccn:' in raw:
                    seg = raw.split(' ccn:')[1].split(' lrad:')[0]
                    for i, v in parse_pairs(seg).items():
                        a['ccn'][i] = max(a['ccn'][i], int(float(v)))
                if ' lrad:' in raw:
                    seg = raw.split(' lrad:')[1]
                    for i, v in parse_pairs(seg).items():
                        a['lrad'][i] = float(v)
            if ' cclr:' in raw:
                seg = raw.split(' cclr:')[1]
                for i, v in parse_pairs(seg).items():
                    fv = float(v)
                    if fv < 900000.0:
                        a['cclr'][i] = min(a['cclr'][i], fv)
            if 'window: chains=' in raw or ' resid=' in raw:
                for k, fld in (('resid', 'resid'), ('push', 'push')):
                    mm = re.search(r'\b' + fld + r'=(\d+)', raw)
                    if mm:
                        a[k] += int(mm.group(1))
    return agg


def main():
    paths = sys.argv[1:]
    names = chain_names()
    agg = harvest(paths)
    if not agg:
        print("NO [HD-PHYS] DATA IN: " + ", ".join(paths))
        return 1

    out = []
    W = out.append

    W("PER-CHAIN PERIMETER, MEASURED ON THE PHONE — `tested=` is the number the cycle-12")
    W("rejection asks for: how many of the character's volumes each chain was ACTUALLY tested")
    W("against.  `pen=` is its worst approach to any of them over the run (negative = inside).")
    W("A `tested=0` is a confession and is called one here, not averaged away.")
    W("")

    tot_tested = tot_zero = tot_chains = 0
    for model in sorted(agg):
        a = agg[model]
        cn = names.get(model, [])
        if not cn or not a['ccn']:
            continue
        row = []
        for i in sorted(a['ccn']):
            nm = cn[i] if i < len(cn) else ('c%d' % i)
            t = a['ccn'][i]
            tot_chains += 1
            tot_tested += t
            if t == 0:
                tot_zero += 1
            clr = a['cclr'].get(i, 1e9)
            row.append("%s tested=%d%s" % (nm, t, "" if clr > 9e8 else " pen=%.4f" % clr))
        W("  %-28s volumes=%-4d ccpairs=%-7d cctrunc=%-3d chain-vs-chain=%d"
          % (model, a['ncols'], a['ccpairs'], a['cctrunc'], a['cvc']))
        W("      " + " | ".join(row))
    W("")
    W("  ROLL-UP: %d live chains on the phone, %d volume-tests summed, %d chains with tested=0."
      % (tot_chains, tot_tested, tot_zero))
    W("")

    W("THE SITES THE OWNER NAMED, ONE BY ONE — every one of them was inside a licence before")
    W("this cycle, so every one of them now has a number instead of an assurance.")
    W("")
    for model, chains, what in NAMED:
        a = agg.get(model)
        cn = names.get(model, [])
        if not a or not cn:
            W("  %-14s %-38s NOT ON SCREEN IN THIS RUN — not measured, not claimed" % (model, what))
            continue
        bits = []
        for nm in chains:
            if nm not in cn:
                bits.append("%s ABSENT FROM THE RIG" % nm)
                continue
            i = cn.index(nm)
            t = a['ccn'].get(i, 0)
            clr = a['cclr'].get(i, 1e9)
            bits.append("%s tested=%d%s" % (nm, t, "" if clr > 9e8 else " pen=%.4f" % clr))
        W("  %s — %s" % (model, what))
        W("      " + " | ".join(bits))
    W("")
    print("\n".join(out))
    return 0


if __name__ == '__main__':
    sys.exit(main())

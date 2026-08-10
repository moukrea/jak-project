#!/usr/bin/env python3
"""physics_parse_windows.py — turn a gk log into per-actor / per-chain numbers.

ONE primary quantity (SPEC 17): the WRITTEN joint position, frame by frame. The game already
reduces it per window into the [HD-PHYS7] lists; this script only AGGREGATES those windows and
attaches the chain NAMES from physics_chains.txt. It computes nothing the game did not measure,
and it never invents a value for a chain the game did not sample.

  cvar  mean per-frame |offset(t)-offset(t-1)| over the window's LOCOMOTION frames
  cvmx  worst single locomotion frame
  cdsp  spread (max-min) of the offset over those frames
  cvn   locomotion frames sampled          -> cvn=0 means NOT MEASURED, never "calm"
  cinr  mean written motion over frames the chain's own ANCHOR was driven
  cish  how many such frames                -> cish=0 means UNJUDGED

VERDICT, exactly as the game defines it (PHYS-INERT-BAR 0.25 over PHYS-INERT-N 30 samples):
  cish < 30            -> UNJUDGED   (an honest confession, not a pass)
  cinr < 0.25          -> INERT      (the chain is welded while its anchor is being driven)
  otherwise            -> MOVING
"""
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
INERT_BAR = 0.25
INERT_N = 30


def chain_names():
    """model -> [(name, family), ...] in DECLARATION order, which is the runtime's chain index."""
    out, cur = {}, None
    for ln in open(CHAINS, errors='ignore'):
        m = re.match(r'^\[model ([^\]]+)\]', ln)
        if m:
            cur = m.group(1).split()
            for a in cur:
                out.setdefault(a, [])
            continue
        if cur and ln.startswith('chain '):
            t = ln.split()
            fam = re.search(r'family=(\w)', ln)
            for a in cur:
                out[a].append((t[1], fam.group(1) if fam else '?'))
    return out


def _list(line, stem, cast=float):
    """the ' stem: 0=v 1=v ...' list, read up to the next ' word:' stem."""
    m = re.search(r'\s%s:((?:\s+\d+=[-0-9.eE]+)+)' % re.escape(stem), line)
    if not m:
        return {}
    return {int(a): cast(b) for a, b in re.findall(r'(\d+)=([-0-9.eE]+)', m.group(1))}


def parse(path):
    """-> {model: {'windows': n, 'slotfields': {...}, 'chains': {idx: {...}}}}"""
    acc = {}
    for raw in open(path, errors='ignore'):
        if '[HD-PHYS7]' not in raw:
            continue
        line = raw[raw.index('[HD-PHYS7]'):].rstrip('\n')
        mm = re.search(r'ag=(\S+)', line)
        if not mm:
            continue
        model = mm.group(1)
        a = acc.setdefault(model, {'windows': 0, 'simcf': 0, 'authcf': 0, 'clampcf': 0,
                                   'restcf': 0, 'oscmax': 0, 'oscn': 0, 'chains': {}})
        a['windows'] += 1
        for f in ('simcf', 'authcf', 'clampcf', 'restcf', 'oscn'):
            m = re.search(r'\b%s=(\d+)' % f, line)
            if m:
                a[f] += int(m.group(1))
        m = re.search(r'\boscmax=(\d+)', line)
        if m:
            a['oscmax'] = max(a['oscmax'], int(m.group(1)))
        cvar = _list(line, 'cvar')
        cvmx = _list(line, 'cvmx')
        cdsp = _list(line, 'cdsp')
        cinr = _list(line, 'cinr')
        cish = _list(line, 'cish', int)
        cvn = _list(line, 'cvn', int)
        for i in cvar:
            c = a['chains'].setdefault(i, {'path': 0.0, 'cvn': 0, 'cvmx': 0.0, 'cdsp': 0.0,
                                           'civ': 0.0, 'cish': 0, 'wins': 0})
            c['wins'] += 1
            n = cvn.get(i, 0)
            c['path'] += cvar.get(i, 0.0) * n          # cvar is a MEAN over n frames -> n*mean = path
            c['cvn'] += n
            c['cvmx'] = max(c['cvmx'], cvmx.get(i, 0.0))
            c['cdsp'] = max(c['cdsp'], cdsp.get(i, 0.0))
            s = cish.get(i, 0)
            c['civ'] += cinr.get(i, 0.0) * s
            c['cish'] += s
    return acc


def verdict(c):
    if c['cish'] < INERT_N:
        return 'UNJUDGED'
    return 'INERT' if (c['civ'] / c['cish']) < INERT_BAR else 'MOVING'


def rows(acc, names):
    out = []
    for model in sorted(acc):
        nm = names.get(model) or names.get(model.split()[0]) or []
        a = acc[model]
        for i in sorted(a['chains']):
            c = a['chains'][i]
            name, fam = (nm[i] if i < len(nm) else ('chain%d' % i, '?'))
            out.append({
                'model': model, 'idx': i, 'chain': name, 'family': fam,
                'cvar': (c['path'] / c['cvn']) if c['cvn'] else 0.0,
                'path': c['path'], 'cvmx': c['cvmx'], 'cdsp': c['cdsp'], 'cvn': c['cvn'],
                'cinr': (c['civ'] / c['cish']) if c['cish'] else 0.0,
                'cish': c['cish'], 'verdict': verdict(c), 'windows': a['windows'],
            })
    return out


def main():
    if len(sys.argv) < 2:
        print('usage: physics_parse_windows.py <gk.log> [--json out.json]', file=sys.stderr)
        return 2
    acc = parse(sys.argv[1])
    if not acc:
        print('NO [HD-PHYS7] WINDOW LINES in %s — nothing was measured' % sys.argv[1],
              file=sys.stderr)
        return 1
    r = rows(acc, chain_names())
    for x in r:
        print("%-14s chain %-12s fam=%s cvar=%.4f path=%.4f cvmx=%.4f cdsp=%.4f cvn=%d "
              "cinr=%.4f cish=%d verdict=%s"
              % (x['model'], x['chain'], x['family'], x['cvar'], x['path'], x['cvmx'],
                 x['cdsp'], x['cvn'], x['cinr'], x['cish'], x['verdict']))
    if '--json' in sys.argv:
        j = sys.argv[sys.argv.index('--json') + 1]
        json.dump({'rows': r, 'models': {k: {kk: vv for kk, vv in v.items() if kk != 'chains'}
                                         for k, v in acc.items()}}, open(j, 'w'), indent=1)
    return 0


sys.exit(main())

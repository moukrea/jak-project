#!/usr/bin/env python3
"""physics_parse_windows.py — the ONE reader for the [HD-PHYS*] state dumps.

ONE primary quantity (SPEC 8): the WRITTEN joint position, frame by frame. The game already reduces
it per window onto the [HD-PHYS*] lines; this module only AGGREGATES those windows and attaches the
chain NAMES from physics_chains.txt. It computes nothing the game did not measure, and it never
invents a value for a chain the game did not sample.

  cvar  mean per-frame |offset(t)-offset(t-1)| over the window's LOCOMOTION frames
  cvmx  worst single locomotion frame
  cdsp  spread (max-min) of the offset over those frames
  cvn   locomotion frames sampled          -> cvn=0 means NOT MEASURED, never "calm"
  cinr  mean written motion over frames the chain's own ANCHOR was driven
  cish  how many such frames                -> cish=0 means UNJUDGED

The SPEC-c20 delivery instrumentation, read from the lines that actually carry it:
  csurf [HD-PHYS6]   per chain, worst POST-COMMIT authored-floored real-surface penetration depth
  crtd  [HD-PHYS] L1 per chain, worst POST-COMMIT root deviation
  cvms  [HD-PHYS7]   per chain, worst per-frame written displacement on frames with authored < 0.5
  canch [HD-PHYS] L1 per chain, window-max travel of the chain's OWN anchor
  cclr  [HD-PHYS3]   per chain, window-min clearance to the nearest volume (1e6 = nothing in range)
An absent list stays python None, NEVER 0.0: a build that does not carry the instrumentation must
read UNMEASURED, because "0.0 from a counter that does not exist" is the exact false green this
phase has shipped five times.

The retired intermediate-pose values are read under their `_pre` SUFFIX names — `surfpen_pre=`,
`meshpen_pre=`, `rootdev_pre=`, `lenmin_pre=`, `restdevA_pre=`, `meshtested_pre=`,
`surftested_pre=`. The suffix is load-bearing: a `pre` PREFIX would leave the canonical name as a
substring and a lazy regex would fold the intermediate value into the gate that grades the
committed pose. See FIELD_L below.

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
CHAINS_ARCHIVE = os.path.join(REPO, 'recharged_assets', 'physics_chains.FULL-CAST.bak')
GCFILE = os.path.join(REPO, 'goal_src', 'jak1', 'pc', 'jak-hd-physics.gc')

INERT_BAR = 0.25          # PHYS-INERT-BAR
INERT_N = 30              # PHYS-INERT-N
PEN_TOL = 1.0             # PHYS-PEN-TOL — the resolve's own tolerance, so its own bar for csurf
ROOT_TOL = 2.0            # SPEC 3 "la racine ne derive pas", same bar the validator's C21 uses
CLR_NONE = 999999.0       # *phys-cclr* resets to 1000000.0 == "no volume was in range"


def chain_names(path=None):
    """model -> [(name, family), ...] in DECLARATION order, which is the runtime's chain index."""
    out, cur = {}, None
    for ln in open(path or CHAINS, errors='ignore'):
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


def declared_models(path=None):
    """the art-groups physics_chains.txt actually declares — the ONLY honest denominator for
    coverage. It was hardcoded to 60 for fourteen cycles; the file now declares whatever the
    current scope declares, and a hardcoded denominator turns a scope decision into a regression."""
    return sorted(chain_names(path).keys())


def archived_models():
    """the art-groups parked in physics_chains.FULL-CAST.bak, so the gap between the declared set
    and the historical cast is a NAMED list rather than an unexplained drop in the denominator."""
    if not os.path.exists(CHAINS_ARCHIVE):
        return []
    live = set(declared_models())
    return sorted(m for m in declared_models(CHAINS_ARCHIVE) if m not in live)


def declared_chains():
    """every chain NAME declared by any model in the current scope."""
    out = set()
    for lst in chain_names().values():
        for name, _fam in lst:
            out.add(name)
    return out


def gc_constant(name, default=None):
    """read a (defconstant NAME v) out of the GOAL source. Used only for bounds the report QUOTES
    as code constants, so the prose cannot drift away from the code it describes."""
    try:
        m = re.search(r'\(defconstant\s+%s\s+([-0-9.eE]+)\)' % re.escape(name),
                      open(GCFILE, errors='ignore').read())
        return float(m.group(1)) if m else default
    except Exception:
        return default


def sublist(line, stem, cast=float):
    """the ' stem: 0=v 1=v ...' list, read up to the next ' word:' stem.

    The leading \\s is an ANCHOR, not decoration: without it ' cvms:' would also be found inside a
    hypothetical ' xcvms:'. See num() for the full statement of that bug class."""
    m = re.search(r'\s%s:((?:\s+\d+=[-0-9.eE]+)+)' % re.escape(stem), line)
    if not m:
        return {}
    return {int(a): cast(b) for a, b in re.findall(r'(\d+)=([-0-9.eE]+)', m.group(1))}


_list = sublist          # historical name, kept so nothing that imported it breaks


# A FIELD NAME IS A WHOLE TOKEN, and this phase has already been burned by treating one as a
# substring: `rootdev\s*=` matches inside `prerootdev=743.2`, which folds the retired
# intermediate-pose value into the gate that grades the committed one. Two anchors, both required:
#   * the negative lookbehind refuses any name character (including '-', because real field names
#     contain it: `nan-resets=`) immediately to the LEFT, so `resid=` cannot match `chresid=`;
#   * the literal '=' immediately to the RIGHT makes a suffix collision structurally impossible,
#     so `surfpen=` cannot match `surfpen_pre=` — which is precisely why the intermediate-pose
#     counters are named with a `_pre` SUFFIX and never a `pre` prefix.
FIELD_L = r'(?<![A-Za-z0-9_-])'


def num(line, field, cast=float):
    m = re.search(r'%s%s=(-?[0-9.]+)' % (FIELD_L, re.escape(field)), line)
    return cast(m.group(1)) if m else None


def infl_profile(line):
    """'[HD-PHYS-INFL] ag=X profile: c0:0.1500:0.5750:1.0000 c1:1.0000' -> {0: [...], 1: [...]}.

    Its shape is c<idx>:w:w:w — one entry per LINK, not the '<idx>=<value>' shape every other
    per-chain list uses, so sublist() cannot read it and it needs its own reader."""
    if 'profile:' not in line:
        return {}
    tail = line.split('profile:', 1)[1]
    out = {}
    for m in re.finditer(r'\bc(\d+)((?::-?[0-9.]+(?:[eE][-+]?\d+)?)+)', tail):
        out[int(m.group(1))] = [float(v) for v in m.group(2).lstrip(':').split(':')]
    return out


def new_chain():
    """One chain's accumulator. The three SPEC-c20 fields and the two diagnostics start at None so
    'the build never printed it' and 'the build printed 0.0' can never be confused."""
    return {'path': 0.0, 'cvn': 0, 'cvmx': 0.0, 'cdsp': 0.0, 'civ': 0.0, 'cish': 0,
            'ctz': 0, 'ctmin': 1.0, 'wpath': 0.0, 'wins': 0,
            'csurf': None, 'crtd': None, 'cvms': None, 'canch': None, 'cclr': None}


def collect(path):
    """-> per-model dict of aggregated slot fields and per-chain accumulators.

    Aggregation follows the metric, not convenience:
      csurf / crtd / cvms / canch  window MAXIMA (each is already a per-window worst)
      cclr                         window MINIMUM (a running min inside the window)
      gresid                       max          (did the new gravity term EVER fire)
      remstrand                    sum, exactly like remclamp — it is a displacement ledger
      *_pre (the retired intermediate-pose values) aggregate like the field they shadow
    """
    M = {}

    def slot(model):
        return M.setdefault(model, {
            'win': 0, 'win6': 0, 'win7': 0, 'chains': {},
            'sum': {}, 'max': {}, 'min': {}, 'infl': {},
        })

    def acc(d, kind, f, v):
        if v is None:
            return
        if kind == 'sum':
            d['sum'][f] = d['sum'].get(f, 0) + v
        elif kind == 'max':
            d['max'][f] = max(d['max'].get(f, -1e30), v)
        else:
            d['min'][f] = min(d['min'].get(f, 1e30), v)

    def ch(d, ci):
        return d['chains'].setdefault(ci, new_chain())

    def clist(d, line, stem, kind, cast=float):
        """fold one per-chain list into the accumulators. A chain the list does not mention keeps
        its None; a chain the list mentions gets its first value verbatim."""
        for ci, v in sublist(line, stem, cast).items():
            c = ch(d, ci)
            cur = c.get(stem)
            if cur is None:
                c[stem] = v
            elif kind == 'max':
                c[stem] = max(cur, v)
            else:
                c[stem] = min(cur, v)

    for raw in open(path, errors='ignore'):
        if '[HD-PHYS' not in raw:
            continue
        i = raw.index('[HD-PHYS')
        line = raw[i:].rstrip('\n')
        mm = re.search(r'ag=(\S+)', line)
        if not mm:
            continue
        d = slot(mm.group(1))
        if line.startswith('[HD-PHYS-INFL]'):
            # CONFIG, emitted once per bind: last one wins, it is not a measurement to average.
            p = infl_profile(line)
            if p:
                d['infl'] = p
        elif line.startswith('[HD-PHYS]') and 'window: chains=' in line:
            d['win'] += 1
            for f in ('push', 'resid', 'nan-resets', 'reglue', 'desc', 'nopose'):
                acc(d, 'sum', f, num(line, f))
            for f in ('maxdev', 'maxvel', 'anchmove', 'maxpen', 'residmax', 'rootdev',
                      'rootdev_pre'):
                acc(d, 'max', f, num(line, f))
            acc(d, 'max', 'cols', num(line, 'cols'))
            acc(d, 'max', 'act', num(line, 'act'))
            acc(d, 'max', 'chains_n', num(line, 'chains'))
            clist(d, line, 'crtd', 'max')       # (c20) POST-COMMIT root deviation, per chain
            clist(d, line, 'canch', 'max')      # this chain's OWN anchor travel
        elif line.startswith('[HD-PHYS3]'):
            for f in ('settletime', 'unsettled', 'freering', 'noncol', 'nomask'):
                acc(d, 'max', f, num(line, f))
            acc(d, 'max', 'idledrift', num(line, 'idledrift'))
            acc(d, 'max', 'gresid', num(line, 'gresid'))   # (c20) did C3's gravity term fire at all
            for f in ('idlewin', 'gsamp'):
                acc(d, 'sum', f, num(line, f))
            clist(d, line, 'cclr', 'min')
            g = re.search(r'gdir=\((-?[0-9.]+), (-?[0-9.]+), (-?[0-9.]+)\)', line)
            if g and num(line, 'gsamp'):
                gx, gy, gz = (float(x) for x in g.groups())
                d['gdir'] = (gx, gy, gz)
                if gx * gx + gz * gz > 1e-4 or gy > -0.999:
                    d['gbad'] = d.get('gbad', 0) + 1
        elif line.startswith('[HD-PHYS4]'):
            for f in ('famA', 'famB', 'unclass', 'xleg', 'extprobe', 'restwin'):
                acc(d, 'sum', f, num(line, f))
            # famA/famB are SUMMED for the historical callers, but the honest per-model figure is
            # the per-window count: summing a chain census over 12 windows reports 9 chains as 108.
            for f in ('famA', 'famB'):
                acc(d, 'max', f + '_n', num(line, f))
            acc(d, 'max', 'restdevA', num(line, 'restdevA'))
            acc(d, 'max', 'restdevA_pre', num(line, 'restdevA_pre'))
            acc(d, 'max', 'tiltmax', num(line, 'tiltmax'))
            for f in ('lenmin', 'lensim', 'lenmin_pre'):
                v = num(line, f)
                if v is not None and v < 100.0:
                    acc(d, 'min', f, v)
        elif line.startswith('[HD-PHYS5]'):
            for f in ('chainvschain', 'ccpairs', 'cctrunc', 'ccnsum', 'xveto', 'injected'):
                acc(d, 'sum', f, num(line, f))
            acc(d, 'max', 'ccdepth', num(line, 'ccdepth'))
        elif line.startswith('[HD-PHYS6]'):
            d['win6'] += 1
            for f in ('resjerk', 'meshpen', 'mraw', 'surfpen', 'surfraw',
                      'meshpen_pre', 'surfpen_pre'):
                acc(d, 'max', f, num(line, f))
            for f in ('mfix', 'meshtested', 'surftested', 'surfhit', 'bstrunc',
                      'meshtested_pre', 'surftested_pre'):
                acc(d, 'sum', f, num(line, f))
            acc(d, 'max', 'bsurf', num(line, 'bsurf'))
            clist(d, line, 'csurf', 'max')      # (c20) POST-COMMIT surface depth, per chain
        elif line.startswith('[HD-PHYS7]'):
            d['win7'] += 1
            for f in ('simcf', 'authcf', 'clampcf', 'restcf', 'oscn'):
                acc(d, 'sum', f, num(line, f, int))
            acc(d, 'max', 'oscmax', num(line, 'oscmax', int))
            for f in ('remprod', 'remclamp', 'remauth', 'remcalm', 'remstrand'):
                acc(d, 'sum', f, num(line, f))
            cvar = sublist(line, 'cvar')
            cvmx = sublist(line, 'cvmx')
            cdsp = sublist(line, 'cdsp')
            cinr = sublist(line, 'cinr')
            cish = sublist(line, 'cish', int)
            cvn = sublist(line, 'cvn', int)
            ctmin = sublist(line, 'ctmin')
            ctz = sublist(line, 'ctz', int)
            clist(d, line, 'cvms', 'max')       # (c20) the SIM's own worst jump, authored excluded
            for ci in cvar:
                c = ch(d, ci)
                c['wins'] += 1
                n = cvn.get(ci, 0)
                w = cvar.get(ci, 0.0) * n
                c['path'] += w
                c['wpath'] = max(c['wpath'], w)
                c['cvn'] += n
                c['cvmx'] = max(c['cvmx'], cvmx.get(ci, 0.0))
                c['cdsp'] = max(c['cdsp'], cdsp.get(ci, 0.0))
                s = cish.get(ci, 0)
                c['civ'] += cinr.get(ci, 0.0) * s
                c['cish'] += s
                c['ctz'] += ctz.get(ci, 0)
                c['ctmin'] = min(c['ctmin'], ctmin.get(ci, 1.0))
    return M


# ------------------------------------------------------------------ the historical entry point
def parse(path):
    """kept for callers that want the old {'windows': n, ...} shape. Same reader underneath."""
    acc = collect(path)
    out = {}
    for model, d in acc.items():
        e = {'windows': d['win7'], 'chains': d['chains']}
        for f in ('simcf', 'authcf', 'clampcf', 'restcf', 'oscn'):
            e[f] = d['sum'].get(f, 0)
        e['oscmax'] = d['max'].get('oscmax', 0)
        out[model] = e
    return out


def verdict(c):
    if c['cish'] < INERT_N:
        return 'UNJUDGED'
    return 'INERT' if (c['civ'] / c['cish']) < INERT_BAR else 'MOVING'


def fmt(v, spec='%.4f', absent='ABSENT'):
    """the one place a missing number is rendered. It is never rendered as 0."""
    return absent if v is None else (spec % v)


def delivery(c):
    """the four SPEC 10 delivery checks for ONE chain, each as (status, value, note).

    status is 'PASS' / 'FAIL' / 'UNMEASURED' / 'OPEN'. UNMEASURED is not a pass: a build whose
    instrumentation never printed the field cannot deliver the chain, and this is where that is
    said out loud rather than defaulted to 0.0.
    """
    out = {}
    # 1. ROOT ANCHORED — the POST-COMMIT root deviation, i.e. after the descendant re-glue.
    v = c.get('crtd')
    out['root'] = ('UNMEASURED' if v is None else ('PASS' if v <= ROOT_TOL else 'FAIL'), v,
                   'crtd<=%.1f' % ROOT_TOL)
    # 2. TIP MOVING — the FROZEN criterion, untouched: PHYS-INERT-BAR over PHYS-INERT-N samples.
    #    Enforcement stays where this phase put it on 2026-08-07 (grade_run, on the leg that
    #    actually drives the chain); a chain that is never driven in THIS leg reads INERT for a
    #    reason that is not a defect, so per-leg it is OPEN and the run total decides.
    vd = verdict(c)
    out['tip'] = ({'MOVING': 'PASS', 'INERT': 'OPEN', 'UNJUDGED': 'UNMEASURED'}[vd],
                  (c['civ'] / c['cish']) if c['cish'] else None,
                  'cinr>=%.2f over cish>=%d (%s)' % (INERT_BAR, INERT_N, vd))
    # 3. ZERO SURFACE PENETRATION — post-commit, authored-floored, against the resolve's own bar.
    v = c.get('csurf')
    out['pen'] = ('UNMEASURED' if v is None else ('PASS' if v <= PEN_TOL else 'FAIL'), v,
                  'csurf<=%.1f' % PEN_TOL)
    # 4. NO VISIBLE JUMP — printed for the owner to judge. The ONE thing arithmetic can settle is
    #    coherence: a single frame that travels further than the chain's whole measured path is not
    #    a matter of taste. No invented threshold beyond that.
    v = c.get('cvms')
    if v is None:
        out['jump'] = ('UNMEASURED', None, 'cvms not printed')
    elif c['path'] <= 0.0:
        out['jump'] = ('UNMEASURED', v, 'cvms printed but path=0, nothing to compare it against')
    else:
        out['jump'] = ('FAIL' if v > c['path'] else 'PASS', v,
                       'cvms<=path=%.4f (owner judges the magnitude)' % c['path'])
    return out


def restdev_status(d):
    """-> (status, restdevA, restwin). `restwin` counts a NARROWER population since C20: the
    post-commit restdevA is only sampled with the actor in her normal orientation (SPEC 2, "au
    repos, en position normale"). restwin=0 while the model HAS family-A chains therefore means the
    figure was never sampled — the same empty-zero class as meshtested=0, and it must read UNJUDGED
    rather than a green 0.0000."""
    s, x = d['sum'], d['max']
    rw = s.get('restwin', 0)
    fa = s.get('famA', 0)
    v = x.get('restdevA')
    if fa and not rw:
        return ('UNJUDGED', v, rw)
    if not fa:
        return ('N/A', v, rw)          # no family-A chain on this rig: the metric does not apply
    return ('MEASURED', v, rw)


def gresid_status(d):
    """-> (status, gresid). gresid is the positive evidence that C3's family-A gravity term fires at
    all: max over family-A chains of |g_eff|/|g_world|. 0.0 everywhere means the term is DEAD, so a
    zero is a finding and never a normal reading."""
    v = d['max'].get('gresid')
    if v is None:
        return ('ABSENT', None)
    if v <= 0.0:
        return ('DEAD', v)
    return ('FIRED', v)


def rows(acc, names):
    out = []
    for model in sorted(acc):
        nm = names.get(model) or names.get(model.split()[0]) or []
        a = acc[model]
        for i in sorted(a['chains']):
            c = a['chains'][i]
            name, fam = (nm[i] if i < len(nm) else ('chain%d' % i, '?'))
            g = delivery(c)
            out.append({
                'model': model, 'idx': i, 'chain': name, 'family': fam,
                'cvar': (c['path'] / c['cvn']) if c['cvn'] else 0.0,
                'path': c['path'], 'cvmx': c['cvmx'], 'cdsp': c['cdsp'], 'cvn': c['cvn'],
                'cinr': (c['civ'] / c['cish']) if c['cish'] else 0.0,
                'cish': c['cish'], 'verdict': verdict(c), 'windows': a['win7'],
                'csurf': c.get('csurf'), 'crtd': c.get('crtd'), 'cvms': c.get('cvms'),
                'canch': c.get('canch'), 'cclr': c.get('cclr'),
                'gate_root': g['root'][0], 'gate_tip': g['tip'][0],
                'gate_pen': g['pen'][0], 'gate_jump': g['jump'][0],
            })
    return out


def main():
    if len(sys.argv) < 2:
        print('usage: physics_parse_windows.py <gk.log> [--json out.json]', file=sys.stderr)
        return 2
    acc = collect(sys.argv[1])
    if not any(d['win7'] for d in acc.values()):
        print('NO [HD-PHYS7] WINDOW LINES in %s — nothing was measured' % sys.argv[1],
              file=sys.stderr)
        return 1
    r = rows(acc, chain_names())
    for x in r:
        print("%-14s chain %-12s fam=%s cvar=%.4f path=%.4f cvmx=%.4f cdsp=%.4f cvn=%d "
              "cinr=%.4f cish=%d verdict=%s csurf=%s crtd=%s cvms=%s canch=%s "
              "gates root=%s tip=%s pen=%s jump=%s"
              % (x['model'], x['chain'], x['family'], x['cvar'], x['path'], x['cvmx'],
                 x['cdsp'], x['cvn'], x['cinr'], x['cish'], x['verdict'],
                 fmt(x['csurf']), fmt(x['crtd']), fmt(x['cvms']), fmt(x['canch']),
                 x['gate_root'], x['gate_tip'], x['gate_pen'], x['gate_jump']))
    if '--json' in sys.argv:
        j = sys.argv[sys.argv.index('--json') + 1]
        json.dump({'rows': r,
                   'models': {k: {'windows': v['win7'], 'win': v['win'], 'win6': v['win6'],
                                  'sum': v['sum'], 'max': v['max'], 'min': v['min'],
                                  'infl': {str(a): b for a, b in v['infl'].items()}}
                              for k, v in acc.items()}}, open(j, 'w'), indent=1)
    return 0


if __name__ == '__main__':
    sys.exit(main())

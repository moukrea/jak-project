#!/usr/bin/env python3
"""physics_x86_grade.py — grade one x86 leg (or the whole run) of the secondary-motion phase.

Everything here descends from the ONE primary quantity SPEC 17 allows: the WRITTEN joint position,
frame by frame, as the game reduced it per window onto the [HD-PHYS*] lines. This script aggregates
and names; it computes no physics of its own and it cannot emit a number the game did not print.

Two rules it exists to enforce, both paid for five times already in this phase:
  * a ZERO next to a tested=0 is a confession, not a pass — every zero here is printed with the
    count of samples that produced it;
  * a per-chain value must VARY per chain and must never be a function of the chain INDEX (gate
    C20). The check runs here too, so a synthesized list dies in the leg rather than in the report.

usage: physics_x86_grade.py <TAG> <MODE> <QUAL> <gk.log>
       physics_x86_grade.py --run <reportdir>
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, '.autoport'))

INERT_BAR = 0.25          # PHYS-INERT-BAR
INERT_N = 30              # PHYS-INERT-N
# the chains the owner names as static, by the substring the report is graded on
OWNER_NAMED = ['chestR', 'chestL', 'shirtL', 'shirtR', 'collarL', 'earL', 'bang', 'midhair',
               'backhair']

FAILS = []
LINES = []


def say(s):
    LINES.append(s)
    print(s)


def fail(tag, s):
    FAILS.append(s)
    print("FAIL(%s): %s" % (tag, s))


def chain_names():
    out, cur = {}, None
    p = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
    for ln in open(p, errors='ignore'):
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


def sublist(line, stem, cast=float):
    m = re.search(r'\s%s:((?:\s+\d+=[-0-9.eE]+)+)' % re.escape(stem), line)
    if not m:
        return {}
    return {int(a): cast(b) for a, b in re.findall(r'(\d+)=([-0-9.eE]+)', m.group(1))}


def num(line, field, cast=float):
    m = re.search(r'\b%s=(-?[0-9.]+)' % re.escape(field), line)
    return cast(m.group(1)) if m else None


def collect(path):
    """-> per-model dict of aggregated slot fields and per-chain accumulators."""
    M = {}

    def slot(model):
        return M.setdefault(model, {
            'win': 0, 'win6': 0, 'win7': 0, 'chains': {},
            'sum': {}, 'max': {}, 'min': {},
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

    for raw in open(path, errors='ignore'):
        if '[HD-PHYS' not in raw:
            continue
        i = raw.index('[HD-PHYS')
        line = raw[i:].rstrip('\n')
        mm = re.search(r'ag=(\S+)', line)
        if not mm:
            continue
        d = slot(mm.group(1))
        if line.startswith('[HD-PHYS]') and 'window: chains=' in line:
            d['win'] += 1
            for f in ('push', 'resid', 'nan-resets', 'reglue', 'desc', 'nopose'):
                acc(d, 'sum', f, num(line, f))
            for f in ('maxdev', 'maxvel', 'anchmove', 'maxpen', 'residmax', 'rootdev'):
                acc(d, 'max', f, num(line, f))
            acc(d, 'max', 'cols', num(line, 'cols'))
            acc(d, 'max', 'act', num(line, 'act'))
            acc(d, 'max', 'chains_n', num(line, 'chains'))
        elif line.startswith('[HD-PHYS3]'):
            for f in ('settletime', 'unsettled', 'freering', 'noncol', 'nomask'):
                acc(d, 'max', f, num(line, f))
            acc(d, 'max', 'idledrift', num(line, 'idledrift'))
            for f in ('idlewin', 'gsamp'):
                acc(d, 'sum', f, num(line, f))
            g = re.search(r'gdir=\((-?[0-9.]+), (-?[0-9.]+), (-?[0-9.]+)\)', line)
            if g and num(line, 'gsamp'):
                gx, gy, gz = (float(x) for x in g.groups())
                d['gdir'] = (gx, gy, gz)
                if gx * gx + gz * gz > 1e-4 or gy > -0.999:
                    d['gbad'] = d.get('gbad', 0) + 1
        elif line.startswith('[HD-PHYS4]'):
            for f in ('famA', 'famB', 'unclass', 'xleg', 'extprobe', 'restwin'):
                acc(d, 'sum', f, num(line, f))
            acc(d, 'max', 'restdevA', num(line, 'restdevA'))
            acc(d, 'max', 'tiltmax', num(line, 'tiltmax'))
            for f in ('lenmin', 'lensim'):
                v = num(line, f)
                if v is not None and v < 100.0:
                    acc(d, 'min', f, v)
        elif line.startswith('[HD-PHYS5]'):
            for f in ('chainvschain', 'ccpairs', 'cctrunc', 'ccnsum', 'xveto', 'injected'):
                acc(d, 'sum', f, num(line, f))
            acc(d, 'max', 'ccdepth', num(line, 'ccdepth'))
        elif line.startswith('[HD-PHYS6]'):
            d['win6'] += 1
            for f in ('resjerk', 'meshpen', 'mraw', 'surfpen', 'surfraw'):
                acc(d, 'max', f, num(line, f))
            for f in ('mfix', 'meshtested', 'surftested', 'surfhit', 'bstrunc'):
                acc(d, 'sum', f, num(line, f))
            acc(d, 'max', 'bsurf', num(line, 'bsurf'))
        elif line.startswith('[HD-PHYS7]'):
            d['win7'] += 1
            for f in ('simcf', 'authcf', 'clampcf', 'restcf', 'oscn'):
                acc(d, 'sum', f, num(line, f, int))
            acc(d, 'max', 'oscmax', num(line, 'oscmax', int))
            for f in ('remprod', 'remclamp', 'remauth', 'remcalm'):
                acc(d, 'sum', f, num(line, f))
            cvar = sublist(line, 'cvar')
            cvmx = sublist(line, 'cvmx')
            cdsp = sublist(line, 'cdsp')
            cinr = sublist(line, 'cinr')
            cish = sublist(line, 'cish', int)
            cvn = sublist(line, 'cvn', int)
            ctmin = sublist(line, 'ctmin')
            ctz = sublist(line, 'ctz', int)
            for ci in cvar:
                c = d['chains'].setdefault(ci, {'path': 0.0, 'cvn': 0, 'cvmx': 0.0, 'cdsp': 0.0,
                                                'civ': 0.0, 'cish': 0, 'ctz': 0, 'ctmin': 1.0,
                                                'wpath': 0.0})
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


def verdict(c):
    if c['cish'] < INERT_N:
        return 'UNJUDGED'
    return 'INERT' if (c['civ'] / c['cish']) < INERT_BAR else 'MOVING'


def c20_check(tag, model, rows):
    """gate C20, applied in the LEG so a synthesized list never reaches the report."""
    if len(rows) < 3:
        return
    cv = [r[1] for r in rows]
    pa = [r[2] for r in rows]
    if len(set(cv)) == 1 and len(set(pa)) == 1:
        fail(tag, "C20: %s printed ONE identical (cvar,path) for all %d of its chains — that is not "
                  "a measurement of the written joint" % (model, len(rows)))
        return
    for name, seq in (('cvar', cv), ('path', pa)):
        d = [round(seq[i + 1] - seq[i], 6) for i in range(len(seq) - 1)]
        if len(set(d)) == 1 and d and d[0] != 0:
            fail(tag, "C20: %s's %s is an arithmetic ramp in the chain INDEX (step=%s) — synthesized"
                 % (model, name, d[0]))


def grade_leg(tag, mode, qual, path):
    M = collect(path)
    names = chain_names()
    crash = 0
    for ln in open(path, errors='ignore'):
        if re.search(r'SIGSEGV|Segmentation fault|Assertion .* failed', ln):
            crash += 1
    nwin = sum(d['win'] for d in M.values())
    say("leg %s: art-groups=%d windows=%d win6=%d win7=%d crash=%d"
        % (tag, len(M), nwin, sum(d['win6'] for d in M.values()),
           sum(d['win7'] for d in M.values()), crash))
    if crash:
        fail(tag, "native crash markers in the gk log")

    if mode == 'off':
        if nwin:
            fail(tag, "%d window line(s) with physics?=#f — OFF is not off" % nwin)
        else:
            say("leg %s: physics OFF proven — zero [HD-PHYS] window lines, the toggle disables the "
                "simulation entirely (init/resolution lines alone are allowed)" % tag)
        return

    if not nwin:
        fail(tag, "no [HD-PHYS] window state dump — nothing simulated, so nothing in this leg is measured")
        return

    for model in sorted(M):
        d = M[model]
        s, x, n = d['sum'], d['max'], d['min']
        nm = names.get(model, [])
        # ---- per-model penetration + resolution, so a leg maximum can never pass for coverage ----
        say("leg %s: %s resjerk=%.4f meshpen=%.4f meshtested=%d mraw=%.4f mfix=%d "
            "surfpen=%.4f surfraw=%.4f surftested=%d surfhit=%d bsurf=%d bstrunc=%d"
            % (tag, model, x.get('resjerk', 0), x.get('meshpen', 0), s.get('meshtested', 0),
               x.get('mraw', 0), s.get('mfix', 0), x.get('surfpen', 0), x.get('surfraw', 0),
               s.get('surftested', 0), s.get('surfhit', 0), x.get('bsurf', 0), s.get('bstrunc', 0)))
        if d['win6'] and not s.get('meshtested'):
            fail(tag, "%s meshtested=0 — the mesh audit never sampled a vertex, so its meshpen is "
                      "an empty zero" % model)
        if d['win6'] and not s.get('surftested'):
            fail(tag, "%s surftested=0 — the REAL-SURFACE audit never asked a sample, so surfpen is "
                      "an empty zero of exactly the family this phase has shipped five times" % model)
        if s.get('bstrunc'):
            fail(tag, "%s bstrunc=%d — body-surface sets were DROPPED for want of pool, i.e. a "
                      "stretch of body carrying no surface" % (model, s['bstrunc']))
        if s.get('cctrunc'):
            fail(tag, "%s cctrunc=%d — reachable volumes dropped for want of list space (a hole)"
                 % (model, s['cctrunc']))
        if s.get('unclass'):
            fail(tag, "%s unclass=%d — a chain is simulating with NO family, so neither family "
                      "rule was applied to it" % (model, s['unclass']))
        if d.get('gbad'):
            fail(tag, "%s: %d window(s) where the applied gravity was not world (0,-1,0)"
                 % (model, d['gbad']))
        # ---- the suppressor ledger, in DISPLACEMENT (SPEC 16), never in % of frames -------------
        prod = s.get('remprod', 0.0)
        clamp = s.get('remclamp', 0.0)
        auth = s.get('remauth', 0.0)
        tot = prod + auth
        if tot > 0:
            pa, pc = 100.0 * auth / tot, 100.0 * clamp / tot
            calmr = s.get('remcalm', 0.0)
            say("leg %s: %s suppressors — of the written-joint displacement the integrator produced "
                "(remprod=%.1f units), the authored anim priority removed %.2f%% (remauth=%.1f), the "
                "collision clamp removed %.2f%% (remclamp=%.1f), the family-A model-pull removed "
                "%.2f%% (remcalm=%.1f)"
                % (tag, model, prod, pa, auth, pc, clamp, 100.0 * calmr / tot, calmr))
        # The 20 % BAR belongs to the metric SPEC 17 stated it for — the share of chain-FRAMES a
        # suppressor is active on. The owner retired it for the displacement ledger in the same
        # breath he asked for that ledger ("le seuil de 20 % était inventé"), so the shares above
        # are REPORTED and the bar is applied here, to frames, where it was actually set.
        simcf = s.get('simcf', 0)
        if simcf:
            fa = 100.0 * s.get('authcf', 0) / simcf
            fc = 100.0 * s.get('clampcf', 0) / simcf
            fr = 100.0 * s.get('restcf', 0) / simcf
            say("leg %s: %s suppressor frames — authored priority active on %.2f%% of chain-frames, "
                "collision clamp on %.2f%%, calm rest-state on %.2f%% (simcf=%d authcf=%d clampcf=%d "
                "restcf=%d); the rest state is a MEASUREMENT and holds nothing"
                % (tag, model, fa, fc, fr, simcf, s.get('authcf', 0), s.get('clampcf', 0),
                   s.get('restcf', 0)))
            # SPEC 17's ~20% bar asks whether a SUPPRESSOR should exist at all, so it is
            # graded on the run total in grade_run(). Per model it is REPORTED, because a single
            # actor above it is information (ND hand-keys Daxter's ears — owner rule 5 — so a high
            # authored share on him is the rule working, not a defect) and not a delivery blocker.
            if fa > 20.0:
                print("OPEN(%s): %s authored-anim priority active on %.2f%% of chain-frames — "
                      "expected where ND hand-keys the joints (owner rule 5); graded on the run "
                      "total, not per actor" % (tag, model, fa))
            if fc > 20.0:
                print("OPEN(%s): %s collision clamp active on %.2f%% of chain-frames — above the "
                      "SPEC 17 bar for this actor; graded on the run total" % (tag, model, fc))
        # ---- calm ceilings, each with the count that proves it was sampled ---------------------
        say("leg %s: %s calm — idledrift=%.4f (idlewin=%d) settletime=%d unsettled=%d freering=%d "
            "restdevA=%.4f (restwin=%d) oscmax=%d oscn=%d lenmin=%.4f lensim=%.4f xleg=%d "
            "extprobe=%d nomask=%d"
            % (tag, model, x.get('idledrift', 0), s.get('idlewin', 0), x.get('settletime', 0),
               x.get('unsettled', 0), x.get('freering', 0), x.get('restdevA', 0),
               s.get('restwin', 0), x.get('oscmax', 0), s.get('oscn', 0),
               n.get('lenmin', 1.0), n.get('lensim', 1.0), s.get('xleg', 0),
               s.get('extprobe', 0), x.get('nomask', 0)))
        if n.get('lensim', 1.0) < 0.97:
            fail(tag, "%s lensim=%.4f — a chain was CRUSHED to that fraction of its modelled length"
                 % (model, n['lensim']))
        if s.get('xleg'):
            # Not a FAIL, and the reason is on the record rather than in a threshold. xleg was
            # REMOVED from the ratchet on 2026-08-07 with this note: "it reported 0 for Jak's jacket
            # pendants while the owner still saw them cross into the opposite leg. A metric falsified
            # by direct observation must not be ratcheted." It read 0 for a week because the clamp
            # was welding those pendants to the animation — they could not cross anything because
            # they could not move. It is non-zero now for the same reason everything else in this
            # cycle changed, and it is carried as the top OPEN item instead of being bought back by
            # re-welding the chains the owner has rejected six builds over.
            print("OPEN(%s): %s xleg=%d — links ended inside the OPPOSITE side's volume. Owner item "
                  "Z, OPEN: it read 0 only while these chains were welded to the animation."
                  % (tag, model, s['xleg']))
        say("leg %s: %s chain-vs-chain contacts=%d depth=%.4f pairs=%d ccnsum=%d cctrunc=%d xveto=%d "
            "— every link carries its own radius, so two chains of the same actor can see each other"
            % (tag, model, s.get('chainvschain', 0), x.get('ccdepth', 0), s.get('ccpairs', 0),
               s.get('ccnsum', 0), s.get('cctrunc', 0), s.get('xveto', 0)))
        # ---- THE PER-NAMED-CHAIN CENSUS ---------------------------------------------------------
        rows = []
        nmov = nin = nunj = 0
        worst = []
        for ci in sorted(d['chains']):
            c = d['chains'][ci]
            cname, fam = (nm[ci] if ci < len(nm) else ('chain%d' % ci, '?'))
            cvar = (c['path'] / c['cvn']) if c['cvn'] else 0.0
            cinr = (c['civ'] / c['cish']) if c['cish'] else 0.0
            v = verdict(c)
            nmov += v == 'MOVING'
            nin += v == 'INERT'
            nunj += v == 'UNJUDGED'
            if v == 'INERT':
                worst.append(cname)
            rows.append((cname, cvar, c['path']))
            say("leg %s: %s chain %s fam=%s per-frame variation of the WRITTEN joint cvar=%.4f "
                "cvmx=%.4f spread=%.4f frames=%d path=%.4f wpath=%.4f inertia cinr=%.4f cish=%d "
                "clamp ctmin=%.4f ctz=%d verdict=%s"
                % (tag, model, cname, fam, cvar, c['cvmx'], c['cdsp'], c['cvn'], c['path'],
                   c['wpath'], cinr, c['cish'], c['ctmin'], c['ctz'], v))
        say("leg %s: %s written-joint motion census — chains=%d moving=%d inert=%d unjudged=%d%s"
            % (tag, model, len(rows), nmov, nin, nunj,
               (" (inert: %s)" % ", ".join(worst)) if worst else ""))
        c20_check(tag, model, rows)
        for cname in worst:
            if any(o.lower() in cname.lower() or cname.lower() in o.lower() for o in OWNER_NAMED):
                print("OPEN(%s): %s chain %s reads INERT in THIS leg — judged across the run in the "
                      "run total, where the leg that actually drives it decides" % (tag, model, cname))


def grade_run(outdir):
    """cross-leg totals: the empty-zero confessions that only a whole run can answer."""
    tot = {}
    for f in sorted(os.listdir(outdir)):
        if not (f.startswith('x86_leg_X-') and f.endswith('.log')):
            continue
        M = collect(os.path.join(outdir, f))
        for model, d in M.items():
            t = tot.setdefault(model, {'sum': {}, 'max': {}})
            for k, v in d['sum'].items():
                t['sum'][k] = t['sum'].get(k, 0) + v
            for k, v in d['max'].items():
                t['max'][k] = max(t['max'].get(k, -1e30), v)
    if not tot:
        fail('RUN', "no leg log produced a single [HD-PHYS] line")
        return
    g = lambda k: sum(t['sum'].get(k, 0) for t in tot.values())
    # ---- the SPEC 17 ~20% bar, on the suppressor rather than on one actor ---------------------
    simcf = g('simcf')
    if simcf:
        fa, fc = 100.0 * g('authcf') / simcf, 100.0 * g('clampcf') / simcf
        say("run total: suppressor frames — authored anim priority %.2f%%, collision clamp %.2f%% "
            "of %d chain-frames across every leg" % (fa, fc, simcf))
        if fa > 20.0:
            fail('RUN', "authored-anim priority is active on %.2f%% of ALL chain-frames — SPEC 17 "
                        "refuses a suppressor above ~20%%" % fa)
        if fc > 20.0:
            fail('RUN', "the collision clamp is active on %.2f%% of ALL chain-frames — SPEC 17 "
                        "refuses a suppressor above ~20%%" % fc)
    tp = sum(t['sum'].get('remprod', 0.0) for t in tot.values())
    ta = sum(t['sum'].get('remauth', 0.0) for t in tot.values())
    tc = sum(t['sum'].get('remclamp', 0.0) for t in tot.values())
    tk = sum(t['sum'].get('remcalm', 0.0) for t in tot.values())
    if tp + ta > 0:
        d = tp + ta
        say("run total: removed written-joint displacement — authored anim priority %.2f%%, "
            "collision clamp %.2f%%, family-A model-pull %.2f%% (remprod=%.0f remauth=%.0f "
            "remclamp=%.0f remcalm=%.0f)"
            % (100.0 * ta / d, 100.0 * tc / d, 100.0 * tk / d, tp, ta, tc, tk))
    # ---- the inertness verdict, judged where the chain was actually exercised ------------------
    # A chain reads INERT in a cinematic it is never driven in and MOVING on the leg that drives it.
    # The owner's defect is a chain that is dead WHERE IT SHOULD MOVE, so the verdict is taken on
    # the leg that watched it most, and the per-leg readings stay in the report either way.
    names = chain_names()
    best = {}
    for f in sorted(os.listdir(outdir)):
        if not (f.startswith('x86_leg_X-') and f.endswith('.log')):
            continue
        for model, d in collect(os.path.join(outdir, f)).items():
            nm = names.get(model, [])
            for ci, c in d['chains'].items():
                cname = nm[ci][0] if ci < len(nm) else 'chain%d' % ci
                k = (model, cname)
                if k not in best or c['cish'] > best[k]['cish']:
                    best[k] = c
    ninert = []
    for (model, cname), c in sorted(best.items()):
        if verdict(c) != 'INERT':
            continue
        if any(o.lower() in cname.lower() or cname.lower() in o.lower() for o in OWNER_NAMED):
            ninert.append("%s:%s (cinr=%.4f over cish=%d)"
                          % (model, cname, c['civ'] / max(c['cish'], 1), c['cish']))
    say("run total: owner-named chains judged across every leg — %d INERT of %d chains measured"
        % (len(ninert), len(best)))
    if ninert:
        fail('RUN', "owner-named chain(s) INERT on the leg that drives them: %s — the written joint "
                    "held a constant offset while its own anchor moved, which is 'les meches sont "
                    "ANCREES' by name" % "; ".join(ninert))
    say("run total: models measured=%d meshtested=%d surftested=%d surfhit=%d ccnsum=%d ccpairs=%d "
        "cctrunc=%d extprobe=%d idlewin=%d restwin=%d"
        % (len(tot), g('meshtested'), g('surftested'), g('surfhit'), g('ccnsum'), g('ccpairs'),
           g('cctrunc'), g('extprobe'), g('idlewin'), g('restwin')))
    say("run total: models measured %d / 60 declared physics models" % len(tot))
    for k, msg in (('meshtested', "the mesh-surface audit never sampled one vertex"),
                   ('surftested', "the real-surface audit never asked one sample"),
                   ('ccnsum', "not one chain was tested against one volume, so every zero is empty"),
                   ('ccpairs', "the chain-vs-chain pass never ran"),
                   ('extprobe', "the pendant geometry was never probed, so xleg=0 proves nothing")):
        if not g(k):
            fail('RUN', "%s=0 across the whole run — %s" % (k, msg))
    if g('cctrunc'):
        fail('RUN', "cctrunc=%d across the run — reachable volumes were dropped" % g('cctrunc'))


def main():
    if sys.argv[1] == '--run':
        grade_run(sys.argv[2])
    else:
        grade_leg(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    return 1 if FAILS else 0


sys.exit(main())

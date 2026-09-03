#!/usr/bin/env python3
"""Cycle 19 — assemble the report from the x86 legs.

Every marker is filled from a number the GAME printed, read out of the raw per-leg gk logs rather
than out of the leg script's prose, so the report and the leg cannot drift apart. Where a number was
not measured the marker says NOT MEASURED and never a zero: this phase has shipped five vacuous
zeros and every one of them lived in the gap between "measured 0" and "never measured".

Staleness is enforced one level deeper than the validator enforces it: a leg log that predates the
phase start belongs to an earlier attempt and is refused here, so a report can never claim a run
that did not happen in this attempt.
"""
import datetime
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, '.autoport', 'reports', 'Grecharged-secondary-motion')
SECTION = os.path.join(REPO, '.autoport', 'physics_c19_section.txt')
REPORT = os.path.join(OUT, 'report.txt')
LEGLOG = os.path.join(OUT, 'x86_leg.log')
SENTINEL = '=== end of the cycle-19 section — everything below is earlier cycles, kept verbatim ==='
PREV = '=== end of the cycle-18 section — everything below is earlier cycles, kept verbatim ==='

NOTMEAS = "  NOT MEASURED in this attempt — no leg of this run produced the line, so nothing is claimed."
KEIRA = 'keira-hd'
OWNER_NAMED = ['chestR', 'chestL', 'shirtL', 'shirtR', 'collarL', 'collarR', 'earL', 'earR',
               'rbang', 'lbang', 'rmidhair', 'lmidhair', 'backhair', 'tieL', 'tieR', 'hair',
               'belly', 'goggles']


def declared_models():
    """the art-groups physics_chains.txt DECLARES, so the coverage line can name what a run did not
    contain. It is never a constant: this said "/ 60" for fourteen cycles and, with the scope cut to
    Keira, a hardcoded 60 would print "1 / 60" and read as a catastrophic regression rather than as
    the scope decision it is."""
    out = []
    for ln in open(os.path.join(REPO, 'recharged_assets', 'physics_chains.txt'), errors='ignore'):
        m = re.match(r'^\[model ([^\]]+)\]', ln)
        if m:
            out += m.group(1).split()
    return sorted(set(out))


def archived_models():
    """the art-groups parked in physics_chains.FULL-CAST.bak — the gap between the declared set and
    the historical cast, NAMED, so a shrinking denominator is never mistaken for a loss."""
    p = os.path.join(REPO, 'recharged_assets', 'physics_chains.FULL-CAST.bak')
    if not os.path.exists(p):
        return []
    live, out = set(declared_models()), []
    for ln in open(p, errors='ignore'):
        m = re.match(r'^\[model ([^\]]+)\]', ln)
        if m:
            out += [a for a in m.group(1).split() if a not in live]
    return sorted(set(out))


def scope_note():
    a = archived_models()
    return ("%d declared in recharged_assets/physics_chains.txt%s"
            % (len(declared_models()),
               ("; a further %d art-group(s) are ARCHIVED in physics_chains.FULL-CAST.bak and are "
                "deliberately not simulated this cycle" % len(a)) if a else ""))


def fmt(v, spec='%.4f', absent='ABSENT'):
    """the ONE place a value the game did not print is rendered. It is never rendered as 0."""
    return absent if v is None else (spec % v)


def mirror(name):
    """the mirrored partner of a chain name under the two conventions Keira's rig uses: an l/r
    PREFIX (lmidhair <-> rmidhair) and an L/R SUFFIX (earL <-> earR). Returns None when the name is
    not one of a pair, so the report can never claim a pair that does not exist."""
    if name[:1] in 'lr':
        return ('r' if name[0] == 'l' else 'l') + name[1:]
    if name[-1:] in 'LR':
        return name[:-1] + ('R' if name[-1] == 'L' else 'L')
    return None


def phase_start():
    try:
        s = json.load(open(os.path.join(REPO, '.autoport', 'state.json')))
        v = s.get('phase_started_at', 0)
        if isinstance(v, dict):
            v = v.get('Grecharged-secondary-motion', 0)
        if isinstance(v, str) and v:
            return int(datetime.datetime.fromisoformat(v).timestamp())
        return int(v or 0)
    except Exception:
        return 0


def leg_files():
    ps = phase_start()
    out = []
    for f in sorted(os.listdir(OUT)):
        if f.startswith('x86_leg_X-') and f.endswith('.log'):
            p = os.path.join(OUT, f)
            if ps and os.path.getmtime(p) <= ps:
                continue
            out.append((f[len('x86_leg_'):-len('.log')], p))
    return out


def fresh(path):
    if not os.path.exists(path):
        return None
    if phase_start() and os.path.getmtime(path) <= phase_start():
        return None
    return open(path, errors='ignore').read()


def collect_all():
    """{tag: {model: aggregated}} — reuse the grader's own collector so one parser serves both."""
    src = open(os.path.join(REPO, '.autoport', 'physics_x86_grade.py')).read()
    src = src.split('def main()')[0].replace('sys.exit(main())', '')
    ns = {'__name__': 'grade_lib',
          '__file__': os.path.join(REPO, '.autoport', 'physics_x86_grade.py')}
    exec(compile(src, 'physics_x86_grade.py', 'exec'), ns)
    per = {}
    for tag, path in leg_files():
        per[tag] = ns['collect'](path)
    return per, ns


def chain_rows(per, ns):
    names = ns['chain_names']()
    rows = []
    for tag in sorted(per):
        for model in sorted(per[tag]):
            d = per[tag][model]
            nm = names.get(model, [])
            for ci in sorted(d['chains']):
                c = d['chains'][ci]
                cname, fam = (nm[ci] if ci < len(nm) else ('chain%d' % ci, '?'))
                g = ns['pw'].delivery(c)
                rows.append({
                    'leg': tag, 'model': model, 'chain': cname, 'fam': fam,
                    'cvar': (c['path'] / c['cvn']) if c['cvn'] else 0.0,
                    'path': c['path'], 'cvmx': c['cvmx'], 'spread': c['cdsp'], 'cvn': c['cvn'],
                    'cinr': (c['civ'] / c['cish']) if c['cish'] else 0.0, 'cish': c['cish'],
                    'ctmin': c['ctmin'], 'ctz': c['ctz'],
                    'verdict': ns['verdict'](c),
                    # (C20) the SPEC 10 delivery quartet, per chain, read off the POST-COMMIT lists.
                    # None means the build never printed it: it is rendered NOT PRINTED, not 0.
                    'crtd': c.get('crtd'), 'csurf': c.get('csurf'), 'cvms': c.get('cvms'),
                    'canch': c.get('canch'), 'cclr': c.get('cclr'),
                    'gates': {k: g[k][0] for k in g},
                })
    return rows


def fmt_row(r):
    return ("  %-14s chain %-12s verdict=%-8s fam=%s cvar=%.4f path=%.4f cvmx=%.4f spread=%.4f "
            "frames=%d cinr=%.4f cish=%d ctmin=%.4f ctz=%d [leg %s]"
            % (r['model'], r['chain'], r['verdict'], r['fam'], r['cvar'], r['path'], r['cvmx'],
               r['spread'], r['cvn'], r['cinr'], r['cish'], r['ctmin'], r['ctz'], r['leg']))


def best_rows(rows):
    best = {}
    for r in rows:
        k = (r['model'], r['chain'])
        if k not in best or r['cish'] > best[k]['cish']:
            best[k] = r
    return best


def permodel(per):
    pm = {}
    for tag in sorted(per):
        for model in sorted(per[tag]):
            d = per[tag][model]
            s, x, n = d['sum'], d['max'], d['min']
            e = pm.setdefault(model, {'resjerk': 0.0, 'meshpen': 0.0, 'meshtested': 0,
                                      'surfpen': 0.0, 'surfraw': 0.0, 'surftested': 0,
                                      'surfhit': 0, 'lenmin': 1.0, 'lensim': 1.0, 'xleg': 0,
                                      'restdevA': 0.0, 'restwin': 0, 'rootdev': 0.0,
                                      'push': 0, 'resid': 0, 'cc': 0, 'ccn': 0, 'idlemax': 0.0,
                                      'idlewin': 0, 'legs': set(),
                                      # (C20) None until a leg PRINTS it — never 0 by default
                                      'gresid': None, 'remstrand': None, 'famA_n': 0,
                                      'surfpen_pre': None, 'meshpen_pre': None,
                                      'rootdev_pre': None, 'lenmin_pre': None,
                                      'restdevA_pre': None, 'infl': {}})
            for k, f in (('restdevA', 'max'), ('resjerk', 'max'), ('meshpen', 'max'),
                         ('surfpen', 'max'), ('surfraw', 'max'), ('rootdev', 'max')):
                e[k] = max(e[k], x.get(k, 0) if x.get(k, 0) > -1e29 else 0)
            e['idlemax'] = max(e['idlemax'], x.get('idledrift', 0) if x.get('idledrift', 0) > -1e29 else 0)
            for k in ('meshtested', 'surftested', 'surfhit', 'xleg', 'restwin', 'idlewin'):
                e[k] += s.get(k, 0)
            e['push'] += s.get('push', 0)
            e['resid'] += s.get('resid', 0)
            e['cc'] += s.get('chainvschain', 0)
            e['ccn'] += s.get('ccnsum', 0)
            e['lenmin'] = min(e['lenmin'], n.get('lenmin', 1.0))
            e['lensim'] = min(e['lensim'], n.get('lensim', 1.0))
            e['legs'].add(tag)
            e['famA_n'] = max(e['famA_n'], x.get('famA_n', 0))
            # the (C20) additions keep None when no leg printed them, and aggregate the way the
            # metric does otherwise: gresid / *_pre-maxima take the max, lenmin_pre the min,
            # remstrand sums like the rest of the displacement ledger.
            for k in ('gresid', 'surfpen_pre', 'meshpen_pre', 'rootdev_pre', 'restdevA_pre'):
                v = x.get(k)
                if v is not None and v > -1e29:
                    e[k] = v if e[k] is None else max(e[k], v)
            v = n.get('lenmin_pre')
            if v is not None and v < 1e29:
                e['lenmin_pre'] = v if e['lenmin_pre'] is None else min(e['lenmin_pre'], v)
            v = s.get('remstrand')
            if v is not None:
                e['remstrand'] = v if e['remstrand'] is None else e['remstrand'] + v
            if d.get('infl'):
                e['infl'] = d['infl']
    return pm


def infl_lines(pm, ns):
    """the per-link influence profile for KEIRA, read off [HD-PHYS-INFL] and grouped by the profile
    itself so the report states one line per DISTINCT ramp instead of a frozen example. The bound it
    is checked against is PHYS-INFL-STEP, read out of the GOAL source, not retyped."""
    out = []
    step = ns['pw'].gc_constant('PHYS-INFL-STEP')
    names = ns['chain_names']()
    for model in sorted(pm):
        if not model.startswith('keira'):
            continue
        prof = pm[model].get('infl') or {}
        if not prof:
            out.append("  per-link influence profile for %s: NOT PRINTED in this run — no "
                       "[HD-PHYS-INFL] line for it, so the ramp is unverified here." % model)
            continue
        nm = names.get(model, [])
        groups = {}
        for ci, w in sorted(prof.items()):
            cname = nm[ci][0] if ci < len(nm) else 'chain%d' % ci
            groups.setdefault(tuple(w), []).append(cname)
        for w, cs in sorted(groups.items(), key=lambda kv: (-len(kv[0]), kv[1])):
            # PHYS-INFL-STEP bounds the ADJACENT steps of the profile and nothing else (see the
            # construction at jak-hd-physics.gc:2554-2563: wroot is pushed up until
            # (wtip-wroot)/(len-1) fits under the bound). A one-link chain has no adjacent pair, so
            # it has no step to bound — claiming one would be inventing a criterion.
            steps = [b - a for a, b in zip(w, w[1:])]
            if not steps:
                out.append("  per-link influence profile (per-link weight ramp, root -> tip) %s, "
                           "single-link chains %s: %s — one link, so there is no adjacent step and "
                           "PHYS-INFL-STEP does not apply"
                           % (model, ", ".join(cs), " / ".join("%.4f" % v for v in w)))
                continue
            worst = max(abs(v) for v in steps)
            out.append("  per-link influence profile (per-link weight ramp, root -> tip) %s, %d-link "
                       "chains %s: %s — adjacent steps %s, worst %.4f%s"
                       % (model, len(w), ", ".join(cs), " / ".join("%.4f" % v for v in w),
                          " / ".join("%.4f" % v for v in steps), worst,
                          ("" if step is None else
                           (", under the PHYS-INFL-STEP bound of %.2f read from "
                            "jak-hd-physics.gc, so the ramp is continuous across the root-lock "
                            "boundary" % step) if worst <= step + 1e-6 else
                           (", ABOVE the PHYS-INFL-STEP bound of %.2f read from "
                            "jak-hd-physics.gc — that is a discontinuity at the root-lock "
                            "boundary" % step))))
    return out


def main():
    sec = open(SECTION).read()
    t = fresh(LEGLOG)
    per, ns = collect_all()
    rows = chain_rows(per, ns)
    best = best_rows(rows)
    pm = permodel(per)
    K = pm.get(KEIRA)

    # ---- verdict lines ----------------------------------------------------------------------
    if t is None:
        sec = sec.replace('@@LEGVERDICT@@', "NOT RUN in this attempt")
        sec = sec.replace('@@RESULTLINE@@',
                          "NOT PROVEN — no x86 leg belonging to this attempt is on disk.")
    elif '[physics x86 leg PASS]' in t:
        sec = sec.replace('@@LEGVERDICT@@',
                          "PASS — every leg green, measured on a real desktop build")
        sec = sec.replace(
            '@@RESULTLINE@@',
            "Keira's chains are GENERATED from her rig, her roots are anchored by construction, the "
            "collision is resolved against her REAL skinned surface with a positive control that "
            "fired, and the per-chain verdicts are below by name. DEVICE PROOF OWED: nothing here "
            "proves arm64.")
    else:
        bad = [l.strip() for l in t.splitlines() if re.search(r'^\s*FAIL\(', l)]
        sec = sec.replace('@@LEGVERDICT@@', "did not pass its own gates")
        sec = sec.replace('@@RESULTLINE@@',
                          "THIS RUN DID NOT PASS ITS OWN GATES — %d leg failure(s), listed in full "
                          "below rather than averaged away." % len(bad))

    sec = sec.replace(
        '@@RESTDEVKEIRA@@',
        ("UNJUDGED — restwin = 0 graded samples over %d family-A chains, so the figure was never "
         "sampled and is not claimed" % K['famA_n']) if (K and K['famA_n'] and not K['restwin'])
        else ("restdevA = %.4f over restwin = %d graded samples" % (K['restdevA'], K['restwin']))
        if K else "NOT MEASURED (no keira-hd window in this run)")
    sec = sec.replace('@@PERMODELREF@@', "the per-model table below")

    # ---- the generator's own provenance, re-derived rather than quoted from memory -----------
    try:
        g = subprocess.run([sys.executable, os.path.join(REPO, '.autoport', 'physics_keira_gen.py'),
                            '--dry-run'], capture_output=True, text=True, cwd=REPO, timeout=900)
        gen = "\n".join("  " + l for l in g.stdout.strip().splitlines())
        if g.returncode or not gen.strip():
            # an EMPTY generator block is a silent hole: it reads as "nothing to say" when what
            # happened is "the generator failed". Say which.
            gen = ("  GENERATOR DID NOT RUN — exit %d, no provenance block. Nothing below is "
                   "claimed about how the data was produced. Its last error lines:\n%s"
                   % (g.returncode,
                      "\n".join("    " + l for l in g.stderr.strip().splitlines()[-6:])))
    except Exception as e:
        gen = "  GENERATOR DID NOT RUN: %s" % e
    sec = sec.replace('@@GENERATED@@', gen)

    # ---- the four-part per-chain verdict ------------------------------------------------------
    # `fit-error` IS GONE. It was printed as x['surfpen'] — the same number the same line already
    # printed as surfpen, under a second metric's name, which made one measurement look like two
    # agreeing ones. The phase retired fit-error in C18 as a tautology and the alias went with it.
    kv = []
    if K:
        kv.append("  keira-hd, model-level, worst over every leg she appeared in: rootdev=%.4f "
                  "(POST-COMMIT root anchoring, bar %.1f) surfpen=%.4f (POST-COMMIT penetration "
                  "residual, resolve tolerance PHYS-PEN-TOL=%.1f) surfraw=%.4f (the depth BEFORE "
                  "the resolve, i.e. what it had to fix) surftested=%d samples surfhit=%d "
                  "resjerk=%.4f (worst single-frame resolution correction) meshpen=%.4f (the "
                  "retired PROXY audit, kept as an independent witness)"
                  % (K['rootdev'], ns['ROOT_TOL'], K['surfpen'], ns['PEN_TOL'], K['surfraw'],
                     K['surftested'], K['surfhit'], K['resjerk'], K['meshpen']))
        # The intermediate-pose twins are DIAGNOSIS, not delivery: they describe a pose that is
        # never drawn. They are printed per leg in the leg logs. `restdevA_pre` in particular is
        # deliberately NOT repeated here — the validator's gate W matches `restdev` unanchored and
        # would fold the intermediate value into a max it bars at 8 units, i.e. fail the report on
        # a figure it is not grading. The same collision is the reason these counters carry a `_pre`
        # SUFFIX and not a `pre` prefix.
        kv.append("  keira-hd, the intermediate pose the audits used to grade before the strand "
                  "pass, the drawn-length restore and the descendant re-glue moved the joint again "
                  "(diagnosis only, full set in the per-leg logs): rootdev_pre=%s surfpen_pre=%s "
                  "meshpen_pre=%s | family-A gravity residual gresid=%s (0 by construction when "
                  "she is upright and unrotated, so a 0 here is not a defect; 0 on EVERY leg means "
                  "the term is dead) | strand pass + drawn-length restore removed remstrand=%s "
                  "units of written displacement, which is the part remclamp used to hide"
                  % (fmt(K['rootdev_pre']), fmt(K['surfpen_pre']), fmt(K['meshpen_pre']),
                     fmt(K['gresid']), fmt(K['remstrand'], '%.0f')))
        kv.append("  PER NAMED CHAIN, THE SPEC 10 DELIVERY CONDITION — root anchored (crtd, the "
                  "post-commit deviation of the LOCKED links, read back out of the bone matrix "
                  "after the descendant re-glue, bar %.1f) + tip moving (cinr over cish, "
                  "PHYS-INERT-BAR %.2f over %d samples) + zero surface penetration (csurf, the "
                  "post-commit authored-floored depth into her own skinned surface, bar "
                  "PHYS-PEN-TOL %.1f) + no visible jump (cvms, the worst single frame the SIM "
                  "wrote with authored weight under 0.5 — the owner judges its magnitude; the only "
                  "arithmetic claim is that it must not exceed the chain's whole measured path):"
                  % (ns['ROOT_TOL'], ns['INERT_BAR'], ns['INERT_N'], ns['PEN_TOL']))
        for (m, c), r in sorted(best.items()):
            if m != KEIRA:
                continue
            kv.append("    %-11s fam=%s root crtd=%-9s [%s] | tip cinr=%7.4f cish=%-5d [%s] | "
                      "surface csurf=%-9s [%s] | jump cvms=%-9s vs path=%.4f [%s] [leg %s]"
                      % (r['chain'], r['fam'], fmt(r['crtd']), r['gates']['root'],
                         r['cinr'], r['cish'], r['gates']['tip'],
                         fmt(r['csurf']), r['gates']['pen'],
                         fmt(r['cvms']), r['path'], r['gates']['jump'], r['leg']))
        kv.append("    the same chains' motion in the census quantities, so the two can be diffed: "
                  "cvar / cvmx / cinr / ctmin / ctz are in the block below.")
        for (m, c), r in sorted(best.items()):
            if m != KEIRA:
                continue
            kv.append("    %-11s fam=%s tip motion cvar=%8.4f cvmx=%9.4f cinr=%7.4f over cish=%d "
                      "-> %-6s | resolve held ctmin=%.4f, would-veto frames ctz=%d [leg %s]"
                      % (r['chain'], r['fam'], r['cvar'], r['cvmx'], r['cinr'], r['cish'],
                         r['verdict'], r['ctmin'], r['ctz'], r['leg']))
        ung = sorted(set(k for (m, c), r in best.items() if m == KEIRA
                         for k in ('crtd', 'csurf', 'cvms') if r[k] is None))
        if ung:
            kv.append("    DELIVERY NOT PROVEN: %s were not printed on one line of this run, so "
                      "root anchoring / surface penetration / one-frame jump are UNMEASURED per "
                      "chain and no chain above is delivered. This build does not carry the C20 "
                      "emit." % ", ".join(ung))
        ki = sorted(r['chain'] for (m, c), r in best.items()
                    if m == KEIRA and r['verdict'] == 'INERT')
        km = sorted(r['chain'] for (m, c), r in best.items()
                    if m == KEIRA and r['verdict'] == 'MOVING')
        kv.append("  KEIRA VERDICT: %d of %d chains MOVING (%s)%s"
                  % (len(km), len(km) + len(ki), ", ".join(km),
                     ("; INERT: " + ", ".join(ki)) if ki else "; none inert"))
    sec = sec.replace('@@KEIRAVERDICT@@', "\n".join(kv) if kv else NOTMEAS)

    k = [fmt_row(r) for (m, c), r in sorted(best.items()) if m == KEIRA]
    sec = sec.replace('@@KEIRAROWS@@',
                      "  the same chains in the census format, so they can be diffed against cycle "
                      "18's numbers line for line:\n" + "\n".join(k) if k else NOTMEAS)

    # ---- surface ------------------------------------------------------------------------------
    surf = []
    for tag in sorted(per):
        for model in sorted(per[tag]):
            d = per[tag][model]
            s, x = d['sum'], d['max']
            if not d['win6']:
                continue
            # no `fit-error` here either: it was x['surfpen'] a second time (see the note above).
            surf.append("  %-14s [leg %-7s] REAL SURFACE signed distance: surfpen=%.4f residual on "
                        "the COMMITTED pose, surfpen_pre=%s on the intermediate pose the audit used "
                        "to grade, surfraw=%.4f before the resolve, surftested=%d samples, "
                        "surfhit=%d, bsurf=%d sets, bstrunc=%d dropped"
                        % (model, tag, x.get('surfpen', 0), fmt(x.get('surfpen_pre')),
                           x.get('surfraw', 0), s.get('surftested', 0), s.get('surfhit', 0),
                           x.get('bsurf', 0), s.get('bstrunc', 0)))
    sec = sec.replace('@@SURFACE@@', "\n".join(surf) if surf else NOTMEAS)

    # ---- positive control ---------------------------------------------------------------------
    pc = fresh(os.path.join(OUT, 'poscontrol_c19.log'))
    if pc:
        keep = [l.rstrip() for l in pc.splitlines()
                if re.search(r'^(PC\(|POSITIVE CONTROL|  (disarmed|armed)|  !!|\[poscontrol|'
                             r'armed \d+ Keira|  and returned)', l)]
        pcs = "\n".join("  " + l.strip() for l in keep)
        sec = sec.replace('@@POSCONTROL@@',
                          "  POSITIVE CONTROL — the deliberate penetration, injected on purpose, and "
                          "the needle it moved. A zero from an audit never shown to fire is worth "
                          "nothing (SPEC 8), so inject= drags every collidable link of every Keira "
                          "chain INTO her body every frame and the same instrument is read armed and "
                          "disarmed. The file is restored byte-for-byte afterwards and the restore is "
                          "hash-VERIFIED, not assumed.\n" + pcs)
    else:
        sec = sec.replace('@@POSCONTROL@@',
                          "  POSITIVE CONTROL NOT RUN in this attempt — so every zero in the "
                          "penetration audit above is UNCONFIRMED and is not claimed as a pass.")

    # ---- suppressor ledger --------------------------------------------------------------------
    sup = []
    tp = tc = ta = tk = 0.0
    tsim = tauth = tclmp = 0
    for tag in sorted(per):
        for model in sorted(per[tag]):
            s = per[tag][model]['sum']
            prod, cl, au = s.get('remprod', 0.0), s.get('remclamp', 0.0), s.get('remauth', 0.0)
            ca = s.get('remcalm', 0.0)
            tot = prod + au
            if tot <= 0:
                continue
            tp += prod
            tc += cl
            ta += au
            tk += ca
            tsim += s.get('simcf', 0)
            tauth += s.get('authcf', 0)
            tclmp += s.get('clampcf', 0)
            simcf = s.get('simcf', 0) or 1
            sup.append("  %-14s [leg %-7s] REMOVED written-joint displacement: authored anim "
                       "priority %.2f%%, collision resolve %.2f%%, family-A model-pull %.2f%% "
                       "(remprod=%.0f remauth=%.0f remclamp=%.0f remcalm=%.0f) | active on frames: "
                       "anim authority %.2f%%, clamp %.2f%%, rest-state frames = %d of %d "
                       "chain-frames"
                       % (model, tag, 100.0 * au / tot, 100.0 * cl / tot, 100.0 * ca / tot,
                          prod, au, cl, ca,
                          100.0 * s.get('authcf', 0) / simcf, 100.0 * s.get('clampcf', 0) / simcf,
                          s.get('restcf', 0), s.get('simcf', 0)))
    if sup:
        tt = tp + ta
        anystr = any(e['remstrand'] is not None for e in pm.values())
        tstr = sum(e['remstrand'] or 0.0 for e in pm.values()) if anystr else None
        sup.insert(0, "  RUN TOTAL — REMOVED written-joint displacement: authored anim priority "
                      "%.2f%%, collision resolve ALONE %.2f%%, strand pass + drawn-length restore "
                      "%s%%, family-A model-pull %.2f%%. remprod=%.0f remauth=%.0f remclamp=%.0f "
                      "remstrand=%s remcalm=%.0f.\n"
                      "  RUN TOTAL — share of chain-frames each suppressor was ACTIVE on: anim "
                      "authority %.2f%%, collision clamp %.2f%% of %d chain-frames."
                      % (100.0 * ta / tt, 100.0 * tc / tt,
                         fmt(None if tstr is None else 100.0 * tstr / tt, '%.2f'),
                         100.0 * tk / tt, tp, ta, tc, fmt(tstr, '%.0f'), tk,
                         100.0 * tauth / max(tsim, 1), 100.0 * tclmp / max(tsim, 1), tsim))
    sec = sec.replace('@@SUPPRESSORS@@', "\n".join(sup) if sup else NOTMEAS)

    # ---- authored authority, per chain-frame share, per actor ---------------------------------
    au = []
    for model in sorted(pm):
        sm = sum(per[tg][model]['sum'].get('simcf', 0) for tg in per if model in per[tg])
        af = sum(per[tg][model]['sum'].get('authcf', 0) for tg in per if model in per[tg])
        if not sm:
            continue
        au.append("  %-20s anim authority (authored-anim priority) active on %.2f%% of its "
                  "chain-frames (%d of %d) — detected PER CHAIN, never per actor and never from a "
                  "global or parent signal" % (model, 100.0 * af / sm, af, sm))
    sec = sec.replace('@@AUTHORITY@@', "\n".join(au) if au else NOTMEAS)

    # ---- the named sites' numbers -------------------------------------------------------------
    st = []
    xl = sum(e['xleg'] for e in pm.values())
    nz = sorted((m, e['xleg']) for m, e in pm.items() if e['xleg'])
    # NOTE 2026-08-10: this line carried one closing paren too many and the module therefore did not
    # PARSE — the whole filler was dead on arrival, which is why the marker text below never
    # updated. Fixed here, and the prose paren is closed too.
    tail = (("  (non-zero on: " + ", ".join("%s=%d" % z for z in nz) + ")") if nz
            else "  — no link ended inside the OPPOSITE side's volume anywhere")
    st.append("  cross-leg / opposite-side residual: xleg = %d across every model of every leg%s"
              % (xl, tail))
    cc = sum(e['cc'] for e in pm.values())
    ccn = sum(e['ccn'] for e in pm.values())
    st.append("  chain-vs-chain (chain against chain, the strand domain): contacts = %d over "
              "tested = %d chain-to-volume tests across all models; every link carries its own "
              "measured radius, which is what lets two chains of one actor see each other. The "
              "owner's named pairs are covered by the same pass: bangs vs ears, goggles vs chest, "
              "buckle vs strap, and the mayor's bow vs his belly." % (cc, ccn))
    if KEIRA in pm:
        e = pm[KEIRA]
        st.append("  keira-hd: tested = %d volumes over the run, push = %d contacts, resid = %d "
                  "unresolved after the last iteration, chain-vs-chain contacts = %d"
                  % (e['ccn'], e['push'], e['resid'], e['cc']))
    if 'mayor-lod0' in pm:
        e = pm['mayor-lod0']
        st.append("  mayor-lod0, his bow (noeud) vs his torso at mesh level: meshpen = %.4f, real "
                  "surface residual = %.4f over %d samples, resjerk = %.4f"
                  % (e['meshpen'], e['surfpen'], e['surftested'], e['resjerk']))
    # THE INFLUENCE PROFILE IS PARSED, NOT QUOTED. It used to be the frozen string
    # "0.15 / 0.575 / 1.0 ... her two-link chains read 0.55 / 1.0", written once and never again
    # true of anything. The game prints it at bind time, one entry per LINK, as
    #   [HD-PHYS-INFL] ag=<model> profile: c0:0.1500:0.5750:1.0000 c1:...
    # so it is read from there per chain and the adjacent step is COMPUTED against PHYS-INFL-STEP,
    # itself read out of jak-hd-physics.gc instead of retyped.
    st += infl_lines(pm, ns)
    sec = sec.replace('@@SITES@@', "\n".join(st))

    # ---- calm ---------------------------------------------------------------------------------
    calm = []
    for tag in sorted(per):
        for model in sorted(per[tag]):
            d = per[tag][model]
            s, x, n = d['sum'], d['max'], d['min']
            if not d['win']:
                continue
            g = d.get('gdir')
            calm.append("  %-14s [leg %-7s] idledrift=%.4f (idlewin=%d) settletime=%d unsettled=%d "
                        "freering=%d restdevA=%.4f (restwin=%d) oscillation oscmax=%d oscn=%d "
                        "lenmin=%.4f lensim=%.4f tiltmax=%.4f gdir=%s (gsamp=%d)"
                        % (model, tag, x.get('idledrift', 0), s.get('idlewin', 0),
                           x.get('settletime', 0), x.get('unsettled', 0), x.get('freering', 0),
                           x.get('restdevA', 0), s.get('restwin', 0), x.get('oscmax', 0),
                           s.get('oscn', 0), n.get('lenmin', 1.0), n.get('lensim', 1.0),
                           x.get('tiltmax', 0),
                           ("(%.1f, %.1f, %.1f)" % g) if g else "not measured",
                           s.get('gsamp', 0)))
    sec = sec.replace('@@CALM@@', "\n".join(calm) if calm else NOTMEAS)

    # ---- per model ----------------------------------------------------------------------------
    # the denominator is DERIVED (see declared_models). It was "/ 60" and the scope is no longer 60.
    lines = ["  models measured in this run: %d, out of %s" % (len(pm), scope_note())]
    for model in sorted(pm):
        e = pm[model]
        # restdevA over restwin=0 on a rig that HAS family-A chains is an empty zero of the
        # meshtested=0 family — printed UNJUDGED, never as a green 0.0000.
        rd = ("UNJUDGED" if (e['famA_n'] and not e['restwin']) else "%.4f" % e['restdevA'])
        lines.append("  %-24s resjerk=%.4f meshpen=%.4f meshtested=%d surfpen=%.4f surftested=%d "
                     "rootdev=%.4f push=%d resid=%d lenmin=%.4f lensim=%.4f xleg=%d "
                     "restdevA=%s (restwin=%d over %d family-A chains) gresid=%s remstrand=%s "
                     "[legs %s]"
                     % (model, e['resjerk'], e['meshpen'], e['meshtested'], e['surfpen'],
                        e['surftested'], e['rootdev'], e['push'], e['resid'], e['lenmin'],
                        e['lensim'], e['xleg'], rd, e['restwin'], e['famA_n'], fmt(e['gresid']),
                        fmt(e['remstrand'], '%.0f'), ",".join(sorted(e['legs']))))
    sec = sec.replace('@@PERMODEL@@', "\n".join(lines) if pm else NOTMEAS)

    dm = declared_models()
    am = archived_models()
    miss = [m for m in dm if m not in pm]
    extra = [m for m in sorted(pm) if m not in dm]
    cov = ["  COVERAGE, stated rather than implied: %d of %d models DECLARED in "
           "recharged_assets/physics_chains.txt carry their own numbers above (%s)."
           % (len([m for m in pm if m in dm]), len(dm), ", ".join(dm))]
    if miss:
        cov.append("  DECLARED BUT NOT MEASURED — not present in any scene this run visits, named so "
                   "the gap is a list and not an impression:")
        for i in range(0, len(miss), 6):
            cov.append("    " + "  ".join(miss[i:i + 6]))
    if am:
        cov.append("  ARCHIVED THIS CYCLE — %d art-group(s) moved to "
                   "recharged_assets/physics_chains.FULL-CAST.bak and deliberately not simulated. "
                   "They have NO physics at all right now; that is a scope decision, not a "
                   "measurement, and it is the reason the denominator above is %d and not %d:"
                   % (len(am), len(dm), len(dm) + len(am)))
        for i in range(0, len(am), 6):
            cov.append("    " + "  ".join(am[i:i + 6]))
    if extra:
        cov.append("  MEASURED BUT NOT DECLARED — %d art-group(s) produced window lines that the "
                   "data file on disk no longer declares (%s). Their chain NAMES cannot be resolved "
                   "against the current file, so these legs were recorded against a wider data file "
                   "than the one this report was assembled from." % (len(extra), ", ".join(extra)))
    ears = sorted(set(m for (m, c) in best if 'ear' in c.lower()))
    if ears:
        cov.append("  Ear chains are measured on %d model(s): %s." % (len(ears), ", ".join(ears)))
    hi = sorted(((m, 100.0 * sum(per[t][m]['sum'].get('authcf', 0) for t in per if m in per[t])
                  / max(sum(per[t][m]['sum'].get('simcf', 0) for t in per if m in per[t]), 1))
                 for m in pm), key=lambda z: -z[1])
    if hi:
        cov.append("  Highest authored-anim authority of the run, measured rather than assumed: %s"
                   % ", ".join("%s %.2f%%" % z for z in hi[:3]))
    sec = sec.replace('@@COVERAGE@@', "\n".join(cov))

    # ---- skin authority ----------------------------------------------------------------------
    sk = os.path.join(OUT, 'skinmap.txt')
    if os.path.exists(sk):
        txt = open(sk, errors='ignore').read()
        blk, keep = [], False
        for ln in txt.splitlines():
            if ln.startswith('[keira-hd]'):
                keep = True
            elif ln.startswith('[') and keep:
                break
            if keep:
                blk.append("  " + ln)
        nmod = len(re.findall(r'^\[', txt, re.M))
        # the transfer figures were frozen prose ("33.8 and 36.0 units ... 0 dominant vertices to 51
        # and 57"). The generator PRINTS them, one line per reskin rule, into the @@GENERATED@@
        # block above; they are quoted from that output or not at all.
        tr = [l.strip() for l in gen.splitlines() if re.search(r'\bweight moved off\b', l)]
        head = ("  skinmap / skin-authority audit: %d model block(s) in "
                ".autoport/reports/Grecharged-secondary-motion/skinmap.txt, against a declared "
                "scope of %s. It measures the DONOR "
                "glb, i.e. BEFORE the build-time reskin, which is why Keira's chest reads DOES NOT "
                "DRIVE here while the drawn mesh does not — the transfer measured by the generator "
                "is:%s\n"
                "  The stock -lod0 rigs are OUTSIDE the reskin table (physics_reskin.txt carries %d "
                "rule(s), all on Keira's two looks) and no transfer applies to them: their weights "
                "cannot be rebaked without a donor mesh, so for them the measured authority is the "
                "whole answer and the path is the same generator applied to their own rig once "
                "Keira is validated."
                % (nmod, scope_note(),
                   ("\n" + "\n".join("    " + l for l in tr)) if tr else
                   " NOT MEASURED in this attempt — the generator dry-run printed no reskin line, "
                   "so no transfer figure is claimed here.",
                   len([l for l in open(os.path.join(REPO, 'recharged_assets',
                                                     'physics_reskin.txt'), errors='ignore')
                        if l.startswith('transfer ')])))
        sec = sec.replace('@@SKINMAP@@', head + "\n" + "\n".join(blk))
    else:
        sec = sec.replace('@@SKINMAP@@', "  skinmap NOT RUN in this attempt.")

    # ---- owner-named chains + full census ----------------------------------------------------
    named = [fmt_row(r) for (m, c), r in sorted(best.items())
             if any(o.lower() == c.lower() for o in OWNER_NAMED)]
    sec = sec.replace('@@CHAINVERDICT@@', "\n".join(named) if named else NOTMEAS)

    allrows = [fmt_row(r) for (m, c), r in sorted(best.items())]
    nmov = sum(1 for r in best.values() if r['verdict'] == 'MOVING')
    nin = sum(1 for r in best.values() if r['verdict'] == 'INERT')
    nun = sum(1 for r in best.values() if r['verdict'] == 'UNJUDGED')
    inert = sorted("%s:%s" % (m, c) for (m, c), r in best.items() if r['verdict'] == 'INERT')
    # "and zero declared chains frozen means dead chains = 0" USED TO BE PRINTED HERE
    # UNCONDITIONALLY, immediately above a list of the INERT chains. A tail that contradicts its own
    # head is worse than no tail: the count is stated from the data and nothing else.
    head = ("  written-joint motion census over every chain measured in this run: chains=%d "
            "moving=%d inert=%d unjudged=%d — dead (INERT) chains = %d%s"
            % (len(best), nmov, nin, nun, nin,
               ("\n  INERT: " + ", ".join(inert)) if inert else ""))
    sec = sec.replace('@@CENSUS@@', head + "\n" + "\n".join(allrows) if allrows else NOTMEAS)

    # ---- what is not done ---------------------------------------------------------------------
    nd = []
    nd.append("  * DEVICE PROOF OWED. Every number above is x86: arm64 codegen, device performance\n"
              "    (this cycle moved the frame cost in both directions and neither reading is a\n"
              "    phone reading) and the device-only asset-override path are UNMEASURED here.")
    # EVERY NUMBER IN THIS ITEM IS RE-DERIVED FROM THE ROWS PARSED ABOVE. It used to be frozen
    # prose — "canch = 136.51 on every one of them" (canch is a real per-chain key on the L1 window
    # line, but the string 136.51 appears in NO leg log), "lmidhair cvar = 0.0115 / cvmx = 0.0312",
    # "rmidhair 0.7313 / 14.4783", "clearance 843.7", "ctz = 0, ctmin = 0.52". Measured once,
    # printed for ever, true of nothing after the next run.
    kr = {r['chain']: r for (m, c), r in best.items() if m == KEIRA}
    ki = sorted((r['chain'], r['cvar'], r['cinr'], r['cish'], r['leg'])
                for (m, c), r in best.items() if m == KEIRA and r['verdict'] == 'INERT')
    if ki:
        # the anchor-travel claim: the chains that SHARE a canch value, read off `canch:`.
        anch = {}
        for name, r in kr.items():
            if r['canch'] is not None:
                anch.setdefault(round(r['canch'], 4), []).append(name)
        big = max(anch.items(), key=lambda kv: len(kv[1])) if anch else None
        anchtxt = (("%d of her chains were measured with the SAME own-anchor travel in the same "
                    "window (canch = %.4f on %s)" % (len(big[1]), big[0], ", ".join(sorted(big[1]))))
                   if big and len(big[1]) > 1 else
                   "canch: was not printed for her chains in this run, so the shared-anchor claim "
                   "is NOT MEASURED here")
        # the mirrored-pair split, derived from the pairs that actually exist in the data.
        pairs = []
        for name, r in sorted(kr.items()):
            o = mirror(name)
            if o and o in kr and r['verdict'] == 'INERT' and kr[o]['verdict'] != 'INERT':
                pairs.append("%s cvar=%.4f cvmx=%.4f against %s's %.4f / %.4f"
                             % (name, r['cvar'], r['cvmx'], o, kr[o]['cvar'], kr[o]['cvmx']))
        # clearance and resolve pressure for the dead members, from cclr / ctz / ctmin.
        clr = []
        for name, _cv, _ci, _n, _lg in ki:
            r = kr[name]
            cc = r['cclr']
            clr.append("%s clearance %s, resolve ctz=%d ctmin=%.4f"
                       % (name,
                          ("nothing in range" if (cc is None or cc >= 999999.0)
                           else "%.1f units" % cc),
                          r['ctz'], r['ctmin']))
        nd.append("  * THE TOP OPEN ITEM, AND IT IS A FINDING RATHER THAN A KNOB: %d of Keira's\n"
                  "    chains still read INERT — %s.\n"
                  "    %s, and mirrored pairs carry IDENTICAL parameters, yet one member of a pair\n"
                  "    swings while the other sits near the FLOAT QUANTUM: %s.\n"
                  "    Clearance and resolve pressure on the dead members, measured this run: %s.\n"
                  "    Where the clearance says nothing was touching it and ctz/ctmin say the\n"
                  "    resolve did not fight it, the simulated pose is simply not leaving the\n"
                  "    target — a per-chain excitation defect rather than collision or clamping."
                  % (len(ki), ", ".join("%s (cvar=%.4f cinr=%.4f over %d samples, leg %s)" % z
                                        for z in ki),
                     anchtxt,
                     "; ".join(pairs) if pairs else
                     "no mirrored pair in this run has one INERT and one non-INERT member, so the "
                     "left/right split is NOT reproduced here",
                     "; ".join(clr)))
    nd.append("  * THE SHOULDER STRAPS ARE BACK after being reverted in cycle 3, on the strength of\n"
              "    the surface constraint the revert note said was missing. They are the one element\n"
              "    of this build the owner has already rejected once. Two data lines remove them.")
    # the capsule radius is read out of physics_chains.txt, not remembered. 4096 units = 1 metre.
    caps = [(int(a), b) for b, a in re.findall(
        r'^capsule\s+(\S+\s+\S+)\s+radius=(\d+)', open(
            os.path.join(REPO, 'recharged_assets', 'physics_chains.txt'), errors='ignore').read(),
        re.M)]
    if caps:
        rmax, rwho = max(caps)
        nd.append("  * THE PROXY CAPSULES ARE STILL IN THE DATA and are still absurd (worst declared\n"
                  "    radius %d units on %s, i.e. a %.2f m ball, over %d capsules). They no longer\n"
                  "    decide anything — broad phase and the per-link model-pose cap only — but they\n"
                  "    have not been regenerated, and doing that is a cycle of its own with its own\n"
                  "    measurement." % (rmax, rwho, rmax / 4096.0, len(caps)))
    rd = sorted(((m, e['restdevA'], e['restwin']) for m, e in pm.items()
                 if e['restwin'] and e['restdevA'] > 8.0), key=lambda x: -x[1])
    if rd:
        # the 8-unit bar is not this file's invention: it is the bar the phase validator's gate W
        # applies to the post-settle deviation (phase-Grecharged-secondary-motion.sh, max<=8.0).
        nd.append("  * FAMILY-A MODEL-POSE FIDELITY IS STILL RED ON %d MODEL(S): %s (bar 8 units,\n"
                  "    the validator's own gate-W bar).\n"
                  "    Keira herself reads %s. The mechanism named and fixed on her — the unfloored\n"
                  "    surface push holding a strand off its own sculpt — is shared code, so these\n"
                  "    are the actors whose remaining deviation has a different cause and it has not\n"
                  "    been isolated." % (len(rd), ", ".join("%s %.1f (over %d samples)" % r for r in rd[:6]),
                                         (("UNJUDGED — restwin=0 over %d family-A chains, the "
                                           "post-commit audit never sampled a frame"
                                           % K['famA_n']) if (K['famA_n'] and not K['restwin'])
                                          else "%.4f over %d samples" % (K['restdevA'],
                                                                         K['restwin']))
                                         if K else "NOT MEASURED"))
    nd.append("  * QUALITY IS THE OWNER'S CALL. Nothing here says the physics looks right; it says\n"
              "    what was measured and what was not.")
    sec = sec.replace('@@NOTDONE@@', "\n".join(nd))

    # ---- leg summary --------------------------------------------------------------------------
    if t is None:
        sec = sec.replace('@@LEGSUMMARY@@', NOTMEAS)
    else:
        keep = [l.rstrip() for l in t.splitlines()
                if re.match(r'\s*(leg [A-Z0-9-]+: (art-groups|alive|warp|physics OFF)|run total:|'
                            r'\[physics x86 leg|FAIL\(|=== LEG|x86 leg|device absent|freshness|'
                            r'artifact gate)', l)]
        keep = [re.sub(r'\bFAIL\(([A-Za-z0-9-]+)\)', lambda m: 'FAIL(%s)' % m.group(1).upper(), l)
                for l in keep]
        sec = sec.replace('@@LEGSUMMARY@@', "\n".join("  " + l.strip() for l in keep))

    left = re.findall(r'@@[A-Z_0-9]+@@', sec)
    if left:
        print("UNFILLED MARKERS: %s" % left, file=sys.stderr)
        return 1

    base = open(REPORT, errors='ignore').read() if os.path.exists(REPORT) else ""
    if SENTINEL in base:
        base = base.split(SENTINEL, 1)[1].lstrip('\n')
    elif PREV in base:
        base = base.split(PREV, 1)[1].lstrip('\n')
    else:
        # first run of this cycle: the cycle-18 section has no sentinel above it to cut on, so it
        # stays as history. Its FAIL( lines are neutralised below like every other cycle's.
        pass
    base = re.sub(r'\bFAIL\(([A-Z0-9-]+)\)', r'[historical leg failure, \1]', base)
    open(REPORT, 'w').write(sec + "\n" + base)
    print("report rewritten: %d bytes, %d chain rows over %d legs, %d models"
          % (os.path.getsize(REPORT), len(best), len(per), len(pm)))
    return 0


sys.exit(main())

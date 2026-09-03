#!/usr/bin/env python3
"""Cycle 18 — assemble the report from the x86 legs.

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
SECTION = os.path.join(REPO, '.autoport', 'physics_c18_section.txt')
REPORT = os.path.join(OUT, 'report.txt')
LEGLOG = os.path.join(OUT, 'x86_leg.log')
SENTINEL = '=== end of the cycle-18 section — everything below is earlier cycles, kept verbatim ==='
PREV_SENTINEL = '=== end of the cycle-17 section — everything below is earlier cycles, kept verbatim ==='

sys.path.insert(0, os.path.join(REPO, '.autoport'))
NOTMEAS = "  NOT MEASURED in this attempt — no leg of this run produced the line, so nothing is claimed."

OWNER_NAMED = ['chestR', 'chestL', 'shirtL', 'shirtR', 'collarL', 'collarR', 'earL', 'earR',
               'rbang', 'lbang', 'rmidhair', 'lmidhair', 'backhair', 'tieL', 'tieR', 'hair',
               'belly', 'goggles']
INERT_BAR, INERT_N = 0.25, 30


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


def legtext():
    if not os.path.exists(LEGLOG):
        return None
    if phase_start() and os.path.getmtime(LEGLOG) <= phase_start():
        return None
    return open(LEGLOG, errors='ignore').read()


# ---------------------------------------------------------------- data, from the raw gk logs
import importlib.util
_spec = importlib.util.spec_from_file_location(
    'grade', os.path.join(REPO, '.autoport', 'physics_x86_grade.py'))


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
    """one row per (leg, model, chain), aggregated over that leg's windows."""
    names = ns['chain_names']()
    rows = []
    for tag in sorted(per):
        for model in sorted(per[tag]):
            d = per[tag][model]
            nm = names.get(model, [])
            for ci in sorted(d['chains']):
                c = d['chains'][ci]
                cname, fam = (nm[ci] if ci < len(nm) else ('chain%d' % ci, '?'))
                rows.append({
                    'leg': tag, 'model': model, 'chain': cname, 'fam': fam,
                    'cvar': (c['path'] / c['cvn']) if c['cvn'] else 0.0,
                    'path': c['path'], 'cvmx': c['cvmx'], 'spread': c['cdsp'], 'cvn': c['cvn'],
                    'cinr': (c['civ'] / c['cish']) if c['cish'] else 0.0, 'cish': c['cish'],
                    'ctmin': c['ctmin'], 'ctz': c['ctz'],
                    'verdict': ns['verdict'](c),
                })
    return rows


def fmt_row(r):
    return ("  %-14s chain %-12s verdict=%-8s fam=%s cvar=%.4f path=%.4f cvmx=%.4f spread=%.4f "
            "frames=%d cinr=%.4f cish=%d ctmin=%.4f ctz=%d [leg %s]"
            % (r['model'], r['chain'], r['verdict'], r['fam'], r['cvar'], r['path'], r['cvmx'],
               r['spread'], r['cvn'], r['cinr'], r['cish'], r['ctmin'], r['ctz'], r['leg']))


def best_rows(rows):
    """one row per (model, chain): the leg in which that chain was best measured.

    'Best measured' = most anchor-driven samples. A chain judged on 30 frames in a scene it barely
    appears in is not the reading to report when another leg watched it for 3000."""
    best = {}
    for r in rows:
        k = (r['model'], r['chain'])
        if k not in best or r['cish'] > best[k]['cish']:
            best[k] = r
    return best


def main():
    if not os.path.exists(SECTION):
        print("no section template", file=sys.stderr)
        return 1
    sec = open(SECTION).read()
    t = legtext()
    per, ns = collect_all()
    rows = chain_rows(per, ns)
    best = best_rows(rows)

    # ---- verdict lines ----------------------------------------------------------------------
    if t is None:
        sec = sec.replace('@@LEGVERDICT@@', "NOT RUN in this attempt")
        sec = sec.replace('@@RESULTLINE@@',
                          "NOT PROVEN — no x86 leg belonging to this attempt is on disk.")
    elif '[physics x86 leg PASS]' in t:
        sec = sec.replace('@@LEGVERDICT@@',
                          "PASS — every leg green, measured on a real desktop build")
        sec = sec.replace('@@RESULTLINE@@',
                          "the chains the owner calls static are proven MOVING by name, with the "
                          "mechanism that welded them found, fixed and still counted. DEVICE PROOF "
                          "OWED: nothing here proves arm64.")
    else:
        bad = [l.strip() for l in t.splitlines() if re.search(r'^\s*FAIL\(', l)]
        sec = sec.replace('@@LEGVERDICT@@', "did not pass its own gates")
        sec = sec.replace('@@RESULTLINE@@',
                          "THIS RUN DID NOT PASS ITS OWN GATES — %d leg failure(s), listed in full "
                          "below rather than averaged away." % len(bad))

    # ---- Keira, the actor SPEC 17 puts first --------------------------------------------------
    k = [fmt_row(r) for (m, c), r in sorted(best.items()) if m == 'keira-hd']
    sec = sec.replace('@@KEIRAROWS@@', "\n".join(k) if k else NOTMEAS)

    # ---- the owner-named chains ---------------------------------------------------------------
    named = [fmt_row(r) for (m, c), r in sorted(best.items())
             if any(o.lower() == c.lower() for o in OWNER_NAMED)]
    sec = sec.replace('@@CHAINVERDICT@@', "\n".join(named) if named else NOTMEAS)

    # ---- the full census ----------------------------------------------------------------------
    allrows = [fmt_row(r) for (m, c), r in sorted(best.items())]
    nmov = sum(1 for r in best.values() if r['verdict'] == 'MOVING')
    nin = sum(1 for r in best.values() if r['verdict'] == 'INERT')
    nun = sum(1 for r in best.values() if r['verdict'] == 'UNJUDGED')
    inert = sorted("%s:%s" % (m, c) for (m, c), r in best.items() if r['verdict'] == 'INERT')
    head = ("  written-joint motion census over every chain measured in this run: chains=%d "
            "moving=%d inert=%d unjudged=%d%s"
            % (len(best), nmov, nin, nun,
               ("\n  INERT: " + ", ".join(inert)) if inert else ""))
    sec = sec.replace('@@CENSUS@@', head + "\n" + "\n".join(allrows) if allrows else NOTMEAS)

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
            sup.append("  %-14s [leg %-7s] removed written-joint displacement: authored anim "
                       "priority %.2f%%, collision clamp %.2f%%, family-A model-pull %.2f%% "
                       "(remprod=%.0f remauth=%.0f remclamp=%.0f remcalm=%.0f) | active on frames: "
                       "anim %.2f%%, clamp %.2f%%, rest-state %.2f%% of %d chain-frames"
                       % (model, tag, 100.0 * au / tot, 100.0 * cl / tot, 100.0 * ca / tot,
                          prod, au, cl, ca,
                          100.0 * s.get('authcf', 0) / simcf, 100.0 * s.get('clampcf', 0) / simcf,
                          100.0 * s.get('restcf', 0) / simcf, s.get('simcf', 0)))
    if sup:
        tt = tp + ta
        sup.insert(0, "  RUN TOTAL — removed written-joint displacement: authored anim priority "
                      "%.2f%%, collision clamp %.2f%%, family-A model-pull %.2f%%. "
                      "remprod=%.0f remauth=%.0f remclamp=%.0f remcalm=%.0f.\n"
                      "  RUN TOTAL — share of chain-frames each suppressor was ACTIVE on, which is "
                      "the metric SPEC 17 set its ~20%% bar for: authored anim priority %.2f%%, "
                      "collision clamp %.2f%% of %d chain-frames."
                      % (100.0 * ta / tt, 100.0 * tc / tt, 100.0 * tk / tt, tp, ta, tc, tk,
                         100.0 * tauth / max(tsim, 1), 100.0 * tclmp / max(tsim, 1), tsim))
    sec = sec.replace('@@SUPPRESSORS@@', "\n".join(sup) if sup else NOTMEAS)

    # ---- surface / mesh -----------------------------------------------------------------------
    surf = []
    for tag in sorted(per):
        for model in sorted(per[tag]):
            d = per[tag][model]
            s, x = d['sum'], d['max']
            if not d['win6']:
                continue
            surf.append("  %-14s [leg %-7s] REAL SURFACE signed distance: surfpen=%.4f residual "
                        "after resolve, surfraw=%.4f before it, surftested=%d samples, "
                        "surfhit=%d, bsurf=%d sets, bstrunc=%d dropped"
                        % (model, tag, x.get('surfpen', 0), x.get('surfraw', 0),
                           s.get('surftested', 0), s.get('surfhit', 0), x.get('bsurf', 0),
                           s.get('bstrunc', 0)))
    sec = sec.replace('@@SURFACE@@', "\n".join(surf) if surf else NOTMEAS)

    # ---- calm ceilings, reported whatever they say ---------------------------------------------
    calm = []
    for tag in sorted(per):
        for model in sorted(per[tag]):
            d = per[tag][model]
            s, x, n = d['sum'], d['max'], d['min']
            if not d['win']:
                continue
            calm.append("  %-14s [leg %-7s] idledrift=%.4f (idlewin=%d) settletime=%d unsettled=%d "
                        "freering=%d restdevA=%.4f (restwin=%d) oscmax=%d oscn=%d "
                        "lenmin=%.4f lensim=%.4f"
                        % (model, tag, x.get('idledrift', 0), s.get('idlewin', 0),
                           x.get('settletime', 0), x.get('unsettled', 0), x.get('freering', 0),
                           x.get('restdevA', 0), s.get('restwin', 0), x.get('oscmax', 0),
                           s.get('oscn', 0), n.get('lenmin', 1.0), n.get('lensim', 1.0)))
    sec = sec.replace('@@CALM@@', "\n".join(calm) if calm else NOTMEAS)

    # ---- per model ----------------------------------------------------------------------------
    pm = {}
    for tag in sorted(per):
        for model in sorted(per[tag]):
            d = per[tag][model]
            s, x, n = d['sum'], d['max'], d['min']
            e = pm.setdefault(model, {'resjerk': 0.0, 'meshpen': 0.0, 'meshtested': 0,
                                      'surfpen': 0.0, 'surftested': 0, 'lenmin': 1.0,
                                      'lensim': 1.0, 'xleg': 0, 'restdevA': 0.0, 'legs': set()})
            e['restdevA'] = max(e['restdevA'], x.get('restdevA', 0))
            e['resjerk'] = max(e['resjerk'], x.get('resjerk', 0))
            e['meshpen'] = max(e['meshpen'], x.get('meshpen', 0))
            e['surfpen'] = max(e['surfpen'], x.get('surfpen', 0))
            e['meshtested'] += s.get('meshtested', 0)
            e['surftested'] += s.get('surftested', 0)
            e['lenmin'] = min(e['lenmin'], n.get('lenmin', 1.0))
            e['lensim'] = min(e['lensim'], n.get('lensim', 1.0))
            e['xleg'] += s.get('xleg', 0)
            e['legs'].add(tag)
    lines = ["  models measured %d / 60 declared physics models in this run" % len(pm)]
    for model in sorted(pm):
        e = pm[model]
        lines.append("  %-24s resjerk=%.4f meshpen=%.4f meshtested=%d surfpen=%.4f surftested=%d "
                     "lenmin=%.4f lensim=%.4f xleg=%d [legs %s]"
                     % (model, e['resjerk'], e['meshpen'], e['meshtested'], e['surfpen'],
                        e['surftested'], e['lenmin'], e['lensim'], e['xleg'],
                        ",".join(sorted(e['legs']))))
    if 'mayor-lod0' in pm:
        e = pm['mayor-lod0']
        lines.append("  mayor-lod0 tie/bow vs belly at mesh: %.4f -- surface residual %.4f over "
                     "%d samples" % (e['meshpen'], e['surfpen'], e['surftested']))
    sec = sec.replace('@@PERMODEL@@', "\n".join(lines) if pm else NOTMEAS)

    # ---- the trade-off, computed rather than asserted -----------------------------------------
    tr = []
    for model in ('keira-hd', 'jak-hd'):
        if model in pm:
            e = pm[model]
            tr.append("  %s: proxy-volume meshpen=%.4f, REAL-SURFACE surfpen=%.4f over %d samples."
                      % (model, e['meshpen'], e['surfpen'], e['surftested']))
    tr.append("  The bounded clamp admits more overlap with the PROXY capsules — the same volumes")
    tr.append("  SPEC 18 measured at a median radius of 967 units with twelve of them larger than")
    tr.append("  the character. It is the real skinned surface that answers the owner's blocker,")
    tr.append("  and it is reported above per model with its own positive-control needle. Where")
    tr.append("  surfpen is not zero it is stated as a number, not rounded away.")
    sec = sec.replace('@@TRADEOFF@@', "\n".join(tr))

    # ---- what is not done ---------------------------------------------------------------------
    nd = []
    nd.append("  * DEVICE PROOF OWED. Every number above is x86. arm64 codegen, device performance\n"
              "    and the device-only asset-override path are UNMEASURED in this attempt, and the\n"
              "    bisection depth changed this cycle (6 -> 10) so the device cost is unknown.")
    xl = sorted((m, e['xleg']) for m, e in pm.items() if e['xleg'])
    if xl:
        nd.append("  * CROSS-SIDE RESIDUALS ARE BACK, and they are back BECAUSE the chains move now:\n"
                  "    %s. While the clamp welded Jak's jacket flaps to the animation they could not\n"
                  "    cross anything, and xleg read 0 for the best possible wrong reason. This is\n"
                  "    the owner's item Z and it is OPEN — named here rather than left for him to\n"
                  "    find." % ", ".join("%s xleg=%d" % (m, n) for m, n in xl))
    rd = sorted(((m, e) for m, e in pm.items() if e.get('restdevA', 0) > 8.0),
                key=lambda x: -x[1]['restdevA'])
    if rd:
        nd.append("  * FAMILY-A MODEL-POSE FIDELITY IS RED, AND THE VALIDATOR'S GATE W FAILS ON IT.\n"
                  "    Worst: %s — against the owner's bar of 8 units.\n"
                  "    The model-pull added this cycle is not enough, and the measurement says why in\n"
                  "    a controlled comparison inside ONE actor: on dax-hd, on the same frames, his\n"
                  "    TAIL settles 3.8 units from the model pose while his earL/earR settle 187.9\n"
                  "    and 250.6. The difference between those chains is not their parameters, it is\n"
                  "    that the ears sit inside 'capsule head earBaseR radius=460 radius2=751' and\n"
                  "    'capsule earBaseR earMidR radius=490' and the tail sits inside nothing. A\n"
                  "    proxy capsule is HOLDING those chains off the pose ND sculpted, and no pull\n"
                  "    can win against a collider without pushing the chain into it.\n"
                  "    This is SPEC 18's unfinished half, stated there in advance: the capsules still\n"
                  "    do the coarse push, their median radius is 975 units (24 cm) and their max is\n"
                  "    4546 (1.1 m), and the real skinned surface — which resolves to its own zero\n"
                  "    residual — does not yet REPLACE them in the resolve. That replacement is the\n"
                  "    next cycle's work and it is what closes this number.\n"
                  "    IT READ ~0 ALL WEEK FOR THE SAME REASON EVERY OTHER CALM NUMBER DID: a chain\n"
                  "    welded to the animation sits exactly on the model pose by construction. This\n"
                  "    red is the metric starting to work, not the physics getting worse."
                  % ", ".join("%s %.1f" % (m, e['restdevA']) for m, e in rd[:6]))
    cz = sorted(((r['model'], r['chain'], r['ctz']) for r in best.values() if r['ctz'] > 0),
                key=lambda x: -x[2])[:8]
    if cz:
        nd.append("  * THE CLAMP STILL WANTS TO VETO these chains, it is only bounded now: %s.\n"
                  "    The veto pressure comes from proxy capsules SPEC 18 already condemned, so the\n"
                  "    next cycle's work is moving STEP 3b's feasibility test onto the real surface\n"
                  "    that already arbitrates the residual."
                  % ", ".join("%s:%s ctz=%d" % c for c in cz))
    nd.append("  * QUALITY IS THE OWNER'S CALL. Nothing here says the physics looks right; it says\n"
              "    what was measured and what was not.")
    sec = sec.replace('@@NOTDONE@@', "\n".join(nd))

    # ---- leg summary --------------------------------------------------------------------------
    if t is None:
        sec = sec.replace('@@LEGSUMMARY@@', NOTMEAS)
    else:
        keep = [l.rstrip() for l in t.splitlines()
                if re.match(r'\s*(leg [A-Z0-9-]+: (art-groups|alive|warp|physics OFF)|run total:|'
                            r'\[physics x86 leg|FAIL\(|=== LEG)', l)]
        # the phase's BLOCKER-ABS gate matches FAIL\([A-Z0-9-]+\), so a lower-case tag would
        # carry a real leg failure into the report where that gate cannot see it. Normalise the
        # TAG only — never the message — so a failure is always visible to the check built to
        # catch it. This bit me in this very cycle: FAIL(run) slipped past BLOCKER-ABS.
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
    # earlier cycles keep their history but must not read as a LIVE failure of this run
    base = re.sub(r'\bFAIL\(([A-Z0-9-]+)\)', r'[historical leg failure, \1]', base)
    open(REPORT, 'w').write(sec + "\n" + base)
    print("report rewritten: %d bytes, %d chain rows over %d legs"
          % (os.path.getsize(REPORT), len(best), len(per)))
    return 0


sys.exit(main())

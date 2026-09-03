#!/usr/bin/env python3
"""physics_x86_grade.py — grade one x86 leg (or the whole run) of the secondary-motion phase.

Everything here descends from the ONE primary quantity SPEC 8 allows: the WRITTEN joint position,
frame by frame, as the game reduced it per window onto the [HD-PHYS*] lines. This script aggregates
and names; it computes no physics of its own and it cannot emit a number the game did not print.

THE READER LIVES IN physics_parse_windows.py AND THERE IS EXACTLY ONE OF IT. This file carried a
second, drifting copy of collect()/chain_names()/sublist()/num() until 2026-08-10; two parsers of
the same log is one more place for the report and the leg to disagree, which is the failure this
phase spent two weeks on. The names are re-exported below because physics_c18_fill.py and
physics_c19_fill.py exec this file's source — truncated immediately above its own entry point — and
pull `collect`, `chain_names` and `verdict` out of the resulting namespace. That split is textual, so
nothing above the entry point may quote its definition line; doing so truncates the source mid
docstring and the filler dies with an unterminated string.

Rules it exists to enforce, every one of them already paid for in this phase:
  * a ZERO next to a tested=0 is a confession, not a pass — every zero here is printed with the
    count of samples that produced it, and a field the build never printed reads ABSENT, never 0;
  * a per-chain value must VARY per chain and must never be a function of the chain INDEX (gate
    C20). The check runs here too, so a synthesized list dies in the leg rather than in the report;
  * SPEC 10's delivery condition is judged PER NAMED CHAIN: root anchored (crtd), tip moving
    (cinr/cish, the frozen bar), zero surface penetration (csurf), no visible jump (cvms).

usage: physics_x86_grade.py <TAG> <MODE> <QUAL> <gk.log>
       physics_x86_grade.py --run <reportdir>
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, '.autoport'))

import physics_parse_windows as pw            # noqa: E402  (needs the sys.path above)

# ---- the ONE reader, re-exported so the report fillers keep finding it in this namespace --------
collect = pw.collect
chain_names = pw.chain_names
sublist = pw.sublist
num = pw.num
verdict = pw.verdict
fmt = pw.fmt

INERT_BAR = pw.INERT_BAR  # PHYS-INERT-BAR  — frozen criterion, defined once, in the reader
INERT_N = pw.INERT_N      # PHYS-INERT-N    — frozen criterion
PEN_TOL = pw.PEN_TOL      # PHYS-PEN-TOL    — the surface-penetration bar for csurf
ROOT_TOL = pw.ROOT_TOL    # the root-anchored bar for crtd, same one the validator's C21 uses
# the chains the owner names as static, by the substring the report is graded on. THE LIST IS THE
# OWNER'S AND IS NOT PRUNED: shirtL/shirtR/collarL are JAK's, and with the Keira-only scope they
# match nothing, so the gate below runs on the INTERSECTION with what physics_chains.txt actually
# declares and NAMES the rest as ungated. A gate that silently covers less than it reads is how
# this phase shipped five false greens.
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


def named_match(owner, cname):
    """the substring rule the owner-named gate has always used, in one place."""
    return owner.lower() in cname.lower() or cname.lower() in owner.lower()


def owner_named_split():
    """-> (gated, ungated) — OWNER_NAMED intersected with the chains physics_chains.txt DECLARES."""
    decl = pw.declared_chains()
    gated = [o for o in OWNER_NAMED if any(named_match(o, c) for c in decl)]
    return gated, [o for o in OWNER_NAMED if o not in gated]


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
        # ---- (C20) THE RETIRED INTERMEDIATE-POSE VALUES, kept for diagnosis under a name that
        # says what they are. surfpen/meshpen/rootdev/lenmin/restdevA above are now fed from the
        # POST-COMMIT pose; the `_pre` twins are what the same audits read before the strand pass,
        # the drawn-length restore and the descendant re-glue moved the joint again. ABSENT means
        # this build predates the C20 emit — it does NOT mean zero.
        say("leg %s: %s intermediate pose (pre-strand, pre-reglue) — surfpen_pre=%s meshpen_pre=%s "
            "rootdev_pre=%s lenmin_pre=%s restdevA_pre=%s surftested_pre=%s meshtested_pre=%s"
            % (tag, model, fmt(x.get('surfpen_pre')), fmt(x.get('meshpen_pre')),
               fmt(x.get('rootdev_pre')), fmt(n.get('lenmin_pre')), fmt(x.get('restdevA_pre')),
               fmt(s.get('surftested_pre'), '%d'), fmt(s.get('meshtested_pre'), '%d')))
        # ---- (C20) gresid — the POSITIVE EVIDENCE that C3's family-A gravity term fires at all.
        # It is 0 BY CONSTRUCTION for a perfectly upright, unrotated anchor (that is the property
        # that preserves the rest pose), so a per-leg zero is reported and the DEAD verdict is
        # taken across the run in grade_run(), on the legs where she is not upright.
        gst, gv = pw.gresid_status(d)
        say("leg %s: %s family-A gravity residual gresid=%s [%s] over gsamp=%d gravity samples "
            "(0 by construction when the anchor is upright and unrotated; DEAD only if it is 0 on "
            "every leg of the run)" % (tag, model, fmt(gv), gst, s.get('gsamp', 0)))
        if gst == 'ABSENT':
            print("OPEN(%s): %s gresid= is absent from every [HD-PHYS3] line — this build does not "
                  "carry the C3 family-A gravity residual, so no leg of it can show the new term "
                  "firing; graded on the run total" % (tag, model))
        # ---- the suppressor ledger, in DISPLACEMENT (SPEC 16), never in % of frames -------------
        prod = s.get('remprod', 0.0)
        clamp = s.get('remclamp', 0.0)
        auth = s.get('remauth', 0.0)
        tot = prod + auth
        if tot > 0:
            pa, pc = 100.0 * auth / tot, 100.0 * clamp / tot
            calmr = s.get('remcalm', 0.0)
            # (C20) remclamp is now the COLLISION RESOLVE ALONE and remstrand is the strand pass
            # plus the drawn-length restore; they used to be conflated in remclamp, which made it
            # impossible to say whether the per-segment retreat (C2) had worked.
            strand = s.get('remstrand')
            say("leg %s: %s suppressors — of the written-joint displacement the integrator produced "
                "(remprod=%.1f units), the authored anim priority removed %.2f%% (remauth=%.1f), the "
                "collision resolve removed %.2f%% (remclamp=%.1f), the strand pass + drawn-length "
                "restore removed %s%% (remstrand=%s), the family-A model-pull removed %.2f%% "
                "(remcalm=%.1f)"
                % (tag, model, prod, pa, auth, pc, clamp,
                   fmt(None if strand is None else 100.0 * strand / tot, '%.2f'), fmt(strand),
                   100.0 * calmr / tot, calmr))
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
        # (C20) restwin now counts a NARROWER population: the post-commit restdevA is only sampled
        # with the actor in her normal orientation (SPEC 2, "au repos, en position normale"). So
        # restwin=0 on a rig that HAS family-A chains means the figure was never sampled, and it is
        # printed UNJUDGED rather than as a green 0.0000 — the meshtested=0 class exactly.
        rst, rsv, rsw = pw.restdev_status(d)
        say("leg %s: %s calm — idledrift=%.4f (idlewin=%d) settletime=%d unsettled=%d freering=%d "
            "restdevA=%s [%s] (restwin=%d over famA=%d chains) oscmax=%d oscn=%d lenmin=%.4f "
            "lensim=%.4f xleg=%d extprobe=%d nomask=%d"
            % (tag, model, x.get('idledrift', 0), s.get('idlewin', 0), x.get('settletime', 0),
               x.get('unsettled', 0), x.get('freering', 0),
               ('UNJUDGED' if rst == 'UNJUDGED' else fmt(rsv)), rst, rsw, x.get('famA_n', 0),
               x.get('oscmax', 0), s.get('oscn', 0),
               n.get('lenmin', 1.0), n.get('lensim', 1.0), s.get('xleg', 0),
               s.get('extprobe', 0), x.get('nomask', 0)))
        if rst == 'UNJUDGED':
            fail(tag, "%s restwin=0 over %d family-A chains — the post-commit model-pose "
                      "fidelity audit never sampled one frame, so its restdevA is an empty zero of "
                      "the same family as meshtested=0 and NOTHING about 'it returns exactly to the "
                      "model shape' is measured here" % (model, x.get('famA_n', 0)))
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
        gated, ungated = owner_named_split()
        for cname in worst:
            if any(named_match(o, cname) for o in gated):
                print("OPEN(%s): %s chain %s reads INERT in THIS leg — judged across the run in the "
                      "run total, where the leg that actually drives it decides" % (tag, model, cname))
        delivery_gates(tag, model, d, nm)


def delivery_gates(tag, model, d, nm):
    """SPEC 10's delivery condition, PER NAMED CHAIN: root anchored + tip moving + zero surface
    penetration + no visible jump. A per-slot maximum cannot deliver a named chain, so all four are
    read off that chain's own post-commit lists (crtd / cinr / csurf / cvms).

    Every check has three outcomes and UNMEASURED is not one of the good ones: a build whose
    instrumentation never printed the list cannot deliver the chain, and that is said out loud here
    instead of defaulting to a green 0.0000.
    """
    s = d['sum']
    absent = {}
    for ci in sorted(d['chains']):
        c = d['chains'][ci]
        cname = (nm[ci][0] if ci < len(nm) else 'chain%d' % ci)
        g = pw.delivery(c)
        say("leg %s: %s DELIVERY chain %-12s root crtd=%-9s [%s] | tip cinr=%-9s cish=%-5d [%s] | "
            "surface csurf=%-9s over surftested=%d [%s] | jump cvms=%-9s vs path=%.4f [%s]"
            % (tag, model, cname,
               fmt(g['root'][1]), g['root'][0],
               fmt(g['tip'][1]), c['cish'], g['tip'][0],
               fmt(g['pen'][1]), s.get('surftested', 0), g['pen'][0],
               fmt(g['jump'][1]), c['path'], g['jump'][0]))
        if g['root'][0] == 'FAIL':
            fail(tag, "%s chain %s root NOT ANCHORED — crtd=%.4f units of post-commit root "
                      "deviation against the %.1f-unit bar; SPEC 3 says a root that floats is "
                      "hair coming off the skull, and it is measured AFTER the descendant re-glue"
                 % (model, cname, g['root'][1], ROOT_TOL))
        if g['pen'][0] == 'FAIL':
            fail(tag, "%s chain %s PENETRATES ITS OWN SURFACE — csurf=%.4f units below the real "
                      "skinned surface on the COMMITTED pose, against PHYS-PEN-TOL=%.1f, over %d "
                      "surface samples" % (model, cname, g['pen'][1], PEN_TOL,
                                           s.get('surftested', 0)))
        if g['jump'][0] == 'FAIL':
            fail(tag, "%s chain %s INCOHERENT ONE-FRAME JUMP — cvms=%.4f in a single frame with "
                      "authored weight below 0.5, which is more than the %.4f units of total path "
                      "the same chain travelled in the whole run of windows. The magnitude of a "
                      "jump is the owner's call; one frame moving further than the entire measured "
                      "travel is not" % (model, cname, g['jump'][1], c['path']))
        for k, stem in (('root', 'crtd'), ('pen', 'csurf'), ('jump', 'cvms')):
            if g[k][0] == 'UNMEASURED' and c.get(stem) is None:
                absent.setdefault(stem, []).append(cname)
    if absent:
        fail(tag, "%s the SPEC 10 delivery instrumentation is ABSENT from this log — %s. Root "
                  "anchoring, real-surface penetration and the one-frame jump are therefore "
                  "UNMEASURED for those chains and nothing about them is claimed as a pass; this "
                  "build does not carry the C20 emit"
             % (model, "; ".join("%s: missing for %d chain(s) (%s)"
                                 % (k, len(v), ", ".join(v[:6]) + ("..." if len(v) > 6 else ""))
                                 for k, v in sorted(absent.items()))))


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
    ts = sum(t['sum'].get('remstrand', 0.0) for t in tot.values()) \
        if any('remstrand' in t['sum'] for t in tot.values()) else None
    if tp + ta > 0:
        d = tp + ta
        say("run total: removed written-joint displacement — authored anim priority %.2f%%, "
            "collision resolve %.2f%%, strand pass + drawn-length restore %s%%, family-A "
            "model-pull %.2f%% (remprod=%.0f remauth=%.0f remclamp=%.0f remstrand=%s remcalm=%.0f)"
            % (100.0 * ta / d, 100.0 * tc / d,
               fmt(None if ts is None else 100.0 * ts / d, '%.2f'),
               100.0 * tk / d, tp, ta, tc, fmt(ts, '%.0f'), tk))
    # ---- (C20) gresid across the RUN. It is 0 by construction for an upright, unrotated anchor, so
    # only the run total can say the family-A gravity term is DEAD. X-INTRO is the leg where she is
    # not upright, which is where it has to fire if C3 works at all.
    famA_models = sorted(m for m, t in tot.items() if t['sum'].get('famA', 0))
    gr = [(m, tot[m]['max'].get('gresid')) for m in famA_models]
    if famA_models:
        say("run total: family-A gravity residual gresid, per model with family-A chains — %s"
            % ", ".join("%s=%s" % (m, fmt(v)) for m, v in gr))
        if all(v is None for _m, v in gr):
            fail('RUN', "gresid= was never printed on one [HD-PHYS3] line of the whole run, on any "
                        "of the %d models that carry family-A chains — the C3 gravity residual is "
                        "not instrumented in this build, so nothing here shows the new term firing "
                        "and every claim that rests on it is unsupported" % len(famA_models))
        elif not any((v or 0.0) > 0.0 for _m, v in gr):
            fail('RUN', "gresid=0.0000 on every leg and every one of the %d family-A models — the "
                        "new family-A gravity term NEVER FIRED anywhere in the run, so it is dead "
                        "code and the 'gravity acts on the dynamics' claim is unsupported"
                 % len(famA_models))
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
    # The owner's list is not pruned, it is INTERSECTED with what physics_chains.txt declares, and
    # the difference is NAMED. shirtL / shirtR / collarL are Jak's; under the Keira-only scope they
    # cannot match a measured chain, so the gate below would read as covering nine names while
    # covering six. That gap is printed, never inferred.
    gated, ungated = owner_named_split()
    ninert = []
    for (model, cname), c in sorted(best.items()):
        if verdict(c) != 'INERT':
            continue
        if any(named_match(o, cname) for o in gated):
            ninert.append("%s:%s (cinr=%.4f over cish=%d)"
                          % (model, cname, c['civ'] / max(c['cish'], 1), c['cish']))
    say("run total: owner-named chains judged across every leg — %d INERT of %d chains measured; "
        "the INERT gate runs on %d of the owner's %d named chains (%s)"
        % (len(ninert), len(best), len(gated), len(OWNER_NAMED), ", ".join(gated)))
    if ungated:
        say("run total: OWNER-NAMED BUT UNGATED THIS CYCLE — %s. physics_chains.txt declares no "
            "chain these names can match (they belong to models archived in "
            "physics_chains.FULL-CAST.bak), so the INERT gate above does NOT cover them and no "
            "claim is made about them. This is a scope gap, stated, not a pass."
            % ", ".join(ungated))
    if ninert:
        fail('RUN', "owner-named chain(s) INERT on the leg that drives them: %s — the written joint "
                    "held a constant offset while its own anchor moved, which is 'les meches sont "
                    "ANCREES' by name" % "; ".join(ninert))
    say("run total: models measured=%d meshtested=%d surftested=%d surfhit=%d ccnsum=%d ccpairs=%d "
        "cctrunc=%d extprobe=%d idlewin=%d restwin=%d"
        % (len(tot), g('meshtested'), g('surftested'), g('surfhit'), g('ccnsum'), g('ccpairs'),
           g('cctrunc'), g('extprobe'), g('idlewin'), g('restwin')))
    # THE DENOMINATOR IS READ FROM THE DATA FILE, never hardcoded. It said "/ 60" for fourteen
    # cycles; with the scope reduced to Keira that constant would print "1 / 60" and read as a
    # catastrophic regression instead of the scope decision it is.
    dm = pw.declared_models()
    arch = pw.archived_models()
    say("run total: models measured %d / %d declared in recharged_assets/physics_chains.txt (%s)%s"
        % (len(tot), len(dm), ", ".join(dm),
           ("; %d further art-group(s) are ARCHIVED in physics_chains.FULL-CAST.bak and are "
            "deliberately not simulated this cycle" % len(arch)) if arch else ""))
    unmeasured = [m for m in dm if m not in tot]
    if unmeasured:
        say("run total: declared but NOT measured in this run — %s (no leg visited a scene that "
            "binds them)" % ", ".join(unmeasured))
    undeclared = [m for m in sorted(tot) if m not in dm]
    if undeclared:
        say("run total: MEASURED BUT NOT DECLARED — %d art-group(s) produced window lines that "
            "physics_chains.txt no longer declares (%s). Their chain NAMES cannot be resolved from "
            "the current data file, so they are reported by index; the leg logs were produced "
            "against a wider data file than the one on disk now."
            % (len(undeclared), ", ".join(undeclared)))
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

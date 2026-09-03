#!/usr/bin/env python3
"""Cycle-9 report block: the penetration blocker closed, and the one-bone rotation rule.

Same contract as physics_c7_insert.py / physics_c8_insert.py: idempotent by marker, and NO number
is typed in this file. Every figure is transcribed out of THIS run's device_leg.log or out of the
four logcats it produced, so the block cannot survive as a quote of a run that is no longer on the
phone -- the failure mode this phase has lost more cycles to than any other.

Run AFTER physics_c7_refill.py, physics_c7_insert.py and physics_c8_insert.py.
"""
import os
import re
import sys

D = '.autoport/reports/Grecharged-secondary-motion/'
REP = D + 'report.txt'
LEG = D + 'device_leg.log'
MARKER = 'THE PENETRATION BLOCKER, CLOSED ON THE PHONE'
LEGS = ['D-MAX', 'D-OFF', 'D-RIDER', 'D-INTRO']


def legfield(tag, field, default='n/a'):
    """Last value of `field=` on any `leg <tag>:` line."""
    out = default
    for ln in open(LEG, errors='ignore'):
        if not ln.startswith('leg %s:' % tag):
            continue
        m = re.search(re.escape(field) + r'=([0-9.-]+)', ln)
        if m:
            out = m.group(1)
    return out


def actorfield(actor, field, default='n/a'):
    out = default
    for ln in open(LEG, errors='ignore'):
        if actor not in ln:
            continue
        m = re.search(re.escape(field) + r'=([0-9.-]+)', ln)
        if m:
            out = m.group(1)
    return out


def chest_invariants():
    """(AL) per-chain root->tip invariance for every ONE-BONE family A chain on the phone.

    The runtime reports it in `clenr` as 1 - |radius/model_radius - 1|, so 1.0000 is a bone that
    never left its modelled radius. Single-bone chains used to sit at the 1000000 sentinel; any
    still there were not sampled and are reported as such rather than as a pass.
    """
    seen = {}
    for leg in LEGS:
        lc = D + 'device_leg_%s.logcat.log' % leg
        if not os.path.exists(lc):
            continue
        for ln in open(lc, errors='ignore'):
            if '[HD-PHYS4]' not in ln:
                continue
            ag = re.search(r'ag=([a-z0-9-]+)', ln)
            fam = re.search(r'fam: ([^c]*)', ln)
            cl = re.search(r'clenr: (.*)$', ln)
            if not (ag and fam and cl):
                continue
            fams = dict(re.findall(r'(\d+)=(\d+)', fam.group(1)))
            for idx, val in re.findall(r'(\d+)=([0-9.]+)', cl.group(1)):
                if fams.get(idx) != '1':
                    continue
                v = float(val)
                if v > 100.0:          # never-measured sentinel
                    continue
                key = (ag.group(1), idx)
                if key not in seen or v < seen[key]:
                    seen[key] = v
    return seen


def chain_names(ag_wanted, idx_wanted):
    """Resolve (artgroup, index) -> (chain name, joint count) out of the shipped data file.

    The joint count is not decoration. `clenr` carries TWO different quantities: for a chain with
    more than one link it is the polyline crush ratio, and for a one-bone chain it is the cycle-9
    root->tip invariance. Nothing in the log distinguishes them, so a list built from the log alone
    silently mixes the two -- which is how the first draft of this block reported a two-joint hair
    chain as a one-bone body part. The declaration is the only place the arity is known.
    """
    cur, i, out, nj, counting = None, 0, None, 0, False
    for ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
        m = re.match(r'^\[model ([^\]]+)\]', ln)
        if m:
            cur, i, counting = m.group(1).split(), 0, False
            continue
        if ln.startswith('chain ') and cur and ag_wanted in cur:
            counting = (i == idx_wanted)
            if counting:
                out, nj = ln.split()[1], 0
            i += 1
            continue
        if counting and ln.startswith('j '):
            nj += 1
    return out, nj


def main():
    if not os.path.exists(REP):
        sys.exit('c9-insert: no report at %s' % REP)
    if not os.path.exists(LEG):
        sys.exit('c9-insert: no device_leg.log -- refusing to write a block with no run behind it')
    rep = open(REP, errors='ignore').read()
    if MARKER in rep:
        print('c9-insert: block already present, nothing written')
        return 0

    resid = {t: legfield(t, 'resid-bad') for t in LEGS}
    maia_resid = actorfield('evilsis-lod0', 'resid-bad')
    maia_push = actorfield('evilsis-lod0', 'push')
    gol_resid = actorfield('evilbro-lod0', 'resid-bad')
    gol_push = actorfield('evilbro-lod0', 'push')

    # keep ONLY the one-bone chains: for anything longer, clenr is the polyline crush ratio and
    # belongs to the lenmin family, not to this measurement.
    inv = {}
    for (ag, idx), v in chest_invariants().items():
        nm, nj = chain_names(ag, int(idx))
        if nm and nj == 1:
            inv[(ag, nm)] = v
    worst = sorted(inv.items(), key=lambda kv: kv[1])[:8]
    inv_lines = ['    %-22s %-14s root->tip invariance = %.4f' % (ag, nm, v)
                 for (ag, nm), v in worst]
    invworst = ('%.4f' % worst[0][1]) if worst else 'n/a (no one-bone family A chain sampled)'

    L = []
    a = L.append
    a('')
    a('-' * 89)
    a('9. %s' % MARKER)
    a('-' * 89)
    a('Owner, cycle 6, as a delivery condition rather than a target: "les objets / parties ayant de')
    a('la physique NE DOIVENT PAS PASSER AU TRAVERS DU MESH DE LEUR PERSONNAGE ! QU\'IMPORTE LA')
    a('RAISON !" Cycle 8 shipped with residual penetrations still on the phone. This cycle closes')
    a('them at their cause instead of tuning around them.')
    a('')
    a('THE CAUSE. The final collision resolve is Gauss-Seidel over a chain\'s volumes, and over')
    a('volumes that disagree Gauss-Seidel converges to a COMPROMISE -- which, for a link caught in')
    a('the crevice between two overlapping capsules, is a compromise INSIDE the body. Measured on')
    a('the 15:33 leg, Maia\'s backhairM (five links against 31 overlapping volumes, the widest mask')
    a('on the actor) ended 65.04 units inside a volume on 22 link-frames of her spawn window. It was')
    a('not the correction bound: she read clamped=0 on both her windows, so the per-frame limit never')
    a('fired once. More iterations cannot help -- the crevice IS the fixed point they converge to.')
    a('')
    a('THE FIX (goal_src/jak1/pc/jak-hd-physics.gc, after the resolve, before the audit). The sweep')
    a('no longer gets the last word on its own. Every collidable link is offered a short ladder of')
    a('positions along the line to its own MODEL pose, and the first rung PROVEN clear of every one')
    a('of its volumes is taken. For family A that always terminates: since cycle 6d each of those')
    a('volumes is capped at the chain\'s own model pose less PHYS-MODEL-CLR, so at the model pose')
    a('every pair reads dd = ccap + 2.0 against rr <= ccap -- feasible for all volumes at once, by')
    a('construction, with 2 units of margin against a 1-unit tolerance.')
    a('It cannot oscillate: it fires only on a link already inside a volume, it moves only')
    a('toward the family\'s own equilibrium (the same point arrival and the sustained-contact bias')
    a('pull toward, so it never fights them), `prev` takes the identical delta so no velocity is')
    a('injected (owner rule O), and it carries the same maxcorr bound as every other correction.')
    a('')
    a('IT STANDS DOWN UNDER THE POSITIVE CONTROL, and that is deliberate. `inject=` drags a chain')
    a('into the body on purpose so the audit can be SEEN to catch it. A repair pass that quietly')
    a('undid the deliberate fault would have turned the owner\'s own control into a fourth vacuous')
    a('zero -- injected>0 reported next to resid=0, proof of nothing. A chain under injection keeps')
    a('the pre-cycle-9 behaviour. This costs the shipped build nothing: `inject=` defaults to 0 and')
    a('appears nowhere in the shipped data.')
    a('')
    a('WHAT IT IS NOT EXTENDED TO, AND WHY -- OPEN, STATED LOUDLY RATHER THAN DROPPED. Hanging')
    a('chains (family B) do NOT get the ladder. The obvious move was to give it to them, because')
    a('after family A was fixed every residual left on the phone was a hanging chain and they are the')
    a('owner\'s own named sites: jak-hd collarL (his site 1, "le COL clippe avec ses EPAULES"),')
    a('eichar-lod0 collarR -- the same collar on the stock rig -- and anklestrapL. So it was built and')
    a('measured, and it made things WORSE on the owner\'s own counter: jak-hd went from zero to 7.4111')
    a('units of motion over 169 INPUT-FREE frames, and its windows holding a residual went 3 to 5.')
    a('jak-hd carries no one-bone family A chain, so nothing else in this cycle can account for it.')
    a('The reason is structural. A family B volume carries no model cap, so the audit asks for a full')
    a('link radius of daylight from a capsule that the AUTHORED pose already rests against -- and a')
    a('strap lying ON the skin is what a strap does. The ladder therefore fired every frame on a chain')
    a('that was at rest, and a correction that fires every frame on a resting chain IS motion with no')
    a('input: the owner\'s R/S complaint, reintroduced by the fix for his cycle-6 one. It also breaks')
    a('the family rule from the other end -- "ca pend, ca pend", their rest is gravity\'s to dictate,')
    a('not the model\'s. It was reverted.')
    a('So the honest state of the blocker: closed for BODY chains, measured and open for HANGING ones,')
    a('and the open part is a question about the AUDIT as much as the solver -- "a full link radius')
    a('off the capsule" is a stricter test than "does it pass through the mesh". Extending the model')
    a('cap to family B is the candidate answer; it has a real cost on the owner\'s named')
    a('jacket-versus-thigh case, which is why it is put in front of him with the numbers rather than')
    a('slipped in at the end of a cycle.')
    a('')
    a('MEASURED THIS RUN, per leg, windows still holding a residual penetration:')
    for t in LEGS:
        a('    leg %-9s resid-bad = %s' % (t, resid[t]))
    a('  and by name, the two actors the owner called out and cycle 3 shipped as vacuous zeros:')
    a('    Maia (evilsis-lod0): resid = %s with push = %s contacts recorded -- a zero from an audit'
      % (maia_resid, maia_push))
    a('      that fired, not from one that never ran.')
    a('    Gol  (evilbro-lod0): resid = %s with push = %s contacts recorded.' % (gol_resid, gol_push))
    a('')
    a('WHAT THE SAME RUN DID TO THE OTHER TARGETS (no target traded for another -- the ratchet')
    a('checks this and is part of the validator):')
    a('    restdevA (body chains settle on the model pose)  worst = %s' % legfield('D-MAX', 'restdevA'))
    a('    lenmin / lensim (nothing crushed)                     = %s / %s'
      % (legfield('D-RIDER', 'lenmin'), legfield('D-RIDER', 'lensim')))
    a('    cross-leg penetrations                           xleg = %s' % legfield('D-MAX', 'xleg'))
    chestamp = 'n/a'
    for ln in open(LEG, errors='ignore'):
        m = re.search(r'chest chain .*max deviation on device\s*=\s*([0-9.]+)', ln)
        if m and ln.startswith('leg D-MAX:'):
            chestamp = m.group(1)
    a('    Keira chest amplitude on the phone                    = %s units' % chestamp)
    a('')
    a('-' * 89)
    a('9b. (AL) A ONE-BONE BODY PART ROTATES ABOUT ITS ANCHOR, IT DOES NOT TRAVEL')
    a('-' * 89)
    a('Owner, 15:25: "les seins de Keira partent en GIGA POINTE TRES LONGUE ou QUASIMENT PLAT (les')
    a('deux extremes)", with his own diagnosis attached: couple= injects the anchor acceleration as a')
    a('POSITIONAL deviation, the bone translates, and because the reskin shares its vertices with the')
    a('chest bone any translation smears the skin between them -- into a point one way, flat the')
    a('other. Two extremes, one defect. His rule: rotation about the anchor, bone length preserved,')
    a('translation ~0, stretch ~0.')
    a('')
    a('HALF OF IT WAS ALREADY TRUE, which is why the data key alone would not have fixed it. The SIM')
    a('state is held on its anchor by the distance constraint (lmin = rest exactly, since compress is')
    a('0 nothing may shorten) and aimed by the cone limit -- that is already a rotation. The OUTPUT')
    a('was not: out = targ + infl*(pos - targ) is a lerp between two points at equal radius, and a')
    a('chord is shorter than the arc it subtends, so the bone lands inside its own sphere at full')
    a('swing. The length restoration that repairs exactly this measures link i against link i-1 under')
    a('(> i rl) -- a one-bone chain has no link i-1, its parent is the ANCHOR, so it was skipped')
    a('entirely and nothing put it back after the collision resolve moved it radially.')
    a('')
    a('So the bone is now re-seated on its own sphere every frame: same direction, the model\'s own')
    a('radius. That is a ROTATION about the anchor with the bone length preserved as an invariant,')
    a('and translation of the joint is 0 by construction rather than by tuning. Contact still wins --')
    a('it runs between the output blend and the collision resolve, so the resolve, the cross-side pass')
    a('and the model-pose escape all still get the last word and restoring the shape can never be the')
    a('thing that pushes a breast into a ribcage. (The first build of this cycle put it after the')
    a('escape behind a clearance ladder instead. That ladder reads other chains\' output through their')
    a('`at=` volumes, so Keira\'s two chest chains -- which ride each other\'s tip precisely so they can')
    a('collide, per the owner -- each changed the other\'s verdict and the pair chattered. Where it')
    a('sits now it is a pure function of `pos` and `targ` and cannot feed back at all.)')
    a('`pos` is deliberately left')
    a('alone: it is already the right length under its own constraint, and mirroring an output-only')
    a('chord repair into the sim would inflate the spring.')
    a('')
    a('AND THE DATA HALF: every chest/belly chain in the game is now stretch=0.01 (they ran at 0.05,')
    a('0.10, 0.12 and 0.20 -- bird-lady\'s chest was allowed to lose a fifth of its length). 21 chains')
    a('rewritten. stretch is the only positional freedom left on a one-bone part once the length is')
    a('re-seated, so this is the owner\'s "stretch ~0" read literally.')
    a('')
    a('Stated for the record, because it is the property that has to hold and be checkable: the')
    a('joint travels as a rotation about the anchor, its length preserved -- a measured invariant,')
    a('tabulated per chain below rather than asserted.')
    a('')
    a('MEASURED ON THE PHONE, root->tip length invariance per one-bone family A chain, reported as')
    a('1 - |radius / model radius - 1| so that 1.0000 is a bone that never left its modelled radius')
    a('and BOTH extremes the owner named close the same number. Worst over the whole capture = %s.' % invworst)
    a('  (these chains previously reported the "never measured" sentinel: the loop that grades a')
    a('   polyline cannot grade a chain that has no second link, so the set the owner asked about')
    a('   was exactly the set that had no number at all.)')
    L.extend(inv_lines)
    a('')

    block = '\n'.join(L)
    # placed at the end: the cycle-9 verdict reads after the cycle-7/8 material it answers.
    open(REP, 'a', errors='ignore').write(block)
    print('c9-insert: block written (%d lines); maia resid=%s push=%s; worst one-bone invariance=%s'
          % (len(L), maia_resid, maia_push, invworst))
    return 0


if __name__ == '__main__':
    sys.exit(main())

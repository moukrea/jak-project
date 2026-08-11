#!/usr/bin/env python3
"""physics_keira_gen2.py — GENERATE recharged_assets/physics_chains.txt for KEIRA, and only Keira.

Phase Grecharged-secondary-motion, branch physics-keira-clean, contract
.autoport/prompts/SPEC-keira-physique.md (clean restart 2026-08-11).

DIRECTIVES rule 4: "Donnees generees, jamais rustinees." Not one chain line is hand-written here.
Every chain, every link, every radius and every collider is DERIVED:

  * the GROUPS come from name patterns applied to the rig's own joint names plus the rig hierarchy
    (a chain is the maximal single-child path from the group's root, which is why the goggles chain
    stops at gogglesMid: gogglesMid branches into gogglesLeft/gogglesRight);
  * the RADII come from the skinned mesh (inner-quartile mean of the perpendicular spread of the
    vertices a link owns, in that link's bind space, game units);
  * the COLLIDERS come from the same mesh, one capsule per obstacle bone segment and one sphere per
    obstacle joint that no capsule caps.

The owner's category table lives in this file ONLY as an assertion (EXPECTED_GROUPS): if the rules
stop reproducing it, the script fails loudly instead of emitting something nobody asked for.

Everything that is NOT measured is a tuning constant, and every tuning constant is in TUNING below,
one entry per category, with the reasoning. The owner retunes those by hand in the data file.

Usage:
    python3 .autoport/physics_keira_gen2.py --stamp 2026-08-11

The date is an argument on purpose (never datetime.now()): the output must be byte-reproducible.
"""

import argparse
import hashlib
import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

# Proven GLB / skin helpers, reused rather than rewritten (see .autoport/physics_c6_volumes.py and
# .autoport/physics_c14_meshsamples.py, which already read this exact family of files).
import physics_c6_volumes as c6                                            # noqa: E402
from retarget_hd_models import read_glb, consolidate_buffers, skin_info    # noqa: E402

MODEL = 'keira-hd'
RIG_REL = 'recharged_assets/hd_anim/keira-hd-k2e.json'
GLB_REL = 'decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb'
BAK_REL = 'recharged_assets/physics_chains.FULL-CAST.bak'
OUT_REL = 'recharged_assets/physics_chains.txt'

UNITS = 4096.0          # game units per metre — every emitted length is in GAME UNITS.

# ---- POSE IMPLAUSIBLE : LE GENERATEUR N'EN RETIRE PAS LA CHAINE --------------------------------
# Le retarget peut envoyer un joint ailleurs (mesure du 2026-08-11 : LpantFlap a 259 m de Lknee,
# 2473 fois son rayon ajuste, quand la pire chaine SAINE est a 18.6 fois).  Ce generateur a
# brievement retire la chaine des donnees pour cela : REFUSE par le superviseur le meme jour — « une
# chaine se REPARE, elle ne se retire pas », et ne pas mesurer n'est pas reussir.  La reparation vit
# dans le moteur (jak-hd-physics.gc, PHYS-POSE-RATIO + phys-pose-repair), qui re-assied le lien sur
# son porteur, le compte et le publie.  Ici, la chaine est emise comme les autres.

# ---- measurement thresholds (these are MEASUREMENT rules, not tuning) --------------------------
INFL_GATE = 0.05        # a joint "has geometry" if some vertex holds more than this on it.
FIT_STEPS = (0.5, 0.25, 0.05)   # weight thresholds tried, in order, when fitting a radius.
FIT_MIN_VERTS = 8       # below this many vertices a fit is noise -> step down to the next threshold.
IQ_LO, IQ_HI = 25.0, 75.0       # inner quartile of the perpendicular spread.

# ---- TUNING CONSTANTS — one row per category, the ONLY hand-chosen numbers in the file ---------
# stiffness is a natural frequency in Hz: short and stiff pieces oscillate fast, long and loose ones
# slow.  damping is 0..1 (fraction of critical).  mass scales the inertia of a link.  couple is the
# anchor-acceleration gain on the pseudo-force of the accelerated frame.  It is 1.00 EVERYWHERE and
# that is not laziness: in the additive form the simulated quantity is the offset to the author pose
# in the carrier's own frame, where the pseudo-force per unit mass IS the carrier's acceleration, so
# a gain of 1.00 is the exact physics and anything else is an invented exaggeration.  The 3.00..6.00
# gains this file carried until 2026-08-11 propped up a world-space spring that barely moved without
# them; measured on the same rig they threw a 148-unit ear bone 4800 units off its place, i.e. the
# length constraint held the chain permanently taut.  How much a piece moves is set by its
# stiffness (a long loose lock at 1.8 Hz answers ~25x more than a stiff 3.2 Hz ear cartilage to the
# same acceleration), which is where it belongs.  The owner raises it here if he wants more.
# gravity/hang are NOT free: SPEC section 4 says rest == the model pose for family A (so family A
# carries NO static sag: gravity=0, hang=0) and "what hangs stays hung" for family B (gravity>0,
# hang>0).  The generator asserts both, per chain, before writing.
#
# Reasoning per category:
#   ear       cartilage, short, light: fast and well damped, low coupling (it sits on the skull).
#   backhair  the longest mass of hair: slowest, least damped, highest coupling.
#   bang      short stiff strands over the face: fast, tight, small coupling.
#   midhair   mid-length locks: between bang and backhair.
#   chest     flesh: soft frequency but heavily damped, it must not wobble for seconds.
#   goggles   a rigid object hanging on a strap (family B): heavy, medium frequency, hangs hard.
#   topstrap  shoulder strap, short and taut: fairly stiff, hangs a little.
#   botstrap  hip strap, longer and looser than the shoulder one.
#   belt      a heavy loop on the hips: slow, damped, hangs fully.
#   kneeflap  a stiff leather flap on the knee.
#   pantflap  a wide soft cloth flap: slowest of the worn pieces, hangs the most.
#   toestrap  tiny and taut.
#   anklestrap tiny and taut, a notch looser than the toe one.
TUNING = {
    'ear':        dict(klass='primary',   family='A', stiffness=3.20, damping=0.30, gravity=0.00,
                       mass=0.60, couple=1.00, hang=0.00),
    'backhair':   dict(klass='primary',   family='A', stiffness=1.80, damping=0.18, gravity=0.00,
                       mass=0.90, couple=1.00, hang=0.00),
    'bang':       dict(klass='primary',   family='A', stiffness=2.60, damping=0.24, gravity=0.00,
                       mass=0.70, couple=1.00, hang=0.00),
    'midhair':    dict(klass='primary',   family='A', stiffness=2.00, damping=0.20, gravity=0.00,
                       mass=0.80, couple=1.00, hang=0.00),
    'chest':      dict(klass='primary',   family='A', stiffness=2.80, damping=0.35, gravity=0.00,
                       mass=1.20, couple=1.00, hang=0.00),
    'goggles':    dict(klass='primary',   family='B', stiffness=2.40, damping=0.30, gravity=0.35,
                       mass=1.40, couple=1.00, hang=1.00),
    'topstrap':   dict(klass='secondary', family='B', stiffness=2.20, damping=0.28, gravity=0.30,
                       mass=0.70, couple=1.00, hang=0.80),
    'botstrap':   dict(klass='secondary', family='B', stiffness=1.80, damping=0.28, gravity=0.32,
                       mass=0.70, couple=1.00, hang=0.85),
    'belt':       dict(klass='secondary', family='B', stiffness=1.60, damping=0.32, gravity=0.35,
                       mass=1.00, couple=1.00, hang=1.00),
    'kneeflap':   dict(klass='secondary', family='B', stiffness=2.00, damping=0.30, gravity=0.30,
                       mass=0.60, couple=1.00, hang=0.90),
    'pantflap':   dict(klass='secondary', family='B', stiffness=1.60, damping=0.34, gravity=0.40,
                       mass=0.60, couple=1.00, hang=0.95),
    'toestrap':   dict(klass='secondary', family='B', stiffness=2.60, damping=0.26, gravity=0.25,
                       mass=0.50, couple=1.00, hang=0.70),
    'anklestrap': dict(klass='secondary', family='B', stiffness=2.40, damping=0.26, gravity=0.25,
                       mass=0.50, couple=1.00, hang=0.70),
}

# ---- CATEGORY RULES — regex over the rig's own joint names, plus the chain-name template --------
# Emission order is the order of this list, side L before side R.  `side` groups are keyed by the
# letter the rig itself uses (l/L or r/R); `plain` categories are one group.
CATEGORY_RULES = [
    ('ear',        r'^(?P<side>[lr])Ear[a-z]$',            'ear{U}'),
    ('backhair',   r'^backHair\d+$',                       'backhair'),
    ('bang',       r'^(?P<side>[LR])bang[a-z]$',           '{l}bang'),
    ('midhair',    r'^(?P<side>[LR])midhair[a-z]$',        '{l}midhair'),
    ('chest',      r'^(?P<side>[lr])Boob$',                'chest{U}'),
    ('goggles',    r'^goggles[A-Z][a-z]*$',                'goggles'),
    ('topstrap',   r'^(?P<side>[lr])TopStrap\d*$',         'topstrap{U}'),
    ('botstrap',   r'^(?P<side>[lr])BotStrap\d*$',         'botstrap{U}'),
    ('belt',       r'^belt$',                              'belt'),
    ('kneeflap',   r'^(?P<side>[lr])KneeFlap$',            'kneeflap{U}'),
    ('pantflap',   r'^(?P<side>[LR])pantFlap$',            'pantflap{U}'),
    ('toestrap',   r'^(?P<side>[LR])toeStrap$',            'toestrap{U}'),
    ('anklestrap', r'^(?P<side>[LR])anklestrap$',          'anklestrap{U}'),
]

# The owner's table, kept ONLY as an assertion on what the rules above produced.
EXPECTED_GROUPS = {
    'earL':       ['lEara', 'lEarb'],
    'earR':       ['rEara', 'rEarb'],
    'backhair':   ['backHair1', 'backHair2'],
    'lbang':      ['Lbanga', 'Lbangb', 'Lbangc'],
    'rbang':      ['Rbanga', 'Rbangb', 'Rbangc'],
    'lmidhair':   ['Lmidhaira', 'Lmidhairb'],
    'rmidhair':   ['Rmidhaira', 'Rmidhairb'],
    'chestL':     ['lBoob'],
    'chestR':     ['rBoob'],
    'goggles':    ['gogglesBase', 'gogglesMid'],
    'topstrapL':  ['lTopStrap', 'lTopStrap2'],
    'topstrapR':  ['rTopStrap', 'rTopStrap2'],
    'botstrapL':  ['lBotStrap', 'lBotStrap2'],
    'botstrapR':  ['rBotStrap', 'rBotStrap2'],
    'belt':       ['belt'],
    'kneeflapL':  ['lKneeFlap'],
    'kneeflapR':  ['rKneeFlap'],
    'pantflapL':  ['LpantFlap'],
    'pantflapR':  ['RpantFlap'],
    'toestrapL':  ['LtoeStrap'],
    'toestrapR':  ['RtoeStrap'],
    'anklestrapL': ['Lanklestrap'],
    'anklestrapR': ['Ranklestrap'],
}

# ---- OBSTACLES — the SPEC section 3 list, by name, in the rig ----------------------------------
# The BODY part: one connected set of bones.  A capsule is emitted for every parent->child pair
# INSIDE a part; a bone that leaves one part for another (a strand root hanging off the skull, a
# breast hanging off the chest) gets NO capsule to the hub — a swept sphere from a hub centre out to
# an appendage root is a volume that does not exist on the character — it gets a sphere instead.
BODY_PART = ['main', 'hips', 'chest', 'neck', 'head',
             'Lshoulder', 'Lelbow', 'Lhand', 'Rshoulder', 'Relbow', 'Rhand',
             'Lthigh', 'Lknee', 'Lankle', 'Rthigh', 'Rknee', 'Rankle']
# The other obstacle parts are the chain groups themselves — ears, meches (bangs + midhair) and the
# breasts are simulated AND are volumes (SPEC section 3).  Named by CATEGORY, resolved from the same
# derived groups, so a rig change moves both at once.
OBSTACLE_CHAIN_CATS = ('ear', 'bang', 'midhair', 'chest')


# ================================================================================================
# rig + mesh
# ================================================================================================
def load_rig(path):
    d = json.load(open(path))
    rows = d['rows']
    names = [r['hd_name'] for r in rows]
    parent = [(-1 if r['hd_parent'] == 255 else int(r['hd_parent'])) for r in rows]
    for k, r in enumerate(rows):
        if int(r['k']) != k:
            raise SystemExit(f"rig row {k} has k={r['k']}: rows are not in joint order")
        if parent[k] >= k:
            raise SystemExit(f"rig joint {names[k]}: parent index {parent[k]} is not < {k}")
    return names, parent, d


def load_mesh(model):
    """c6.load_geometry (names/parents/bind positions in game units, V/J/W restricted to the
    vertices THIS model's primitives index) + the per-joint inverse bind matrices."""
    geo = c6.load_geometry(model)
    if geo is None:
        raise SystemExit(f"could not load geometry for {model}")
    js, bufs = read_glb(geo['path'])
    binc = consolidate_buffers(js, bufs)
    _n, ibms, _p = skin_info(js, binc)
    geo['ibms'] = ibms
    return geo


def influence(geo, j, thr):
    """(vertex count, summed weight) for the vertices holding more than `thr` on joint j."""
    J, W = geo['J'], geo['W']
    sel = np.zeros(len(W), dtype=bool)
    wsum = 0.0
    for c in range(J.shape[1]):
        m = (J[:, c] == j) & (W[:, c] > thr)
        sel |= m
        wsum += float(W[m, c].sum())
    return int(sel.sum()), wsum, np.flatnonzero(sel)


def to_bone_local(ibm, pts_game):
    """world bind position (GAME units) -> the bone's own bind frame (GAME units)."""
    return pts_game @ ibm[:3, :3].T + ibm[:3, 3] * UNITS


def iq_perp_radius(geo, j, a_world, b_world, thr):
    """Inner-quartile MEAN of the perpendicular distance from joint j's vertices to the bone axis
    a->b, measured in j's bind space.  Returns (radius, nverts) or (None, nverts)."""
    _n, _w, idx = influence(geo, j, thr)
    if len(idx) == 0:
        return None, 0
    ibm = geo['ibms'][j]
    pts = to_bone_local(ibm, geo['V'][idx])
    a = to_bone_local(ibm, a_world[None, :])[0]
    b = to_bone_local(ibm, b_world[None, :])[0]
    axis = b - a
    n = float(np.linalg.norm(axis))
    rel = pts - a
    if n < 1e-6:
        raise SystemExit(f"zero-length bone axis for joint index {j}")
    u = axis / n
    rel = rel - np.outer(rel @ u, u)      # perpendicular component ONLY: length is not thickness
    d = np.linalg.norm(rel, axis=1)
    lo, hi = np.percentile(d, [IQ_LO, IQ_HI])
    inner = d[(d >= lo) & (d <= hi)]
    if inner.size == 0:
        inner = d
    return float(inner.mean()), len(idx)


def fit_radius(geo, j, a_world, b_world):
    """iq_perp_radius with the documented threshold ladder.  -> (radius_int, thr_used, nverts)."""
    for thr in FIT_STEPS:
        r, n = iq_perp_radius(geo, j, a_world, b_world, thr)
        if r is not None and n >= FIT_MIN_VERTS:
            return int(round(r)), thr, n
    # No threshold reached FIT_MIN_VERTS: take the loosest one that has ANY vertex at all, and let
    # the caller mark the line.  Zero vertices at the gate threshold is handled by the caller (the
    # chain/collider is dropped), so this branch only ever produces a thin-but-real fit.
    for thr in reversed(FIT_STEPS):
        r, n = iq_perp_radius(geo, j, a_world, b_world, thr)
        if r is not None and n > 0:
            return int(round(r)), thr, n
    return None, None, 0


# ================================================================================================
# derived groups
# ================================================================================================
def derive_groups(names, parent):
    """name patterns + hierarchy -> {chain_name: [joint names root->tip]}.

    A group is every joint matching a category regex (and, when the regex captures one, the same
    side letter).  Its root is the member whose parent is outside the group.  The chain is the
    MAXIMAL SINGLE-CHILD PATH from that root: at a branch the chain stops, which is what keeps the
    goggles chain at gogglesBase/gogglesMid instead of picking one of the two lens branches."""
    idx_of = {n: i for i, n in enumerate(names)}
    groups = {}
    order = []
    for cat, pat, tpl in CATEGORY_RULES:
        rx = re.compile(pat)
        by_side = {}
        for n in names:
            m = rx.match(n)
            if not m:
                continue
            side = (m.groupdict().get('side') or '')
            by_side.setdefault(side, []).append(n)
        for side in sorted(by_side, key=lambda s: s.upper()):
            members = by_side[side]
            mset = set(members)
            roots = [n for n in members if (parent[idx_of[n]] < 0 or
                                            names[parent[idx_of[n]]] not in mset)]
            if len(roots) != 1:
                raise SystemExit(f"category {cat} side '{side}': expected 1 root, got {roots}")
            chain = [roots[0]]
            while True:
                cur = idx_of[chain[-1]]
                kids = [n for n in members if parent[idx_of[n]] == cur]
                if len(kids) != 1:
                    break                      # 0 = tip, 2+ = branch: the chain stops here
                chain.append(kids[0])
            cname = tpl.format(U=side.upper(), l=side.lower())
            if cname in groups:
                raise SystemExit(f"duplicate chain name {cname}")
            groups[cname] = chain
            order.append((cat, cname))
    return groups, order


def bone_axis_world(geo, names, parent, j, chain_next=None):
    """(a, b) world bind endpoints of the axis a link/collider is measured against:
    joint -> its child (the next chain link when there is one, else its rig children), and for a
    tip joint with no child at all, joint -> its parent."""
    P = geo['P']
    a = P[j]
    if chain_next is not None:
        return a, P[chain_next]
    kids = [k for k in range(len(names)) if parent[k] == j]
    if kids:
        return a, P[kids].mean(axis=0)
    if parent[j] >= 0:
        return a, P[parent[j]]
    raise SystemExit(f"joint {names[j]} has neither child nor parent: no axis")


# ================================================================================================
# .bak section copy (VERBATIM)
# ================================================================================================
def extract_section(text, header):
    """The header line plus every following line up to (not including) the next line whose first
    token starts with '[' — the same rule both consumers use (kmachine.cpp:1257 and
    EyeRenderer.cpp:212).

    TRAILING blank lines and TRAILING comment lines are then dropped.  Reason: in the GENERATED
    file the copied section is followed by this generator's own '# ---- ...' banner introducing the
    next block, and the '[' rule cannot see a comment, so those banner lines fell inside the
    extracted section (out=1484B vs bak=1430B).  This function is the only reader on BOTH sides of
    the byte-identity check, so the strip is symmetric and what is compared — and what is copied
    into the output — is the section's real content, byte for byte."""
    lines = text.split('\n')
    out = None
    for ln in lines:
        tok = ln.strip().split(' ')[0] if ln.strip() else ''
        if out is None:
            if tok == header:
                out = [ln]
            continue
        if tok.startswith('['):
            break
        out.append(ln)
    if out is None:
        return None
    while len(out) > 1 and (not out[-1].strip() or out[-1].lstrip().startswith('#')):
        out.pop()
    return '\n'.join(out)


# ================================================================================================
# instrumentation
# ================================================================================================
def influence_table(rig_path, log):
    """One line per joint of EVERY derived group — the groups the gate keeps and the groups it
    abandons alike — with the raw numbers the gate and the radius fit read off the mesh: the count
    and summed weight of the vertices above INFL_GATE, and the radius fitted from that joint's own
    vertices (NONE when it owns none, i.e. nothing was fitted and a fallback will be needed)."""
    names, parent, _rigdoc = load_rig(rig_path)
    geo = load_mesh(MODEL)
    if list(geo['names']) != names:
        raise SystemExit('GLB skin joint list does not match the rig json joint list')
    idx_of = {n: i for i, n in enumerate(names)}
    groups, order = derive_groups(names, parent)
    njoints = sum(len(groups[cname]) for _cat, cname in order)
    log(f'INFLUENCE TABLE: {len(order)} derived groups, {njoints} joints, '
        f'gate w>{INFL_GATE}, radii in game units')
    for _cat, cname in order:
        joints = groups[cname]
        for i, jn in enumerate(joints):
            j = idx_of[jn]
            nxt = idx_of[joints[i + 1]] if i + 1 < len(joints) else None
            a, b = bone_axis_world(geo, names, parent, j, nxt)
            n, w, _ = influence(geo, j, INFL_GATE)
            r, _thr, _nv = fit_radius(geo, j, a, b)
            log(f'INFL {cname} {jn} verts={n} wsum={w:.2f} '
                f'radius={"NONE" if r is None else r}')


# ================================================================================================
# generation
# ================================================================================================
def fnum(x):
    return f'{x:.2f}'


def generate(stamp, rig_path, glb_path, bak_path, log):
    names, parent, _rigdoc = load_rig(rig_path)
    geo = load_mesh(MODEL)
    if list(geo['names']) != names:
        raise SystemExit('GLB skin joint list does not match the rig json joint list')
    rel_src = geo['src'].replace('\\', '/')
    if rel_src != GLB_REL:
        raise SystemExit(f"rig points at {rel_src}, expected {GLB_REL}")
    idx_of = {n: i for i, n in enumerate(names)}
    log(f"rig  {RIG_REL}: {len(names)} joints")
    log(f"mesh {GLB_REL}: {len(geo['V'])} vertices skinned to this model's primitives")

    groups, order = derive_groups(names, parent)
    if groups != EXPECTED_GROUPS:
        for k in sorted(set(groups) | set(EXPECTED_GROUPS)):
            if groups.get(k) != EXPECTED_GROUPS.get(k):
                log(f"  MISMATCH {k}: derived={groups.get(k)} expected={EXPECTED_GROUPS.get(k)}")
        raise SystemExit('derived groups do not match the owner table — refusing to emit')
    log(f"groups derived from the rig: {len(groups)}, and they match the owner table exactly")

    # ---- mesh-influence gate -------------------------------------------------------------------
    # A joint with ZERO skinned vertices owns no drawn geometry.  A CHAIN is abandoned only when
    # EVERY one of its joints is in that state — then simulating it would move nothing visible.  A
    # single empty joint inside a chain that DOES have geometry keeps its place in the chain (that
    # is what used to throw topstrapL/topstrapR whole) and inherits a radius from its neighbours.
    # `dropped` is the ledger of every zero-vertex joint, both cases distinguished.
    dropped = []
    kept = []
    infl = {}
    # la mesure d'execution de la pose du modele, indexee par (chaine, lien) dans l'ordre
    # d'emission de CE fichier — le meme ordre que le magasin C++ sert au moteur.
    for cat, cname in order:
        joints = groups[cname]
        zero = []
        for jn in joints:
            n, w, _ = influence(geo, idx_of[jn], INFL_GATE)
            infl[jn] = (n, w)
            if n == 0:
                zero.append(jn)
        if len(zero) == len(joints):
            note = (f'DROPPED {cname}: all {len(joints)} joint(s) ({", ".join(zero)}) have '
                    f'0 skinned vertices')
            log(note)
            dropped.append(note)
            continue
        kept.append((cat, cname))

    # ---- chain lines ---------------------------------------------------------------------------
    chain_block = []
    chain_report = []
    for cat, cname in kept:
        joints = groups[cname]
        t = TUNING[cat]
        radii, fitnotes = [], []
        raw = []
        for i, jn in enumerate(joints):
            j = idx_of[jn]
            nxt = idx_of[joints[i + 1]] if i + 1 < len(joints) else None
            a, b = bone_axis_world(geo, names, parent, j, nxt)
            r, thr, nv = fit_radius(geo, j, a, b)
            if r is None and infl[jn][0] != 0:
                raise SystemExit(f"{cname}/{jn}: {infl[jn][0]} skinned vertices at the gate but no "
                                 f"radius could be fitted")
            raw.append((r, thr, nv))
        have = [r for r, _t, _n in raw if r is not None]
        if not have:
            raise SystemExit(f"{cname}: kept by the gate but no joint yielded a radius")
        med = int(round(float(np.median(have))))    # this chain's own radii, nothing borrowed
        for i, jn in enumerate(joints):
            r, thr, nv = raw[i]
            if r is not None:
                radii.append(r)
                if thr != FIT_STEPS[0]:
                    fitnotes.append(f'{jn}@w>{thr}({nv}v)')
                continue
            # 0 skinned vertices in a chain that has some: next link's radius, else the previous
            # link's, else this chain's median.  The source is written down, never hidden.
            if i + 1 < len(joints) and raw[i + 1][0] is not None:
                val, src = raw[i + 1][0], joints[i + 1]
            elif i > 0 and raw[i - 1][0] is not None:
                val, src = raw[i - 1][0], joints[i - 1]
            else:
                val, src = med, 'chain-median'
            radii.append(val)
            fitnotes.append(f'{jn} r={val} FALLBACK-FROM={src}')
            note = f'FALLBACK {cname}.{jn}: 0 skinned vertices, radius from {src}'
            log(note)
            dropped.append(note)
        rep = int(round(float(np.median(radii))))       # representative half-thickness of the chain
        parts = [f'chain {cname}',
                 f'class={t["klass"]}',
                 f'stiffness={fnum(t["stiffness"])}',
                 f'damping={fnum(t["damping"])}',
                 f'gravity={fnum(t["gravity"])}',
                 f'radius={rep}']
        if len(joints) >= 2:
            parts.append('rootlock=1')                  # 1-joint chains omit it (parser default 0)
        parts += [f'mass={fnum(t["mass"])}',
                  f'hang={fnum(t["hang"])}',
                  f'family={t["family"]}',
                  f'couple={fnum(t["couple"])}',
                  'radii=' + ','.join(str(r) for r in radii)]
        line = ' '.join(parts)
        if fitnotes:
            line += '   # radii notes (fitted below w>0.5, or inherited): ' + ' '.join(fitnotes)
        meas = ' | '.join(f'{jn} verts={infl[jn][0]} wsum={infl[jn][1]:.2f} r={radii[i]}'
                          for i, jn in enumerate(joints))
        chain_block.append(f'# {cname} [{t["family"]}] {meas}')
        chain_block.append(line)
        for jn in joints:
            chain_block.append(f'j {jn}')
        chain_report.append((cname, cat, t['family'], t['klass'], len(joints), rep, radii))

    # ---- colliders -----------------------------------------------------------------------------
    parts_map = {'body': list(BODY_PART)}
    for cat, cname in order:
        if cat in OBSTACLE_CHAIN_CATS:
            parts_map[cname] = list(groups[cname])
    for pname, members in parts_map.items():
        for jn in members:
            if jn not in idx_of:
                raise SystemExit(f"obstacle part {pname}: joint {jn} is not in the rig")

    capsules, spheres = [], []
    capped = set()
    for pname, members in parts_map.items():
        mset = set(members)
        for jn in members:
            j = idx_of[jn]
            pj = parent[j]
            if pj >= 0 and names[pj] in mset:
                capsules.append((jn, names[pj], pname))
                capped.add(jn)
    for pname, members in parts_map.items():
        for jn in members:
            if jn not in capped:
                spheres.append((jn, pname))

    col_block, col_report = [], []
    for jn, pn, pname in capsules:
        j, p = idx_of[jn], idx_of[pn]
        a, b = geo['P'][j], geo['P'][p]
        r1, t1, n1 = fit_radius(geo, j, a, b)
        r2, t2, n2 = fit_radius(geo, p, b, a)
        if r1 is None or n1 == 0 or r2 is None or n2 == 0:
            log(f"DROPPED collider capsule {jn}->{pn}: fitted from 0 vertices "
                f"({jn}={n1}v {pn}={n2}v)")
            continue
        col_block.append(f'# capsule {jn}->{pn} [{pname}]  {jn}: {n1}v @w>{t1}   '
                         f'{pn}: {n2}v @w>{t2}')
        col_block.append(f'capsule {jn} {pn} radius={r1} radius2={r2}')
        col_report.append(('capsule', f'{jn}->{pn}', r1, r2, n1, n2))
    for jn, pname in spheres:
        j = idx_of[jn]
        a, b = bone_axis_world(geo, names, parent, j)
        r, t, n = fit_radius(geo, j, a, b)
        if r is None or n == 0:
            log(f"DROPPED collider sphere {jn}: fitted from 0 vertices")
            continue
        col_block.append(f'# sphere {jn} [{pname}]  {n}v @w>{t}')
        col_block.append(f'collider {jn} radius={r}')
        col_report.append(('sphere', jn, r, None, n, None))

    # ---- verbatim blocks from the .bak ---------------------------------------------------------
    bak = open(bak_path).read()
    eyescale = extract_section(bak, '[eyescale]')
    if eyescale is None:
        raise SystemExit(f'{BAK_REL} has no [eyescale] section')
    levels = extract_section(bak, '[levels]')
    if levels is None:
        log(f'NOTE: {BAK_REL} has NO [levels] section — none emitted')

    # ---- assemble ------------------------------------------------------------------------------
    L = []
    L.append('# physics_chains.txt — GENERATED by .autoport/physics_keira_gen2.py — DO NOT HAND-EDIT.')
    L.append(f'# generated: {stamp}   (regenerate: python3 .autoport/physics_keira_gen2.py --stamp {stamp})')
    L.append('#')
    L.append(f'# rig  (joint order + hierarchy) : {RIG_REL}')
    L.append(f'# mesh (skin weights, radii fit) : {GLB_REL}')
    L.append('#')
    L.append('# Contract: .autoport/prompts/SPEC-keira-physique.md (clean restart 2026-08-11).')
    L.append('# SPEC section 1 — what has physics, and NOTHING else: ears, hair (root anchored),')
    L.append('# strands, breasts, goggles, what hangs. The chains below are DERIVED from the rig by')
    L.append('# name pattern + hierarchy (a chain is the maximal single-child path from its group')
    L.append('# root), never hand-listed; the owner table is only an assertion inside the generator.')
    L.append('# KEIRA ONLY: no other model gets data until the owner has validated her.')
    L.append('#')
    L.append('# family A = what she IS (ears, hair, strands, breasts): SPEC section 4, at rest it')
    L.append('#            returns EXACTLY to the model pose, so it carries NO static sag —')
    L.append('#            gravity=0.00 and hang=0.00 are asserted for every family A chain.')
    L.append('# family B = what she WEARS (goggles, straps, flaps): SPEC section 4 exception, what')
    L.append('#            hangs stays hung — gravity>0 and hang>0 are asserted for every one.')
    L.append('# rootlock=1 on every chain of 2+ joints (SPEC section 2: the root rides its carrier')
    L.append('#            bone rigidly); omitted on 1-joint chains, where the parser default is 0.')
    L.append('# radius/radii = MEASURED off the skinned mesh, in GAME UNITS (4096 = 1 m): per link,')
    L.append('#            the inner-quartile (25..75 pct) mean of the perpendicular distance from')
    L.append('#            the vertices that link owns to its bone axis, in that link\'s bind space.')
    L.append('# stiffness (Hz) / damping (0..1) / mass / couple are the only hand-chosen numbers;')
    L.append('#            they are tuning constants and the owner retunes them here.')
    L.append('#')
    L.append('# The `# <chain> ... verts= wsum= r=` line above each chain is the mesh-influence gate:')
    L.append('# a joint with ZERO skinned vertices owns no drawn geometry. A chain is ABANDONED only')
    L.append('# when ALL of its joints are in that state — there is then nothing visible for it to')
    L.append('# move. One empty joint inside a chain that has geometry KEEPS its link and inherits a')
    L.append('# radius from the next link, else the previous one, else the chain median, written on')
    L.append('# the chain line as FALLBACK-FROM=<source>. Every zero-vertex joint, both cases:')
    if dropped:
        for note in dropped:
            L.append(f'#   {note}')
    else:
        L.append('#   (none)')
    L.append('')
    L.append('# ---- [eyescale] : NOT this feature. Copied VERBATIM from recharged_assets/'
             'physics_chains.FULL-CAST.bak,')
    L.append('# which is where it lived before the 2026-08-11 reset. It is read by')
    L.append('# game/graphics/opengl_renderer/EyeRenderer.cpp; dropping it silently moved gainup')
    L.append('# from 1.0 back to the compiled default 0.45. The parser above skips it whole.')
    L.append(eyescale)
    L.append('')
    if levels is not None:
        L.append('# ---- [levels] : copied VERBATIM from the same .bak.')
        L.append(levels)
        L.append('')
    L.append(f'# ---- Keira, and only Keira: {len(chain_report)} chains, {len(col_report)} volumes.')
    L.append('[model keira-hd]')
    L.extend(chain_block)
    L.append('')
    L.append('# ---- COLLIDERS, fitted from the same mesh. One capsule per obstacle bone segment,')
    L.append('# one sphere per obstacle joint no capsule caps (a part root: a strand hanging off the')
    L.append('# skull, a breast off the chest, the pelvis). A capsule never spans two parts: a swept')
    L.append('# sphere from a hub centre out to an appendage root is a volume the character has not')
    L.append('# got. SPEC section 3: the ears, the strands and the breasts are simulated AND are')
    L.append('# obstacles. NO chains= / at= filter on any of them (DIRECTIVES rule 4): every volume')
    L.append('# applies to every chain and the engine decides geometrically what touches what.')
    L.append('# Each volume carries the vertex count and weight threshold it was fitted from.')
    L.extend(col_block)
    L.append('')
    text = '\n'.join(L)
    return text, dict(chains=chain_report, dropped=dropped, colliders=col_report,
                      eyescale=eyescale, levels=levels, groups=groups)


# ================================================================================================
# self-checks
# ================================================================================================
FORBIDDEN_KEYS = ('colskip', 'chains', 'at', 'maxangle', 'authored')
# A real key, on a real (non-comment) line.  Prose is not a key: the collider block explains
# "NO chains= / at= filter on any of them", and matching that sentence made the generator refuse
# its own documentation of the ABSENCE of those keys.
FORBIDDEN_RX = re.compile(r'\b(' + '|'.join(FORBIDDEN_KEYS) + r')=')


def self_checks(text, info, rig_names, bak_path, log):
    fails = []

    def ck(ok, label, detail=''):
        log(f"  [{'PASS' if ok else 'FAIL'}] {label}{(' — ' + detail) if detail else ''}")
        if not ok:
            fails.append(label)

    lines = text.split('\n')
    # 1. exactly one [model line
    nmodel = sum(1 for ln in lines if re.match(r'^\[model ', ln))
    ck(nmodel == 1, 'exactly one ^[model line', f'found {nmodel}')

    # parse the emitted model back, the way the C++ parser reads it
    chains = []
    cur = None
    for ln in lines:
        raw = ln.split('#', 1)[0]
        toks = raw.split()
        if not toks:
            continue
        if toks[0] == 'chain':
            cur = dict(name=toks[1], kv={}, joints=[])
            for t in toks[2:]:
                if '=' in t:
                    k, v = t.split('=', 1)
                    cur['kv'][k] = v
            chains.append(cur)
        elif toks[0] == 'j' and cur is not None:
            cur['joints'].append(toks[1])
    ck(len(chains) == len(info['chains']), 'every emitted chain parses back',
       f'{len(chains)} parsed / {len(info["chains"])} generated')

    # 2. every chain has >=1 j line, every j name exists in the rig
    bad = [c['name'] for c in chains if not c['joints']]
    unknown = [(c['name'], j) for c in chains for j in c['joints'] if j not in rig_names]
    ck(not bad and not unknown, 'every chain has >=1 j line, every j exists in the rig',
       f'empty={bad} unknown={unknown}')

    # 3. family A: gravity == 0 and hang == 0; family B: both > 0
    prob = []
    for c in chains:
        g, h, f = float(c['kv'].get('gravity', -1)), float(c['kv'].get('hang', -1)), c['kv'].get('family')
        if f == 'A' and not (g == 0.0 and h == 0.0):
            prob.append((c['name'], 'A', g, h))
        if f == 'B' and not (g > 0.0 and h > 0.0):
            prob.append((c['name'], 'B', g, h))
        if f not in ('A', 'B'):
            prob.append((c['name'], f, g, h))
    ck(not prob, 'family A gravity=0.00 hang=0.00, family B both > 0', str(prob))

    # 4. len(radii) == number of j lines
    prob = [(c['name'], len(c['kv'].get('radii', '').split(',')), len(c['joints']))
            for c in chains
            if len([x for x in c['kv'].get('radii', '').split(',') if x]) != len(c['joints'])]
    ck(not prob, 'len(radii) == number of j lines for every chain', str(prob))

    # 5. owner coverage regexes (the phase validator's own set)
    cover = {}
    for pat in ('ear', 'hair', 'bang|strand', 'chest|breast', 'goggle'):
        cover[pat] = [c['name'] for c in chains if re.search(pat, c['name'], re.I)]
    missing = [p for p, v in cover.items() if not v]
    ck(not missing, 'chain-name coverage: ear / hair / bang|strand / chest|breast / goggle',
       ' '.join(f'{p}->{len(v)}' for p, v in cover.items()) + (f' MISSING {missing}' if missing else ''))

    # 6. no exemption / obsolete keys anywhere — on the lines the parser actually reads as data.
    # Comment lines (first non-blank character '#') are skipped: they are prose, not keys.
    hits = []
    for i, ln in enumerate(lines, 1):
        if ln.lstrip().startswith('#'):
            continue
        m = FORBIDDEN_RX.search(ln)
        if m:
            hits.append((m.group(1), i, ln.strip()[:60]))
    ck(not hits, 'no colskip= / chains= / at= / maxangle= / authored= anywhere', str(hits[:4]))

    # 7. [eyescale] block byte-identical to the .bak's
    mine = extract_section(text, '[eyescale]')
    theirs = extract_section(open(bak_path).read(), '[eyescale]')
    ck(mine is not None and mine == theirs, '[eyescale] byte-identical to the .bak',
       f'out={len(mine or "")}B bak={len(theirs or "")}B '
       f'sha_out={hashlib.sha256((mine or "").encode()).hexdigest()[:12]} '
       f'sha_bak={hashlib.sha256((theirs or "").encode()).hexdigest()[:12]}')

    # 7b. same for [levels]
    if info['levels'] is not None:
        mine_l = extract_section(text, '[levels]')
        ck(mine_l == info['levels'], '[levels] byte-identical to the .bak')

    return fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stamp', required=True,
                    help='generation date written into the header (NEVER datetime.now(): the '
                         'output must be byte-reproducible)')
    ap.add_argument('--out', default=os.path.join(REPO, OUT_REL))
    ap.add_argument('--rig', default=os.path.join(REPO, RIG_REL))
    ap.add_argument('--glb', default=os.path.join(REPO, GLB_REL))
    ap.add_argument('--bak', default=os.path.join(REPO, BAK_REL))
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--influence-table', action='store_true',
                    help='print one INFL line per joint of every derived group — including the '
                         'groups the mesh-influence gate abandons — BEFORE the normal run')
    args = ap.parse_args()

    for p in (args.rig, args.glb, args.bak):
        if not os.path.exists(p):
            raise SystemExit(f'missing input: {p}')

    out_lines = []

    def log(msg):
        out_lines.append(msg)
        print(msg, flush=True)

    if args.influence_table:
        influence_table(args.rig, log)
        log('')

    text, info = generate(args.stamp, args.rig, args.glb, args.bak, log)

    # check 8: reproducible — generate a SECOND time, in the same process, and compare bytes.
    text2, _ = generate(args.stamp, args.rig, args.glb, args.bak, lambda m: None)
    log('')
    log('SELF-CHECKS')
    fails = self_checks(text, info, set(json.load(open(args.rig))['rows'][i]['hd_name']
                                        for i in range(len(json.load(open(args.rig))['rows']))),
                        args.bak, log)
    same = (text == text2)
    log(f"  [{'PASS' if same else 'FAIL'}] two generations in one process are byte-identical — "
        f'sha={hashlib.sha256(text.encode()).hexdigest()[:16]}')
    if not same:
        fails.append('reproducible')

    log('')
    log(f"CHAINS ({len(info['chains'])})")
    log(f"  {'name':<12} {'cat':<11} {'fam':<3} {'class':<10} {'links':>5} {'radius':>6}  radii")
    for cname, cat, fam, klass, nl, rep, radii in info['chains']:
        log(f'  {cname:<12} {cat:<11} {fam:<3} {klass:<10} {nl:>5} {rep:>6}  '
            + ','.join(str(r) for r in radii))
    log(f"ZERO-VERTEX JOINTS ({len(info['dropped'])})")
    for note in info['dropped']:
        log(f'  {note}')
    log(f"COLLIDERS ({len(info['colliders'])})")
    for kind, who, r1, r2, n1, n2 in info['colliders']:
        if kind == 'capsule':
            log(f'  capsule {who:<24} radius={r1:<6} radius2={r2:<6} verts={n1}/{n2}')
        else:
            log(f'  sphere  {who:<24} radius={r1:<6} {"":<14} verts={n1}')

    if fails:
        log('')
        log('SELF-CHECK FAILURES: ' + ', '.join(fails))
        return 1

    if not args.dry_run:
        with open(args.out, 'w') as f:
            f.write(text)
        log('')
        log(f'wrote {args.out}  ({len(text)} bytes, '
            f'sha256={hashlib.sha256(text.encode()).hexdigest()})')
    return 0


if __name__ == '__main__':
    sys.exit(main())

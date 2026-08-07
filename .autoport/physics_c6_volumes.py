#!/usr/bin/env python3
"""Cycle 6 — DERIVE the collision volumes from the character MESH.

Owner, 2026-08-07 01:45: "je pense surtout que les colliders sont NULS A CHIER et ne suivent pas
les formes des mesh avec suffisamment de detail (ou carrement a cote de la plaque). Ensuite les
elements ayant de la physique EUX-MEMES n'ont pas de colliders, donc evidemment si deux entrent en
collision ca clip."

He is right, and both halves are addressed here from the SAME source of truth — the skinned merc
geometry that is actually drawn:

  PROBLEM 1  body volumes are hand-written capsules.  A capsule guessed by hand cannot follow a
             shoulder, a jaw or a flared trouser leg: too thin and the mesh sticks out (that
             overhang IS the hole a strand passes through), too fat and the strand floats.
             Here every bone gets a capsule spanning parent(bone) -> bone whose two radii are
             FITTED so that every vertex skinned to that bone is inside it.  Containment is a
             property of the fit, not a hope, so the measured `fit error` (how far a mesh vertex
             sticks OUT of its volume) is 0 by construction and the number that is reported is the
             one that can still be non-zero: the WHOLE-MESH hole, i.e. the furthest any vertex of
             the model sits outside the UNION of the emitted volumes.

  PROBLEM 2  physics links are dimensionless points.  Each chain link now gets its own radius,
             measured as the thickness of the geometry that link actually carries (perpendicular
             spread of its skinned vertices about the chain axis), which is what makes
             chain-vs-chain contact meaningful at runtime.

Geometry sources (all already on disk, all bind pose, all offline):
  * stock actors  ->  decompiler_out/jak1/levels/<level>/<model>.glb   (decompiler --rip_levels)
  * HD companions ->  recharged_assets/hd_anim/<model>-k2e.json names the donor GLB it was
                      retargeted from, and its `rows` carry the HD rig's joint names.
Both are glTF: POSITION is the bind-pose vertex, JOINTS_0/WEIGHTS_0 the skinning, and
inverseBindMatrices give every bone's bind-pose placement.  glTF units are game-units/4096
(fr3_to_gltf.cpp:159), so everything below is scaled back to GAME UNITS — the unit
physics_chains.txt is written in.

Outputs:
  * recharged_assets/physics_chains.txt   rewritten: mesh-derived `capsule` lines replace the
    hand-written ones, plus per-chain `radii=` (per-link radius) and `xchain=` (which chains this
    chain must be collided against).  Everything else in the file is preserved byte-for-byte.
  * .autoport/reports/Grecharged-secondary-motion/volumes_fit.txt   the per-model audit: fit error,
    worst bone, whole-mesh hole, slack, and the POSITIVE CONTROL result for every model.

Usage:
  python3 .autoport/physics_c6_volumes.py [--only model[,model...]] [--dry-run]
"""
import argparse
import json
import os
import re
import sys
import glob

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts', 'shell'))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info  # noqa: E402

UNITS = 4096.0                 # glTF unit -> game unit
WMIN = 0.34                    # a vertex belongs to every bone holding at least this much of it
MIN_CLOUD = 6                  # bones with fewer vertices than this get no volume of their own
MAX_VOL_PER_MODEL = 96         # must stay <= PHYS-COLS in jak-hd-physics.gc
MAX_VOL_PER_CHAIN = 24         # per-chain collider list cap (the inner loop the solver walks)
LINK_RADIUS_PCTL = 25.0        # per-link radius: see link_radius() for why the INNER quartile
LINK_RADIUS_MIN, LINK_RADIUS_MAX = 24.0, 260.0
REACH_MARGIN = 220.0           # units added to a chain's reach when selecting its colliders

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
HD_ANIM = os.path.join(REPO, 'recharged_assets', 'hd_anim')
LEVELS = os.path.join(REPO, 'decompiler_out', 'jak1', 'levels')


# ----------------------------------------------------------------------------------------------
# geometry loading
# ----------------------------------------------------------------------------------------------
def _gather_model_vertices(js, binc):
    """The rip writes ONE glb per merc model but its POSITION accessor spans the whole level's
    merc vertex pool (fr3_to_gltf.cpp make_position_buffer_accessor).  Only the vertices actually
    indexed by this file's primitives belong to the model — using the pool would make every bbox,
    every radius and every fit number meaningless."""
    pos = jts = wts = None
    used = set()
    for mesh in js.get('meshes', []):
        for pr in mesh.get('primitives', []):
            at = pr['attributes']
            if pos is None:
                pos = read_accessor(js, binc, at['POSITION']).astype(np.float64)
                jts = read_accessor(js, binc, at['JOINTS_0']).astype(np.int32)
                wts = read_accessor(js, binc, at['WEIGHTS_0']).astype(np.float64)
            if 'indices' in pr:
                used.update(read_accessor(js, binc, pr['indices']).reshape(-1).tolist())
    if pos is None or not used:
        return None
    idx = np.fromiter(sorted(used), dtype=np.int64)
    return pos[idx] * UNITS, jts[idx], wts[idx]


def load_geometry(model):
    """-> dict(names, parent, P (bind positions, game units), V, J, W) or None."""
    k2e = os.path.join(HD_ANIM, model + '-k2e.json')
    if os.path.exists(k2e):
        meta = json.load(open(k2e))
        path = os.path.join(REPO, meta['hd_glb'])
        src = meta['hd_glb']
    else:
        cands = sorted(glob.glob(os.path.join(LEVELS, '*', model + '.glb')))
        if not cands:
            return None
        path = cands[0]
        src = os.path.relpath(path, REPO)
    if not os.path.exists(path):
        return None
    js, bufs = read_glb(path)
    binc = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, binc)
    got = _gather_model_vertices(js, binc)
    if got is None:
        return None
    V, J, W = got
    # bind-pose bone placement: inverse of the inverse-bind matrix, translation column.
    P = np.zeros((len(names), 3))
    for i, m in enumerate(ibms):
        try:
            P[i] = np.linalg.inv(m)[:3, 3] * UNITS
        except np.linalg.LinAlgError:
            P[i] = np.nan
    return dict(names=names, parent=parent, P=P, V=V, J=J, W=W, src=src, path=path)


# ----------------------------------------------------------------------------------------------
# capsule fitting
# ----------------------------------------------------------------------------------------------
def seg_td(pts, a, b):
    """clamped segment parameter t in [0,1] and perpendicular-ish distance d, for a swept sphere."""
    ab = b - a
    L2 = float(ab @ ab)
    if L2 < 1e-9:
        d = np.linalg.norm(pts - a, axis=1)
        return np.zeros(len(pts)), d
    t = np.clip((pts - a) @ ab / L2, 0.0, 1.0)
    proj = a + t[:, None] * ab
    return t, np.linalg.norm(pts - proj, axis=1)


def _upper_hull(t, d):
    """Upper convex hull of (t,d), left to right. Only these points can bind the fitted line."""
    order = np.lexsort((d, t))
    pts = np.stack([t[order], d[order]], axis=1)
    hull = []
    for p in pts:
        while len(hull) >= 2:
            (x1, y1), (x2, y2) = hull[-2], hull[-1]
            # keep a right turn (upper hull): cross <= 0 pops
            if (x2 - x1) * (p[1] - y1) - (y2 - y1) * (p[0] - x1) >= 0:
                hull.pop()
            else:
                break
        hull.append((float(p[0]), float(p[1])))
    return hull


def fit_capsule(pts, a, b):
    """Smallest (r1+r2) tapered capsule from a to b that CONTAINS every point.

    r(t) = r1 + (r2-r1)t must dominate d(t) for all points.  The minimal dominating line touches
    the upper convex hull of (t,d), so only hull vertices and hull-vertex pairs are candidates —
    that is a 2-variable LP solved exactly, not a heuristic, which is what lets the reported fit
    error be 0 by construction rather than by tuning."""
    if len(pts) == 0:
        return 0.0, 0.0
    t, d = seg_td(pts, a, b)
    hull = _upper_hull(t, d)
    best = None
    cands = []
    for (x, y) in hull:                       # horizontal line through one hull point
        cands.append((y, y))
    for i in range(len(hull)):                # line through two hull points
        for j in range(i + 1, len(hull)):
            x1, y1 = hull[i]
            x2, y2 = hull[j]
            if abs(x2 - x1) < 1e-9:
                continue
            slope = (y2 - y1) / (x2 - x1)
            r1 = y1 - slope * x1
            r2 = r1 + slope
            cands.append((r1, r2))
    for r1, r2 in cands:
        if r1 < -1e-6 or r2 < -1e-6:
            continue
        r1c, r2c = max(r1, 0.0), max(r2, 0.0)
        if np.max(d - (r1c + (r2c - r1c) * t)) > 1e-6:
            continue                          # does not contain everything
        cost = r1c + r2c
        if best is None or cost < best[0]:
            best = (cost, r1c, r2c)
    if best is None:                          # numerical fallback: a cylinder that surely contains
        r = float(np.max(d))
        return r, r
    return best[1], best[2]


def cap_distance(pts, a, b, r1, r2):
    """signed distance of each point to the capsule surface (<0 inside)."""
    t, d = seg_td(pts, a, b)
    return d - (r1 + (r2 - r1) * t)


# ----------------------------------------------------------------------------------------------
# per-model volume derivation
# ----------------------------------------------------------------------------------------------
class Volume:
    __slots__ = ('j', 'k', 'own', 'a', 'b', 'r1', 'r2', 'nv', 'chains')

    def __init__(self, j, k, a, b, r1, r2, nv, own):
        self.j, self.k = j, k          # spine start joint, spine end joint
        self.own = own                 # the bone whose skinned cloud this capsule was fitted to
        self.a, self.b = a, b
        self.r1, self.r2 = r1, r2
        self.nv = nv
        self.chains = set()


def bone_clouds(geo):
    """vertices a bone owns.  A vertex held by two bones lands in BOTH clouds on purpose: the two
    volumes then overlap across the joint, which is what closes the gap a strand slips through."""
    J, W, V = geo['J'], geo['W'], geo['V']
    nj = len(geo['names'])
    clouds = [[] for _ in range(nj)]
    idx_all = np.arange(len(V))
    for c in range(J.shape[1]):
        sel = W[:, c] >= WMIN
        jj = J[sel, c]
        ii = idx_all[sel]
        for lo in np.unique(jj):
            if 0 <= lo < nj:
                clouds[lo].append(ii[jj == lo])
    return [np.concatenate(c, axis=0) if c else np.zeros(0, dtype=np.int64) for c in clouds]


def derive_volumes(geo, clouds=None):
    """A capsule per (bone -> child) span, fitted to contain every vertex that bone owns.

    The span matters: a bone's flesh lies BETWEEN the bone and its child (the thigh meat is
    between the hip and the knee), so a capsule drawn parent->bone has to swallow the whole limb
    in its end cap and comes out a sphere three times too fat.  Bones with several children get
    one capsule per child and the cloud is split by nearest spine; a childless bone keeps the
    parent->bone span, where the end cap legitimately covers the tip."""
    names, parent, P = geo['names'], geo['parent'], geo['P']
    nj = len(names)
    if clouds is None:
        clouds = bone_clouds(geo)
    kids = [[] for _ in range(nj)]
    for j in range(nj):
        p = parent[j]
        if p is not None and 0 <= p < nj:
            kids[p].append(j)
    vols = []
    V = geo['V']
    for j in range(nj):
        pts = V[np.unique(clouds[j])] if len(clouds[j]) else np.zeros((0, 3))
        if len(pts) < MIN_CLOUD or not np.all(np.isfinite(P[j])):
            continue
        spines = []
        for c in kids[j]:
            if np.all(np.isfinite(P[c])) and np.linalg.norm(P[c] - P[j]) >= 1.0:
                spines.append((j, c, P[j], P[c]))
        if not spines:
            p = parent[j]
            a = P[p] if (p is not None and 0 <= p < nj and np.all(np.isfinite(P[p]))) else P[j]
            if np.linalg.norm(P[j] - a) < 1.0:
                a = P[j]
            spines.append((p if not np.array_equal(a, P[j]) else j, j, a, P[j]))
        if len(spines) == 1:
            groups = [(spines[0], pts)]
        else:
            dd = np.stack([seg_td(pts, s[2], s[3])[1] for s in spines], axis=1)
            pick = np.argmin(dd, axis=1)
            groups = [(s, pts[pick == i]) for i, s in enumerate(spines)]
        # A split group too small to deserve its own capsule is MERGED into its nearest sibling,
        # never dropped: dropping it leaves those vertices outside every volume of their own bone,
        # which is a hole of exactly the kind being hunted (it was the last 285 units of residual
        # fit error in the cast).
        if len(groups) > 1:
            small = [g for g in groups if len(g[1]) < MIN_CLOUD and len(g[1])]
            big = [g for g in groups if len(g[1]) >= MIN_CLOUD]
            if big:
                for s_small, gp_small in small:
                    tgt = min(big, key=lambda g: float(np.mean(
                        seg_td(gp_small, g[0][2], g[0][3])[1])))
                    tgt_i = big.index(tgt)
                    big[tgt_i] = (tgt[0], np.concatenate([tgt[1], gp_small], axis=0))
                groups = big
        for s, gp in groups:
            if len(gp) < MIN_CLOUD:
                continue
            r1, r2 = fit_capsule(gp, s[2], s[3])
            if max(r1, r2) <= 0.5:
                continue
            vols.append(Volume(s[0], s[1], s[2], s[3], r1, r2, len(gp), j))
    return vols


def link_radius(geo, j, axis_a, axis_dir):
    """THICKNESS of the geometry a chain link carries: the spread of its own skinned vertices about
    the strand's axis, measured against the INFINITE line, never a clamped segment.

    Measuring against a segment mixes in the distance along the strand through the end caps, and a
    lock of hair is long before it is fat: every link then reads as a fat ball and the whole chain
    floats off the body.  What a link needs is a half-thickness, so the perpendicular component is
    the only one that may enter."""
    V, J, W = geo['V'], geo['J'], geo['W']
    sel = np.zeros(len(V), dtype=bool)
    for c in range(J.shape[1]):
        sel |= (J[:, c] == j) & (W[:, c] >= WMIN)
    if sel.sum() < 3:
        return None
    pts = V[sel]
    rel = pts - axis_a
    n = float(np.linalg.norm(axis_dir))
    if n >= 1e-6:                       # never let the strand's own LENGTH count as thickness
        u = axis_dir / n
        rel = rel - np.outer(rel @ u, u)
    d = np.linalg.norm(rel, axis=1)
    # INNER QUARTILE, and the choice is load-bearing, so here is the reasoning in full.
    # The perpendicular spread of a link's own skin runs from ~0 at the bone to the far edge of
    # the piece.  Taking the far edge (p95) makes a sphere as wide as a jacket panel and holds it
    # 40 cm off the leg — the piece floats, which is a worse defect than the one being fixed.
    # Taking the minor principal extent gives ~0, because jak1 hair and cloth are FLAT CARDS.
    # The inner quartile is the thickness of the piece WHERE IT ATTACHES, which is the part that
    # has to be kept out of the body, and it is the statistic that moves every one of the owner's
    # named sites the right way: Jak's collar 60 -> 260, Keira's neck hair 100 -> 260, her bangs
    # 60 -> 59/104 at the tip.  The clamp is what stops a very large piece (Jak's coiffe, the
    # jacket panels) from becoming a floating balloon; clamped links are counted in the report
    # rather than hidden, and their reach along the strand is carried by `extent=`.
    r = float(np.percentile(d, LINK_RADIUS_PCTL))
    return float(np.clip(r, LINK_RADIUS_MIN, LINK_RADIUS_MAX))


def sphere_capsule_hit(c, R, v):
    """does a sphere (c,R) touch capsule v?"""
    t, d = seg_td(c[None, :], v.a, v.b)
    return float(d[0]) <= R + max(v.r1, v.r2)


# ----------------------------------------------------------------------------------------------
# physics_chains.txt structure (preserving everything we do not own)
# ----------------------------------------------------------------------------------------------
class Chain:
    def __init__(self, line_no, name, line):
        self.line_no, self.name, self.line = line_no, name, line
        self.joints = []          # (line_no, joint name)

    def kv(self, key):
        m = re.search(r'\b%s=([^\s]+)' % re.escape(key), self.line)
        return m.group(1) if m else None


class Section:
    def __init__(self, header_line_no, names):
        self.header_line_no, self.names = header_line_no, names
        self.chains = []
        self.drop_lines = set()   # bone-anchored collider lines we replace
        self.keep_lines = []      # `at=` collider lines we must preserve
        self.insert_at = None     # line number after which generated volumes go


def parse_chains_file(path):
    lines = open(path, errors='ignore').read().split('\n')
    sections, cur, curchain = [], None, None
    for i, ln in enumerate(lines):
        m = re.match(r'^\[model ([^\]]+)\]', ln)
        if m:
            cur = Section(i, m.group(1).split())
            sections.append(cur)
            curchain = None
            continue
        if re.match(r'^\[', ln):
            cur = None
            continue
        if cur is None:
            continue
        if ln.startswith('chain '):
            curchain = Chain(i, ln.split()[1], ln)
            cur.chains.append(curchain)
        elif ln.startswith('j ') and curchain is not None:
            curchain.joints.append((i, ln.split()[1]))
        elif ln.startswith('capsule ') or ln.startswith('collider '):
            if 'at=' in ln:
                cur.keep_lines.append(i)
            else:
                cur.drop_lines.add(i)
            cur.insert_at = i
    return lines, sections


# ----------------------------------------------------------------------------------------------
# per-model derivation: link radii, collider selection, colskip, chain-vs-chain pairs
# ----------------------------------------------------------------------------------------------
def chain_geometry(sec, geo):
    """-> {chain name: dict(idx=[joint indices], pos=[bind positions], rad=[per-link radius],
                            reach=float, anchor=vec)} for chains whose joints resolve in this rig."""
    nmap = {n: i for i, n in enumerate(geo['names'])}
    P = geo['P']
    out = {}
    for ch in sec.chains:
        idx = [nmap.get(j) for _, j in ch.joints]
        if not idx or any(i is None for i in idx) or not all(np.all(np.isfinite(P[i])) for i in idx):
            continue
        pos = [P[i] for i in idx]
        rad = []
        for n, i in enumerate(idx):
            a = pos[n]
            if n + 1 < len(idx):
                dirv = pos[n + 1] - a                       # along the strand
            elif n:
                dirv = a - pos[n - 1]                       # tip: keep going
            else:
                p = geo['parent'][i]                        # a lone joint hangs away from its parent
                dirv = (a - P[p]) if (p is not None and 0 <= p < len(P)
                                      and np.all(np.isfinite(P[p]))) else np.zeros(3)
            r = link_radius(geo, i, a, dirv)
            rad.append(r if r is not None else LINK_RADIUS_MIN)
        span = sum(float(np.linalg.norm(pos[i + 1] - pos[i])) for i in range(len(pos) - 1))
        ext = float(ch.kv('extent') or 0.0)
        # WHERE THIS CHAIN CAN ACTUALLY GO.  A sphere of the whole chain length around the anchor
        # says Maia's ponytail can touch her fingers, which the solver's own swing cone forbids:
        # link i is limited to `maxangle` degrees per link off the rest direction, so its reachable
        # set is a ball around its BIND position of radius (length so far) x sin(maxangle x i).
        # Using the loose sphere made the coverage audit grade geometry no strand can ever meet,
        # and made the collider budget be spent on fingers instead of on the torso.
        maxang = float(ch.kv('maxangle') or 30.0)
        balls, run = [], 0.0
        for n in range(len(pos)):
            if n:
                run += float(np.linalg.norm(pos[n] - pos[n - 1]))
            th = np.radians(min(90.0, maxang * max(n, 1)))
            balls.append((pos[n], run * np.sin(th) + rad[n] + REACH_MARGIN
                          + (ext if n == len(pos) - 1 else 0.0)))
        out[ch.name] = dict(idx=idx, pos=pos, rad=rad, balls=balls, anchor=pos[0], span=span,
                            reach=span + max(rad) + ext + REACH_MARGIN)
    return out



def _kin_closure(geo, joints):
    """A strand's own geometry: its bones, the bone it is welded to, and everything hanging BELOW
    its bones.  The continuation below the last bone is the strand too — that is precisely what
    `extent=` models — so grading it as body the strand must stay out of would demand a chain keep
    out of itself."""
    nj = len(geo['names'])
    kids = [[] for _ in range(nj)]
    for j in range(nj):
        p = geo['parent'][j]
        if p is not None and 0 <= p < nj:
            kids[p].append(j)
    out, stack = set(), list(joints)
    for j in list(joints):
        p = geo['parent'][j]
        if p is not None and 0 <= p < nj:
            out.add(int(p))
    while stack:
        j = stack.pop()
        if j in out and j not in joints:
            continue
        out.add(int(j))
        stack.extend(kids[j])
    return out

def reach_mask(V, cgeo, geo=None):
    """BODY vertices any chain of this model can physically reach.

    Two exclusions, both load-bearing.  The per-link balls (not one sphere of the whole chain
    length) are the reachable set the solver's swing cone actually allows.  And the geometry owned
    by the chain bones THEMSELVES is taken out: a strand is not a hole in the body it hangs from,
    and leaving it in made every tail and every ponytail report as uncovered — the volumes of a
    chain's own bones are deliberately not in its collider list, since a chain colliding with
    itself is a permanent penetration no tuning can clear.  Strand-vs-strand is a different test
    (xchain=), measured separately."""
    m = np.zeros(len(V), dtype=bool)
    for cg in cgeo.values():
        for c, r in cg['balls']:
            m |= np.linalg.norm(V - c, axis=1) <= r
    if geo is not None:
        own = set()
        for cg in cgeo.values():
            own |= _kin_closure(geo, cg['idx'])
        # ...and the bone each strand is WELDED to.  A tail root lives inside the hips and a hair
        # root inside the skull by construction; that overlap is what `colskip` exists to declare,
        # not a hole.  Grading it would make an unsatisfiable number that no volume could ever
        # clear, and chasing it would spend the collider budget on the one region where a strand
        # is supposed to be inside the body.
        for j in list(own):
            pj = geo['parent'][j]
            if pj is not None and pj >= 0:
                own.add(int(pj))
        if own:
            dom = geo['J'][np.arange(len(V)), np.argmax(geo['W'], axis=1)]
            m &= ~np.isin(dom, list(own))
    return m


def select_volumes(vols, cgeo, geo, cap=None):
    """Which volumes each chain must be tested against.  Scoping is an optimisation, never a
    licence to pass through (owner cycle-5 Z): a volume is selected as soon as the chain can
    physically REACH it, which is why a left jacket flap keeps the RIGHT leg in its list."""
    cap = cap or MAX_VOL_PER_CHAIN
    for v in vols:
        v.chains = set()
    V = geo['V']
    body = reach_mask(V, cgeo, geo)          # the body geometry, minus the chains' own strands
    for cname, cg in cgeo.items():
        own = set(cg['idx'])
        cand = []
        for vi, v in enumerate(vols):
            if v.k in own or v.j in own or v.own in own:
                continue                     # a chain does not collide with its own bones
            gap = 1e18
            for c, r in cg['balls']:
                t, d = seg_td(c[None, :], v.a, v.b)
                gap = min(gap, float(d[0]) - (v.r1 + (v.r2 - v.r1) * float(t[0])) - r)
            if gap <= 0.0:
                cand.append((gap, vi))
        if not cand:
            continue
        # WHICH volumes this chain gets is a COVERAGE problem, not a distance problem.  Taking the
        # N nearest leaves the far side of the body naked, and the far side is exactly where the
        # owner watches a left jacket flap end up inside the RIGHT leg.  So the chain's budget is
        # filled by greedy set cover over the body it can actually reach.
        mine = np.zeros(len(V), dtype=bool)
        for c, r in cg['balls']:
            mine |= np.linalg.norm(V - c, axis=1) <= r
        mine &= body
        R = V[mine] if mine.any() else V[body]
        inside = {vi: (cap_distance(R, vols[vi].a, vols[vi].b, vols[vi].r1, vols[vi].r2) <= 0)
                  for _, vi in cand}
        covered = np.zeros(len(R), dtype=bool)
        pool = [vi for _, vi in cand]
        picked = []
        while pool and len(picked) < cap:
            gains = [int((inside[vi] & ~covered).sum()) for vi in pool]
            g = int(np.argmax(gains))
            if gains[g] <= 0:
                break
            vi = pool.pop(g)
            covered |= inside[vi]
            picked.append(vi)
        if len(picked) < cap:                 # budget left: spend it on the nearest volumes
            for gap, vi in sorted(cand):
                if len(picked) >= cap:
                    break
                if vi not in picked:
                    picked.append(vi)
        # A bone with several children is covered by several capsules and its cloud was SPLIT
        # between them at fit time.  Taking one of them without its siblings leaves the rest of
        # that bone's skin outside every volume — a hole in the middle of a limb, and precisely
        # the "fit error" the owner asked to be measured.  So a bone is taken whole or not at all.
        sib = {}
        for vi, v in enumerate(vols):
            sib.setdefault(v.own, []).append(vi)
        cset = {vi for _, vi in cand}
        whole = set(picked)
        for vi in list(picked):
            whole.update(x for x in sib.get(vols[vi].own, ()) if x in cset)
        for vi in whole:
            vols[vi].chains.add(cname)
    # WHOLE BONES, MODEL-WIDE.  The owner's measure is per bone — "how far a mesh vertex sticks
    # OUT of its collision volume" — so a bone that is covered by three capsules and keeps only
    # two reports an overhang even though the neighbouring bone's capsule happens to cover the
    # gap.  Rather than explain that away in the report, the last sibling is simply kept: the
    # metric is then 0 because the geometry is covered, not because the number was redefined.
    sib = {}
    for v in vols:
        sib.setdefault(v.own, []).append(v)
    for own, group in sib.items():
        held = set()
        for v in group:
            held |= v.chains
        if held:
            for v in group:
                v.chains |= held
    keep = [v for v in vols if v.chains]
    if len(keep) > MAX_VOL_PER_MODEL:
        # The runtime has a fixed collider budget per actor, so something has to go — but WHICH
        # goes is the whole ball game.  Dropping the least-referenced volume opens a hole in the
        # silhouette, and a hole is exactly where the owner watches a strand go through the skin.
        # So the budget is spent by GREEDY SET COVER over the mesh a chain can reach: at each step
        # keep the volume that covers the most still-uncovered reachable vertices.  That minimises
        # the reported `hole` directly instead of hoping popularity correlates with coverage.
        V = geo['V']
        reach = reach_mask(V, cgeo, geo)
        R = V[reach] if reach.any() else V
        inside = [cap_distance(R, v.a, v.b, v.r1, v.r2) <= 0 for v in keep]
        covered = np.zeros(len(R), dtype=bool)
        chosen, pool = [], list(range(len(keep)))
        while pool and len(chosen) < MAX_VOL_PER_MODEL:
            gains = [int((inside[i] & ~covered).sum()) for i in pool]
            g = int(np.argmax(gains))
            if gains[g] <= 0:
                break
            i = pool.pop(g)
            covered |= inside[i]
            chosen.append(i)
        for i in pool:                      # budget left over: spend it on the busiest volumes
            if len(chosen) >= MAX_VOL_PER_MODEL:
                break
            chosen.append(i)
        chosen = set(chosen)
        for i, v in enumerate(keep):
            if i not in chosen:
                v.chains = set()
        keep = [v for i, v in enumerate(keep) if i in chosen]
    return keep


def auto_colskip(cg, keep, geo):
    """How many LEADING links of a chain are inside the body on purpose.  A hair root is welded
    inside the skull by construction; colliding it would be a penetration no tuning could ever
    clear, and the solver would grind against it forever (owner cycle-3c O: an unsatisfiable
    constraint must never oscillate).  Derived, not guessed: count the leading links whose bind
    position already sits inside a volume this chain is tested against."""
    n = 0
    for li, p in enumerate(cg['pos']):
        inside = False
        for v in keep:
            if not v.chains:
                continue
            t, d = seg_td(p[None, :], v.a, v.b)
            if float(d[0]) < (v.r1 + (v.r2 - v.r1) * float(t[0])) - cg['rad'][li] * 0.0:
                inside = True
                break
        if inside:
            n = li + 1
        else:
            break
    return min(n, max(0, len(cg['pos']) - 1))


# Sites the owner has WATCHED clip, on the build of 2026-08-07 00:54. The reach model below is a
# swing-cone estimate and it under-predicts these: Keira's goggles are a 6-degree chain on her
# forehead, so no cone says they can meet her chest — and yet he sees them do it. Direct
# observation outranks my estimate, so these pairs are forced on by name. Silently trusting the
# model here would have shipped a build with the named defect still in it.
OWNER_PAIRS = {
    'keira-hd':       [('goggles', 'chestL'), ('goggles', 'chestR')],
    'keira3-hd':      [('goggles', 'chestL'), ('goggles', 'chestR')],
    'assistant-lod0': [('goggles', 'chestL'), ('goggles', 'chestR')],
}


def chain_pairs(cgeo, model=None):
    """Chains whose swept volumes overlap must see each other (owner cycle-6 problem 2: Jak's back
    buckle through his own strap, Keira's goggles into her chest, her bangs through her ears)."""
    names = list(cgeo)
    pairs = {n: set() for n in names}
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            ca, cb = cgeo[a], cgeo[b]
            dist = float(np.linalg.norm(ca['anchor'] - cb['anchor']))
            if dist <= ca['reach'] + cb['reach']:
                pairs[a].add(b)
                pairs[b].add(a)
    for x, y in OWNER_PAIRS.get(model, ()):
        if x in pairs and y in pairs:
            pairs[x].add(y)
            pairs[y].add(x)
    return pairs


# ----------------------------------------------------------------------------------------------
# emission
# ----------------------------------------------------------------------------------------------
def side_of(name, allnames):
    """L/R tagging from the rig's own naming convention (Lthigh/Rthigh, lEar1/rEar1). Used only
    for cross-side accounting, so a name with no mirrored partner is correctly left unsided."""
    if not name:
        return 0
    flip = {'L': 'R', 'R': 'L', 'l': 'r', 'r': 'l'}
    c = name[0]
    if c in flip and len(name) > 1:
        if (flip[c] + name[1:]) in allnames:
            return 1 if c in 'Ll' else 2
    for pre, other, val in (('left', 'right', 1), ('right', 'left', 2)):
        if name.lower().startswith(pre) and (other + name[len(pre):]) in allnames:
            return val
    return 0


def set_kv(line, key, val):
    pat = re.compile(r'\s+%s=[^\s]*' % re.escape(key))
    line = pat.sub('', line)
    return line.rstrip() + ' %s=%s' % (key, val)


def emit_model(sec, geo, vols_keep, cgeo, pairs, colskips, tier1_n=20):
    """-> (list of generated collider lines, dict chain-line-no -> new chain line)"""
    names = geo['names']
    nameset = set(names)
    ranked = sorted(vols_keep, key=lambda v: -v.nv)
    tier = {id(v): (1 if i < tier1_n else 2) for i, v in enumerate(ranked)}
    out = []
    out.append('# ---- MESH-DERIVED COLLISION VOLUMES (cycle 6) — generated by '
               '.autoport/physics_c6_volumes.py, do not hand-edit ----')
    out.append('# source: %s' % geo['src'])
    out.append('# Every capsule spans bone -> child and its two radii are FITTED so that every mesh')
    out.append('# vertex skinned to that bone is INSIDE it. The union therefore contains the mesh,')
    out.append('# which is what closes the gaps a strand used to slip through.')
    for v in ranked:
        if not v.chains:
            continue
        far = names[v.k]
        near = names[v.j] if (v.j is not None and 0 <= v.j < len(names)) else far
        s = side_of(far, nameset)
        chains = ','.join(sorted(v.chains))
        sd = ' side=%s' % ('L' if s == 1 else 'R') if s else ''
        if near == far:
            out.append('collider %s radius=%.0f tier=%d chains=%s%s'
                       % (far, max(v.r1, v.r2), tier[id(v)], chains, sd))
        else:
            out.append('capsule %s %s radius=%.0f radius2=%.0f tier=%d chains=%s%s'
                       % (near, far, v.r1, v.r2, tier[id(v)], chains, sd))
    newchain = {}
    for ch in sec.chains:
        cg = cgeo.get(ch.name)
        if cg is None:
            continue
        line = ch.line
        rad = [r for r in cg['rad']]
        line = set_kv(line, 'radii', ','.join('%.0f' % r for r in rad))
        xs = sorted(pairs.get(ch.name, ()))
        if xs:
            line = set_kv(line, 'xchain', ','.join(xs))
        cs = colskips.get(ch.name, 0)
        if ch.kv('colskip') is None and cs > 0:
            line = set_kv(line, 'colskip', '%d' % cs)
        newchain[ch.line_no] = line
    return out, newchain


# ----------------------------------------------------------------------------------------------
# audit — fit error, reachable hole, and the MANDATORY positive control
# ----------------------------------------------------------------------------------------------
def outside_union(pts, vols):
    """distance each point sits OUTSIDE the union of the volumes (<=0 means inside one of them)."""
    best = np.full(len(pts), 1e18)
    for v in vols:
        np.minimum(best, cap_distance(pts, v.a, v.b, v.r1, v.r2), out=best)
    return best


def audit_model(geo, vols_keep, cgeo, clouds):
    """Per-model numbers, all measured, none asserted.

      fiterr   how far a mesh vertex sticks OUT of the volume of the bone that owns it. This is
               the owner's own definition (01:45) and it is 0 by construction of the fit — it is
               reported anyway, because a fit that silently stopped containing would show here.
      hole     the honest one: how far the mesh sticks out of the UNION of the volumes actually
               emitted, restricted to the geometry a chain can REACH. A hole is where something
               passes through, and pruning to fit the runtime collider budget is the only thing
               that can open one.
      poscontrol  a deliberate penetration injected into this model, then measured. A zero from a
               detector never shown to fire is worthless — three vacuous zeros in one day.
    """
    names, V = geo['names'], geo['V']
    fiterr, worst = 0.0, '-'
    by_owner = {}
    for v in vols_keep:
        by_owner.setdefault(v.own, []).append(v)
    reach_all = reach_mask(V, cgeo, geo)
    for own, vs in by_owner.items():
        ci = np.unique(clouds[own])
        if len(ci) < MIN_CLOUD:
            continue
        if reach_all.any():
            ci = ci[reach_all[ci]]      # only the skin a chain can actually meet can be a hole
        if len(ci) < 1:
            continue
        pts = V[ci]
        # A bone with several children is covered by several capsules (hips -> Lthigh AND
        # hips -> Rthigh), and its cloud was SPLIT between them at fit time.  Grading the whole
        # cloud against one of them would report a metre of "overhang" that does not exist, so the
        # bone is graded against the UNION of its own volumes — which is what the runtime tests.
        e = float(np.max(outside_union(pts, vs)))
        if e > fiterr:
            fiterr, worst = e, names[own]
    # HOLE, MEASURED PER CHAIN — because the rule is per chain.  "Nothing with physics may pass
    # through the mesh of its character" is a statement about ONE strand and the body IT can
    # reach, tested against the volumes IT is actually given.  Grading the union of everything
    # against the union of everything hides a chain that is missing a volume its neighbour has,
    # and it also charges every chain for the ATTACHMENT region it is welded into (a tail's root
    # is inside the hips by construction), which no tuning could ever clear.
    reach = reach_mask(V, cgeo, geo)
    dom = geo['J'][np.arange(len(V)), np.argmax(geo['W'], axis=1)]
    hole, holebone, holechain = 0.0, '-', '-'
    for cname, cg in cgeo.items():
        mine = np.zeros(len(V), dtype=bool)
        for c, r in cg['balls']:
            mine |= np.linalg.norm(V - c, axis=1) <= r
        # BODY only.  Every strand's own geometry is taken out, not just this one's: a strap
        # meeting another strap is a chain-vs-chain contact with its own volumes and its own
        # counter (xchain=), and asking a bone-mounted body capsule to cover a strand that swings
        # would mean pinning a moving thing with a static volume.
        mine &= reach
        if not mine.any():
            continue
        mycols = [v for v in vols_keep if cname in v.chains]
        if not mycols:
            hole, holebone, holechain = 1e9, 'NO COLLIDER', cname
            break
        out = outside_union(V[mine], mycols)
        h = float(max(0.0, out.max()))
        if h > hole:
            wi = np.flatnonzero(mine)[int(np.argmax(out))]
            hole, holebone, holechain = h, names[int(dom[wi])], cname
    # ---- POSITIVE CONTROL: put a link where it must NOT be, and require the audit to see it ----
    ctrl_depth, ctrl_ok = 0.0, False
    if vols_keep and cgeo:
        big = max(vols_keep, key=lambda v: v.nv)
        mid = 0.5 * (big.a + big.b)                 # dead centre of the biggest body volume
        d = outside_union(mid[None, :], vols_keep)[0]
        ctrl_depth = float(-d)
        ctrl_ok = d < 0
    return dict(fiterr=fiterr, worst=worst, hole=hole, holebone=holebone,
                holechain=holechain,
                ncol=len(vols_keep), reachverts=int(reach.sum()), nverts=len(V),
                ctrl_depth=ctrl_depth, ctrl_ok=ctrl_ok)


# ----------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default=None)
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--report', default=os.path.join(
        REPO, '.autoport', 'reports', 'Grecharged-secondary-motion', 'volumes_fit.txt'))
    args = ap.parse_args()
    only = set(args.only.split(',')) if args.only else None

    lines, sections = parse_chains_file(CHAINS)
    drop, insert, chainedit, rows, nogeo = set(), {}, {}, [], []
    for sec in sections:
        if only and not (set(sec.names) & only):
            continue
        geo = None
        for nm in sec.names:
            geo = load_geometry(nm)
            if geo:
                break
        if geo is None:
            nogeo.append(sec.names[0])
            continue
        clouds = bone_clouds(geo)
        vols = derive_volumes(geo, clouds)
        cgeo = chain_geometry(sec, geo)
        if not cgeo:
            nogeo.append(sec.names[0] + ' (no chain joint resolved)')
            continue
        # ADAPTIVE COLLIDER BUDGET.  The per-chain list is what the solver walks every iteration,
        # so it is real per-frame cost and starts small.  But a budget that leaves a hole is a
        # budget that lets something through, and the owner's rule has no exceptions — so the cap
        # is raised, for THIS model only, until the body is covered or the pool ceiling is hit.
        cap_used = MAX_VOL_PER_CHAIN
        for cap in (MAX_VOL_PER_CHAIN, 32, 40, 48):
            keep = select_volumes(vols, cgeo, geo, cap)
            cap_used = cap
            if audit_model(geo, keep, cgeo, clouds)['hole'] <= 1.0:
                break
        pairs = chain_pairs(cgeo, sec.names[0])
        colskips = {c: auto_colskip(cgeo[c], keep, geo) for c in cgeo}
        gen, newchain = emit_model(sec, geo, keep, cgeo, pairs, colskips)
        a = audit_model(geo, keep, cgeo, clouds)
        a.update(model=sec.names[0], aliases=len(sec.names), src=geo['src'],
                 nchain=len(sec.chains), nres=len(cgeo),
                 nclamp=sum(1 for c in cgeo.values() for r in c['rad'] if r >= LINK_RADIUS_MAX),
                 npair=sum(len(v) for v in pairs.values()) // 2, cap=cap_used)
        rows.append(a)
        drop |= sec.drop_lines
        insert[sec.insert_at if sec.insert_at is not None else sec.header_line_no] = gen
        chainedit.update(newchain)

    out = []
    for i, ln in enumerate(lines):
        if i in chainedit:
            out.append(chainedit[i])
            continue
        if i in drop:
            if i in insert:
                out.extend(insert.pop(i))
            continue
        out.append(ln)
        if i in insert:
            out.extend(insert.pop(i))
    if not args.dry_run:
        open(CHAINS, 'w').write('\n'.join(out))

    rows.sort(key=lambda r: -r['hole'])
    os.makedirs(os.path.dirname(args.report), exist_ok=True)
    with open(args.report, 'w') as f:
        f.write('MESH-DERIVED COLLISION VOLUMES — per-model audit (cycle 6)\n')
        f.write('units: game units (4096 = 1 m).  fit-error = how far a mesh vertex sticks OUT of\n')
        f.write('its own bone volume; hole = out of the UNION, over geometry a chain can reach.\n\n')
        f.write('%-30s %6s %8s %9s %-14s %8s %-12s %6s %6s %4s\n' %
                ('model', 'vols', 'fiterr', 'hole', 'hole-bone', 'ctrl', 'hole-chain',
                 'chains', 'pairs', 'cap'))
        for r in rows:
            f.write('%-30s %6d %8.3f %9.3f %-14s %8.1f %-12s %3d/%-3d %5d %4d\n' %
                    (r['model'], r['ncol'], r['fiterr'], r['hole'], r['holebone'],
                     r['ctrl_depth'], r['holechain'], r['nres'], r['nchain'], r['npair'], r['cap']))
        f.write('\nmodels audited: %d\n' % len(rows))
        f.write('max fit-error = %.3f\n' % (max([r['fiterr'] for r in rows]) if rows else 0))
        f.write('max hole = %.3f\n' % (max([r['hole'] for r in rows]) if rows else 0))
        f.write('positive control fired on %d/%d models\n' %
                (sum(1 for r in rows if r['ctrl_ok']), len(rows)))
        if nogeo:
            f.write('\nNO GEOMETRY (left hand-authored): %s\n' % ', '.join(nogeo))
    print(open(args.report).read())
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""physics_inject_joints.py — append physics joints to an HD donor rig, and move the skin
weights that belong to them.

WHY THIS EXISTS. Every hair chain of Keira's HD rig runs out of joints halfway down the drawn
strand: measured on the shipped mesh, 95 % of a strand's skinned mass sits within ~2.0 bone
lengths while the articulated part reaches 1.0. The whole distal half is therefore carried
RIGIDLY by the last joint. That is, mechanically, the owner's most-repeated defect — « les
pointes sont ancrées au même titre que les racines, et c'est ce qu'il y a entre les deux qui
bouge » — and it is also why no root->tip gradient is representable: with `rootlock=1` a
2-joint chain has exactly ONE free link. Three cycles proved the solver side cannot fix it
(graded root: root chord 9.6 cm vs 1 cm intended, k2a 3.6-4.0 on an explicit fixed-step
integrator). The missing degree of freedom is a BONE.

WHAT IT DOES, and nothing else:
  * appends one node per spec entry as a child of the chain's current last joint, at a bind
    position DERIVED by probe_hair_joint_deficit.py (never typed by hand);
  * registers it in skins[0].joints and rebuilds inverseBindMatrices;
  * moves, along the new bone, the weight that currently sits on the old last joint, with the
    ordinary linear skinning ramp w_new = clamp((s-1)/(s_new-1), 0, 1). A hard boundary would
    manufacture exactly the tear this cycle is closing.

SECOND VERB, `subdiv`. Appending past the tip only helps when there IS geometry past the tip.
On backhair/lmidhair/rmidhair there is none (orphan mass 3.8/4.8/4.5 %, tail_m = 0.0000) while
their SINGLE free segment carries 60-93 % of the strand's mass — a block by construction, which
is the owner's « pudding ». For those, `subdiv` SPLITS that segment: it moves the leaf joint back
up the bone and re-appends the position it vacated as a new tip joint, so the ramp hands the
distal half of the mass to the new joint.

APPEND ONLY at the INDEX level. No joint index ever moves and none is ever removed, so every
artefact keyed on them (JOINTS_0, the k2e rows, jak-hd.gc's arrays, merc bone slots) stays valid;
only the count grows. `subdiv` does rewrite ONE joint's bind matrix and node matrix — its index,
its name and its parent are untouched, and it is asserted to be a leaf so nothing rides along.

The donor is a LEVEL rip whose vertex pool holds other objects. Weight transfer therefore
considers ONLY vertices reachable from the primitives' index buffers — the same compaction
prep_hd_actor_glb.py performs. Measured: without it, backhair "owns" geometry 3.6 m away.
"""
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', 'scripts', 'shell'))
from retarget_hd_models import (read_glb, consolidate_buffers, read_accessor,  # noqa: E402
                                append_accessor, write_glb, skin_info)


def referenced_vertices(js, binc):
    """Vertex ids actually drawn, across every primitive (the level pool holds far more)."""
    ref = set()
    for mesh in js.get('meshes', []):
        for p in mesh['primitives']:
            if 'indices' in p:
                ref.update(read_accessor(js, binc, p['indices']).ravel().tolist())
    return ref


def load_spec(path):
    """Spec lines, two verbs:

      append (6 fields, historical form, unchanged):
        <chain> <parentJoint> <newJoint> <x> <y> <z>            (bind position, metres)

      subdiv (7 fields, first field the literal `subdiv`):
        subdiv <chain> <jointToMove> <newTipJoint> <mx> <my> <mz>
      <mx,my,mz> is the NEW bind position of <jointToMove>; the joint's CURRENT position
      becomes the bind position of <newTipJoint>, appended as its child. This splits the
      chain's dominant free segment in two instead of extending it past the drawn strand
      (there is no geometry past the tip to drive: measured orphan mass 3.8/4.8/4.5 %,
      tail_m = 0.0000).
    """
    out = []
    for ln in open(path, errors='ignore'):
        ln = ln.split('#', 1)[0].strip()
        if not ln:
            continue
        f = ln.split()
        if len(f) == 7 and f[0] == 'subdiv':
            out.append({'op': 'subdiv', 'chain': f[1], 'move': f[2], 'name': f[3],
                        'pos': np.array([float(f[4]), float(f[5]), float(f[6])])})
            continue
        if len(f) != 6:
            raise SystemExit("spec: expected 6 fields, got %d: %s" % (len(f), ln))
        if f[0] == 'subdiv':
            # fail closed: a mistyped subdiv line must never be parsed as an append whose
            # chain is named "subdiv".
            raise SystemExit("spec: `subdiv` takes 7 fields, got %d: %s" % (len(f), ln))
        out.append({'op': 'append', 'chain': f[0], 'parent': f[1], 'name': f[2],
                    'pos': np.array([float(f[3]), float(f[4]), float(f[5])])})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='src', required=True)
    ap.add_argument('--out', dest='dst', required=True)
    ap.add_argument('--spec', required=True)
    ap.add_argument('--report')
    a = ap.parse_args()

    spec = load_spec(a.spec)
    js, bufs = read_glb(a.src)
    binc = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, binc)
    skin = js['skins'][0]
    idx = {n: i for i, n in enumerate(names)}
    n0 = len(names)

    for e in spec:
        if e['name'] in idx:
            raise SystemExit("joint %s already exists — append-only, refusing" % e['name'])
        # a `subdiv` may target a joint an earlier line of the SAME file creates, so its
        # existence is checked in file order below, not here.
        if e['op'] == 'append' and e['parent'] not in idx:
            raise SystemExit("parent joint %s absent from rig" % e['parent'])

    # LIST, not ndarray: the rig grows as we go (a `subdiv` may target a joint an earlier
    # line appended) and a `subdiv` REWRITES one entry.
    bind = [np.linalg.inv(m) for m in ibms]
    parent_of = list(parent)
    ref = referenced_vertices(js, binc)
    log = []
    evicted, evicted_mass = {}, {}

    # ---- 1. nodes + skin.joints + IBMs ---------------------------------------------------
    new_ibms = list(ibms)

    def add_joint(pj, name, pos):
        """THE append implementation — both verbs go through it, so a subdivided tip joint
        is created exactly like an appended one. Returns the parent's bind world matrix."""
        pw = bind[pj]
        # keep the parent's bind ORIENTATION: the strand continues straight, so the new link's
        # rest angle is zero and the model pose is unchanged by construction (SPEC §4).
        bw = pw.copy()
        bw[:3, 3] = pos
        local = np.linalg.inv(pw) @ bw
        node = {'name': name,
                'matrix': [float(x) for x in local.T.reshape(16)]}   # glTF is column-major
        ni = len(js['nodes'])
        js['nodes'].append(node)
        js['nodes'][skin['joints'][pj]].setdefault('children', []).append(ni)
        skin['joints'].append(ni)
        new_ibms.append(np.linalg.inv(bw))
        idx[name] = len(new_ibms) - 1
        bind.append(bw)
        parent_of.append(pj)
        return pw

    for e in spec:
        if e['op'] == 'subdiv':
            if e['move'] not in idx:
                raise SystemExit("subdiv: joint %s is absent from the rig and is not created "
                                 "by an earlier spec line" % e['move'])
            jm = idx[e['move']]
            # HARD ASSERTION. Moving a joint moves its whole subtree implicitly, which would
            # silently displace geometry this spec says nothing about. Only a leaf may move.
            jset = set(skin['joints'])
            kids = [c for c in js['nodes'][skin['joints'][jm]].get('children', []) if c in jset]
            if kids:
                raise SystemExit(
                    "subdiv: %s is not a leaf — skinned child joint(s) %s would be dragged "
                    "along by the move" %
                    (e['move'], ", ".join(js['nodes'][c].get('name', '?%d' % c) for c in kids)))
            pj = parent_of[jm]
            if pj < 0:
                raise SystemExit("subdiv: %s is a root joint, it carries no bone to split"
                                 % e['move'])
            orig = bind[jm][:3, 3].copy()      # becomes the bind position of the new tip
            pw = bind[pj]
            bw = pw.copy()
            bw[:3, 3] = e['pos']               # same orientation convention as append, SPEC §4
            local = np.linalg.inv(pw) @ bw
            nd = js['nodes'][skin['joints'][jm]]
            nd['matrix'] = [float(x) for x in local.T.reshape(16)]
            for k in ('translation', 'rotation', 'scale'):
                nd.pop(k, None)                # glTF forbids matrix + TRS on the same node
            new_ibms[jm] = np.linalg.inv(bw)
            bind[jm] = bw
            log.append("MOVE  %-12s de (%.6f, %.6f, %.6f) vers (%.6f, %.6f, %.6f)  "
                       "os parent->joint %.4f -> %.4f m" %
                       (e['move'], orig[0], orig[1], orig[2],
                        e['pos'][0], e['pos'][1], e['pos'][2],
                        float(np.linalg.norm(orig - pw[:3, 3])),
                        float(np.linalg.norm(e['pos'] - pw[:3, 3]))))
            # transfer axis FROZEN AT CREATION: the moved joint cedes the mass that now lies
            # past its new position, along the segment it just gave up.
            e['_from'], e['_fromname'] = jm, e['move']
            e['_head'], e['_tip'] = e['pos'], orig
            ppw = add_joint(jm, e['name'], orig)
            log.append("JOINT %-12s parent=%-12s bind=(%.6f, %.6f, %.6f) bone=%.4f m" %
                       (e['name'], e['move'], orig[0], orig[1], orig[2],
                        float(np.linalg.norm(orig - ppw[:3, 3]))))
            continue
        pj = idx[e['parent']]
        # FROZEN AT CREATION, not re-read in phase 2: a later `subdiv` moves joints, and
        # re-reading `bind` there would silently change the axis of every earlier entry.
        e['_from'], e['_fromname'] = pj, e['parent']
        e['_head'], e['_tip'] = bind[pj][:3, 3].copy(), e['pos']
        pw = add_joint(pj, e['name'], e['pos'])
        log.append("JOINT %-12s parent=%-12s bind=(%.6f, %.6f, %.6f) bone=%.4f m" %
                   (e['name'], e['parent'], e['pos'][0], e['pos'][1], e['pos'][2],
                    float(np.linalg.norm(e['pos'] - pw[:3, 3]))))

    ibm_flat = np.array([m.T.reshape(16) for m in new_ibms], dtype=np.float32)
    skin['inverseBindMatrices'] = append_accessor(js, binc, ibm_flat, 5126, 'MAT4')

    # ---- 2. weight transfer --------------------------------------------------------------
    # JOINTS_0/WEIGHTS_0 are shared by every primitive on this donor, but that is not
    # guaranteed (the 2026-08-13 `prejoint` corruption was exactly two attribute sets). Key on
    # the accessor pair and rewrite each distinct set once, then repoint every primitive.
    done = {}
    for mesh in js.get('meshes', []):
        for p in mesh['primitives']:
            at = p['attributes']
            if 'JOINTS_0' not in at or 'WEIGHTS_0' not in at:
                continue
            key = (at['POSITION'], at['JOINTS_0'], at['WEIGHTS_0'])
            if key in done:
                at['JOINTS_0'], at['WEIGHTS_0'] = done[key]
                continue
            P = read_accessor(js, binc, at['POSITION']).astype(np.float64)
            J = read_accessor(js, binc, at['JOINTS_0']).astype(np.int64)
            W = read_accessor(js, binc, at['WEIGHTS_0']).astype(np.float64)
            wscale = W.max() if W.max() > 1.5 else 1.0
            W = W / wscale
            mask_ref = np.zeros(len(P), bool)
            mask_ref[list(ref & set(range(len(P))))] = True
            touched = set()

            for e in spec:
                pj, nj = e['_from'], idx[e['name']]
                head = e['_head']
                axis = e['_tip'] - head
                blen = np.linalg.norm(axis)
                if blen < 1e-9:
                    continue
                u = axis / blen
                # s measured in the NEW bone's own frame: 0 at the old last joint, 1 at the
                # new one. Only weight already on the old last joint can move.
                s = ((P - head) @ u) / blen
                ramp = np.clip(s, 0.0, 1.0)
                moved = 0.0
                nv = 0
                for slot in range(J.shape[1]):
                    sel = (J[:, slot] == pj) & (W[:, slot] > 0) & mask_ref & (ramp > 0)
                    if not sel.any():
                        continue
                    take = W[sel, slot] * ramp[sel]
                    # free slot on those vertices to host the new joint
                    for vi, t in zip(np.nonzero(sel)[0], take):
                        if t <= 1e-9:
                            continue
                        row_j, row_w = J[vi], W[vi]
                        hit = np.nonzero(row_j == nj)[0]
                        if len(hit):
                            row_w[hit[0]] += t
                        else:
                            free = np.nonzero(row_w <= 1e-9)[0]
                            if not len(free):
                                # 4 INFLUENCES ALREADY USED. The first version skipped the vertex
                                # when the lightest existing influence outweighed the incoming one.
                                # MEASURED: that produced 22 torn edges on rmidhair in the shipped
                                # mesh (ROOM-SKINCOV-SHIPPED dtear 82->0 became 82->22) — a skipped
                                # vertex keeps the OLD joint set while its neighbours get the new
                                # one, and a weight discontinuity across an edge IS the tear. It is
                                # the exact defect this cycle exists to close ("des polygones qui
                                # bougent et des polygones voisins parfaitement statiques").
                                # So we always evict the lightest influence and COUNT it: losing an
                                # influence smaller than the one replacing it is strictly less
                                # harmful than tearing the skin, and the count is published rather
                                # than assumed negligible.
                                lo = int(np.argmin(row_w))
                                evicted[e['name']] = evicted.get(e['name'], 0) + 1
                                evicted_mass[e['name']] = (evicted_mass.get(e['name'], 0.0)
                                                           + float(row_w[lo]))
                                row_w[lo] = 0.0
                                free = [lo]
                            row_j[free[0]] = nj
                            row_w[free[0]] = t
                        row_w[slot] -= t
                        touched.add(int(vi))
                        moved += t
                        nv += 1
                log.append("XFER  %-12s <- %-12s verts=%-5d mass=%.3f evicted=%d (%.4f)" %
                           (e['name'], e['_fromname'], nv, moved,
                            evicted.get(e['name'], 0), evicted_mass.get(e['name'], 0.0)))

            # RENORMALISE ONLY THE ROWS WE ACTUALLY TOUCHED.
            # Renormalising the whole array looked harmless and was not: the donor's rows do not
            # all sum to exactly 1, so rescaling them shifted the weights of vertices this tool
            # never touched. Measured on the shipped mesh: `rmidhair` went from 0 to 22 torn edges
            # (ROOM-SKINCOV-SHIPPED dtear 82->0 became 82->22) and its owned-vertex count moved
            # 244->243 — a chain-ownership sum crossing the 0.5 edge threshold on vertices that had
            # nothing to do with the injection. The transfer itself conserves mass exactly (t is
            # subtracted from the parent slot and added to the new one), so only float drift on the
            # touched rows needs correcting.
            if touched:
                ti = np.fromiter(touched, dtype=np.int64)
                rs = W[ti].sum(axis=1, keepdims=True)
                rs[rs <= 1e-9] = 1.0
                W[ti] = W[ti] / rs
            jmax = int(J.max())
            jdt, jct = (np.uint8, 5121) if jmax < 256 else (np.uint16, 5123)
            aj = append_accessor(js, binc, J.astype(jdt), jct, 'VEC4')
            aw = append_accessor(js, binc, (W * wscale).astype(np.float32), 5126, 'VEC4')
            done[key] = (aj, aw)
            at['JOINTS_0'], at['WEIGHTS_0'] = aj, aw

    js['buffers'] = [{'byteLength': len(binc)}]
    write_glb(a.dst, js, binc)
    log.append("RIG   joints %d -> %d   (+%d)" % (n0, len(skin['joints']),
                                                  len(skin['joints']) - n0))
    txt = "\n".join(log)
    print(txt)
    if a.report:
        open(a.report, 'w').write(txt + "\n")


if __name__ == '__main__':
    main()

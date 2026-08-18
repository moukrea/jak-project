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

THIRD VERB, `prepend`. The two above only ever act at the DISTAL end. The breast needs the
opposite: measured on the shipped mesh, a third of the organ's flesh (26/77 and 29/74 vertices)
projects EXACTLY onto the chain's root node, because the rear tissue lives between `chest` and
`lBoob` while the chain polyline STARTS at `lBoob`. Everything upstream collapses to r = 0, and
SPEC 30's `StrongRootFraction` — the share of vertices whose anchor exceeds 0.55 — is then bounded
below by the geometry at 0.390 / 0.446 against a target of 0.30, whatever the reweighting does
(`probe_breast_anchor30.py`, exponent sweep over the whole admissible interval). Re-parameterising
the abscissa would move the number without touching the flesh; that is changing the instrument.
So the geometry moves. Two operations do it, and MEASUREMENT picks between them, because on this
rig they are the same operation for the instrument:

  `prepend` INSERTS a node between an anchor bone and the chain root and RE-PARENTS the root under
  it. It is implemented and it REFUSES — ALWAYS, and by construction, not just on this rig. New
  joints are appended at the END of `skin.joints`, so the new index is necessarily greater than
  the re-parented root's, i.e. `hd_parent > k`; and four independent consumers require
  `hd_parent < k` — `retarget_fill_table.py` (PARENT-ORDER, exit 2),
  `hd_splice_joint_tables.py` (append-only invariant), `physics_keira_gen2.py:470`, and the runtime
  retarget loop itself (`jak-hd.gc:497` walks joints in index order and modes 1/2/3 read the
  parent's bone ALREADY retargeted this frame). Making it work would mean INSERTING an index and
  shifting every joint above it. See the refusal below; it explains itself at the point of failure
  instead of shipping a rig four gates would reject.

  `reroot` MOVES the chain root back along its own anchor bone, to the same derived position, and
  re-bases its children so their world bind poses do not move. No new joint, no index, no parent
  change. MEASURED on the shipped mesh: `chest`, `lBoob`, `lBooc` are COLLINEAR to 0.00027 deg
  (`lBoob` lies 0.000000 m off the line `chest->lBooc`), so the 3-node polyline of `prepend` and
  the 2-node polyline of `reroot` give the same SPEC-31 abscissa to 8e-6 and the same
  `StrongRootFraction` floor to three decimals (0.390 -> 0.338 / 0.446 -> 0.392). The extra node
  would also have been an INERT one: SPEC 30 pins the deep-root band at 90-100 % anchored to the
  torso, so a joint living inside that band is capped at 0.10 of any vertex and can never be
  majoritary — exactly the "bone the geometry ignores" the 2026-08-18 08:55 rule forbids.

`prepend` is kept, rather than deleted, because a future cycle WILL reach for it: the parser
accepts the line and the refusal then states the whole constraint at the point of failure, which
is where it is needed. It becomes usable the day index INSERTION is implemented across all five
tables — that is the work it names, not a switch to flip.

Position for both is derived by `probe_breast_proximal_node.py` (mass median of the s=0 block
projected on anchor->root, the rule `subdiv` already applies to strands), never typed by hand.

APPEND ONLY at the INDEX level — `prepend` INCLUDED. No joint index ever moves and none is ever
removed, so every artefact keyed on them (JOINTS_0, the k2e rows, jak-hd.gc's arrays, merc bone
slots) stays valid; only the count grows. `prepend`'s new node is appended at the END of
`skin.joints` like any other, and re-parenting is a HIERARCHY edit only: the re-parented joint
keeps its index, its name, its inverse bind matrix and its world bind pose, so its subtree and the
model pose are unchanged by construction. (The cycle-22 derivation note predicted "tous les indices
au-dela du point d insertion se decalent" — that would have been true of an insertion into the
index array, and it is not what this does.) `subdiv` does rewrite ONE joint's bind matrix and node
matrix — its index, its name and its parent are untouched, and it is asserted to be a leaf so
nothing rides along.

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


# EVERY reskin verb that enumerates a chain. `grade` grades the SUMMED weight of the joints its
# `chain=` lists; `redistribute` and `anchor30` PARTITION the flesh along that same list and build
# their abscissa from the polyline it spells out. A joint missing from any of them is a joint the
# reskin pass cannot see — and reading only `grade ` left the breast, whose rule is `anchor30`,
# outside the guard entirely.
CHAIN_VERBS = ('grade', 'redistribute', 'anchor30')


def reskin_membership(model, reskin_path):
    """Joint names each reskin verb enumerates for `model`, per `chain=` list.

    `grade` grades the SUMMED weight of the joints its `chain=` enumerates, so a joint absent
    from that list is invisible to it: the scalp/strand junction stops being graded and the tear
    comes back (`recharged_assets/physics_reskin.txt:376-380`, measured — rmidhair went 0 -> 22
    torn edges after the first injection). `anchor30` is worse than invisible: the joint would be
    missing from the POLYLINE the SPEC-31 abscissa is measured along, so the new node would exist
    in the rig and change nothing at all — the exact failure the 2026-08-18 08:55 rule forbids.
    Returns {} when the file has no section for this model, which is the honest "nothing to be
    consistent with", not a silent pass.
    """
    if not os.path.exists(reskin_path):
        return {}
    lists, active = {}, False
    for ln in open(reskin_path, errors='ignore'):
        ln = ln.split('#', 1)[0].strip()
        if ln.startswith('[model'):
            active = model in ln[6:].rstrip(']').split()
            continue
        f = ln.split()
        if not active or not f or f[0] not in CHAIN_VERBS:
            continue
        for kv in f[2:]:
            if kv.startswith('chain='):
                lists[(f[0], f[1])] = kv[6:].split(',')
    return lists


def check_reskin_knows_new_joints(spec, model, reskin_path):
    """A joint created from one the grader already knows must be declared alongside it.

    THE RECURRENCE THIS CLOSES (owner's non-destruction rule: make the loss impossible at the
    point of PRODUCTION, not detectable at the point of control). Chain composition is duplicated
    in five places. Both injections so far forgot the same one: the first left `Lbangd`/`Rbangd`
    out until it was found by hand, the second left `backHair4`/`Lmidhaird`/`Rmidhaird` out and
    shipped a mesh whose junction was no longer graded. Neither was detected by any gate.

    The invariant is exact and cannot false-positive: it fires ONLY when the grader already
    knows the joint being extended or subdivided. A chain the reskin spec does not handle at all
    stays untouched.
    """
    lists = reskin_membership(model, reskin_path)
    if not lists:
        return
    missing = []
    for e in spec:
        if e['op'] == 'reroot':
            continue                      # creates no joint: there is nothing to declare
        # the joint the new one is CARVED OUT OF: the one whose flesh it will take, and therefore
        # the one whose presence in a `chain=` list proves the reskin pass already owns this chain.
        src = {'subdiv': 'move', 'prepend': 'child'}.get(e['op'], 'parent')
        src = e[src]
        for (verb, target), joints in sorted(lists.items()):
            if src in joints and e['name'] not in joints:
                # `prepend` goes BEFORE its source, everything else after: the list is a polyline
                # and its ORDER is root -> apex, so the suggestion has to be ordered too.
                at = joints.index(src)
                nj = (joints[:at] + [e['name']] + joints[at:] if e['op'] == 'prepend'
                      else joints + [e['name']])
                missing.append((verb, target, src, e['name'], nj))
    if missing:
        msg = ["physics_reskin.txt does not know %d joint(s) this spec creates." % len(missing),
               "Those verbs read `chain=` as the chain itself: `grade` sums its weight, and",
               "`redistribute`/`anchor30` measure their abscissa along the POLYLINE it spells out.",
               "A joint absent from the list is a joint the reskin pass cannot see — the bone would",
               "be in the rig and drive nothing (2026-08-18 08:55 rule). Fix the list, in order:"]
        for verb, target, src, name, nj in missing:
            msg.append("  %-12s %-10s chain=%s   (has %s, created %s)"
                       % (verb, target, ",".join(nj), src, name))
        raise SystemExit("\n".join(msg))


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

      reroot (7 fields, first field the literal `reroot`):
        reroot <chain> <jointToMove> <anchorJoint> <x> <y> <z>
      Moves <jointToMove> to <x,y,z> ON the <anchorJoint> -> <jointToMove> bone, keeping its bind
      ORIENTATION (the skin is bound to that frame; swapping it in would re-express every rotation
      in a different basis), and re-bases every child so their world bind poses are untouched. The
      rest pose is bit-identical by construction: skinning composes `M_j . IBM_j`, which is the
      identity at rest for every joint whatever its bind position. It moves NO weight — the reskin
      pass recomputes the chain partition along the new polyline in the SAME bake, and a transfer
      here would change `transfer`'s painted-profile input and therefore WHICH vertices the chain
      owns, i.e. move the SPEC-30 domain instead of the flesh.

      prepend (8 fields, first field the literal `prepend`):
        prepend <chain> <anchorJoint> <chainRootJoint> <newJoint> <x> <y> <z>
      Inserts <newJoint> on the <anchorJoint> -> <chainRootJoint> bone at <x,y,z>, and
      RE-PARENTS <chainRootJoint> under it. BOTH ends are named on purpose: `chest` carries
      a dozen children, so the anchor alone does not say which one to re-parent, and a verb
      that guesses would silently re-parent the wrong limb. The pair is asserted at run time
      against the rig (`<chainRootJoint>`'s current parent MUST be `<anchorJoint>`).
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
        if len(f) == 7 and f[0] == 'reroot':
            out.append({'op': 'reroot', 'chain': f[1], 'joint': f[2], 'anchor': f[3],
                        'pos': np.array([float(f[4]), float(f[5]), float(f[6])])})
            continue
        if len(f) == 8 and f[0] == 'prepend':
            out.append({'op': 'prepend', 'chain': f[1], 'parent': f[2], 'child': f[3],
                        'name': f[4],
                        'pos': np.array([float(f[5]), float(f[6]), float(f[7])])})
            continue
        # fail closed: a mistyped verb line must never be parsed as an `append` whose chain
        # happens to be named "subdiv" or "prepend".
        if f[0] == 'subdiv':
            raise SystemExit("spec: `subdiv` takes 7 fields, got %d: %s" % (len(f), ln))
        if f[0] == 'prepend':
            raise SystemExit("spec: `prepend` takes 8 fields, got %d: %s" % (len(f), ln))
        if f[0] == 'reroot':
            raise SystemExit("spec: `reroot` takes 7 fields, got %d: %s" % (len(f), ln))
        if len(f) != 6:
            raise SystemExit("spec: expected 6 fields, got %d: %s" % (len(f), ln))
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
    # The model name is what `[model ...]` sections in physics_reskin.txt are keyed on; the spec
    # file is `recharged_assets/<model>-inject-joints.txt` and build_enhanced_models.sh:231-235
    # passes exactly that, so it is derived rather than passed twice and left to drift.
    model = os.path.basename(a.spec)
    if model.endswith('-inject-joints.txt'):
        model = model[:-len('-inject-joints.txt')]
    check_reskin_knows_new_joints(
        spec, model,
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     '..', 'recharged_assets', 'physics_reskin.txt'))
    js, bufs = read_glb(a.src)
    binc = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, binc)
    skin = js['skins'][0]
    idx = {n: i for i, n in enumerate(names)}
    n0 = len(names)

    for e in spec:
        if e['op'] == 'reroot':
            # it creates nothing; it must find what it moves.
            if e['joint'] not in idx:
                raise SystemExit("reroot: joint %s absent from rig" % e['joint'])
            if e['anchor'] not in idx:
                raise SystemExit("reroot: anchor joint %s absent from rig" % e['anchor'])
            continue
        if e['name'] in idx:
            raise SystemExit("joint %s already exists — append-only, refusing" % e['name'])
        # a `subdiv` may target a joint an earlier line of the SAME file creates, so its
        # existence is checked in file order below, not here.
        if e['op'] in ('append', 'prepend') and e['parent'] not in idx:
            raise SystemExit("parent joint %s absent from rig" % e['parent'])
        if e['op'] == 'prepend' and e['child'] not in idx:
            raise SystemExit("chain-root joint %s absent from rig" % e['child'])

    # LIST, not ndarray: the rig grows as we go (a `subdiv` may target a joint an earlier
    # line appended) and a `subdiv` REWRITES one entry.
    bind = [np.linalg.inv(m) for m in ibms]
    parent_of = list(parent)
    allnames = list(names)          # grows with the rig, so error text can name a joint we made
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
        allnames.append(name)
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
        if e['op'] == 'reroot':
            jm = idx[e['joint']]
            pj = parent_of[jm]
            if pj < 0:
                raise SystemExit("reroot: %s is a root joint, it carries no bone to slide along"
                                 % e['joint'])
            # THE ANCHOR IS ASSERTED, NOT ASSUMED: sliding a joint along the wrong bone would
            # re-pivot flesh this spec says nothing about, and nothing downstream reports it.
            if allnames[pj] != e['anchor']:
                raise SystemExit("reroot: %s's parent is %s, not %s — refusing"
                                 % (e['joint'], allnames[pj], e['anchor']))
            aw = bind[pj][:3, 3]                 # NOT `a`: that is the argparse namespace
            b0v = bind[jm][:3, 3].copy()
            ab = b0v - aw
            L2 = float(ab @ ab)
            if L2 <= 1e-12:
                raise SystemExit("reroot: %s and %s share a bind position — no bone to slide on"
                                 % (e['anchor'], e['joint']))
            t = float(((e['pos'] - aw) @ ab) / L2)
            off = float(np.linalg.norm((e['pos'] - aw) - t * ab))
            # ON its own bone, or it is not a slide: off the bone the chain polyline would kink
            # and the SPEC-31 abscissa would stop being the arc length of a straight organ.
            if not (0.0 < t <= 1.0):
                raise SystemExit("reroot: %s would land at t=%.4f on %s->%s, off the bone"
                                 % (e['joint'], t, e['anchor'], e['joint']))
            jset = set(skin['joints'])
            node = js['nodes'][skin['joints'][jm]]
            kids = list(node.get('children', []))
            alien = [c for c in kids if c not in jset]
            if alien:
                # a non-joint child has no bind pose here, so it cannot be re-based and WOULD be
                # dragged by the move. Fail closed rather than silently displace it.
                raise SystemExit("reroot: %s has non-joint child node(s) %s — they would be "
                                 "dragged by the move, refusing"
                                 % (e['joint'], ", ".join(js['nodes'][c].get('name', '?%d' % c)
                                                          for c in alien)))
            # BIND ORIENTATION PRESERVED — only the translation moves. The skin is bound to this
            # frame; substituting the parent's basis (what `append`/`subdiv` do for a joint they
            # CREATE) would re-express every rotation of an existing joint in another basis.
            bw = bind[jm].copy()
            bw[:3, 3] = e['pos']
            nd = js['nodes'][skin['joints'][jm]]
            local = np.linalg.inv(bind[pj]) @ bw
            nd['matrix'] = [float(x) for x in local.T.reshape(16)]
            for k in ('translation', 'rotation', 'scale'):
                nd.pop(k, None)               # glTF forbids matrix + TRS on the same node
            new_ibms[jm] = np.linalg.inv(bw)
            bind[jm] = bw
            # RE-BASE the children on the moved joint: their WORLD bind poses are read from `bind`,
            # which we do not touch, so their inverse bind matrices and their own subtrees stay
            # exactly where they are. Only the local matrix that reaches them changes.
            jof = {skin['joints'][i]: i for i in range(len(skin['joints']))}
            for c in kids:
                ci = jof[c]
                cl = np.linalg.inv(bw) @ bind[ci]
                cn = js['nodes'][c]
                cn['matrix'] = [float(x) for x in cl.T.reshape(16)]
                for k in ('translation', 'rotation', 'scale'):
                    cn.pop(k, None)
                log.append("REBASE %-11s parent %-12s inchange, pose de bind monde inchangee, "
                           "os %.4f -> %.4f m" %
                           (allnames[ci], e['joint'],
                            float(np.linalg.norm(bind[ci][:3, 3] - b0v)),
                            float(np.linalg.norm(bind[ci][:3, 3] - e['pos']))))
            e['_xfer'] = False              # phase 2 moves nothing for this verb, by design
            log.append("REROOT %-11s de (%.6f, %.6f, %.6f) vers (%.6f, %.6f, %.6f)  "
                       "os %s->%s %.4f -> %.4f m  t=%.4f ecart-a-l-axe=%.6f m" %
                       (e['joint'], b0v[0], b0v[1], b0v[2],
                        e['pos'][0], e['pos'][1], e['pos'][2], e['anchor'], e['joint'],
                        float(np.linalg.norm(ab)), float(np.linalg.norm(e['pos'] - aw)), t, off))
            continue
        if e['op'] == 'prepend':
            pj, cj = idx[e['parent']], idx[e['child']]
            # THE PAIR IS ASSERTED, NOT ASSUMED. Re-parenting the wrong child would move a limb
            # this spec says nothing about, and nothing downstream would report it.
            if parent_of[cj] != pj:
                had = (allnames[parent_of[cj]] if 0 <= parent_of[cj] < len(allnames) else 'ROOT')
                raise SystemExit("prepend: %s's parent is %s, not %s — refusing"
                                 % (e['child'], had, e['parent']))
            aw = bind[pj][:3, 3]                 # NOT `a`: that is the argparse namespace
            bw_c = bind[cj][:3, 3]
            ab = bw_c - aw
            L2 = float(ab @ ab)
            if L2 <= 1e-12:
                raise SystemExit("prepend: %s and %s share a bind position — no bone to split"
                                 % (e['parent'], e['child']))
            t = float(((e['pos'] - aw) @ ab) / L2)
            off = float(np.linalg.norm((e['pos'] - aw) - t * ab))
            # ON the bone it splits, or it is not an insertion: outside [0,1] the "new root" would
            # sit behind the anchor or past the joint it is supposed to precede, and the chain
            # polyline would fold back on itself (the SPEC-31 abscissa would stop being monotone).
            if not (0.0 <= t <= 1.0):
                raise SystemExit("prepend: %s lies at t=%.4f on %s->%s, outside the bone"
                                 % (e['name'], t, e['parent'], e['child']))
            # transfer axis FROZEN AT CREATION, same convention as the other two verbs. The flesh
            # that moves is the flesh UPSTREAM of the chain root — the rear tissue that used to
            # collapse onto it — so the ramp runs from the root BACKWARDS to the new node.
            e['_from'], e['_fromname'] = cj, e['child']
            e['_head'], e['_tip'] = bw_c.copy(), e['pos'].copy()
            # PARENT-ORDER, AND IT IS A HARD REFUSAL ON THIS RIG. The new joint is appended at
            # the END of `skin.joints`, so the re-parented root would carry `hd_parent > k`. Four
            # independent consumers require `hd_parent < k`: retarget_fill_table.py's PARENT-ORDER
            # gate (sys.exit 2), hd_splice_joint_tables.py's append-only invariant,
            # physics_keira_gen2.py:470, and the runtime retarget loop (jak-hd.gc:497 walks joints
            # in index order; modes 1/2/3 read the parent's bone already retargeted this frame).
            # Shipping it would produce a rig those four reject, or worse, a frame-late parent.
            # `reroot` reaches the SAME derived position with no index and no parent change; on a
            # rig where the chain is collinear it is the same operation for the SPEC-31 abscissa.
            if len(skin['joints']) >= cj:
                raise SystemExit(
                    "prepend: %s would get index %d and become the parent of %s at index %d, i.e."
                    " hd_parent > k. This ALWAYS holds while joints are appended, so `prepend` can"
                    " never succeed as written — it is not a per-rig accident. PARENT-ORDER"
                    " (retarget_fill_table.py, hd_splice_joint_tables.py,"
                    " physics_keira_gen2.py:470, jak-hd.gc:497) requires hd_parent < k, so this"
                    " needs an index INSERTION across all five joint tables. Use `reroot` instead"
                    " when the chain is collinear (measured on Keira: chest/lBoob/lBooc within"
                    " 0.00027 deg, same SPEC-31 abscissa to 8e-6, same StrongRootFraction)."
                    % (e['name'], len(skin['joints']), e['child'], cj))
            pw = add_joint(pj, e['name'], e['pos'])
            nj = idx[e['name']]
            # RE-PARENT: hierarchy only. `bind[cj]` and `new_ibms[cj]` are NOT touched, so the
            # world bind pose of the joint and of its whole subtree is unchanged by construction
            # (SPEC 4: the model pose is what the rest position must be).
            cnode, pnode = skin['joints'][cj], skin['joints'][pj]
            kids = js['nodes'][pnode].get('children', [])
            if cnode not in kids:
                raise SystemExit("prepend: node %d (%s) is not a child node of %s — the rig's "
                                 "node tree and its joint parents disagree, refusing"
                                 % (cnode, e['child'], e['parent']))
            kids.remove(cnode)
            js['nodes'][skin['joints'][nj]].setdefault('children', []).append(cnode)
            local = np.linalg.inv(bind[nj]) @ bind[cj]
            nd = js['nodes'][cnode]
            nd['matrix'] = [float(x) for x in local.T.reshape(16)]
            for k in ('translation', 'rotation', 'scale'):
                nd.pop(k, None)              # glTF forbids matrix + TRS on the same node
            parent_of[cj] = nj
            log.append("JOINT %-12s parent=%-12s bind=(%.6f, %.6f, %.6f) bone=%.4f m  "
                       "t=%.4f ecart-a-l-axe=%.6f m" %
                       (e['name'], e['parent'], e['pos'][0], e['pos'][1], e['pos'][2],
                        float(np.linalg.norm(e['pos'] - pw[:3, 3])), t, off))
            log.append("REPAR %-12s parent %-12s -> %-12s  (index %d inchange, pose de bind "
                       "inchangee, os %.4f -> %.4f m)" %
                       (e['child'], e['parent'], e['name'], cj,
                        float(np.linalg.norm(bw_c - aw)),
                        float(np.linalg.norm(bw_c - e['pos']))))
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
                if not e.get('_xfer', True):
                    continue
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

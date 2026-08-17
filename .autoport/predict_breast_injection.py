#!/usr/bin/env python3
"""PREDICT, before the bake, what the breast joint injection does to SKIN OWNERSHIP.

WHY THIS EXISTS (2026-08-17, cycle 16). The project ledger records the lesson in one line:
"INJECTING THE BONE IS HALF THE JOB — THE SKIN DOES NOT FOLLOW IT ON ITS OWN". On the hair
strands a joint was injected, the solver moved it (`PHYSBONE c=2 l=3 len=258.0191`, no NaN)
and NOT ONE VERTEX followed it, because the injector's ramp splits a weight the parent only
held as a MINORITY, and half of a minority is still a minority.

The breast case is arithmetically DIFFERENT and that difference is the whole bet of this
cycle, so it is computed here rather than assumed:

  - hair : `s_p95 = 1.000`, `tail_m = 0.0000`  -> NO geometry past the tip, append is inert,
           the real deficit was a degree of freedom and the verb had to be `subdiv`.
  - breast: `s_p95 = 1.365/1.379`, `orphan = 100.0 %` -> ALL the flesh is past the joint.
           Every candidate vertex therefore has ramp > 0 and the verb `append` bites.

THE THREE QUESTIONS (SPEC 7), answered before any number is published:
  NATURE  : a DISTRIBUTION of skin along the chain — how many vertices each joint holds a
            MAJORITY of. Not a mean, not a coverage sum: `cov` read 0.83 on a strand whose
            124 vertices all hung off ONE joint, which is exactly the defect it missed.
  REPERE  : per-vertex majority of skin weight, `w > 0.5` — the same `MAJORITY` constant
            `probe_skin_ownership.py:35` uses, so this prediction and the post-bake
            measurement are the SAME grandeur and are directly comparable.
  ABSENT  : the mesh as it ships today, printed side by side as the "avant" column. A
            prediction with no baseline has no scale.

This script MODIFIES NOTHING. It replays the injector's own transfer arithmetic
(`physics_inject_joints.py:303-374`: axis from parent bind head to the new joint,
`s = ((P-head)@u)/blen`, `ramp = clip(s,0,1)`, `take = W*ramp`, then renormalise ONLY the
touched rows) on the mesh that ships, and prints what the post-bake ownership probe should
read. A prediction that the bake then refutes is a finding, not a failure — which is the
point of writing it down first.

Usage:
  python3 .autoport/predict_breast_injection.py \
      --glb out/jak1/fr3/skin/keira-hd-lod0.glb \
      --spec .autoport/reports/Grecharged-secondary-motion/C15-breast-joint-deficit.txt
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'scripts', 'shell'))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info  # noqa: E402

MAJORITY = 0.5


def load_spec(path):
    """The same 6-field `append` lines physics_inject_joints.load_spec accepts."""
    out = []
    for ln in open(path, errors='ignore'):
        ln = ln.split('#', 1)[0].strip()
        if not ln:
            continue
        f = ln.split()
        if len(f) == 6 and f[0] != 'subdiv':
            out.append({'chain': f[0], 'parent': f[1], 'name': f[2],
                        'pos': np.array([float(f[3]), float(f[4]), float(f[5])])})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--glb', required=True)
    ap.add_argument('--spec', required=True)
    a = ap.parse_args()

    spec = load_spec(a.spec)
    if not spec:
        raise SystemExit("spec: aucune ligne `append` a 6 champs dans %s" % a.spec)

    js, bufs = read_glb(a.glb)
    binc = consolidate_buffers(js, bufs)
    names, ibms, _ = skin_info(js, binc)
    idx = {n: i for i, n in enumerate(names)}
    # bind world position of a joint = translation of inv(IBM).
    # `skin_info` ALREADY un-column-majors the glTF matrices (retarget_hd_models.py:224), so
    # transposing again here puts every joint back at the origin and the bone reads as the full
    # position vector (2.02 m instead of 0.087 m). That is the `un-posed frames / bones at origin`
    # trap, and it was caught by the bone length disagreeing with the derived spec.
    bindpos = {n: np.linalg.inv(ibms[i])[:3, 3] for i, n in enumerate(names)}

    prim = js['meshes'][0]['primitives'][0]
    P = read_accessor(js, binc, prim['attributes']['POSITION']).astype(np.float64)
    J = read_accessor(js, binc, prim['attributes']['JOINTS_0']).astype(np.int64)
    W = read_accessor(js, binc, prim['attributes']['WEIGHTS_0']).astype(np.float64)
    wscale = W.max() if W.max() > 1.5 else 1.0
    W = W / wscale

    def owned(ji, Wm, Jm):
        w = np.zeros(len(Wm))
        for c in range(Jm.shape[1]):
            w += np.where(Jm[:, c] == ji, Wm[:, c], 0.0)
        return w

    print("PREDICTION DE L'INJECTION — mesh : %s" % a.glb)
    print("NATURE repartition de la peau le long de la chaine (sommets dont le joint est")
    print("       MAJORITAIRE, w > %.2f) · REPERE majorite de poids par sommet · LIGNE DE BASE" % MAJORITY)
    print("       la meme mesure sur le mesh tel qu'il ship (colonne `avant`).")
    print("METHODE rejoue l'arithmetique de physics_inject_joints.py:303-374. AUCUNE ECRITURE.")
    print()

    for e in spec:
        if e['parent'] not in idx:
            print("%-8s parent %s ABSENT du rig — rien a predire" % (e['chain'], e['parent']))
            continue
        pj = idx[e['parent']]
        head = bindpos[e['parent']]
        axis = e['pos'] - head
        blen = float(np.linalg.norm(axis))
        u = axis / blen
        s = ((P - head) @ u) / blen
        ramp = np.clip(s, 0.0, 1.0)

        w_par0 = owned(pj, W, J)
        cand = w_par0 > 0                      # vertices carrying ANY weight on the parent
        before_par = int((w_par0 > MAJORITY).sum())

        # replay the transfer on a copy (mass conserving: t leaves the parent, joins the new joint)
        Wn = W.copy()
        take = np.where(cand, w_par0 * ramp, 0.0)
        w_par1 = w_par0 - take
        # renormalise the touched rows exactly as the injector does
        touched = np.nonzero(take > 1e-9)[0]
        rows = Wn.sum(axis=1)
        rs = np.where(rows <= 1e-9, 1.0, rows)
        pnorm = np.ones(len(P))
        pnorm[touched] = rs[touched]
        after_par = int(((w_par1 / pnorm) > MAJORITY).sum())
        after_new = int(((take / pnorm) > MAJORITY).sum())

        # CHAIN SUM, and it is NOT redundant with the per-joint majority above.
        # Splitting one joint's weight across two joints of the SAME chain MECHANICALLY lowers
        # every per-joint majority: a vertex at lBoob 0.6 / chest 0.4 becomes lBoob 0.3 /
        # lBooc 0.3 / chest 0.4 and its per-joint majority flips to `chest` — while the chain
        # still drives 60 % of it, exactly as before. Reading only the per-joint column would
        # therefore report a loss the flesh has not suffered. The grandeur that answers "does
        # this vertex still follow the CHAIN" is the sum over the chain's joints, so both are
        # printed and the difference between them is itself the finding.
        chain_before = int((w_par0 > MAJORITY).sum())
        chain_after = int((((w_par1 + take) / pnorm) > MAJORITY).sum())

        sc = s[cand]
        anchored = float((ramp[cand] * w_par0[cand]).sum())
        total = float(w_par0[cand].sum())
        print("%-8s %s -> %s   os %.4f m   sommets porteurs %d" %
              (e['chain'], e['parent'], e['name'], blen, int(cand.sum())))
        print("         s (dans le repere du NOUVEL os, 0 = %s, 1 = %s) :"
              % (e['parent'], e['name']))
        print("           min %.3f  p25 %.3f  p50 %.3f  p75 %.3f  max %.3f"
              % (sc.min(), np.percentile(sc, 25), np.percentile(sc, 50),
                 np.percentile(sc, 75), sc.max()))
        print("         MASSE : %.1f %% part au distal, %.1f %% reste ancree au proximal"
              % (100.0 * anchored / total, 100.0 * (1.0 - anchored / total)))
        print("         PROPRIETE (w>0.5)   avant : %s %d | %s --"
              % (e['parent'], before_par, e['name']))
        print("                             apres : %s %d | %s %d"
              % (e['parent'], after_par, e['name'], after_new))
        print("         CHAINE ENTIERE (somme des 2 joints, w>0.5) : %d -> %d  (%+d)"
              % (chain_before, chain_after, chain_after - chain_before))
        if chain_after < chain_before:
            print("            ^ ces sommets-la quittent VRAIMENT la chaine (dilution sous 0.5")
            print("              au profit d'un joint du buste) : c'est de la chair qui redevient")
            print("              STATIQUE, et c'est le cout reel de l'operation, pas le")
            print("              redecoupage interne ci-dessus.")
        if after_new == 0:
            print("         !! LE NOUVEAU JOINT NE POSSEDERAIT AUCUN SOMMET — l'injection serait")
            print("            INERTE, exactement le defaut mesure sur les meches le 2026-08-13.")
        if after_par == 0:
            print("         !! LE PROXIMAL PERDRAIT TOUTE SA PEAU — ce n'est pas un gradient, c'est")
            print("            un DEPLACEMENT de la charniere, et sa SPEC 30 (30 %% fortement ancre)")
            print("            resterait non representable.")
        print()

    print("LECTURE : sa SPEC 30 veut ~30 %% du volume FORTEMENT ANCRE et sa SPEC 31 un gradient")
    print("racine->pointe SANS frontiere nette. Les deux joints doivent donc posseder chacun une")
    print("part non nulle, et la masse doit se partager progressivement — pas basculer en bloc.")


if __name__ == '__main__':
    main()

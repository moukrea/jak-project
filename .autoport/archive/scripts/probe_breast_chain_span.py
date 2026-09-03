#!/usr/bin/env python3
"""probe_breast_chain_span.py — LA CHAINE SIMULEE COUVRE-T-ELLE L'ORGANE QU'ELLE PILOTE ?

POURQUOI (cycle 31). Sa SPEC 31 ecrit « r = 0 at chest attachment and r = 1 at distal/apex
region », et sa SPEC 30 repartit l'ancrage sur CINQ bandes le long de ce r. Les deux supposent que
les articulations simulees couvrent l'organe. Personne ne l'a jamais mesure : `probe_breast_anchor30`
publie DEUX abscisses qui rendent des verdicts OPPOSES sur les memes sommets (bandes 0/5 contre 5/5),
et cet ecart est aujourd'hui explique par une note de code, pas par un chiffre publie.

LES TROIS QUESTIONS DE SPEC-keira-physique 7, repondues avant d'ecrire :
  NATURE : une COUVERTURE GEOMETRIQUE — quelle part de l'organe le segment simule sous-tend-il.
           Ni une amplitude, ni une frequence : une longueur rapportee a une longueur, et un ANGLE.
  REPERE : la pose de BIND du mesh livre, en unites de jeu. Aucune dynamique n'entre ici ; ce
           nombre est le meme a toutes les frames de toutes les courses.
  ABSENT : si la chaine couvrait l'organe, le segment simule serait colineaire a l'axe principal de
           la chair (angle ~ 0 deg) et sa longueur vaudrait ~ B0. On lirait span ~ 1.00 et
           hors-segment ~ 0 %.

USAGE : python3 .autoport/probe_breast_chain_span.py [chemin.glb]
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)

import physics_keira_gen2 as G          # noqa: E402
import physics_c6_volumes as c6         # noqa: E402
from probe_skin_profile import parse_chain_joints, CHAINS, SHIPPED, GATE   # noqa: E402

# L'ancre RIGIDE de chaque chaine : elle est HORS chaine (physics_chains.txt le dit en clair),
# donc elle ne peut pas etre lue dans les lignes `j` et doit etre nommee ici.
ANCHOR = 'chest'


def main():
    rel = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    geo = c6.load_geometry(G.MODEL, glb=rel)
    if geo is None:
        raise SystemExit("mesh introuvable ou illisible : %s" % rel)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx_of = {n: i for i, n in enumerate(names)}
    if ANCHOR not in idx_of:
        raise SystemExit("ancre '%s' absente du mesh" % ANCHOR)

    chains = parse_chain_joints(CHAINS)
    print("COUVERTURE DE LA CHAINE SUR SON ORGANE — mesh : %s" % rel)
    print("NATURE couverture geometrique (longueur/longueur, et un angle) · REPERE pose de BIND,")
    print("unites de jeu · ABSENT segment colineaire a la chair (0 deg), span 1.00, hors-segment 0 %%")
    print("seuil d'appartenance w>%.2f\n" % GATE)

    for cname, spec in sorted(chains.items()):
        jn = [j for j in spec['joints'] if j in idx_of]
        if len(jn) < 2:
            print("%-8s  moins de 2 joints presents" % cname); continue
        gi = [idx_of[j] for j in jn]
        pj = np.asarray([P[g] for g in gi], dtype=float)
        pa = np.asarray(P[idx_of[ANCHOR]], dtype=float)

        # le nuage de chair de la chaine : meme critere d'appartenance que le generateur
        wsum = np.zeros(len(V))
        for k in range(J.shape[1]):
            for g in gi:
                wsum += np.where(J[:, k] == g, W[:, k], 0.0)
        vi = np.nonzero(wsum > GATE)[0]
        C = np.asarray(V[vi], dtype=float)
        n = len(C)

        # 1. LE SEGMENT SIMULE — celui que le solveur fait tourner (dernier os de la chaine).
        seg = pj[-1] - pj[0]
        lseg = float(np.linalg.norm(seg))
        useg = seg / lseg
        # le LEVIER — l'os qui porte la chaine, ancre -> premier joint. Il n'est pas simule en
        # tant que segment de chair : il place l'organe.
        lev = pj[0] - pa
        llev = float(np.linalg.norm(lev))

        # 2. L'AXE PRINCIPAL DE LA CHAIR — premiere composante principale du nuage, ponderee par
        #    le poids que la chaine y porte (un sommet a 0.06 ne pese pas comme un sommet a 1.0).
        w = wsum[vi]
        mu = (C * w[:, None]).sum(0) / w.sum()
        X = (C - mu) * np.sqrt(w)[:, None]
        _u, _s, vt = np.linalg.svd(X, full_matrices=False)
        uax = vt[0] / np.linalg.norm(vt[0])
        ext = (C - mu) @ uax
        flesh_len = float(ext.max() - ext.min())

        # 3. L'ANGLE entre les deux, ramene dans [0,90] (une direction, pas un sens).
        cosa = abs(float(np.dot(useg, uax)))
        ang = float(np.degrees(np.arccos(min(1.0, cosa))))

        # 4. CE QUE LE SEGMENT SOUS-TEND — projection de la chair sur SA direction.
        t = (C - pj[0]) @ useg / lseg          # 0 = joint proximal, 1 = joint distal
        outside = float(((t < 0.0) | (t > 1.0)).mean())
        span_u = float((t.max() - t.min()) * lseg)

        print("=== %-8s  n=%d sommets" % (cname, n))
        print("  levier   %-5s -> %-6s      %8.2f u    (il PLACE l'organe, il n'est pas de la chair)"
              % (ANCHOR, jn[0], llev))
        print("  segment  %-5s -> %-6s      %8.2f u    <- LE SEUL SEGMENT DE CHAIR SIMULE" % (jn[0], jn[-1], lseg))
        print("  chair    axe principal, etendue   %8.2f u" % flesh_len)
        print("  ANGLE segment simule / axe de la chair          %6.1f deg   (ABSENT : 0)" % ang)
        print("  la chair sous-tendue par le segment             %8.2f u sur %8.2f  = %5.1f %%"
              % (span_u, flesh_len, 100.0 * span_u / flesh_len))
        print("  longueur du segment / etendue de la chair       %5.1f %%" % (100.0 * lseg / flesh_len))
        print("  sommets HORS du segment (t<0 ou t>1)            %5.1f %%   (ABSENT : 0)" % (100.0 * outside))
        print("  t (abscisse sur le segment) : min=%.3f max=%.3f" % (t.min(), t.max()))

        # 5. UN AXE RACINE->APEX QUI NE DOIT RIEN A UNE ACP. Sa SPEC 30 definit elle-meme ses
        #    bandes par l'ANCRAGE (le poids qui reste sur `chest`) : la « deep root » est la bande
        #    90-100 %, l'« apex » la bande 0-10 %. On prend donc le barycentre de chacune, et
        #    l'axe qui les joint EST le « r = 0 at chest attachment -> r = 1 at apex » de sa 31,
        #    sans qu'aucune direction ait ete choisie a la main.
        anc = np.zeros(len(vi))
        ai = idx_of[ANCHOR]
        for k in range(J.shape[1]):
            anc += np.where(J[vi, k] == ai, W[vi, k], 0.0)
        tot = anc + wsum[vi]
        anc = np.where(tot > 1e-9, anc / np.maximum(tot, 1e-9), 0.0)
        mroot, mapex = anc >= 0.90, anc <= 0.10
        if mroot.any() and mapex.any():
            proot = C[mroot].mean(0)
            papex = C[mapex].mean(0)
            ra = papex - proot
            b0m = float(np.linalg.norm(ra))
            ura = ra / b0m
            cosb = abs(float(np.dot(useg, ura)))
            angb = float(np.degrees(np.arccos(min(1.0, cosb))))
            tr = (C - proot) @ ura / b0m
            outr = float(((tr < 0.0) | (tr > 1.0)).mean())
            print("  --- AXE RACINE->APEX DERIVE DES BANDES DE SA SPEC 30 (pas d'ACP) ---")
            print("  racine = barycentre ancrage>=0.90 (n=%d) · apex = barycentre ancrage<=0.10 (n=%d)"
                  % (int(mroot.sum()), int(mapex.sum())))
            print("  B0 MESURE racine->apex                         %8.2f u   (livre dans la chaine : 602)" % b0m)
            print("  ANGLE segment simule / axe racine-apex         %6.1f deg   (ABSENT : 0)" % angb)
            print("  longueur du segment / B0 mesure                %5.1f %%" % (100.0 * lseg / b0m))
            print("  sommets hors de [racine,apex] sur CET axe      %5.1f %%" % (100.0 * outr))
        else:
            print("  --- axe racine->apex : bande vide (root n=%d, apex n=%d), non calculable ---"
                  % (int(mroot.sum()), int(mapex.sum())))

        # 6. LA FORME DU NUAGE — les trois etendues principales. Un axe principal n'a de sens que
        #    si le nuage est allonge ; s'il est presque isotrope, l'ACP designe une direction
        #    arbitraire et l'angle du point 3 ne doit pas etre lu.
        e3 = [float(np.ptp((C - mu) @ (vt[i] / np.linalg.norm(vt[i])))) for i in range(3)]
        print("  etendues principales du nuage : %.1f / %.1f / %.1f u  (rapport 1:%.2f:%.2f)"
              % (e3[0], e3[1], e3[2], e3[1] / e3[0], e3[2] / e3[0]))
    return 0


if __name__ == '__main__':
    sys.exit(main())

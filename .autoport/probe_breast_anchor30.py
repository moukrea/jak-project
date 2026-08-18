#!/usr/bin/env python3
"""probe_breast_anchor30.py — LE PROFIL D'ANCRAGE DE LA POITRINE, CONTRE SA SPEC 30 / SPEC 31.

POURQUOI CET INSTRUMENT (2026-08-18). Le contrat exige que l'injection de `lBooc`/`rBooc` soit
accompagnee du REPESAGE, et que la preuve soit la REPARTITION. La sonde de repartition existe deja
(`probe_skin_ownership.py`) et elle rend, sur le mesh LIVRE, `chestL 21|8` / `chestR 24|3`.
Celle-ci repond a la question d'APRES, la seule qui puisse dire QUOI CORRIGER : ou, le long de
l'organe, le poids est-il place, et que dit sa SPEC 30 qu'il devrait valoir a cet endroit ?

LES TROIS QUESTIONS DE LA SPEC 7, repondues avant d'ecrire le chiffre :

  NATURE  : un PROFIL — l'ancrage en fonction de la PROFONDEUR dans l'organe. Sa SPEC 30 ne donne
            pas un nombre, elle donne CINQ BANDES (racine profonde 90-100 %, arriere 55-85 %,
            mi-volume 25-55 %, distal 5-30 %, apex minimal). Un scalaire ne peut pas etre compare a
            une table de bandes ; c'est le meme piege que `cov` sur les meches.
  REPERE  : l'abscisse curviligne de la polyligne des joints DE LA CHAINE, en pose de bind,
            racine=0 -> pointe=1 — exactement le `r` que sa SPEC 31 definit (« r = 0 at chest
            attachment, r = 1 at distal/apex region »). Ni le monde, ni un repere d'os.
  ABSENT  : le profil d'ancrage DESCEND de ~0.95 a la racine vers ~0 a l'apex. Un ancrage HAUT a
            une abscisse HAUTE est le defaut : la chair qui doit se deformer le plus est soudee au
            thorax.

CE QUE LA SONDE FAIT EN PLUS : elle DERIVE, depuis la spec et depuis la geometrie mesuree, les deux
constantes de l'operateur de repesage (l'exposant d'ancrage `p` de la 30 et le gradient `grad` de la
31) et PREDIT la table de repartition qui en sortira — avant toute cuisson, donc falsifiable.

USAGE : python3 .autoport/probe_breast_anchor30.py [chemin.glb]
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G          # noqa: E402
import physics_c6_volumes as c6         # noqa: E402
from probe_skin_profile import parse_chain_joints, arc_param, CHAINS, SHIPPED  # noqa: E402

GATE = G.INFL_GATE
MAJORITY = 0.5

# --- SPEC-breast-softbody.md 30 : les cinq bandes, recopiees sans retouche -------------------
#     Deep root         90-100 %      (r ~ 0.00)
#     Rear/intermediate 55-85  %      (r ~ 0.25)
#     Mid-volume        25-55  %      (r ~ 0.50)
#     Distal            5-30   %      (r ~ 0.75)
#     Apex              minimal       (r ~ 1.00)
BANDS = [(0.00, 0.90, 1.00, 'Deep root'),
         (0.25, 0.55, 0.85, 'Rear/intermediate'),
         (0.50, 0.25, 0.55, 'Mid-volume'),
         (0.75, 0.05, 0.30, 'Distal'),
         (1.00, 0.00, 0.10, 'Apex (minimal)')]
ROOT_ANCHOR = 0.95          # 30 `RootAnchor = 0.90-1.00`, milieu de bande
STRONG = 0.55               # « strongly attached » = le plancher de la bande Rear/intermediate
STRONG_FRAC = 0.30          # 30 `StrongRootFraction = 0.30` (bande 0.28-0.35)
GRAD_LO, GRAD_NOM, GRAD_HI = 1.6, 1.8, 2.0   # 31 `RootDeformationExponent = 1.6-2.0`


def anchor_of(s, p):
    """Profil d'ancrage de la 30 : ancrage = RootAnchor * (1-r)^p. Descend de 0.95 a 0."""
    return ROOT_ANCHOR * np.power(np.clip(1.0 - s, 0.0, 1.0), p)


def feasible_p():
    """Intervalle des exposants qui tiennent DANS les trois bandes interieures de la 30."""
    lo, hi = 0.0, 99.0
    for r, blo, bhi, _ in BANDS[1:4]:
        # ROOT_ANCHOR * (1-r)^p dans [blo, bhi]  ->  p dans [ln(bhi/RA)/ln(1-r), ln(blo/RA)/ln(1-r)]
        u = np.log(1.0 - r)
        lo = max(lo, np.log(bhi / ROOT_ANCHOR) / u)
        hi = min(hi, np.log(blo / ROOT_ANCHOR) / u)
    return lo, hi


def chain_data(cname, joints, names, idx_of, P, V, J, W):
    grp = [idx_of[j] for j in joints if j in idx_of]
    if len(grp) < 2:
        return None
    ws = np.zeros(len(W))
    for c in range(J.shape[1]):
        ws += np.where(np.isin(J[:, c], grp), W[:, c], 0.0)
    vi = np.flatnonzero(ws > GATE)
    s, beyond = arc_param(np.asarray([P[g] for g in grp], dtype=float),
                          np.asarray(V[vi], dtype=float))
    per = []
    for g in grp:
        w = np.zeros(len(W))
        for c in range(J.shape[1]):
            w += np.where(J[:, c] == g, W[:, c], 0.0)
        per.append(w[vi])
    return dict(vi=vi, s=s, ws=ws[vi], per=np.asarray(per), grp=grp, joints=joints,
                beyond=beyond)


def main():
    rel = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    geo = c6.load_geometry(G.MODEL, glb=rel)
    if geo is None:
        raise SystemExit("mesh introuvable : %s" % rel)
    names, P, V, J, W = geo['names'], geo['P'], geo['V'], geo['J'], geo['W']
    idx_of = {n: i for i, n in enumerate(names)}
    chains = parse_chain_joints(CHAINS)

    plo, phi = feasible_p()
    print("PROFIL D'ANCRAGE DE LA POITRINE — mesh : %s" % rel)
    print("NATURE profil ancrage(r) · REPERE abscisse curviligne de la chaine, pose de bind,")
    print("racine=0 apex=1 (le `r` de sa SPEC 31) · ABSENT le profil DESCEND de 0.95 vers 0")
    print("SPEC 30 : ancrage = poids qui reste sur `chest` (l'ancre rigide, HORS chaine)")
    print("exposant admissible par les trois bandes interieures de la 30 : p dans [%.3f, %.3f]\n"
          % (plo, phi))

    for cname in ('chestL', 'chestR'):
        if cname not in chains:
            continue
        d = chain_data(cname, chains[cname]['joints'], names, idx_of, P, V, J, W)
        if d is None:
            print("%s : moins de 2 joints presents" % cname)
            continue
        s, ws, per = d['s'], d['ws'], d['per']
        anc = 1.0 - ws
        n = len(s)
        print("=== %s   n=%d sommets (poids somme chaine > %.2f)" % (cname, n, GATE))
        print("  s : p25=%.3f p50=%.3f p75=%.3f p90=%.3f p95=%.3f"
              % tuple(np.percentile(s, q) for q in (25, 50, 75, 90, 95)))
        print("  ANCRAGE MESURE vs BANDES DE LA SPEC 30 (moyenne par quart d'abscisse) :")
        for lo, hi, lbl, blo, bhi in ((0.000, 0.125, 'Deep root        r<0.125', 0.90, 1.00),
                                      (0.125, 0.375, 'Rear/intermed  0.125-0.375', 0.55, 0.85),
                                      (0.375, 0.625, 'Mid-volume     0.375-0.625', 0.25, 0.55),
                                      (0.625, 0.875, 'Distal         0.625-0.875', 0.05, 0.30),
                                      (0.875, 1.001, 'Apex             r>0.875', 0.00, 0.10)):
            m = (s >= lo) & (s < hi)
            if not m.any():
                print("    %-28s  n=0" % lbl)
                continue
            a = float(anc[m].mean())
            ok = 'DANS' if blo <= a <= bhi else ('AU-DESSUS' if a > bhi else 'SOUS')
            print("    %-28s n=%3d  ancrage=%.3f   bande %.2f-%.2f   %s"
                  % (lbl, int(m.sum()), a, blo, bhi, ok))
        cur_strong = float((anc >= STRONG).mean())
        print("  StrongRootFraction MESUREE (ancrage >= %.2f, part des sommets) = %.3f"
              "   cible %.2f (bande 0.28-0.35)" % (STRONG, cur_strong, STRONG_FRAC))

        # --- DERIVATION DE `p`. La cible est la grandeur que la 30 NOMME : `StrongRootFraction`
        #     = 0.30. On cherche l'exposant qui l'approche le plus PRES, en restant dans
        #     l'intervalle que les trois bandes interieures autorisent — la spec borne la
        #     derivation, jamais l'inverse. Le 30e centile de `s` ne peut pas servir de seuil ici :
        #     il vaut 0.000 (40 % des sommets se projettent sur le noeud racine), donc l'inverse
        #     de la courbe y est degenere. C'est une PROPRIETE MESUREE de l'organe, pas un reglage.
        cand = np.linspace(plo, phi, 2001)
        frac = np.array([float((anchor_of(s, pc) >= STRONG).mean()) for pc in cand])
        p = float(cand[int(np.argmin(np.abs(frac - STRONG_FRAC)))])
        print("  DERIVATION : p qui approche StrongRootFraction=%.2f dans [%.3f, %.3f] -> p=%.3f"
              "  (fraction atteignable la plus basse = %.3f)"
              % (STRONG_FRAC, plo, phi, p, float(frac.min())))

        # --- prediction de la repartition apres repesage 30+31
        for grad in (GRAD_LO, GRAD_NOM, GRAD_HI):
            tgt = 1.0 - anchor_of(s, p)
            ad = np.power(np.clip(s, 0.0, 1.0), grad)
            wprox, wdist = tgt * (1.0 - ad), tgt * ad
            majp = int((wprox > MAJORITY).sum())
            majd = int((wdist > MAJORITY).sum())
            strong = float((anchor_of(s, p) >= STRONG).mean())
            print("  PREDIT p=%.3f grad=%.2f : majoritaires  %s=%d  %s=%d"
                  "   part distale=%.1f%%   StrongRootFraction=%.3f"
                  % (p, grad, d['joints'][0], majp, d['joints'][1], majd,
                     100.0 * majd / max(1, majp + majd), strong))
        print("  MESURE ACTUELLE            : majoritaires  %s=%d  %s=%d"
              % (d['joints'][0], int((per[0] > MAJORITY).sum()),
                 d['joints'][1], int((per[1] > MAJORITY).sum())))

        # ------------------------------------------------------------------------------------
        # LE MEME PROFIL, LU DANS LE REPERE QUE LA 31 DEFINIT (ajoute le 2026-08-18, cycle 24).
        # ON N'EN REMPLACE AUCUN : les deux colonnes restent cote a cote, pour que l'ecart entre
        # elles reste lisible.
        # POURQUOI. Sa 31 ecrit : « r = 0 at chest attachment and r = 1 at distal/apex region ».
        # Le bloc ci-dessus prend r=0 AU JOINT proximal et r=1 AU JOINT distal — ce n'est pas la
        # meme abscisse. Mesure : la chair s'etend de t=-0.333 a t=+1.206 le long de l'os, donc
        # 26 % (chestL) a 31 % (chestR) du nuage est ECRASE par le clampage sur une des deux
        # bornes, et le profil d'ancrage — qui est une fonction de r — y est SATURE.
        # Depuis le cycle 24 la regle `anchor30` travaille dans CE repere (`axis=flesh`) : lire
        # son resultat dans l'autre compare deux abscisses differentes, exactement le piege de
        # repere qui avait rendu le gradient monde/parent illisible le 2026-08-11.
        pts = np.asarray([P[g] for g in d['grp']], dtype=float)
        axv = pts[-1] - pts[0]
        axv = axv / np.linalg.norm(axv)
        q = (np.asarray(V[d['vi']], dtype=float) - pts[0]) @ axv
        sf = (q - q.min()) / (q.max() - q.min())
        print("  --- LE MEME MESH, ABSCISSE DE LA 31 (r=0 attache thoracique, r=1 apex) ---")
        print("  r : p25=%.3f p50=%.3f p75=%.3f p90=%.3f p95=%.3f"
              % tuple(np.percentile(sf, qq) for qq in (25, 50, 75, 90, 95)))
        nb_in = 0
        for lo, hi, lbl, blo, bhi in ((0.000, 0.125, 'Deep root        r<0.125', 0.90, 1.00),
                                      (0.125, 0.375, 'Rear/intermed  0.125-0.375', 0.55, 0.85),
                                      (0.375, 0.625, 'Mid-volume     0.375-0.625', 0.25, 0.55),
                                      (0.625, 0.875, 'Distal         0.625-0.875', 0.05, 0.30),
                                      (0.875, 1.001, 'Apex             r>0.875', 0.00, 0.10)):
            m = (sf >= lo) & (sf < hi)
            if not m.any():
                print("    %-28s  n=0" % lbl)
                continue
            a = float(anc[m].mean())
            ok = 'DANS' if blo <= a <= bhi else ('AU-DESSUS' if a > bhi else 'SOUS')
            nb_in += 1 if ok == 'DANS' else 0
            print("    %-28s n=%3d  ancrage=%.3f   bande %.2f-%.2f   %s"
                  % (lbl, int(m.sum()), a, blo, bhi, ok))
        majp = int((per[0] > MAJORITY).sum())
        majd = int((per[1] > MAJORITY).sum())
        print("  StrongRootFraction (repere 31) = %.3f   cible %.2f (bande 0.28-0.35)   bandes"
              " DANS : %d/5" % (float((anc >= STRONG).mean()), STRONG_FRAC, nb_in))
        print("  REPARTITION — la grandeur que la directive du 2026-08-18 08:55 exige :")
        print("    %s majoritaire sur %d sommets (%.1f %% de la chaine)"
              % (d['joints'][0], majp, 100.0 * majp / max(1, n)))
        print("    %s majoritaire sur %d sommets (%.1f %% de la chaine)   barre du contrat 30 %%"
              "   %s" % (d['joints'][1], majd, 100.0 * majd / max(1, n),
                         'AU-DESSUS' if majd / max(1, n) >= 0.30 else 'SOUS'))
        print("  poids total porte par chaque os (somme des poids de peau) : %s"
              % "  ".join("%s=%.3f" % (d['joints'][k], float(per[k].sum()))
                          for k in range(len(d['joints']))))
        print()


if __name__ == '__main__':
    main()

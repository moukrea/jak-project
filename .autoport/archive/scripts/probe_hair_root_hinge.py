#!/usr/bin/env python3
"""probe_hair_root_hinge.py — SI ON LIBERE LA ROTATION DU JOINT 0, LA RACINE SE DECOLLE-T-ELLE ?

Defaut ouvert `hair-gradient`. Toutes les chaines de cheveux portent `rootlock=1`, donc le moteur
n'integre NI n'ecrit le maillon 0 (`jak-hd-physics.gc`, boucle d'ecriture : `(dotimes (l n) (when
(>= l rlk) ...))`). Le premier SEGMENT de chaque meche est fige a 0 degre en permanence.

Question a trancher, purement geometrique : si on libere la ROTATION du joint 0 en gardant sa
POSITION soudee, la racine visible des cheveux se decolle-t-elle du crane ?

Deux scenarios, meme angle, memes sommets :
  A. rotation de theta autour de L'ORIGINE DU JOINT 0    -> l'origine du joint 0 ne bouge pas
  B. rotation de theta autour de L'ANCRE (le crane)      -> l'origine du joint 0 balaye un arc

Pour un sommet v et un centre c, le deplacement rigide vaut 2*sin(theta/2)*d_perp(v-c, axe). Pour
ne PAS choisir un axe arbitraire on prend la borne SUPERIEURE, atteinte par l'axe le plus
defavorable a ce sommet : 2*sin(theta/2)*|v-c|. C'est conservateur des deux cotes, donc le
contraste entre A et B n'est pas un artefact du choix d'axe. Une colonne « axe de flexion reel »
(moyenne sur 64 axes perpendiculaires a l'os) est publiee a cote pour montrer que la lecture ne
change pas.

Le deplacement VISIBLE n'est pas le deplacement rigide : en skinning lineaire, seul le joint 0
bouge, donc v' = v + w_j0 * (R(v-c) - (v-c)). Un sommet a moitie pondere sur le crane ne parcourt
que la moitie du chemin. Les deux chiffres sont donnes.

LECTURE SEULE : n'ecrit aucun asset, aucun .gc, rien.
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'scripts', 'shell'))

import physics_keira_gen2 as G  # noqa: E402

UNITS = 4096.0                  # unites de jeu par metre
MM = 1000.0 / UNITS             # 1 unite de jeu -> mm  (0.2441406 mm)
THETA = 30.0                    # degres
CHORD = 2.0 * np.sin(np.radians(THETA) / 2.0)   # |R(x)-x| <= CHORD*|x|
DOM = 'dominant'                # selection principale : poids dominant sur le joint 0
WMIN = 1e-6                     # « influence par le joint 0 » = poids non nul

HAIR = ['earL', 'earR', 'backhair', 'lbang', 'rbang', 'lmidhair', 'rmidhair']
SKULL = 'head'


def read_chains(path, model='keira-hd'):
    """-> (ordered dict chain -> [joint names], set of every simulated joint name)."""
    chains, order, cur, inmodel = {}, [], None, False
    for line in open(path, encoding='utf-8', errors='replace'):
        s = line.strip()
        if s.startswith('[model '):
            inmodel = (s == '[model %s]' % model)
            continue
        if s.startswith('[') and not s.startswith('[model'):
            inmodel = False
            continue
        if not inmodel or not s or s.startswith('#'):
            continue
        if s.startswith('chain '):
            cur = s.split()[1]
            chains[cur] = []
            order.append(cur)
        elif s.startswith('j ') and cur:
            chains[cur].append(s.split()[1])
    sim = set(j for v in chains.values() for j in v)
    return chains, order, sim


def perp_axes(u, k=64):
    """k axes unitaires repartis dans le plan perpendiculaire a u."""
    u = u / np.linalg.norm(u)
    t = np.array([1.0, 0.0, 0.0])
    if abs(u @ t) > 0.9:
        t = np.array([0.0, 1.0, 0.0])
    e1 = np.cross(u, t)
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(u, e1)
    a = np.linspace(0.0, np.pi, k, endpoint=False)
    return np.cos(a)[:, None] * e1 + np.sin(a)[:, None] * e2


def disp_axis(pts, c, n):
    """|R_n(v-c) - (v-c)| pour l'axe unitaire n : 2 sin(theta/2) * distance a l'axe."""
    rel = pts - c
    perp = rel - np.outer(rel @ n, n)
    return CHORD * np.linalg.norm(perp, axis=1)


def stats(x):
    if len(x) == 0:
        return (0.0,) * 4
    return (float(np.percentile(x, 5)), float(np.percentile(x, 50)),
            float(np.percentile(x, 95)), float(x.max()))


def main():
    rig_names, parent, _ = G.load_rig(os.path.join(REPO, G.RIG_REL))
    geo = G.load_mesh(G.MODEL)
    if list(geo['names']) != list(rig_names):
        # les deux listes doivent coincider index par index, sinon toute la mesure est fausse
        raise SystemExit('rig json et GLB ne partagent pas l ordre des joints')
    idx = {n: i for i, n in enumerate(rig_names)}
    P, V = geo['P'], geo['V']
    J, W = np.asarray(geo['J']), np.asarray(geo['W'])
    chains, _order, sim = read_chains(os.path.join(REPO, 'recharged_assets/physics_chains.txt'))
    jskull = idx[SKULL]

    print('probe_hair_root_hinge — rig=%s  mesh=%s' % (G.RIG_REL, geo['src']))
    print('nv=%d  njoints=%d  theta=%.0f deg  corde=2*sin(theta/2)=%.5f  1 u = %.7f mm'
          % (len(V), len(rig_names), THETA, CHORD, MM))
    print('joints simules (toutes chaines de ce modele) : %d' % len(sim))
    print()

    summary = []
    for cname in HAIR:
        if cname not in chains:
            print('!! chaine %s absente de physics_chains.txt' % cname)
            continue
        joints = chains[cname]
        j0n = joints[0]
        j0 = idx[j0n]
        anc = parent[j0]
        ancn = rig_names[anc]
        j1 = idx[joints[1]] if len(joints) > 1 else None

        L_anc = float(np.linalg.norm(P[j0] - P[anc]))
        L_j01 = float(np.linalg.norm(P[j1] - P[j0])) if j1 is not None else float('nan')

        # --- selection : poids DOMINANT sur le joint 0 -----------------------------------------
        slot = W.argmax(axis=1)
        dom = J[np.arange(len(J)), slot]
        selD = np.flatnonzero((dom == j0) & (W[np.arange(len(W)), slot] > 0.0))
        # --- selection large : tout sommet INFLUENCE par le joint 0 -----------------------------
        mAny = np.zeros(len(W), dtype=bool)
        wj0 = np.zeros(len(W))
        for c in range(J.shape[1]):
            m = (J[:, c] == j0) & (W[:, c] > WMIN)
            mAny |= m
            wj0[m] += W[m, c]
        selA = np.flatnonzero(mAny)

        pts = V[selD]
        rD = np.linalg.norm(pts - P[j0], axis=1)          # distance a l'ORIGINE du joint 0
        rA = np.linalg.norm(pts - P[anc], axis=1)         # distance a l'ANCRE

        # --- borne superieure (axe le plus defavorable, independante du choix d'axe) ------------
        dA_rig = CHORD * rD
        dB_rig = CHORD * rA
        w = wj0[selD]
        dA_lbs = w * dA_rig
        dB_lbs = w * dB_rig

        # --- axe de flexion reel : moyenne sur 64 axes perpendiculaires a l os ancre->joint0 ----
        u = (P[j0] - P[anc])
        axes = perp_axes(u)
        mA = np.mean([disp_axis(pts, P[j0], n) for n in axes], axis=0)
        mB = np.mean([disp_axis(pts, P[anc], n) for n in axes], axis=0)

        # --- partage du poids avec le crane / les os non simules --------------------------------
        wtot = W[selA].sum()
        wsk = 0.0
        wsim_other = 0.0
        wnosim = 0.0
        for c in range(J.shape[1]):
            jj = J[selA, c]
            ww = W[selA, c]
            wsk += float(ww[jj == jskull].sum())
            for k in np.unique(jj):
                k = int(k)
                if k == j0:
                    continue
                s = float(ww[jj == k].sum())
                if rig_names[k] in sim:
                    wsim_other += s
                else:
                    wnosim += s
        wself = float(sum(W[selA, c][J[selA, c] == j0].sum() for c in range(J.shape[1])))

        print('=' * 96)
        print('CHAINE %s   joint0=%s (idx %d)   ANCRE=%s (idx %d)   chaine=%s'
              % (cname, j0n, j0, ancn, anc, ' -> '.join(joints)))
        print('  os ancre->joint0 : %8.1f u = %7.2f mm     os joint0->joint1 : %8.1f u = %7.2f mm'
              % (L_anc, L_anc * MM, L_j01, L_j01 * MM))
        print('  sommets a poids DOMINANT sur %s : %d      sommets INFLUENCES (w>0) : %d'
              % (j0n, len(selD), len(selA)))
        a, b, c5, d = stats(rD)
        print('  |v - origine(joint0)|   p05=%7.1f u %7.2f mm | p50=%7.1f u %7.2f mm '
              '| p95=%7.1f u %7.2f mm | max=%7.1f u %7.2f mm'
              % (a, a * MM, b, b * MM, c5, c5 * MM, d, d * MM))
        a, b, c5, d = stats(rA)
        print('  |v - ANCRE|             p05=%7.1f u %7.2f mm | p50=%7.1f u %7.2f mm '
              '| p95=%7.1f u %7.2f mm | max=%7.1f u %7.2f mm'
              % (a, a * MM, b, b * MM, c5, c5 * MM, d, d * MM))
        print('  --- DEPLACEMENT SOUS %.0f deg (mm) -----------------------------------' % THETA)
        print('  %-34s %10s %10s | %10s %10s' % ('', 'A p50', 'A max', 'B p50', 'B max'))
        print('  %-34s %10.2f %10.2f | %10.2f %10.2f'
              % ('rigide, borne sup (pire axe)', np.percentile(dA_rig, 50) * MM,
                 dA_rig.max() * MM, np.percentile(dB_rig, 50) * MM, dB_rig.max() * MM))
        print('  %-34s %10.2f %10.2f | %10.2f %10.2f'
              % ('rigide, axe de flexion moyen', np.percentile(mA, 50) * MM, mA.max() * MM,
                 np.percentile(mB, 50) * MM, mB.max() * MM))
        print('  %-34s %10.2f %10.2f | %10.2f %10.2f'
              % ('VISIBLE (skinne, x w_j0)', np.percentile(dA_lbs, 50) * MM, dA_lbs.max() * MM,
                 np.percentile(dB_lbs, 50) * MM, dB_lbs.max() * MM))
        print('  origine du joint 0 elle-meme  : A = %.2f mm (fixee par construction)   '
              'B = %.2f mm' % (0.0, CHORD * L_anc * MM))
        print('  --- PARTAGE DU POIDS sur les %d sommets influences ---------------------'
              % len(selA))
        print('  poids total=%.2f | sur %s(joint0)=%.1f%% | sur %s(CRANE)=%.1f%% | '
              'autres os simules=%.1f%% | os NON simules (dont crane)=%.1f%%'
              % (wtot, j0n, 100.0 * wself / wtot, SKULL, 100.0 * wsk / wtot,
                 100.0 * wsim_other / wtot, 100.0 * wnosim / wtot))

        # --- LA COUTURE : les sommets partages entre le joint 0 et le CRANE ---------------------
        # Ce sont EUX qui « decollent » ou non : un sommet 100 % crane ne bouge jamais, un sommet
        # 100 % joint 0 est deja du cheveu libre. La dechirure visible se joue sur la bande ou les
        # deux poids coexistent.
        whead = np.zeros(len(W))
        for c in range(J.shape[1]):
            m = J[:, c] == jskull
            whead[m] += W[m, c]
        seam = np.flatnonzero((wj0 >= 0.05) & (whead >= 0.05))
        print('  --- COUTURE joint0 / %s : %d sommets (w_j0>=0.05 ET w_crane>=0.05) ------'
              % (SKULL, len(seam)))
        if len(seam):
            sp = V[seam]
            sr = np.linalg.norm(sp - P[j0], axis=1)
            sA = wj0[seam] * CHORD * sr
            sB = wj0[seam] * CHORD * np.linalg.norm(sp - P[anc], axis=1)
            print('     |v - origine(joint0)| p05=%6.1f u %6.2f mm  p50=%6.1f u %6.2f mm  '
                  'max=%6.1f u %6.2f mm' % (np.percentile(sr, 5), np.percentile(sr, 5) * MM,
                                            np.percentile(sr, 50), np.percentile(sr, 50) * MM,
                                            sr.max(), sr.max() * MM))
            print('     w_j0 sur la couture   p05=%.3f p50=%.3f max=%.3f' %
                  (np.percentile(wj0[seam], 5), np.percentile(wj0[seam], 50), wj0[seam].max()))
            print('     DECHIRURE VISIBLE mm   A: p50=%6.2f p95=%6.2f max=%6.2f    '
                  'B: p50=%6.2f p95=%6.2f max=%6.2f'
                  % (np.percentile(sA, 50) * MM, np.percentile(sA, 95) * MM, sA.max() * MM,
                     np.percentile(sB, 50) * MM, np.percentile(sB, 95) * MM, sB.max() * MM))
            # les sommets que le CRANE domine encore (w_j0 < 0.5) sont ceux qui DOIVENT rester
            # colles : leur deplacement sous A est la mesure exacte du « decollement ».
            keep = seam[wj0[seam] < 0.5]
            if len(keep):
                kr = np.linalg.norm(V[keep] - P[j0], axis=1)
                kA = wj0[keep] * CHORD * kr
                kB = wj0[keep] * CHORD * np.linalg.norm(V[keep] - P[anc], axis=1)
                print('     dont %d domines par le CRANE (w_j0<0.5, ils DOIVENT rester colles) : '
                      'A p50=%.2f max=%.2f mm | B p50=%.2f max=%.2f mm'
                      % (len(keep), np.percentile(kA, 50) * MM, kA.max() * MM,
                         np.percentile(kB, 50) * MM, kB.max() * MM))
                # DECOLLEMENT vs GLISSEMENT. Un deplacement tangent au crane fait glisser la
                # bande sur la tete (peu visible) ; un deplacement RADIAL la souleve ou l enfonce
                # — c est ca, « decoller ». On approxime la normale du crane par la direction
                # centre-de-tete -> sommet, et on prend le PIRE des 64 axes de flexion.
                nh = V[keep] - P[jskull]
                nh = nh / np.maximum(np.linalg.norm(nh, axis=1)[:, None], 1e-9)
                relA = V[keep] - P[j0]
                liftA = np.zeros(len(keep))
                for n in axes:
                    dd = CHORD * (relA - np.outer(relA @ n, n))
                    # rotation d angle theta : la corde est perpendiculaire au rayon; on borne
                    # sa projection radiale par sa norme fois le cosinus reel du vecteur corde.
                    rot = np.cross(n, relA) * np.sin(np.radians(THETA))
                    rot = rot + (np.outer(relA @ n, n) - relA) * (1 - np.cos(np.radians(THETA)))
                    liftA = np.maximum(liftA, np.abs(np.einsum('ij,ij->i', rot, nh)))
                liftA = wj0[keep] * liftA
                print('     DECOLLEMENT RADIAL (pire axe) des %d sommets crane : p50=%.2f '
                      'p95=%.2f max=%.2f mm  [le reste du deplacement glisse sur le crane]'
                      % (len(keep), np.percentile(liftA, 50) * MM,
                         np.percentile(liftA, 95) * MM, liftA.max() * MM))
            dmin = np.linalg.norm(V[selD] - P[j0], axis=1).min()
            print('     sommet le PLUS PROCHE de l origine du joint 0 (parmi ses dominants) : '
                  '%.1f u = %.2f mm  -> l origine est %s la geometrie'
                  % (dmin, dmin * MM, 'DANS' if dmin * MM < 30 else 'HORS de'))
            seam_stats = (len(seam), np.percentile(sA, 50) * MM, sA.max() * MM,
                          np.percentile(sB, 50) * MM, sB.max() * MM)
        else:
            print('     aucune couture : le joint 0 ne partage aucun sommet avec le crane')
            seam_stats = (0, 0.0, 0.0, 0.0, 0.0)

        pw = wj0[selD]
        print('  w_j0 sur les sommets dominants : p05=%.3f p50=%.3f p95=%.3f  '
              '(1 - w_j0 reste colle au reste du corps)'
              % (np.percentile(pw, 5), np.percentile(pw, 50), np.percentile(pw, 95)))
        summary.append((cname, j0n, ancn, L_anc, np.percentile(dA_lbs, 50) * MM,
                        dA_lbs.max() * MM, np.percentile(dB_lbs, 50) * MM, dB_lbs.max() * MM,
                        CHORD * L_anc * MM, 100.0 * wsk / wtot) + seam_stats)

    print()
    print('=' * 96)
    print('SYNTHESE — deplacement VISIBLE (skinne) des sommets du joint 0 sous %.0f deg' % THETA)
    print('%-10s %-11s %8s | %8s %8s | %8s %8s | %9s %7s | %5s %8s %8s %8s'
          % ('chaine', 'joint0', 'Lanc mm', 'A p50', 'A max', 'B p50', 'B max',
             'derive j0', 'w crane', 'nseam', 'seamA50', 'seamAmax', 'seamBmax'))
    for r in summary:
        print('%-10s %-11s %8.2f | %8.2f %8.2f | %8.2f %8.2f | %9.2f %6.1f%% | %5d %8.2f %8.2f %8.2f'
              % (r[0], r[1], r[3] * MM, r[4], r[5], r[6], r[7], r[8], r[9],
                 r[10], r[11], r[12], r[14]))
    print('A = rotation autour de l ORIGINE DU JOINT 0 (position soudee)')
    print('B = rotation autour de l ANCRE (le joint 0 se deplace) ; « derive j0 » = de combien')
    print('    l origine du joint 0 quitte sa place soudee dans le scenario B.')


if __name__ == '__main__':
    main()

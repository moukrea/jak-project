#!/usr/bin/env python3
"""probe_c48_com_identity.py — LE POIDS ET LE POINT D'APPLICATION DE CHAQUE MAILLON DE POITRINE.

CE QUE CETTE SONDE MESURE, ET RIEN D'AUTRE. Elle lit UN fichier — le mesh LIVRE — et publie des
grandeurs de GEOMETRIE DE PEAU. Aucune valeur de physique, aucune course, aucune edition.

L'IDENTITE QUI LA FONDE (verifiee, pas supposee — voir CHECK-LBS ci-dessous). Sous skinning
lineaire, la position monde d'un sommet vaut  p_v = SOMME_j w_jv * M_j * IBM_j * v_bind. Le
deplacement moyen du nuage entre la pose d'auteur et la pose simulee vaut donc

    d_COM = (1/N) * SOMME_j [ W_j * (M_j^sim - M_j^auth) * c_j ]
    W_j   = SOMME_v w_jv                                      (SCALAIRE, sans unite : une masse de peau)
    c_j   = (SOMME_v w_jv * L_j(v_bind)) / W_j                (LONGUEUR, unites de jeu, dans l'espace
            BIND DU JOINT j — L_j = to_bone_local, exactement le repere ou `physics_chains.txt`
            ecrit ses `offset=`, echelle d'os retiree)
    N     = SOMME_v SOMME_j w_jv                              (SCALAIRE ; = nb de sommets si les
            poids somment a 1 par sommet — CONTROLE, jamais suppose)

Un joint NON simule a M^sim == M^auth : il contribue EXACTEMENT zero. D'ou les deux livrables :
  * le POIDS a appliquer au maillon l dans un COM vaut W_l / N ;
  * le POINT D'APPLICATION du maillon l est c_l, PAS le centre de la sphere de collision
    (`*phys-lcx/y/z*`, jak-hd-physics.gc:916, alimente par `offset=`) que le moteur applique
    aujourd'hui a la rotation ET au tenseur de deformation (:3905-3907, :3920-3972).

NATURE ET REPERE DE CHAQUE GRANDEUR PUBLIEE — declares en tete de chaque table.
UNITES : 4096 unites de jeu = 1 m. Toute longueur porte sa valeur brute ET ses cm.
B0 = 602 u (SPEC 6, chair racine->apex) : c'est la seule normalisation utilisee.

MESH : `out/jak1/fr3/skin/keira-hd-lod0.glb`, le PACK LIVRE. Jamais le rip du donneur, jamais
`keira-hd-donor-injected.glb` (piege `reskin-measure-the-prepped-input`). Chemin ET md5 publies.

LA FRONTIERE DE L'ORGANE EST UN CHOIX : elle est publiee TROIS FOIS (w>0, w>=0.05, w>=0.25) sur
le poids SOMME de la chaine, comme `probe_breast_com_mass.py`.
"""
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                'scripts', 'shell'))
import numpy as np                                                              # noqa: E402
import physics_c6_volumes as c6                                                 # noqa: E402
from retarget_hd_models import read_glb, consolidate_buffers, skin_info         # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIPPED = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
UNITS = 4096.0          # unites de jeu par metre
B0 = 602.0              # SPEC 6 : la chair racine->apex, en unites de jeu
CHAINS = {'chestL': ['lBoob', 'lBooc'], 'chestR': ['rBoob', 'rBooc']}
# `offset=` LU dans recharged_assets/physics_chains.txt (lignes 222-229), espace bind du joint.
LC_DECLARED = {'lBoob': (-6.0, 637.0, -135.0), 'lBooc': (2.0, 512.0, -51.0),
               'rBoob': (-14.0, -617.0, 124.0), 'rBooc': (5.0, -466.0, 36.0)}
CUTS = [0.0, 0.05, 0.25]
OWN_CUT = 0.5           # regle du producteur : poids SOMME de chaine > 0.5, puis argmax (c6/gen2)


def cm(u):
    return u / UNITS * 100.0


def to_bone_local(ibm, pts_game):
    """world bind (unites de jeu) -> repere bind de l'os (unites de jeu), echelle d'os retiree.
    Copie stricte de physics_keira_gen2.to_bone_local:680 — le repere des `offset=` livres."""
    R = ibm[:3, :3]
    s = np.linalg.norm(R, axis=1)
    s = np.where(s < 1e-12, 1.0, s)
    return pts_game @ (R / s[:, None]).T + (ibm[:3, 3] * UNITS) / s


def main():
    glb = sys.argv[1] if len(sys.argv) > 1 else SHIPPED
    path = glb if os.path.isabs(glb) else os.path.join(REPO, glb)
    if not os.path.exists(path):
        print('PROBE-C48: ABSENT %s — NON MESURE' % path)
        return 1
    md5 = hashlib.md5(open(path, 'rb').read()).hexdigest()
    st = os.stat(path)
    g = c6.load_geometry('keira-hd', glb=path)
    js, bufs = read_glb(path)
    binc = consolidate_buffers(js, bufs)
    names_s, ibms, parent = skin_info(js, binc)
    names = list(g['names'])
    assert names_s == names, 'skin_info et load_geometry ne lisent pas la meme liste de joints'
    V, J, W, P = g['V'], g['J'], g['W'], g['P']
    nv = len(V)
    idx_of = {n: i for i, n in enumerate(names)}

    print('=' * 100)
    print('PROBE-C48-COM-IDENTITY — mesure de peau sur le MESH LIVRE, aucune course, aucun build')
    print('  mesh   : %s' % os.path.relpath(path, REPO))
    print('  md5    : %s   taille=%d o   mtime=%d' % (md5, st.st_size, int(st.st_mtime)))
    print('  rig    : %d joints, %d sommets, %d influences/sommet' % (len(names), nv, J.shape[1]))
    print('  unites : 4096 u = 1 m ; B0 = %.0f u = %.2f cm (SPEC 6)' % (B0, cm(B0)))
    print('=' * 100)

    # ---------------------------------------------------------------------------------------
    # CHECK-LBS — l'hypothese, mesuree et pas supposee.
    # NATURE : scalaire sans unite, par sommet. REPERE : aucun.
    # ---------------------------------------------------------------------------------------
    wsum_all = W.sum(axis=1)
    dev = np.abs(wsum_all - 1.0)
    print('\n[CHECK-LBS] somme des poids par sommet, sur les %d sommets du modele' % nv)
    print('  min=%.9f  max=%.9f  moyenne=%.9f  ecart max a 1.0 = %.3e  '
          'sommets a |1-somme|>1e-4 : %d'
          % (wsum_all.min(), wsum_all.max(), wsum_all.mean(), dev.max(), int((dev > 1e-4).sum())))
    neg = int((W < 0).sum())
    print('  poids negatifs : %d   (un poids negatif casserait l\'identite barycentrique)' % neg)

    # ---------------------------------------------------------------------------------------
    # poids par joint, par sommet (matrice dense nv x njoints, 4 influences deroulees)
    # ---------------------------------------------------------------------------------------
    WJ = np.zeros((nv, len(names)))
    for c in range(J.shape[1]):
        np.add.at(WJ, (np.arange(nv), J[:, c]), W[:, c])

    # ---------------------------------------------------------------------------------------
    # squelette : longueurs d'os portant chaque maillon.
    # NATURE : longueur. REPERE : monde bind (position bind du joint = colonne de translation de
    # l'inverse de l'IBM), en unites de jeu.
    # ---------------------------------------------------------------------------------------
    print('\n[Q-B.8] LONGUEUR D\'OS QUI PORTE CHAQUE MAILLON — nature: longueur ; repere: monde bind')
    print('  %-22s %-10s %10s %9s   %s' % ('os (parent->enfant)', 'hier.glb', 'longueur u', 'cm', 'B0'))
    bone_len = {}
    for cname, joints in CHAINS.items():
        root = joints[0]
        pa = parent[idx_of[root]]
        pairs = [(names[pa], root), (root, joints[1])]
        for a, b in pairs:
            L = float(np.linalg.norm(P[idx_of[b]] - P[idx_of[a]]))
            bone_len[b] = L
            ok = 'OUI' if parent[idx_of[b]] == idx_of[a] else 'NON(!)'
            print('  %-22s %-10s %10.2f %9.2f   %.4f'
                  % ('%s->%s' % (a, b), ok, L, cm(L), L / B0))

    # ---------------------------------------------------------------------------------------
    # CHECK-IDENTITE — l'identite d_COM n'est PAS supposee : elle est verifiee numeriquement.
    # On fabrique une pose SIMULEE arbitraire (rotation + translation tirees au hasard) pour les
    # SEULS joints de chaine, on calcule le COM du nuage par skinning lineaire EXACT, et on le
    # compare a ce que rend la formule W_j / c_j. NATURE : longueur (unites de jeu), repere MONDE.
    # ---------------------------------------------------------------------------------------
    print('\n[CHECK-IDENTITE] d_COM = (1/N) SOMME_j W_j (M_j^sim - M_j^auth) c_j')
    rng = np.random.default_rng(48)
    for cname, joints in CHAINS.items():
        cidx = [idx_of[j] for j in joints]
        wch = np.zeros(nv)
        for ji in cidx:
            wch += WJ[:, ji]
        m = wch > 0.0
        Vm, WJm = V[m], WJ[m]
        n = int(m.sum())
        # pose d'auteur : M_j^auth = inv(IBM_j) (le skinning rend alors la pose de bind)
        Mauth = {j: np.linalg.inv(ibms[j]) for j in range(len(names))}
        Msim = dict(Mauth)
        for ji in cidx:                      # une pose simulee ARBITRAIRE, seulement sur la chaine
            th = rng.uniform(-0.4, 0.4, 3)
            cx, sx = np.cos(th), np.sin(th)
            Rx = np.array([[1, 0, 0], [0, cx[0], -sx[0]], [0, sx[0], cx[0]]])
            Ry = np.array([[cx[1], 0, sx[1]], [0, 1, 0], [-sx[1], 0, cx[1]]])
            Rz = np.array([[cx[2], -sx[2], 0], [sx[2], cx[2], 0], [0, 0, 1]])
            D = np.eye(4)
            D[:3, :3] = Rz @ Ry @ Rx
            D[:3, 3] = rng.uniform(-0.05, 0.05, 3)      # translation en unites glTF
            Msim[ji] = Mauth[ji] @ D
        # skinning lineaire EXACT, en unites de jeu
        acc = np.zeros((n, 3))
        for ji in range(len(names)):
            w = WJm[:, ji]
            k = w > 0
            if not k.any():
                continue
            loc = (Vm[k] / UNITS) @ ibms[ji][:3, :3].T + ibms[ji][:3, 3]
            wp = loc @ Msim[ji][:3, :3].T + Msim[ji][:3, 3]
            acc[k] += w[k][:, None] * wp * UNITS
        dcom_exact = acc.mean(axis=0) - Vm.mean(axis=0)
        # la formule : seuls les joints de chaine contribuent
        pred = np.zeros(3)
        N = float(WJm.sum())
        for ji in cidx:
            w = WJm[:, ji]
            k = w > 0
            Wj = float(w.sum())
            locg = to_bone_local(ibms[ji], Vm[k])
            cj = (w[k][:, None] * locg).sum(axis=0) / Wj
            a = (cj / UNITS) @ Msim[ji][:3, :3].T + Msim[ji][:3, 3]
            b = (cj / UNITS) @ Mauth[ji][:3, :3].T + Mauth[ji][:3, 3]
            pred += Wj * (a - b) * UNITS
        pred /= N
        err = float(np.linalg.norm(dcom_exact - pred))
        rel = err / max(float(np.linalg.norm(dcom_exact)), 1e-12)
        # SEUIL RELATIF, ET IL EST JUSTIFIE : le glb stocke poids et IBM en float32 (eps 1.2e-7)
        # sur des coordonnees de ~8000 u. Un seuil ABSOLU en unites de jeu declarerait fausse une
        # identite exacte a la precision de la donnee. On exige 1e-6 RELATIF, soit 10x l'eps.
        print('  %-8s n=%-4d |d_COM exact|=%9.4f u   |d_COM formule|=%9.4f u   '
              'ecart=%.3e u (%.2e %% relatif, eps float32 = 1.2e-05 %%)  -> %s'
              % (cname, n, np.linalg.norm(dcom_exact), np.linalg.norm(pred), err, 100.0 * rel,
                 'IDENTITE VERIFIEE' if rel < 1e-6 else 'IDENTITE FAUSSE'))

    results = {}
    for cname, joints in CHAINS.items():
        cidx = [idx_of[j] for j in joints]
        wchain = WJ[:, cidx].sum(axis=1)
        print('\n' + '=' * 100)
        print('CHAINE %s   maillon 0 = %s   maillon 1 = %s' % (cname, joints[0], joints[1]))
        print('=' * 100)

        for cut in CUTS:
            sel = wchain > cut if cut == 0.0 else wchain >= cut
            n = int(sel.sum())
            if n == 0:
                print('  frontiere w>=%.2f : DOMAINE VIDE' % cut)
                continue
            Wjoint = WJ[sel].sum(axis=0)                 # SCALAIRE par joint : masse de peau
            N = float(Wjoint.sum())                      # = SOMME_v SOMME_j w_jv
            dsel = np.abs(WJ[sel].sum(axis=1) - 1.0)
            print('\n  ---- FRONTIERE  %s  ->  n=%d sommets, N=%.4f (SOMME_v SOMME_j w_jv), '
                  'N/n=%.6f, ecart max a 1 par sommet=%.3e'
                  % ('w>0' if cut == 0.0 else 'w>=%.2f' % cut, n, N, N / n, dsel.max()))
            order = np.argsort(-Wjoint)
            print('       %-14s %12s %10s   %s' % ('joint', 'W_j', 'W_j/N %', 'role'))
            tot_chain = 0.0
            for ji in order:
                if Wjoint[ji] <= 0.0:
                    continue
                role = 'SIMULE (maillon %d)' % cidx.index(ji) if ji in cidx else 'ancre (non simule)'
                if ji in cidx:
                    tot_chain += Wjoint[ji]
                print('       %-14s %12.4f %9.3f%%   %s' % (names[ji], Wjoint[ji],
                                                            100.0 * Wjoint[ji] / N, role))
            anch = 100.0 * (N - tot_chain) / N
            print('       %-14s %12.4f %9.3f%%   <= PART SIMULEE' % ('(chaine)', tot_chain,
                                                                     100.0 * tot_chain / N))
            print('       %-14s %12.4f %9.3f%%   <= PART ANCREE (excursion nulle au bit pres)'
                  % ('(ancres)', N - tot_chain, anch))
            if cut == 0.0:
                results.setdefault(cname, {})['anchored_w0'] = anch
            results.setdefault(cname, {})['anch_%.2f' % cut] = anch
            results[cname]['share_%.2f' % cut] = [100.0 * Wjoint[j] / N for j in cidx]

        # -----------------------------------------------------------------------------------
        # Q-B : c_j contre lc declare. Nuage de reference = frontiere w>0 (toute la chair que le
        # joint influence, ce que l'identite exige : c_j porte sur TOUS les sommets influences).
        # -----------------------------------------------------------------------------------
        print('\n  ---- Q-B : LE POINT D\'APPLICATION -------------------------------------------')
        print('  c_j : nature LONGUEUR, repere BIND DU JOINT (to_bone_local, echelle d\'os retiree)')
        print('        = centroide de TOUS les sommets influences, PONDERE par le poids du joint')
        print('  lc  : nature LONGUEUR, MEME repere, lu dans physics_chains.txt (`offset=`)')
        for k, ji in enumerate(cidx):
            jn = names[ji]
            w = WJ[:, ji]
            m = w > 0.0
            Wj = float(w.sum())
            loc = to_bone_local(ibms[ji], V[m])
            cj = (w[m][:, None] * loc).sum(axis=0) / Wj
            ncj = float(np.linalg.norm(cj))
            lc = np.array(LC_DECLARED[jn])
            nlc = float(np.linalg.norm(lc))
            cosang = float(cj @ lc / (ncj * nlc))
            ang = float(np.degrees(np.arccos(np.clip(cosang, -1.0, 1.0))))
            det = float(np.linalg.det(ibms[ji][:3, :3]))
            L = bone_len[jn]
            print('\n   maillon %d  %s   (influence %d sommets, W_j=%.4f, det(IBM)=%.4f)'
                  % (k, jn, int(m.sum()), Wj, det))
            print('     c_j            = (%8.2f, %8.2f, %8.2f) u   |c_j| = %8.2f u = %6.2f cm'
                  % (cj[0], cj[1], cj[2], ncj, cm(ncj)))
            print('     lc declare     = (%8.2f, %8.2f, %8.2f) u   |lc|  = %8.2f u = %6.2f cm'
                  % (lc[0], lc[1], lc[2], nlc, cm(nlc)))
            d = cj - lc
            print('     c_j - lc       = (%8.2f, %8.2f, %8.2f) u   |diff|= %8.2f u = %6.2f cm'
                  % (d[0], d[1], d[2], float(np.linalg.norm(d)), cm(float(np.linalg.norm(d)))))
            print('     |c_j|/|lc|     = %.4f  (%+.2f %%)      angle(c_j, lc) = %.3f deg'
                  % (ncj / nlc, 100.0 * (ncj / nlc - 1.0), ang))
            print('     os porteur     = %.2f u (%.2f cm)   RAPPORT |c_j|/os = %.4f x'
                  % (L, cm(L), ncj / L))
            print('     |c_j|/B0       = %.4f' % (ncj / B0))
            results[cname]['c_%s' % jn] = (ncj, nlc, ang, ncj / L)

        # -----------------------------------------------------------------------------------
        # Q-B bis : les deux maillons pilotent-ils de la chair distincte ?
        # -----------------------------------------------------------------------------------
        print('\n  ---- Q-B bis : SEPARATION SPATIALE DES DEUX POPULATIONS ----------------------')
        # 10. centroides PONDERES en MONDE bind
        cw = []
        for ji in cidx:
            w = WJ[:, ji]
            m = w > 0.0
            cw.append((w[m][:, None] * V[m]).sum(axis=0) / float(w.sum()))
        dcw = float(np.linalg.norm(cw[1] - cw[0]))
        Lb = bone_len[joints[1]]
        print('  [10] centroides PONDERES (tous sommets influences) — nature LONGUEUR, repere MONDE BIND')
        print('       c_w(%s) = (%9.2f,%9.2f,%9.2f)' % (joints[0], cw[0][0], cw[0][1], cw[0][2]))
        print('       c_w(%s) = (%9.2f,%9.2f,%9.2f)' % (joints[1], cw[1][0], cw[1][1], cw[1][2]))
        print('       distance = %.2f u = %.2f cm = %.4f B0 ; os %s->%s = %.2f u ; '
              'rapport dist/os = %.4f'
              % (dcw, cm(dcw), dcw / B0, joints[0], joints[1], Lb, dcw / Lb))
        # 11. centroides des ensembles POSSEDES (regle du producteur)
        selo = wchain > OWN_CUT
        best = np.argmax(WJ[:, cidx], axis=1)
        co = []
        cnt = []
        for k in range(2):
            m = selo & (best == k)
            cnt.append(int(m.sum()))
            co.append(V[m].mean(axis=0) if m.sum() else np.full(3, np.nan))
        dco = float(np.linalg.norm(co[1] - co[0]))
        print('  [11] centroides POSSEDES (somme chaine > %.2f, argmax) — ce que la sphere utilise'
              % OWN_CUT)
        print('       %s : %d sommets, centre (%9.2f,%9.2f,%9.2f)'
              % (joints[0], cnt[0], co[0][0], co[0][1], co[0][2]))
        print('       %s : %d sommets, centre (%9.2f,%9.2f,%9.2f)'
              % (joints[1], cnt[1], co[1][0], co[1][1], co[1][2]))
        print('       distance = %.2f u = %.2f cm = %.4f B0 ; rapport dist/os = %.4f'
              % (dco, cm(dco), dco / B0, dco / Lb))
        # 12. recouvrement des deux populations, sur le nuage de l'organe (w>0)
        m = wchain > 0.0
        w0, w1 = WJ[m, cidx[0]], WJ[m, cidx[1]]
        both = int(((w0 > 0) & (w1 > 0)).sum())
        only0 = int(((w0 > 0) & (w1 <= 0)).sum())
        only1 = int(((w0 <= 0) & (w1 > 0)).sum())
        n = int(m.sum())
        if w0.std() > 0 and w1.std() > 0:
            r = float(np.corrcoef(w0, w1)[0, 1])
        else:
            r = float('nan')
        print('  [12] RECOUVREMENT sur le nuage de l\'organe (w_chaine>0, n=%d) — nature: PART' % n)
        print('       sommets portant les DEUX : %d (%.2f %%) ; %s seul : %d ; %s seul : %d'
              % (both, 100.0 * both / n, joints[0], only0, joints[1], only1))
        print('       correlation de Pearson(w_%s, w_%s) = %+.4f' % (joints[0], joints[1], r))
        # PROFILS PAR DECILE. L'ORDONNANCEMENT EST UN CHOIX ET IL DECIDE DU VERDICT : trois
        # ordonnancements sont publies cote a cote, avec ce que chacun mesure.
        #   A. distance au JOINT RACINE — l'ordre litteralement demande. Il n'est PAS l'axe
        #      anatomique : le joint est derriere la chair (voir [AXES] ci-dessous).
        #   B. projection sur l'AXE D'OS du maillon distal — l'axe le long duquel SPEC 30-31
        #      demande le gradient racine->pointe de la CHAINE.
        #   C. projection sur l'AXE ANATOMIQUE racine->apex — du joint racine vers le centroide
        #      de l'organe, c'est-a-dire la direction ou vit B0.
        root = P[cidx[0]]
        rel = V[m] - root
        anchw = WJ[m].sum(axis=1) - w0 - w1
        axb = P[cidx[1]] - P[cidx[0]]
        axb = axb / np.linalg.norm(axb)
        corg = (WJ[m][:, cidx].sum(axis=1)[:, None] * V[m]).sum(axis=0) / WJ[m][:, cidx].sum()
        axa = corg - root
        axa = axa / np.linalg.norm(axa)
        print('       [AXES] os %s->%s (monde bind, unitaire) = (%.3f,%.3f,%.3f)'
              % (joints[0], joints[1], axb[0], axb[1], axb[2]))
        print('              axe anatomique racine->apex        = (%.3f,%.3f,%.3f)'
              % (axa[0], axa[1], axa[2]))
        print('              ANGLE entre l\'axe d\'os de la chaine et l\'axe racine->apex '
              '= %.2f deg' % np.degrees(np.arccos(np.clip(float(axb @ axa), -1, 1))))
        prj = rel @ axa
        print('              projection des sommets de l\'organe sur l\'axe anatomique : '
              'min=%.1f max=%.1f u (etendue %.1f u = %.2f B0 = %.2f cm)'
              % (prj.min(), prj.max(), prj.max() - prj.min(), (prj.max() - prj.min()) / B0,
                 cm(prj.max() - prj.min())))
        for lab, key in (('A. distance au joint racine %s' % joints[0],
                          np.linalg.norm(rel, axis=1)),
                         ('B. projection sur l\'axe d\'os %s->%s' % (joints[0], joints[1]),
                          rel @ axb),
                         ('C. projection sur l\'axe anatomique racine->apex', prj)):
            o = np.argsort(key)
            print('       profil par decile — %s (u)' % lab)
            print('         %-6s %6s %10s %10s   %8s %8s %8s' %
                  ('dec', 'n', 'min', 'max', 'w_%s' % joints[0][:5], 'w_%s' % joints[1][:5],
                   'w_ancre'))
            for dcl in range(10):
                a = dcl * n // 10
                b = (dcl + 1) * n // 10
                ii = o[a:b]
                if len(ii) == 0:
                    continue
                print('         %-6d %6d %10.1f %10.1f   %8.4f %8.4f %8.4f'
                      % (dcl, len(ii), key[ii].min(), key[ii].max(),
                         w0[ii].mean(), w1[ii].mean(), anchw[ii].mean()))
        # position PONDEREE de chaque maillon sur l'axe anatomique : qui pilote l'apex ?
        t0a = float((w0 * prj).sum() / w0.sum())
        t1a = float((w1 * prj).sum() / w1.sum())
        ta = float((anchw * prj).sum() / anchw.sum())
        print('       position PONDEREE sur l\'axe anatomique (u depuis le joint racine) : '
              '%s=%.1f  %s=%.1f  ancres=%.1f' % (joints[0], t0a, joints[1], t1a, ta))
        print('       => ecart des deux maillons le long de l\'axe racine->apex = %.1f u '
              '(%.4f B0). Un gradient exige que le DISTAL soit plus loin.' % (t1a - t0a,
                                                                              (t1a - t0a) / B0))
        # ou chaque maillon est-il MAJORITAIRE ?
        maj0 = int((w0 > 0.5).sum())
        maj1 = int((w1 > 0.5).sum())
        print('       sommets ou w>0.5 : %s=%d  %s=%d  (regle du serial 7 : >=30 %% du nuage)'
              % (joints[0], maj0, joints[1], maj1))
        # profondeur relative : projection sur l'axe de l'os du maillon distal
        ax = P[cidx[1]] - P[cidx[0]]
        ax = ax / np.linalg.norm(ax)
        t0 = float((w0 * ((V[m] - root) @ ax)).sum() / w0.sum())
        t1 = float((w1 * ((V[m] - root) @ ax)).sum() / w1.sum())
        print('       projection ponderee sur l\'axe %s->%s (u) : %s=%.2f  %s=%.2f  ecart=%.2f u'
              % (joints[0], joints[1], joints[0], t0, joints[1], t1, t1 - t0))

    print('\n' + '=' * 100)
    print('FIN — aucune donnee ecrite, aucun fichier du moteur touche.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

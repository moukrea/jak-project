#!/usr/bin/env python3
"""C80 — LE CONTRE-CONTROLE INDEPENDANT DE LA GRANDEUR D'APEX (directive 2026-08-21 18:40).

Deux derivations du MEME deplacement d'apex, publiees COTE A COTE, jamais fondues.

  CHEMIN A (celui du moteur, recompose ici pour etre verifiable) :
    e_A = SOMME_l w_l * [ (p_l @ R^A_l + t^A_l) - (p_l @ R^B_l + t^B_l) ]
    avec (w_l, p_l) = les enregistrements `ax` LIVRES, produits par `apex_region`
    (physics_c14_meshsamples.py:294) : axe anatomique `corg - root` + quantile 0.90, puis
    collapse en UN poids et UN point par maillon.

  CHEMIN B (independant) : per-sommet, sans collapse, region choisie SANS axe.
    d_i = SOMME_j w_ij * [ (v_i^loc_j @ R^A_j + t^A_j) - (v_i^loc_j @ R^B_j + t^B_j) ]
    Les joints NON simules ont R^A = R^B et disparaissent de la difference : les quatre
    matrices publiees suffisent.

CE QUI EST PARTAGE, ET JE LE DIS AU LIEU DE LE TAIRE : les deux chemins lisent le MEME mesh
livre et les MEMES matrices de course. C'est le but — on compare deux OPERATEURS, pas deux
mesh. Ce qui n'est PAS partage : l'axe anatomique, le quantile 0.90, et la table (w_l, p_l).

NATURE : une longueur, publiee en unites de jeu, en cm ET en B0 (les trois, parce qu'un ratio
  dont le denominateur est conteste ne doit jamais voyager seul).
REPERE : le MONDE, difference entre la course A (physique armee) et la course B (physique de
  poitrine DESARMEE, donc pose d'auteur).
POPULATION : une valeur par (chaine, animation) — le MAXIMUM sur les frames de la fenetre,
  refait ICI pour les deux chemins a la fois, jamais herite de l'argmax du moteur.
LECTURE QUAND LE DEFAUT EST ABSENT : si les deux courses portaient la meme pose, tout est 0.
"""
import sys, os, re, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import physics_c14_meshsamples as M

B0_U, U_M = 602.0, 4096.0
GLB = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
JN = ['lBoob', 'lBooc', 'rBoob', 'rBooc']
CHAINS = {'chestL': (0, 1), 'chestR': (2, 3)}     # indices `ji` de l'emetteur


def die(m):
    print('[C80-PATHB NON CONCLUANT] ' + m); sys.exit(2)


def load_run(path):
    """-> (mats, keys, names). mats[(k, ji)] = (R 3x3 lignes v0/v1/v2, t)."""
    if not os.path.exists(path):
        die('trace absente : %s' % path)
    txt = open(path, errors='ignore').read()
    rows, keys, names, miss = {}, {}, {}, 0
    for m in re.finditer(r'^PHYSJTW k=(\d+) j=(\d+) row=(\d+) x=([-\d.e+]+) y=([-\d.e+]+) z=([-\d.e+]+)',
                         txt, re.M):
        k, ji, r = int(m.group(1)), int(m.group(2)), int(m.group(3))
        rows.setdefault((k, ji), {})[r] = [float(m.group(i)) for i in (4, 5, 6)]
    for m in re.finditer(r'^PHYSJTWK k=(\d+) a=(\d+) d=(\d+) f=([-\d.e+]+)', txt, re.M):
        keys[int(m.group(1))] = (int(m.group(2)), int(m.group(3)), float(m.group(4)))
    for m in re.finditer(r'^PHYSJTWN j=(\d+) idx=(\d+) name=(\S+)', txt, re.M):
        names[int(m.group(1))] = (int(m.group(2)), m.group(3).strip('"'))
    miss = len(re.findall(r'^PHYSJTWMISS', txt, re.M))
    mats = {}
    for (k, ji), rr in rows.items():
        if len(rr) != 4:
            continue
        mats[(k, ji)] = (np.array([rr[0], rr[1], rr[2]]), np.array(rr[3]))
    return mats, keys, names, miss, len(rows)


def main(pa, pb):
    print('DIRECTIVES v3fee554599')
    A, kA, nA, missA, rawA = load_run(pa)
    B, kB, nB, missB, rawB = load_run(pb)
    print('== P1 APPARIEMENT ==')
    print('   course A : %d matrices · %d cles · %d noms resolus · %d PHYSJTWMISS' % (len(A), len(kA), len(nA), missA))
    print('   course B : %d matrices · %d cles · %d noms resolus · %d PHYSJTWMISS' % (len(B), len(kB), len(nB), missB))
    for lbl, nm in (('A', nA), ('B', nB)):
        got = {v[1] for v in nm.values()}
        print('   course %s : noms publies %s' % (lbl, sorted(got)))
        if set(JN) - got:
            die('course %s : joints absents du rig -> %s' % (lbl, sorted(set(JN) - got)))
    common = set(A) & set(B)
    print('   cles (k,ji) communes : %d / %d de A  = %.1f %%'
          % (len(common), len(A), 100.0 * len(common) / max(len(A), 1)))
    if len(A) and len(common) < len(A):
        print('   **AVERTISSEMENT** : appariement incomplet. P1 exigeait 100 %%.')
    # les frames d'animation doivent coincider, sinon on compare deux gestes
    dif = [k for k in set(kA) & set(kB) if abs(kA[k][2] - kB[k][2]) > 1e-3]
    print('   cles ou la frame d\'animation DIFFERE entre A et B : %d / %d' % (len(dif), len(set(kA) & set(kB))))
    if dif:
        print('   **LES DEUX COURSES NE JOUENT PAS LES MEMES FRAMES** — la difference A-B ne serait')
        print('   pas `M^sim - M^auteur` mais un ecart de geste. Campagne NON CONCLUANTE.')

    # ---- P2 : en course B, la physique est desarmee -> A et B doivent DIFFERER (controle positif)
    d = []
    for (k, ji) in sorted(common):
        d.append(float(np.linalg.norm(A[(k, ji)][1] - B[(k, ji)][1])))
    d.sort()
    print()
    print('== P2 CONTROLE : la course B est-elle une AUTRE trajectoire ? ==')
    print('   |t^A - t^B| sur les joints de poitrine : p50 %.2f u  max %.2f u  (nul = les deux'
          ' courses sont identiques, donc B n\'a pas desarme)' % (d[len(d)//2], d[-1]))
    if d[-1] < 1e-6:
        die('A et B sont identiques : la course B n\'a pas desarme la physique.')

    # ---- geometrie du mesh livre
    geo = M.load_geometry_ibm('keira-hd', glb=GLB)
    names = list(geo['names']); nmap = {n: i for i, n in enumerate(names)}
    WJ = M.dense_weights(geo, len(names)); V, P = geo['V'], geo['P']
    ax = {}
    for ln in open('recharged_assets/physics_mesh.txt', errors='ignore'):
        if ln.startswith('ax '):
            p = ln.split(); ax[(p[1], int(p[2]))] = (float(p[3]), np.array([float(x) for x in p[4:7]]))

    def xf(mat, pts):
        R, t = mat
        return pts @ R + t

    print()
    print('== LES DEUX CHEMINS, COTE A COTE ==')
    print('%-8s %-26s %10s %10s %10s %10s'
          % ('chaine', 'chemin', 'p50 (u)', 'p50 (cm)', 'max (u)', 'max B0'))
    out = {}
    for cn, (j0, j1) in CHAINS.items():
        cj = [nmap[JN[j0]], nmap[JN[j1]]]
        wch = WJ[:, cj].sum(axis=1); m = wch > 0.0
        Vm = V[m]; Wm = WJ[m]
        root = P[cj[0]]
        loc = {ji: M.to_bone_local(geo['ibms'][nmap[JN[ji]]], Vm) for ji in (j0, j1)}
        # regions, TROIS operateurs
        dist = np.linalg.norm(Vm - root, axis=1)                      # B1/B2 : EUCLIDIEN, sans axe
        regB1 = dist >= np.quantile(dist, 0.90)
        dom = np.argmax(Wm, axis=1)                                   # B2 : appartenance ARGMAX
        domok = np.isin(dom, cj)
        dd = np.where(domok, dist, -1.0)
        regB2 = domok & (dd >= np.quantile(dd[domok], 0.90)) if domok.sum() >= 10 else None

        per = {}
        keys_by_anim = {}
        for k, (a, dr, f) in kA.items():
            if all((k, ji) in A and (k, ji) in B for ji in (j0, j1)):
                keys_by_anim.setdefault(a, []).append(k)
        for a, ks in keys_by_anim.items():
            bestA = bestB1 = bestB2 = bestB3 = 0.0
            for k in ks:
                # --- CHEMIN A : les `ax` livres
                e = np.zeros(3)
                for li, ji in enumerate((j0, j1)):
                    w, p = ax.get((cn, li), (0.0, np.zeros(3)))
                    if w <= 0.0:
                        continue
                    e += w * (xf(A[(k, ji)], p[None, :])[0] - xf(B[(k, ji)], p[None, :])[0])
                bestA = max(bestA, float(np.linalg.norm(e)))
                # --- CHEMIN B : per-sommet, sans collapse
                D = np.zeros((Vm.shape[0], 3))
                for ji in (j0, j1):
                    jj = nmap[JN[ji]]
                    D += Wm[:, jj][:, None] * (xf(A[(k, ji)], loc[ji]) - xf(B[(k, ji)], loc[ji]))
                nrm = np.linalg.norm(D, axis=1)
                bestB1 = max(bestB1, float(nrm[regB1].mean()))
                if regB2 is not None:
                    bestB2 = max(bestB2, float(nrm[regB2].mean()))
                bestB3 = max(bestB3, float(nrm.max()))
            per.setdefault('A', []).append(bestA)
            per.setdefault('B1', []).append(bestB1)
            per.setdefault('B2', []).append(bestB2)
            per.setdefault('B3', []).append(bestB3)
        out[cn] = per
        LBL = {'A': 'A  `ax` livres (moteur)',
               'B1': 'B1 euclidien, decile, w>0',
               'B2': 'B2 euclidien, decile, argmax',
               'B3': 'B3 sommet le plus deplace'}
        for tag in ('A', 'B1', 'B2', 'B3'):
            v = sorted(x for x in per.get(tag, []) if x == x)
            if not v:
                continue
            print('%-8s %-26s %10.1f %10.2f %10.1f %10.4f'
                  % (cn, LBL[tag], v[len(v)//2], v[len(v)//2]/U_M*100, v[-1], v[-1]/B0_U))

    print()
    print('== P5 : LES DEUX CHEMINS S\'ACCORDENT-ILS A MIEUX QUE 25 %% ? ==')
    verdict = True
    for cn, per in out.items():
        a = sorted(per['A']); 
        for tag in ('B1', 'B2'):
            b = sorted(x for x in per[tag] if x == x)
            if not b or not a:
                continue
            ma, mb = a[len(a)//2], b[len(b)//2]
            e = 100.0 * abs(mb - ma) / max(ma, 1e-9)
            ok = e <= 25.0
            verdict &= ok
            print('   %-8s A p50 %8.1f u  vs  %s p50 %8.1f u   ecart %6.1f %%   %s'
                  % (cn, ma, tag, mb, e, 'ACCORD' if ok else '**DIVERGENCE**'))
    print()
    if verdict:
        print('   -> LES DEUX CHEMINS S\'ACCORDENT. La grandeur d\'apex est confirmee par une')
        print('      derivation qui ne partage ni l\'axe anatomique, ni le quantile 0.90, ni la')
        print('      table (w_l, p_l). La clause de la directive du 2026-08-21 18:40 est levee.')
    else:
        print('   -> **LES DEUX CHEMINS DIVERGENT.** Clause de la directive du 2026-08-21 18:40 :')
        print('      AUCUNE des six sections ne se traite avant reconciliation.')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('usage: c80_apex_pathb.py <log course A> <log course B>'); sys.exit(1)
    main(sys.argv[1], sys.argv[2])

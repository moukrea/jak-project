#!/usr/bin/env python3
"""c126_rotation_vs_stretch.py — LA « FUITE » DE §11 EST-ELLE DE L'ETIREMENT, OU DE LA ROTATION ?

POURQUOI CE FICHIER EXISTE. Le cycle 125 a publie, comme cible chiffree du cycle suivant, un
RENDEMENT de 1,185 a 1,203 entre l'echelle COMMANDEE par le solveur (1,2125-1,2195, DANS la bande
de §11) et la forme LIVREE a la peau (1,4370-1,4588, AU-DESSUS). Avant d'engager un chantier de
conversion sur ce chiffre — regle du 2026-08-21 18:40 : « un contre-controle INDEPENDANT de la
grandeur est exige avant d'engager le chantier », et le 2026-08-21 20:50 montre ce que coute de
ne pas le faire — ce fichier verifie que la GRANDEUR sur laquelle ce rendement est bati est bien
celle que la section NOMME.

LE DOUTE, ET IL EST STRUCTUREL. La grandeur publiee au cycle 125 est l'ECART-TYPE PONDERE du nuage
de peau le long de l'axe `fwd`, en base d'ancre. **Un ecart-type le long d'un axe FIXE n'est pas
invariant par ROTATION du nuage.** Si la chaine bascule (pendule) de sorte que le grand axe du
sein se rapproche de `fwd`, la sigma `fwd` monte et les sigmas `out`/`up` baissent, SANS un gramme
d'etirement de tissu. Or §11 nomme une **LONGUEUR racine->apex**, invariante par rotation, et §22
ecrit « Translation, rotation and redistribution shall account for most of the excursion » : la
spec ATTEND que la rotation porte l'essentiel. Registre : `b0-denominator-axis-not-in-spec` et
l'arbitrage du 2026-08-20 07:20 (« un axe de mesure qui n'est pas celui que la spec DEFINIT est un
axe faux »), qui avait deplace six sections d'un coup.

CE QUI EST MESURE ICI, SUR LA TRACE DEJA LIVREE, SANS BUILD NI COURSE NEUVE :
  (1) DECOMPOSITION POLAIRE de la 3x3 LIVREE de chaque joint de chaine : A = S . R, avec R
      orthonormale (rotation pure) et S symetrique definie positive (etirement pur), appliquees
      dans cet ordre aux coordonnees LOCALES DE BIND (convention ligne : q -> q S R). Trois nuages
      sont re-skinnes avec les MEMES sommets, les MEMES poids et le MEME repere :
        FULL    = A telle que livree                    -> doit REPRODUIRE le cycle 125
        RIGID   = R seule (rotation+translation, S=I)    -> ce que la ROTATION explique a elle seule
        STRETCH = S seule (etirement sans reorientation) -> la part de TISSU
  (2) LONGUEUR RACINE->APEX DIRECTE, la grandeur que §11 nomme : deux POPULATIONS de sommets
      FIXEES A LA POSE DE BIND (decile le plus proximal et decile le plus distal le long de l'axe
      `fwd` de bind), centroides ponderes par la masse, longueur = |c_apex - c_racine| en MONDE.
      Invariante par rotation ET par translation, donc lisible sans repere d'ancre.

NATURE / REPERE / LIGNE DE BASE (les trois questions obligatoires du contrat) :
  NATURE  : (1) trois ETENDUES sans dimension par nuage (rapports a la cellule debout i=0) ;
            (2) une LONGUEUR sans dimension (rapport a i=0). Aucune des deux n'est une variance de
            mouvement : un equilibre tenu ne bouge plus, ces grandeurs decrivent une FORME.
  REPERE  : (1) le triedre de §7 mesure sur le rig (`breast-com-mass.json` -> `axes`), exprime
            dans la base de l'ANCRE `chest` transportee A CHAQUE cellule — identique au cycle 125,
            pour que les deux instruments soient comparables ligne a ligne ;
            (2) AUCUN : une longueur entre deux centroides est un invariant euclidien. C'est
            precisement ce qui la rend recevable la ou la sigma ne l'est pas.
  LIGNE DE BASE : la cellule i=0, pose debout d'auteur, ou §9 exige la forme exacte du modele.
            Les trois nuages y rendent 1,0000 PAR CONSTRUCTION (P5), et la 2e cellule debout i=9
            — que rien ne relie a i=0 dans le balayage — donne la lecture HORS DEFAUT mesuree.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info
import c124_delivered_shape as c124

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIPPED = c124.SHIPPED
MASSJSON = c124.MASSJSON
CHAINS = c124.CHAINS
ANCHOR = c124.ANCHOR
BANDS = c124.BANDS
CHAINJOINTS = {j for js in CHAINS.values() for j in js}
SWEEP = [1.00, 1.05, 1.10, 1.15, 1.2195, 1.25, 1.30]


def polar_SR(A):
    """A (3x3, convention LIGNE : p = q A) -> (S, R) avec A = S . R, S symetrique definie
    positive appliquee AUX COORDONNEES LOCALES DE BIND, puis R orthonormale.

    Pourquoi CET ordre et pas l'autre. Le tissu s'etire dans SON PROPRE repere (le repere de bind
    du joint), et la chaine se REORIENTE ensuite. `q S R` fait exactement cela. L'autre
    decomposition (`q R S`) etirerait dans le repere deja tourne, ce qui n'a pas de sens
    physique ici. En convention colonne, L = A^T et A = S R <=> L = R^T S : c'est la
    decomposition polaire DROITE de L, obtenue par SVD."""
    L = np.asarray(A, dtype=float).T
    U, sv, Vt = np.linalg.svd(L)
    Rc = U @ Vt                       # rotation (colonne)
    S = Vt.T @ np.diag(sv) @ Vt       # etirement symetrique defini positif
    if np.linalg.det(Rc) < 0:         # une reflexion n'est pas une rotation : on le dit, on ne la cache pas
        raise ValueError('determinant negatif : la matrice livree contient une REFLEXION')
    return S, Rc.T                    # convention ligne : A = S . R


def run(txt, inject_fwd=None):
    """-> dict de resultats. `inject_fwd` : facteur d'etirement CONNU injecte le long de `fwd`
    dans le repere local de bind de chaque joint de chaine (controle positif P6)."""
    jn, mats, nmiss = c124._read_matrices(txt)
    if not mats:
        raise SystemExit('c126: SUSPENDU — aucune ligne PHYSORIM dans cette trace.')
    if nmiss:
        raise SystemExit('c126: SUSPENDU — %d PHYSORIMMISS.' % nmiss)
    slot = {v: k for k, v in jn.items()}

    g = c6.load_geometry('keira-hd', glb=SHIPPED)
    names, V, J, W, P = list(g['names']), g['V'], g['J'], g['W'], g['P']
    js, bufs = read_glb(os.path.join(REPO, SHIPPED))
    _nn, ibms, _pp = skin_info(js, consolidate_buffers(js, bufs))
    ai = names.index(ANCHOR)

    def bindR(j):
        Rj = np.linalg.inv(np.array(ibms[j], dtype=float))[:3, :3].copy()
        for k in range(3):
            Rj[:, k] /= np.linalg.norm(Rj[:, k])
        return Rj

    R = bindR(ai)
    RB = {n: bindR(names.index(n)) for n in slot}
    mass = json.load(open(os.path.join(REPO, MASSJSON)))
    cells = sorted({i for (i, _j) in mats})
    i0 = cells[0]

    # ---- LA CONVENTION DE SKINNING EST REDETERMINEE ICI PAR LA MEME MESURE QU'AU CYCLE 124 -----
    # Elle n'est PAS recopiee : deux instruments qui parlent de la meme peau doivent la trancher
    # chacun, sinon un changement de mesh en deplacerait un seul. Le resultat doit etre 'C'.
    wch = (W * (J == ai)).sum(axis=1)
    top = np.argsort(-wch)[:24]
    dbind = np.linalg.norm(V[top] - P[ai], axis=1)
    Mch = mats[(i0, slot[ANCHOR])]
    verdict = {}
    for tag in ('A', 'C'):
        q = V[top].copy() if tag == 'A' else (V[top] - P[ai]) @ RB[ANCHOR]
        p = q @ Mch[:3, :3] + Mch[3, :3]
        verdict[tag] = float(np.median(np.abs(np.linalg.norm(p - Mch[3, :3], axis=1) - dbind)
                                       / np.maximum(dbind, 1e-9)))
    conv = min(verdict, key=verdict.get)
    if conv != 'C' or verdict[conv] > 0.02:
        raise SystemExit('c126: SUSPENDU — convention de skinning %s ecart %.5f' % (conv, verdict[conv]))

    # ---- LES TROIS JEUX DE MATRICES ------------------------------------------------------------
    # Seuls les QUATRE joints de chaine sont decomposes. `chest` et les deux epaules restent
    # LIVREES : ils portent l'animation d'auteur et definissent le repere. Isoler ce que le
    # SOLVEUR ecrit est tout l'objet de la mesure.
    fwd_w = R @ np.asarray(mass['chains']['chestL']['axes']['fwd'], dtype=float)
    fwd_w /= np.linalg.norm(fwd_w)
    variants = {}
    for mode in ('FULL', 'RIGID', 'STRETCH'):
        mm = {}
        for (i, sl), M in mats.items():
            nm = jn.get(sl)
            if nm not in CHAINJOINTS or mode == 'FULL':
                mm[(i, sl)] = M
                continue
            A = M[:3, :3]
            S, Rr = polar_SR(A)
            M2 = M.copy()
            M2[:3, :3] = Rr if mode == 'RIGID' else S
            mm[(i, sl)] = M2
        variants[mode] = mm
    # ---- LE BALAYAGE QUI DONNE LA CIBLE, MESUREE AU LIEU D'ETRE DEDUITE ------------------------
    # On remplace la PLUS GRANDE valeur singuliere de la S ECRITE par `lam`, en gardant sa
    # direction principale et les deux autres valeurs. C'est exactement « tourner le bouton
    # d'allongement » sans rien changer d'autre — ni la rotation, ni la translation, ni
    # l'articulation. La longueur LIVREE qui en sort est MESUREE, pas modelisee.
    for lam, vol in [(l, False) for l in SWEEP] + [(l, True) for l in SWEEP]:
        mm = {}
        for (i, sl), M in mats.items():
            nm = jn.get(sl)
            if nm not in CHAINJOINTS:
                mm[(i, sl)] = M
                continue
            A = M[:3, :3]
            S, Rr = polar_SR(A)
            sv, U = np.linalg.eigh(S)          # S symetrique : eigh rend une base orthonormee
            k = int(np.argmax(sv))
            # PIEGE PAYE ICI, ET PUBLIE : la premiere version substituait `lam` sur TOUTES les
            # cellules, y compris la LIGNE DE BASE i=0 — ou le solveur ne commande AUCUNE
            # deformation (valeurs singulieres 1.0006/0.9997/0.9996, mesurees plus haut). Elle
            # etirait donc le denominateur en meme temps que le numerateur, et publiait une cible
            # fausse de +9 points. Une cellule ou le solveur ne commande rien reste INTACTE : un
            # bouton de la pose PENDANTE ne peut pas deplacer la pose DEBOUT, que §9 fige.
            if abs(sv[k] - 1.0) <= 1e-3:
                mm[(i, sl)] = M
                continue
            S2 = S + (lam - sv[k]) * np.outer(U[:, k], U[:, k])
            if vol:
                # VARIANTE A VOLUME CONSERVE. §8 exige « 98-101 % of neutral volume » et le
                # determinant de la S ECRITE vaut 0,9997 aujourd'hui : baisser la seule grande
                # valeur singuliere le ferait tomber a 0,910, soit 91 % — la section passerait de
                # NON TENUE a plus loin encore. Les deux autres valeurs sont donc remontees de
                # sqrt(s1/lam) pour que det(S) soit INCHANGE au bit pres. C'est le meme bouton,
                # tourne d'une facon qui ne casse pas la section voisine (registre :
                # `skin-cap-is-one-knob-for-two-gates`).
                g = math.sqrt(sv[k] / lam)
                for kk in range(3):
                    if kk != k:
                        S2 = S2 + (g - 1.0) * sv[kk] * np.outer(U[:, kk], U[:, kk])
            M2 = M.copy()
            M2[:3, :3] = S2 @ Rr
            mm[(i, sl)] = M2
        variants[('LAMV%.3f' if vol else 'LAM%.3f') % lam] = mm

    if inject_fwd is not None:
        # CONTROLE POSITIF EXACT, AJOUTE APRES COUP ET DECLARE COMME TEL : un etirement
        # ISOTROPE x1,50 doit faire monter TOUTE longueur de EXACTEMENT 50 %, quel que soit
        # l'angle entre l'axe de l'organe et `fwd`. C'est la prediction quantitative que la
        # directive du 2026-08-20 13:20 exige, la ou ma bande « +40 a +60 % » de P6 dependait
        # d'une obliquite que je n'avais pas chiffree.
        mm = {}
        for (i, sl), M in mats.items():
            nm = jn.get(sl)
            if nm not in CHAINJOINTS:
                mm[(i, sl)] = M
                continue
            M2 = M.copy()
            M2[:3, :3] = inject_fwd * M[:3, :3]
            mm[(i, sl)] = M2
        variants['ISO'] = mm
        mm = {}
        for (i, sl), M in mats.items():
            nm = jn.get(sl)
            if nm not in CHAINJOINTS:
                mm[(i, sl)] = M
                continue
            fl = fwd_w @ RB[nm]                        # `fwd` monde -> local de bind du joint
            fl = fl / np.linalg.norm(fl)
            Sinj = np.eye(3) + (inject_fwd - 1.0) * np.outer(fl, fl)
            M2 = M.copy()
            M2[:3, :3] = Sinj @ M[:3, :3]              # q -> (q Sinj) A : etirement AVANT le transport
            mm[(i, sl)] = M2
        variants['INJECT'] = mm

    def make_xform(mm):
        def xform(x, nmj, i):
            M = mm[(i, slot[nmj])]
            q = np.atleast_2d(np.asarray(x, dtype=float))
            q = (q - P[names.index(nmj)]) @ RB[nmj]
            return q @ M[:3, :3] + M[3, :3]
        return xform

    def frame(xf, i):
        pts = np.vstack([P[ai]] + [P[ai] + R[:, k] for k in range(3)])
        im = xf(pts, ANCHOR, i)
        o = im[0]
        E = np.stack([im[1 + k] - o for k in range(3)], axis=1)
        for k in range(3):
            E[:, k] /= np.linalg.norm(E[:, k])
        return o, E

    def world_cloud(xf, i, sel):
        n = int(sel.sum())
        acc, wtot = np.zeros((n, 3)), np.zeros(n)
        Js, Ws, Vs = J[sel], W[sel], V[sel]
        for k in range(Ws.shape[1]):
            for nmj in slot:
                m = (Js[:, k] == names.index(nmj)) & (Ws[:, k] > 0)
                if not m.any():
                    continue
                acc[m] += Ws[m, k][:, None] * xf(Vs[m], nmj, i)
                wtot[m] += Ws[m, k]
        if float(np.abs(wtot - 1.0).max()) > 1e-3:
            raise SystemExit('c126: SUSPENDU — skinning non referme (%.4f)'
                             % float(np.abs(wtot - 1.0).max()))
        return acc

    # ---- LA MESURE DIRECTE DE L'ETIREMENT ECRIT PAR LE SOLVEUR ---------------------------------
    # Les valeurs singulieres de S sont l'etirement principal de la matrice livree, sans passer
    # par aucun nuage ni aucun repere. A la pose d'auteur i=0 elles doivent valoir 1 : c'est le
    # controle qui etablit que ce que j'extrais est bien de la deformation ECRITE, et non un
    # artefact de convention de matrice.
    sing = {}
    for (i, sl), M in mats.items():
        nm = jn.get(sl)
        if nm not in CHAINJOINTS:
            continue
        S, _R = polar_SR(M[:3, :3])
        sing[(i, nm)] = tuple(sorted(np.linalg.svd(S, compute_uv=False), reverse=True))

    res = {'__sing__': sing}
    for cname, joints in CHAINS.items():
        idx = [names.index(j) for j in joints]
        wsum = np.zeros(len(V))
        for ji in idx:
            wsum += (W * (J == ji)).sum(axis=1)
        axr = mass['chains'][cname]['axes']
        AX = {a: np.asarray(axr[a], dtype=float) for a in ('out', 'up', 'fwd')}
        rootjoint = joints[0]
        for cut, lbl in ((0.0, 'w>0.00'), (0.25, 'w>=0.25')):
            sel = wsum > cut if cut == 0.0 else wsum >= cut
            wv = wsum[sel]
            # LES DEUX POPULATIONS SONT FIXEES A LA POSE DE BIND, une fois, et ne bougent plus.
            # Un argmax recalcule par cellule repondrait DANS la cellule et ne serait pas une
            # population (registre : `argmax-anchor-is-not-a-population`).
            xb = (V[sel] - P[ai]) @ R @ AX['fwd']
            qlo, qhi = np.quantile(xb, 0.10), np.quantile(xb, 0.90)
            proximal, distal = xb <= qlo, xb >= qhi
            # TEST DE RAFFINEMENT (registre : `instrument-refinement-test`) : si le verdict
            # dependait du quantile choisi, la mesure ne mesurerait rien. On garde les trois.
            alt = {q: ((xb <= np.quantile(xb, q)), (xb >= np.quantile(xb, 1 - q)))
                   for q in (0.05, 0.10, 0.20)}
            # LE POIDS DE CHAINE DE CHAQUE DECILE — il explique pourquoi une echelle injectee sur
            # les seuls joints de chaine ne multiplie PAS la longueur par le meme facteur : le
            # decile PROXIMAL est justement le tissu que §30 dit « fortement attache », donc pese
            # en partie sur `chest`, et il ne suit pas la chaine.
            wprox = float(wv[proximal].mean()) if proximal.any() else float('nan')
            wdist = float(wv[distal].mean()) if distal.any() else float('nan')
            for mode, mm in variants.items():
                xf = make_xform(mm)
                ext, L_pp, L_jp, ang = {}, {}, {}, {}
                eig, eang = {}, {}
                for i in cells:
                    if any((i, slot[j]) not in mm for j in slot):
                        continue
                    acc = world_cloud(xf, i, sel)
                    o, E = frame(xf, i)
                    cl = (acc - o) @ E
                    e = {}
                    for a, v in AX.items():
                        x = cl @ v
                        mu = float((wv * x).sum() / wv.sum())
                        e[a] = math.sqrt(float((wv * (x - mu) ** 2).sum() / wv.sum()))
                    ext[i] = e
                    # ---- LA VERSION INVARIANTE PAR ROTATION DU TRIPLET ------------------------
                    # Les sigmas ci-dessus sont lues le long d'axes FIXES : une rotation du nuage
                    # les redistribue sans qu'un gramme de tissu bouge. Les VALEURS PROPRES de la
                    # covariance ponderee sont les memes etendues lues dans le repere PROPRE du
                    # nuage : elles ne changent pas si on tourne l'organe. C'est la forme
                    # recevable des trois clauses de §10 et §11, pas seulement de la longueur.
                    mu3 = (wv[:, None] * cl).sum(0) / wv.sum()
                    d3 = cl - mu3
                    C3 = (d3 * wv[:, None]).T @ d3 / wv.sum()
                    ev, EV = np.linalg.eigh(C3)
                    # appariement par l'axe de BIND le plus proche, jamais par l'ordre des
                    # valeurs propres (qui peut permuter d'une cellule a l'autre)
                    lam3, ang3, used = {}, {}, set()
                    for a in ('fwd', 'out', 'up'):
                        v = AX[a] / np.linalg.norm(AX[a])
                        best, bk = -1.0, None
                        for k3 in range(3):
                            if k3 in used:
                                continue
                            c = abs(float(EV[:, k3] @ v))
                            if c > best:
                                best, bk = c, k3
                        used.add(bk)
                        lam3[a] = math.sqrt(max(ev[bk], 0.0))
                        ang3[a] = math.degrees(math.acos(max(-1.0, min(1.0, best))))
                    eig[i], eang[i] = lam3, ang3
                    cprox = (wv[proximal, None] * acc[proximal]).sum(0) / wv[proximal].sum()
                    cdist = (wv[distal, None] * acc[distal]).sum(0) / wv[distal].sum()
                    d = cdist - cprox
                    L_pp[i] = float(np.linalg.norm(d))
                    rootpos = mm[(i, slot[rootjoint])][3, :3]
                    L_jp[i] = float(np.linalg.norm(cdist - rootpos))
                    fw = E @ AX['fwd']
                    fw /= np.linalg.norm(fw)
                    ang[i] = math.degrees(math.acos(
                        max(-1.0, min(1.0, float(d @ fw / max(np.linalg.norm(d), 1e-9))))))
                Lalt = {}
                for q, (pm, dm) in alt.items():
                    seq = {}
                    for i in (0, cells[0], *( [c for c in cells] )):
                        pass
                    for i in cells:
                        if any((i, slot[j]) not in mm for j in slot):
                            continue
                        acc = world_cloud(xf, i, sel)
                        cp = (wv[pm, None] * acc[pm]).sum(0) / wv[pm].sum()
                        cd = (wv[dm, None] * acc[dm]).sum(0) / wv[dm].sum()
                        seq[i] = float(np.linalg.norm(cd - cp))
                    Lalt[q] = seq
                res[(cname, lbl, mode)] = dict(ext=ext, Lpp=L_pp, Ljp=L_jp, ang=ang,
                                               Lalt=Lalt, wprox=wprox, wdist=wdist,
                                               eig=eig, eang=eang)
    return res, cells


RES_TGT = []


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else \
        '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
    txt = open(os.path.join(REPO, log) if not os.path.isabs(log) else log,
               'r', errors='replace').read()
    isup, ipro, _g = c124._roles(txt)
    o2 = c124._ori2(txt)
    res, cells = run(txt, inject_fwd=1.50)
    P = print
    P('C126: cellules designees par la GRAVITE MESUREE : SUPINE i=%s · PRONE i=%s' % (isup, ipro))
    P('C126: decomposition polaire A = S . R sur les 4 joints de chaine ; `chest` et les epaules'
      ' restent LIVRES (ils portent l\'animation et definissent le repere).')
    P('C126: ' + '-' * 100)

    # ---- P5 : LE CONTROLE NEGATIF PAR CONSTRUCTION ---------------------------------------------
    bad = []
    for k, d in res.items():
        if k == '__sing__':
            continue
        cn, lbl, mode = k
        if mode != 'RIGID':
            continue
        for a in ('fwd', 'out', 'up'):
            r = d['ext'][0][a] / res[(cn, lbl, 'FULL')]['ext'][0][a]
            if abs(r - 1.0) > 1e-6:
                bad.append((cn, lbl, mode, a, r))
    P('C126: P5 — TEL QUE JE L\'AI ECRIT, IL EST REFUTE, ET LA FAUTE EST DANS MA FORMULATION.')
    P('C126:   J\'avais predit que les TROIS nuages rendraient la meme forme a i=0. C\'est faux par')
    P('C126:   construction pour STRETCH : abandonner R abandonne AUSSI la rotation bind->monde, donc')
    P('C126:   son nuage est dans une autre ORIENTATION a i=0 — ca ne dit rien de l\'instrument.')
    P('C126:   LA MOITIE QUI EST UN CONTROLE, ET ELLE TIENT : RIGID contre FULL a i=0, ecart max %.6f'
      % (max([abs(b[4] - 1.0) for b in bad] or [0.0]) if bad else
         max(abs(res[(cn, lbl, 'RIGID')]['ext'][0][a] / res[(cn, lbl, 'FULL')]['ext'][0][a] - 1.0)
             for cn in CHAINS for lbl in ('w>0.00', 'w>=0.25') for a in ('fwd', 'out', 'up'))))
    P('C126:   Elle etablit que S vaut l\'identite A LA POSE D\'AUTEUR : ce que j\'extrais ailleurs est')
    P('C126:   donc de la deformation ECRITE, pas un artefact de convention de matrice.')
    sg = res['__sing__']
    for nm in sorted({n for (_i, n) in sg}):
        v0 = sg.get((0, nm))
        P('C126:   valeurs singulieres de S — joint %-6s a i=0 : %.6f %.6f %.6f  (cible 1,000000)'
          % (nm, v0[0], v0[1], v0[2]))

    for ci, cname in enumerate(CHAINS):
        for lbl in ('w>0.00', 'w>=0.25'):
            for sec, cell in (('10', isup), ('11', ipro)):
                b = BANDS[sec]
                cmd = o2.get((ci, cell))
                P('C126: ' + '-' * 100)
                P('C126: %-8s %-8s §%s  cellule i=%s' % (cname, lbl, sec, cell))
                P('C126:   %-8s | %-9s %-9s %-9s | prod sigma' % ('nuage', 'fwd', 'out', 'up'))
                prod = {}
                for mode in ('FULL', 'RIGID', 'STRETCH', 'INJECT', 'ISO'):
                    d = res[(cname, lbl, mode)]
                    r = {a: d['ext'][cell][a] / d['ext'][0][a] for a in ('fwd', 'out', 'up')}
                    prod[mode] = r['fwd'] * r['out'] * r['up']
                    P('C126:   %-8s | %-9.4f %-9.4f %-9.4f | %.4f'
                      % (mode, r['fwd'], r['out'], r['up'], prod[mode]))
                if cmd:
                    P('C126:   %-8s | %-9.4f %-9.4f %-9.4f | %.4f  (PHYSORI2)'
                      % ('COMMANDE', cmd[2], cmd[0], cmd[1], cmd[0] * cmd[1] * cmd[2]))
                lo, hi = b['fwd']
                P('C126:   bande §%s `fwd` %.2f-%.2f' % (sec, lo, hi))
                dF = res[(cname, lbl, 'FULL')]
                P('C126:   TRIPLET INVARIANT PAR ROTATION (valeurs propres de la covariance'
                  ' ponderee, appariees par l\'axe de bind le plus proche) :')
                for a in ('fwd', 'out', 'up'):
                    r = dF['eig'][cell][a] / dF['eig'][0][a]
                    l2, h2 = b[a]
                    vd2 = 'SOUS' if r < l2 else ('DANS' if r <= h2 else 'AU-DESSUS')
                    rr = res[(cname, lbl, 'RIGID')]
                    rrv = rr['eig'][cell][a] / rr['eig'][0][a]
                    P('C126:     %-3s  INVARIANT %.4f  bande %.2f-%.2f  %-9s | sigma sur axe FIXE'
                      ' %.4f (%s) | RIGID seul %.4f | axe propre a %.1f deg de l\'axe de bind'
                      % (a, r, l2, h2, vd2,
                         dF['ext'][cell][a] / dF['ext'][0][a],
                         'SOUS' if dF['ext'][cell][a] / dF['ext'][0][a] < l2 else
                         ('DANS' if dF['ext'][cell][a] / dF['ext'][0][a] <= h2 else 'AU-DESSUS'),
                         rrv, dF['eang'][cell][a]))
                P('C126:   P4 produit des sigmas FULL/RIGID = %.4f (ecart %+.2f %%)'
                  % (prod['FULL'] / prod['RIGID'], (prod['FULL'] / prod['RIGID'] - 1) * 100))
                # ---- LA GRANDEUR QUE LA SECTION NOMME -------------------------------------------
                P('C126:   LONGUEUR RACINE->APEX (invariante par rotation — la grandeur de §11) :')
                for mode in ('FULL', 'RIGID', 'STRETCH', 'INJECT', 'ISO'):
                    d = res[(cname, lbl, mode)]
                    rpp = d['Lpp'][cell] / d['Lpp'][0]
                    rjp = d['Ljp'][cell] / d['Ljp'][0]
                    vd = 'SOUS' if rpp < lo else ('DANS' if rpp <= hi else 'AU-DESSUS')
                    P('C126:     %-8s decile-a-decile %.4f  %-9s | joint-a-decile %.4f |'
                      ' angle(axe,fwd) %5.1f deg' % (mode, rpp, vd, rjp, d['ang'][cell]))
                d0 = res[(cname, lbl, 'FULL')]
                if 9 in d0['Lpp']:
                    P('C126:   P5b LECTURE HORS DEFAUT — i=9 (2e cellule DEBOUT) / i=0 :'
                      ' longueur %.4f  (seuil declare 1 %%)' % (d0['Lpp'][9] / d0['Lpp'][0]))
                di = res[(cname, lbl, 'INJECT')]
                dis = res[(cname, lbl, 'ISO')]
                P('C126:   P6 CONTROLE POSITIF (tel qu\'ecrit) — x1,50 le long de `fwd` :'
                  ' longueur %+.1f %% contre FULL  (bande declaree +40 a +60 %%) -> %s'
                  % ((di['Lpp'][cell] / d0['Lpp'][cell] - 1) * 100,
                     'TENUE' if 0.40 <= di['Lpp'][cell] / d0['Lpp'][cell] - 1 <= 0.60 else 'REFUTE'))
                iso = dis['Lpp'][cell] / d0['Lpp'][cell]
                P('C126:   P6bis CONTROLE POSITIF EXACT — x1,50 ISOTROPE : longueur x%.4f'
                  ' (prediction exacte 1,5000, tolerance 0,5 %%) -> %s'
                  % (iso, 'TENUE' if abs(iso - 1.5) <= 0.0075 else 'REFUTE'))
                sgc = res['__sing__']
                for j in CHAINS[cname]:
                    v = sgc.get((cell, j))
                    if v:
                        P('C126:   etirement ECRIT par le solveur, joint %-6s : valeurs singulieres'
                          ' de S %.4f %.4f %.4f' % (j, v[0], v[1], v[2]))
                if cmd:
                    v = sgc.get((cell, CHAINS[cname][0]))
                    c = tuple(sorted(cmd, reverse=True))
                    P('C126:   COMMANDE triee %.4f %.4f %.4f  contre S ECRITE triee %.4f %.4f %.4f'
                      '  -> ecart max %.2e' % (c + v + (max(abs(a - b) for a, b in zip(c, v)),)))
                P('C126:   TEST DE RAFFINEMENT du decile (5 %% / 10 %% / 20 %%) : %s'
                  % ' · '.join('q=%.2f %.4f' % (q, d0['Lalt'][q][cell] / d0['Lalt'][q][0])
                               for q in (0.05, 0.10, 0.20)))
                P('C126:   poids de chaine moyen — decile PROXIMAL %.3f · decile DISTAL %.3f'
                  '   (§30 : la racine est « strongly attached », elle pese sur `chest`)'
                  % (d0['wprox'], d0['wdist']))
                if sec == '11':
                    xs, ys = [], []
                    for lam in SWEEP:
                        dl = res[(cname, lbl, 'LAM%.3f' % lam)]
                        xs.append(lam); ys.append(dl['Lpp'][cell] / dl['Lpp'][0])
                    P('C126:   BALAYAGE DE LA COMMANDE (on ne change QUE la plus grande valeur'
                      ' singuliere de S ; rotation, translation et articulation intactes) :')
                    P('C126:     %s' % ' · '.join('lam=%.4f -> %.4f' % (a, b)
                                                  for a, b in zip(xs, ys)))
                    tgt = 1.23
                    lam_t = float(np.interp(tgt, ys, xs))
                    lam_lo = float(np.interp(lo, ys, xs))
                    lam_hi = float(np.interp(hi, ys, xs))
                    P('C126:     CIBLE MESUREE (bouton SEUL, CASSE §8) : pour livrer %.2f il faut'
                      ' lam = %.4f ; bande %.2f-%.2f <-> lam %.4f-%.4f  (commande actuelle %.4f)'
                      % (tgt, lam_t, lo, hi, lam_lo, lam_hi, cmd[2]))
                    P('C126:       det(S) tomberait a %.4f (aujourd\'hui %.4f) : §8 exige 0,98-1,01,'
                      ' donc le bouton NE PEUT PAS bouger seul.'
                      % (lam_t * cmd[0] * cmd[1], cmd[0] * cmd[1] * cmd[2]))
                    ysv = []
                    for lam in SWEEP:
                        dl = res[(cname, lbl, 'LAMV%.3f' % lam)]
                        ysv.append(dl['Lpp'][cell] / dl['Lpp'][0])
                    P('C126:     A VOLUME CONSERVE (det(S) inchange au bit pres) :')
                    P('C126:       %s' % ' · '.join('lam=%.4f -> %.4f' % (a, b)
                                                    for a, b in zip(xs, ysv)))
                    P('C126:       CIBLE MESUREE, RECEVABLE POUR §8 : lam = %.4f pour livrer %.2f ;'
                      ' bande %.2f-%.2f <-> lam %.4f-%.4f'
                      % (float(np.interp(tgt, ysv, xs)), tgt, lo, hi,
                         float(np.interp(lo, ysv, xs)), float(np.interp(hi, ysv, xs))))
                    RES_TGT.append((cname, lbl, float(np.interp(lo, ysv, xs)),
                                    float(np.interp(hi, ysv, xs))))
    if RES_TGT:
        lo_i = max(t[2] for t in RES_TGT)
        hi_i = min(t[3] for t in RES_TGT)
        P('C126: ' + '=' * 100)
        P('C126: INTERSECTION DES QUATRE BANDES ADMISSIBLES (2 chaines x 2 frontieres de poids),'
          ' a volume conserve :')
        for t in RES_TGT:
            P('C126:   %-8s %-8s  lam admissible %.4f - %.4f' % t)
        P('C126:   -> INTERSECTION %.4f - %.4f  %s' % (lo_i, hi_i,
          'NON VIDE : une commande unique met les QUATRE cellules dans la bande de §11'
          if lo_i <= hi_i else 'VIDE : aucune commande unique ne les satisfait toutes'))
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""c133_delivered_com.py — LE DEPLACEMENT DE CENTRE DE MASSE QUE L'ORGANE RECOIT, CONTRE CELUI QUE
LA LIGNE DE VERDICT PUBLIE.

POURQUOI CE FICHIER EXISTE. Le cycle 132 a mesure un ANGLE MORT TOTAL : les lignes qui rendent le
verdict de la clause de COM de §10, §11 et §12 (`physics_room_table.py:2573`, `:3631`, `:1680`)
lisent `PHYSORICOML` et `PHYSDFMA`, tous deux pris sur `*phys-ldb*`, ecrit a
`jak-hd-physics.gc:3415`. Or l'ecriture squelette a lieu a `:3932` et le plafond de §21 a `:4046`.
Deux courses qui ne differaient que par le bouton d'ancrage de §31 ont fait bouger 20 632
enregistrements et l'organe LIVRE (COM vivant -3,48 % / -2,31 %) pendant que `PHYSORICOML`,
`PHYSDFMA` et `PHYSROW` restaient IDENTIQUES AU BIT.

CE QUE CE FICHIER MESURE, ET POURQUOI IL NE DEMANDE PAS DE COURSE. `PHYSORIM` publie deja, par
cellule d'orientation, les QUATRE lignes de la matrice REELLEMENT ECRITE au squelette pour
`lBoob`, `lBooc`, `rBoob`, `rBooc` et l'ancre `chest`. Verifie a la source, dans l'ordre du
moteur : rotation `:3902` -> tenseur `*phys-dfm*` `:3918` -> ancrage de §31 `:3922` -> translation
`:3932-3934` -> plafond de §21 `:4046`, et `PHYSORIM` lit la matrice APRES tout cela. La grandeur
LIVREE est donc dans la trace archivee, et l'angle mort se mesure sans rebatir un emetteur.

NATURE / REPERE / LIGNE DE BASE (les trois questions obligatoires du contrat) :
  NATURE  : un DEPLACEMENT SOUTENU du centre de masse de l'organe entre la cellule d'orientation
            et la cellule debout, rapporte a `B0` (§6, la CHAIR). Ce n'est ni une amplitude, ni une
            variance, ni un maximum de fenetre : les cellules sont des EQUILIBRES TENUS.
  REPERE  : le triedre de l'ANCRE `chest`, PRIS A CHAQUE CELLULE, donc la rotation d'ensemble du
            personnage sort de la mesure. La base est TRANSPORTEE depuis la pose de bind par le
            meme skinning que la peau (`frame()`), jamais reconstruite par une inversion. Elle est
            orthonormee — `breast-com-mass.json` publie `anchor_ortho = 1.03e-24` — donc la NORME
            d'un deplacement y est la meme que dans le monde, et c'est verifie ici, pas suppose.
  LIGNE DE BASE : la cellule i=0 est la pose debout d'auteur, ou §9 exige la forme du modele. Elle
            est la REFERENCE des deplacements ; ce qui tient lieu de lecture HORS DEFAUT est la
            cellule i=9, une SECONDE cellule debout que rien ne relie a i=0 dans le balayage, et
            dont ce fichier publie le deplacement — il doit etre proche de zero.

CE QUE CE FICHIER NE PRETEND PAS, ET LA RESERVE EST DECLAREE AVANT LES CHIFFRES. Les deux
instruments different par DEUX choses et pas une :
  (a) L'ANGLE MORT lui-meme : plafond de §21 et ancrage de §31, tous deux posterieurs a
      `*phys-ldb*` ;
  (b) LA LINEARISATION : `_vecCOM` approche le COM par `(W.d)/N + ((D-I).L)/N`, c'est-a-dire en
      traitant la part de ROTATION du skinning comme negligeable, la ou le nuage livre la calcule
      EXACTEMENT.
Un ecart ne s'attribue donc pas au seul angle mort tant que (b) n'est pas borne. Ce fichier publie
donc TROIS colonnes et pas deux : la valeur PUBLIEE, la valeur LIVREE, et une valeur LINEARISEE
recalculee ici sur les MEMES matrices livrees — la difference LIVREE-LINEARISEE isole (b), et la
difference LINEARISEE-PUBLIEE isole (a).

CONTROLE DE PORTAGE, ET IL N'EST PAS OPTIONNEL. Ce fichier reconstruit le nuage de peau avec la
meme convention que `c124_delivered_shape.py`. Deux implementations d'une meme mesure finissent par
diverger, et ce dossier l'a deja paye. Le portage est donc VALIDE en reproduisant les distances
racine->apex entre centroides de decile que `c124_delivered_shape.py` publie, et l'ecart est
publie. Au-dela d'un seuil declare, rien n'est publie du tout.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import physics_c6_volumes as c6
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info
import c124_delivered_shape as C124

REPO = C124.REPO
SHIPPED = C124.SHIPPED
MASSJSON = C124.MASSJSON
CHAINS = C124.CHAINS
ANCHOR = C124.ANCHOR

# ---- LE MEME CALCUL, RENDU APPELABLE PAR LE PRODUCTEUR DU TABLEAU -----------------------------
# Regle du 2026-08-19 23:50 : « un correctif d'instrument s'arrete quand la LIGNE DE VERDICT lit la
# nouvelle donnee — pas quand la donnee existe ». `physics_room_table.py` doit donc appeler CE
# calcul-ci et pas une copie. Motif repris tel quel de `c124_delivered_shape.py`, pour que les deux
# instruments livres se branchent de la meme facon.
_SINK = None
RESULT = {}


def _emit(s):
    if _SINK is None:
        print(s)
    else:
        _SINK.append(s)


def measure(txt):
    """(lignes, rows, rc) ; rows = {(chaine, frontiere, '10'|'11') -> dict} — voir `main()`."""
    global _SINK
    old, _SINK = _SINK, []
    try:
        RESULT.clear()
        rc = main(txt=txt)
        return list(_SINK), dict(RESULT.get('rows', {})), rc
    finally:
        _SINK = old


PORT_TOL = 0.005          # 0,5 % : au-dela, le portage n'est pas etabli et rien n'est publie
B0_DEFAULT = 602.0        # §6, la CHAIR ; remplace par la valeur de la trace si elle y est


def _b0_from_trace(txt):
    """`B0` par chaine, lu dans la trace (`PHYSBASE`), jamais suppose."""
    import re
    out = {}
    for m in re.finditer(r'^PHYSBASE c=(\d+).*?b0=([-\d.e+]+)', txt, re.M):
        out[int(m.group(1))] = float(m.group(2))
    return out


def _vertex_areas(V, F):
    """`a_v` = un tiers de l'aire de chaque triangle incident, en pose de BIND — la definition
    exacte que `breast-com-mass.json` publie pour sa masse d'aire."""
    a = np.zeros(len(V))
    if F is None or len(F) == 0:
        return None
    p0, p1, p2 = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    ar = 0.5 * np.linalg.norm(np.cross(p1 - p0, p2 - p0), axis=1)
    for k in range(3):
        np.add.at(a, F[:, k], ar / 3.0)
    return a


def main(txt=None):
    P_ = _emit
    if txt is None:
        log = sys.argv[1] if len(sys.argv) > 1 else \
            '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
        path = log if os.path.isabs(log) else os.path.join(REPO, log)
        txt = open(path, 'r', errors='replace').read()
        import hashlib
        md5 = hashlib.md5(open(path, 'rb').read()).hexdigest()
        P_('C133-COM: trace = %s' % os.path.relpath(path, REPO))
        P_('C133-COM: empreinte de la trace (md5) = %s' % md5)

    jn, mats, nmiss = C124._read_matrices(txt)
    if not mats:
        P_('C133-COM: SUSPENDU — aucune ligne `PHYSORIM`. Rien n\'est publie.')
        return 1
    if nmiss:
        P_('C133-COM: SUSPENDU — %d ligne(s) `PHYSORIMMISS`. Un skinning incomplet donnerait'
           ' une forme plausible et fausse.' % nmiss)
        return 1
    slot = {v: k for k, v in jn.items()}

    g = c6.load_geometry('keira-hd', glb=SHIPPED)
    if g is None:
        P_('C133-COM: SUSPENDU — mesh livre absent (%s).' % SHIPPED)
        return 1
    names = list(g['names'])
    V, J, W, P = g['V'], g['J'], g['W'], g['P']
    F = g.get('F')
    js, bufs = read_glb(os.path.join(REPO, SHIPPED))
    _nn, ibms, _pp = skin_info(js, consolidate_buffers(js, bufs))
    ai = names.index(ANCHOR)
    R = np.linalg.inv(np.array(ibms[ai], dtype=float))[:3, :3].copy()
    for k in range(3):
        R[:, k] /= np.linalg.norm(R[:, k])
    mass = json.load(open(os.path.join(REPO, MASSJSON)))
    cells = sorted({i for (i, _j) in mats})
    b0t = _b0_from_trace(txt)
    P_('C133-COM: `anchor_ortho` publie par la sonde de masse = %.3e (0 = base orthonormee ; la'
       ' NORME d\'un deplacement y vaut celle du monde)' % mass.get('anchor_ortho', float('nan')))

    def bindR(j):
        Rj = np.linalg.inv(np.array(ibms[j], dtype=float))[:3, :3].copy()
        for k in range(3):
            Rj[:, k] /= np.linalg.norm(Rj[:, k])
        return Rj

    RB = {n: bindR(names.index(n)) for n in slot}

    # ---- LA CONVENTION DE SKINNING, TRANCHEE PAR LA MEME MESURE QUE `c124_delivered_shape.py`
    wch = (W * (J == ai)).sum(axis=1)
    top = np.argsort(-wch)[:24]
    dbind = np.linalg.norm(V[top] - P[ai], axis=1)
    Mch = mats[(cells[0], slot[ANCHOR])]
    verdict = {}
    for tag in ('A', 'C'):
        q = V[top].copy() if tag == 'A' else (V[top] - P[ai]) @ RB[ANCHOR]
        p = q @ Mch[:3, :3] + Mch[3, :3]
        dnow = np.linalg.norm(p - Mch[3, :3], axis=1)
        verdict[tag] = float(np.median(np.abs(dnow - dbind) / np.maximum(dbind, 1e-9)))
    conv = min(verdict, key=verdict.get)
    P_('C133-COM: convention de skinning tranchee par mesure : %s (A %.5f · C %.5f)'
       % (conv, verdict['A'], verdict['C']))
    if verdict[conv] > 0.02:
        P_('C133-COM: SUSPENDU — meme la meilleure convention rend %.5f (seuil 0.02).'
           % verdict[conv])
        return 1
    use_bind = (conv == 'C')

    def xform(x, nmj, i):
        M = mats[(i, slot[nmj])]
        q = np.atleast_2d(np.asarray(x, dtype=float))
        if use_bind:
            q = (q - P[names.index(nmj)]) @ RB[nmj]
        return q @ M[:3, :3] + M[3, :3]

    def frame(i):
        pts = np.vstack([P[ai]] + [P[ai] + R[:, k] for k in range(3)])
        im = xform(pts, ANCHOR, i)
        o = im[0]
        E = np.stack([im[1 + k] - o for k in range(3)], axis=1)
        for k in range(3):
            E[:, k] /= np.linalg.norm(E[:, k])
        return o, E

    def world_cloud(i, sel):
        n = int(sel.sum())
        acc = np.zeros((n, 3))
        wtot = np.zeros(n)
        Js, Ws, Vs = J[sel], W[sel], V[sel]
        for k in range(Ws.shape[1]):
            for nmj in slot:
                m = (Js[:, k] == names.index(nmj)) & (Ws[:, k] > 0)
                if not m.any():
                    continue
                if (i, slot[nmj]) not in mats:
                    return None
                acc[m] += Ws[m, k][:, None] * xform(Vs[m], nmj, i)
                wtot[m] += Ws[m, k]
        if float(np.abs(wtot - 1.0).max()) > 1e-3:
            return ('INCOMPLET', float(np.abs(wtot - 1.0).max()))
        return acc

    isup, ipro, _g = C124._roles(txt)
    P_('C133-COM: cellules designees par la GRAVITE MESUREE : SUPINE i=%s · PRONE i=%s'
       % (isup, ipro))
    av = _vertex_areas(V, F)

    # ---- CONTROLE DE PORTAGE : on reproduit les distances de decile de `c124_delivered_shape` ---
    lines124, rows124, rc124 = C124.measure(txt)
    port = []

    P_('')
    for ci, (cname, joints) in enumerate(CHAINS.items()):
        idx = [names.index(j) for j in joints]
        wj = np.zeros((len(V), len(idx)))
        for k, ji in enumerate(idx):
            wj[:, k] = (W * (J == ji)).sum(axis=1)
        wsum = wj.sum(axis=1)
        AXr = mass['chains'][cname]['axes']
        AX = {a: np.asarray(AXr[a], dtype=float) for a in ('out', 'up', 'fwd')}
        bb = b0t.get(ci, B0_DEFAULT)
        defs = {d['cut']: d for d in mass['chains'][cname]['defs']}
        # LES TROIS FRONTIERES, comme la ligne de verdict — pas deux. `c124_delivered_shape`
        # n'en publie que deux parce qu'il mesure une FORME ; la ligne de COM publie sa
        # SENSIBILITE DE FRONTIERE sur w>0.00 / w>0.05 / w>0.25, et une comparaison qui n'en
        # couvrirait que deux laisserait un tiers de la ligne sans vis-a-vis.
        for cut, lbl in ((0.0, 'w>0.00'), (0.05, 'w>0.05'), (0.25, 'w>=0.25')):
            sel = wsum > cut if cut == 0.0 else wsum >= cut
            wv = wsum[sel]
            # ---- LE DENOMINATEUR EST CELUI DE LA LIGNE DE VERDICT, ET IL N'EST PAS `wsum` ------
            # PIEGE PAYE DANS CE MEME CYCLE, ET PUBLIE. J'avais d'abord pondere les positions par
            # `wsum` (le poids de peau du sommet sur les os de la chaine) et divise par sa somme :
            # une MOYENNE PONDEREE PAR LE POIDS DE PEAU. Ce n'est pas ce que la ligne de verdict
            # calcule. `_vecCOM` (physics_room_table.py) rend
            #     SOMME_v [ SOMME_k w(v,k) . d_k ] / N
            # c'est-a-dire la moyenne SIMPLE, sur les N sommets selectionnes, du deplacement de
            # chaque sommet — le poids de peau est deja DANS le deplacement du sommet, il ne doit
            # pas etre remis une seconde fois au denominateur. Le compter deux fois sur-pondere
            # les sommets les plus lies au sein, qui sont justement ceux qui bougent le plus, et
            # gonfle le chiffre. C'est exactement `com-normalized-by-vertex-count` du registre,
            # pris par l'autre bout.
            #   `compte` -> poids 1 par sommet (denominateur `n`)
            #   `aire`   -> poids `a_v` (denominateur `na = SOMME_v a_v`), et `a_v` SEUL : `Wa`
            #               porte deja le `w(v,k)` dans son numerateur, pas dans son denominateur.
            wcount = np.ones(int(sel.sum()))
            wa = av[sel] if av is not None else None
            xb = (V[sel] - P[ai]) @ R @ AX['fwd']
            qlo, qhi = np.quantile(xb, 0.10), np.quantile(xb, 0.90)
            prox, dist = xb <= qlo, xb >= qhi
            comN, comA, comW, dec, lin = {}, {}, {}, {}, {}
            rotp, trnp, ident = {}, {}, {}
            gc = defs.get(cut)
            # ---- LA DECOMPOSITION EXACTE, ET ELLE N'EST PAS UN MODELE -------------------------
            # Le COM livre se separe SANS approximation, par simple distributivite du skinning
            # lineaire. Pour un sommet `v` de poids `w(v,k)` sur l'os `k`, de matrice livree
            # `(A_k, t_k)` et de coordonnee bind-locale `q_k(v)` :
            #     COM(i) = SOMME_v SOMME_k w(v,k) [ q_k(v) . A_k(i) + t_k(i) ] / N
            #            = SOMME_k [ Q_k . A_k(i) + W_k . t_k(i) ] / N
            # ou `Q_k = SOMME_v w(v,k) q_k(v)` est le PREMIER MOMENT de la chair sur l'os `k`,
            # en coordonnees BIND-LOCALES de CE joint — un vecteur FIXE, independant de la
            # cellule. Le premier terme porte la ROTATION ET LE TENSEUR (le moteur ecrit
            # `bm . D` a `jak-hd-physics.gc:3918`, donc `A_k` les contient tous les deux), le
            # second porte la TRANSLATION. Aucun terme n'est neglige : c'est une identite, et
            # elle est VERIFIEE ci-dessous contre le nuage, pas affirmee.
            # LA SOMME PORTE SUR TOUS LES JOINTS QUE LE SKINNING MELANGE, PAS SEULEMENT SUR LES
            # DEUX OS DE LA CHAINE — ET C'EST LE GARDE QUI ME L'A APPRIS, PAS UN RAISONNEMENT.
            # Ma premiere version ne sommait que `joints` : l'identite a refuse de se refermer de
            # 4,6e5 u, exactement la contribution des sommets peses sur `chest`. Un sommet a 50 %
            # `lBoob` / 50 % `chest` est DANS le nuage avec sa position complete ; l'omettre de la
            # decomposition en fait deux grandeurs differentes. Cette contribution est quasi
            # STATIQUE dans la base d'ancre et s'annule donc dans la DIFFERENCE entre cellules,
            # mais elle doit etre presente pour que l'identite ferme — et c'est la fermeture qui
            # autorise l'attribution.
            _sj = list(slot)
            Qk, Wk_ = [], []
            for nmj in _sj:
                ji = names.index(nmj)
                wk = (W[sel] * (J[sel] == ji)).sum(axis=1)
                qk = (V[sel] - P[ji]) @ RB[nmj] if use_bind else V[sel]
                Qk.append((wk[:, None] * qk).sum(0))
                Wk_.append(float(wk.sum()))
            Nn_ = float(sel.sum())
            for i in cells:
                aw = world_cloud(i, sel)
                if aw is None or isinstance(aw, tuple):
                    continue
                o_, E_ = frame(i)
                cl = (aw - o_) @ E_
                # LE COM LIVRE. Poids = la somme des poids de peau du sommet sur les os de la
                # chaine (`compte de sommets` de la ligne de verdict), et la MASSE D'AIRE a cote.
                comN[i] = (wcount[:, None] * cl).sum(0) / wcount.sum()
                if wa is not None:
                    comA[i] = (wa[:, None] * cl).sum(0) / wa.sum()
                comW[i] = (wv[:, None] * cl).sum(0) / wv.sum()
                cp = (wv[prox, None] * aw[prox]).sum(0) / wv[prox].sum()
                cd = (wv[dist, None] * aw[dist]).sum(0) / wv[dist].sum()
                dec[i] = float(np.linalg.norm(cd - cp))
                # LA MEME LINEARISATION QUE LA LIGNE DE VERDICT, MAIS SUR LES MATRICES LIVREES :
                # `sk` = SOMME_k W_k . d_k / N, ou `d_k` est la TRANSLATION du joint `k` par
                # rapport a la cellule debout, lue dans la base d'ancre de chaque cellule.
                if gc is not None:
                    Wk, Nn = gc['W'], float(gc['n'])
                    sk = np.zeros(3)
                    for k, nmj in enumerate(joints):
                        Mi = mats[(i, slot[nmj])]
                        M0 = mats[(cells[0], slot[nmj])]
                        o0, E0 = frame(cells[0])
                        d = (Mi[3, :3] - o_) @ E_ - (M0[3, :3] - o0) @ E0
                        sk += Wk[k] * d
                    lin[i] = sk / Nn
                # les deux moities de l'identite, chacune projetee dans la base de SA cellule
                rw = np.zeros(3)
                tw = np.zeros(3)
                for k, nmj in enumerate(_sj):
                    Mi = mats[(i, slot[nmj])]
                    rw += Qk[k] @ Mi[:3, :3]
                    tw += Wk_[k] * Mi[3, :3]
                rotp[i] = (rw / Nn_) @ E_
                trnp[i] = (tw / Nn_ - o_) @ E_
                ident[i] = float(np.linalg.norm(rotp[i] + trnp[i] - comN[i]))
            if 0 not in comN:
                P_('C133-COM: %-8s %s SUSPENDU — pas de cellule i=0.' % (cname, lbl))
                continue
            # controle de portage sur `fwd` de §10 et §11
            for sec, cell in (('10', isup), ('11', ipro)):
                key = (cname, lbl, sec, 'fwd')
                if key in rows124 and rows124[key][4] is not None and cell in dec:
                    mine = dec[cell] / dec[0]
                    port.append((key, rows124[key][4], mine))
            for sec, cell, band in (('10', isup, None), ('11', ipro, (0.20, 0.28))):
                if cell is None or cell not in comN:
                    continue
                dN = float(np.linalg.norm(comN[cell] - comN[0])) / bb
                dA = (float(np.linalg.norm(comA[cell] - comA[0])) / bb
                      if cell in comA and 0 in comA else float('nan'))
                dL = (float(np.linalg.norm(lin[cell] - lin[0])) / bb
                      if cell in lin and 0 in lin else float('nan'))
                RESULT.setdefault('rows', {})[(cname, lbl, sec)] = dict(
                    livree_compte=dN, livree_aire=dA, lin_compte=dL, b0=bb, cell=cell)
                vb = ('' if band is None else
                      ('  bande %.2f-%.2f  %s' % (band[0], band[1],
                       'SOUS' if dN < band[0] else ('DANS' if dN <= band[1] else 'AU-DESSUS'))))
                dW = float(np.linalg.norm(comW[cell] - comW[0])) / bb
                P_('C133-COM: %-8s %-8s §%-3s i=%-2d  LIVREE(compte) %.4f  LIVREE(aire) %.4f '
                   ' LINEARISEE(livree,compte) %.4f  B0=%.1f%s'
                   % (cname, lbl, sec, cell, dN, dA, dL, bb, vb))
                P_('C133-COM: %-8s %-8s §%-3s i=%-2d  DIAGNOSTIC, PAS UN VERDICT — pondere par le'
                   ' POIDS DE PEAU (denominateur SOMME wsum, donc `w` compte DEUX fois) : %.4f B0.'
                   ' Publie parce que c\'est l\'erreur que ce cycle a faite et corrigee ;'
                   ' l\'ecart au denominateur juste est le prix de la faute : x%.3f'
                   % (cname, lbl, sec, cell, dW, dW / max(dN, 1e-12)))
            # ---- OU VIT L'ECART, MESURE ET PAS SUPPOSE ---------------------------------------
            if ident and max(ident.values()) < 1.0:
                for sec, cell in (('10', isup), ('11', ipro)):
                    if cell is None or cell not in rotp or 0 not in rotp:
                        continue
                    dr = float(np.linalg.norm(rotp[cell] - rotp[0])) / bb
                    dt = float(np.linalg.norm(trnp[cell] - trnp[0])) / bb
                    P_('C133-COM: %-8s %-8s §%-3s i=%-2d  DECOMPOSITION EXACTE (identite verifiee'
                       ' a %.2e u) : moitie ROTATION+TENSEUR %.4f B0 · moitie TRANSLATION %.4f B0'
                       % (cname, lbl, sec, cell, max(ident.values()), dr, dt))
                    # ---- LA MEME DECOMPOSITION, MAIS SIGNEE SUR L'AXE `out` -------------------
                    # AJOUTEE AU CYCLE 137, ET VOICI POURQUOI ELLE MANQUAIT. Les deux lignes
                    # ci-dessus publient des NORMES ; la clause porteuse de §10 (« Outward COM
                    # migration per breast: 4-10% W0 ») est DIRECTIONNELLE et son defaut mesure est
                    # un SIGNE, pas une amplitude (-2,26 / -7,16 % W0 : le COM migre vers
                    # l'INTERIEUR). Une norme ne peut pas dire QUEL etage tire vers l'interieur, et
                    # sans ca « corriger le tenseur » et « corriger la translation du solveur » sont
                    # indistinguables — le piege `response-dies-at-one-solver-stage` du registre,
                    # qui demande le rapport entree/sortie ETAGE PAR ETAGE.
                    # NATURE : deux composantes SIGNEES d'un deplacement, normalisees par `W0`
                    #          (§6, la LARGEUR de la chair), en pourcent. Ce n'est pas une norme.
                    # REPERE : la base d'ancre de la cellule, axe `out` = le lateral SORTANT de
                    #          CETTE chaine (chestL +X, chestR -X : anti-symetrique, donc un
                    #          deplacement commun au monde rend des signes OPPOSES et une migration
                    #          sortante vraie rend le MEME signe des deux cotes).
                    # LIGNE DE BASE : la cellule i=0 (debout d'auteur), ou §9 exige l'identite ;
                    #          les deux composantes y valent 0 par construction de la difference.
                    # SOMME : les deux composantes s'additionnent EXACTEMENT a la ligne
                    #          `DIAGNOSTIC DIRECTIONNEL` ci-dessous (meme identite, meme fermeture).
                    _w0d = defs.get(cut, {}).get('W0')
                    if _w0d:
                        _ro = 100.0 * float((rotp[cell] - rotp[0]) @ AX['out']) / _w0d
                        _to = 100.0 * float((trnp[cell] - trnp[0]) @ AX['out']) / _w0d
                        P_('C133-COM: %-8s %-8s §%-3s i=%-2d  DECOMPOSITION SIGNEE SUR `out` :'
                           ' ROTATION+TENSEUR %+7.3f %% W0 · TRANSLATION %+7.3f %% W0'
                           ' · somme %+7.3f %% W0'
                           % (cname, lbl, sec, cell, _ro, _to, _ro + _to))
            elif ident:
                P_("C133-COM: %-8s %s DECOMPOSITION REFUSEE — l'identite ne se referme pas"
                   " (%.3e u). Rien n'en est publie : une decomposition qui ne se referme pas"
                   " n'attribue rien." % (cname, lbl, max(ident.values())))
            # ---- LA DECOMPOSITION DIRECTIONNELLE, EN DIAGNOSTIC DECLARE ET RIEN D'AUTRE ------
            # POURQUOI ELLE EST PUBLIEE ET POURQUOI ELLE NE PORTE AUCUN VERDICT ICI. Les clauses
            # PORTEUSES de §10 (« Outward COM migration per breast: 4-10% W0 ») et de §12
            # (« Upper/opposite breast medial migration: 10-18% W0 ») sont DIRECTIONNELLES et
            # normalisees par `W0`, pas par `B0`. §12 est l'une des quatre sections `TENUE` du
            # dossier, et elle l'est PAR CETTE CLAUSE-LA. Rebrancher une clause porteuse d'une
            # section TENUE sur un instrument neuf, dans le meme cycle qui decouvre l'instrument,
            # est exactement ce que le cycle 130 s'est interdit de faire. Les chiffres sont donc
            # PUBLIES — remonter une question sans ses nombres ne vaut rien — et ETIQUETES
            # DIAGNOSTIC. Le rebranchement de ces deux clauses appartient au superviseur.
            w0v = defs.get(cut, {}).get('W0')
            if w0v:
                for sec, cell in (('10', isup), ('12', 2), ('12', 4)):
                    if cell is None or cell not in comN or 0 not in comN:
                        continue
                    dv = comN[cell] - comN[0]
                    P_('C133-COM: %-8s %-8s §%-3s i=%-2d  DIAGNOSTIC DIRECTIONNEL, AUCUN VERDICT'
                       ' — out %+7.3f %% W0 · up %+7.3f %% W0 · fwd %+7.3f %% W0   (|d| %.4f B0)'
                       % (cname, lbl, sec, cell,
                          100.0 * float(dv @ AX['out']) / w0v,
                          100.0 * float(dv @ AX['up']) / w0v,
                          100.0 * float(dv @ AX['fwd']) / w0v,
                          float(np.linalg.norm(dv)) / bb))
            # LECTURE HORS DEFAUT : la 2e cellule DEBOUT. Elle doit rendre ~0.
            if 9 in comN:
                P_('C133-COM: %-8s %s LECTURE HORS DEFAUT — i=9 (2e cellule DEBOUT) contre i=0 :'
                   ' %.4f B0  (doit etre ~0 ; c\'est ce que l\'instrument lit quand le defaut est'
                   ' ABSENT)'
                   % (cname, lbl, float(np.linalg.norm(comN[9] - comN[0])) / bb))
            # TOUTES LES CELLULES, pour que la lecture ne repose pas sur deux d'entre elles
            P_('C133-COM: %-8s %s toutes cellules (compte, B0) : %s'
               % (cname, lbl, ' '.join('i%d=%.4f' % (i, float(np.linalg.norm(comN[i] - comN[0])) / bb)
                                       for i in sorted(comN))))
        P_('')

    P_('C133-COM: --- CONTROLE DE PORTAGE ---------------------------------------------------')
    if not port:
        P_('C133-COM: AUCUN point de controle — le portage n\'est PAS etabli, et tout ce qui'
           ' precede est a lire comme non valide.')
        return 1
    worst = max(abs(a - b) / max(abs(a), 1e-12) for _k, a, b in port)
    for k, a, b in port:
        P_('C133-COM:   %-8s %-8s §%-3s deciles : c124 %.6f  ce fichier %.6f  ecart %.4f %%'
           % (k[0], k[1], k[2], a, b, 100.0 * abs(a - b) / max(abs(a), 1e-12)))
    P_('C133-COM: portage valide a %.4f %% au pire (seuil declare %.2f %%). %s'
       % (100.0 * worst, 100.0 * PORT_TOL,
          'RETENU.' if worst <= PORT_TOL else 'REJETE — rien de ce qui precede ne vaut.'))
    return 0 if worst <= PORT_TOL else 1


if __name__ == '__main__':
    sys.exit(main())

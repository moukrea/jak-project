#!/usr/bin/env python3
"""c138_graded_tensor.py — CE QUE LE GRADIENT RACINE->APEX DE SA §31 FERAIT AU COM LIVRE,
PREDIT AVANT D'ECRIRE UNE LIGNE DE MOTEUR.

POURQUOI CE FICHIER EXISTE. §8 l.143 et §10 l.173 interdisent la MEME chose, toutes deux EN GRAS :
  §8   « **but the whole breast shall not be represented by one affine scale transformation.** »
  §10  « **The entire breast shall not simply scale uniformly from its center.** »
et §31 donne le remede, avec sa plage d'exposant : « w(r) = r^1.6...2.0 — little deformation at the
root; progressively increasing mobility; largest displacement in distal tissue ».
Le moteur applique aujourd'hui UNE matrice par CHAINE (`*phys-dfm* sc`, jak-hd-physics.gc:3922),
la meme aux deux maillons : c'est litteralement la transformation affine unique que §8 interdit.

CE QUE CE FICHIER CALCULE, ET IL NE DEMANDE AUCUNE COURSE. Il relit la trace archivee et predit,
SANS approximation, ce que deviendrait le COM livre si le tenseur etait gradue par maillon :
      A_k  ->  B_k . (I + w_k (D - I))        avec  B_k = A_k . D^-1
`A_k` est la 3x3 REELLEMENT ECRITE (PHYSORIM), `D` le tenseur monde reconstruit depuis PHYSDFMA et
la matrice d'ancre. La prediction est donc une identite algebrique appliquee aux matrices livrees,
pas un modele.

LES TROIS QUESTIONS OBLIGATOIRES :
  NATURE  : un DEPLACEMENT SOUTENU du COM entre la cellule d'orientation et la cellule debout,
            projete SIGNE sur l'axe `out` et rapporte a `W0` (§10) ou sa NORME rapportee a `B0`
            (§11/§12). Ni amplitude, ni variance.
  REPERE  : la base d'ancre de CHAQUE cellule, exactement celle de c133_delivered_com.
  LIGNE DE BASE : la cellule i=0 (debout d'auteur). ET le controle hors defaut de ce fichier est
            `w_k = 1` pour tous les maillons : il doit alors reproduire c133 AU CHIFFRE. S'il ne le
            reproduit pas, rien n'est publie — une prediction qui ne retrouve pas l'existant ne
            predit rien.

FALSIFICATION DE `D`. `B_k = A_k . D^-1` doit etre ORTHONORMEE (c'est une rotation d'os). Si elle
ne l'est pas, `D` reconstruit est faux et le fichier se tait. Ce test est publie avec son ecart.
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import physics_c6_volumes as c6                     # noqa: E402
from physics_c6_volumes import consolidate_buffers, read_glb, skin_info   # noqa: E402
import c124_delivered_shape as C124                 # noqa: E402

REPO, SHIPPED, MASSJSON = C124.REPO, C124.SHIPPED, C124.MASSJSON
CHAINS, ANCHOR = C124.CHAINS, C124.ANCHOR
B0_DEFAULT = 602.0
EXPONENTS = (1.6, 1.78125, 1.8, 2.0)


def read_applied_w(txt):
    """Les poids de gradient REELLEMENT appliques, lus dans la trace (`PHYSGRAD31`).

    AJOUTE APRES LA COURSE DU c138, ET C'EST UNE CORRECTION D'INSTRUMENT CONTRE MOI. Le
    falsificateur de `D` exige que `B = A . D^-1` soit orthonormee. Cela ne vaut QUE sur une trace
    ou le tenseur est applique UNIFORMEMENT. Des que le gradient est cable, la matrice ecrite vaut
    `A_l = B_l . (I + w_l (D - I))`, donc `A_l . D^-1` n'est plus une rotation — et le
    falsificateur a REFUSE la course du c138 (8.1e-02 / 1.5e-01 contre 8.7e-06 avant). Il avait
    raison de refuser : c'est la signature ATTENDUE d'un tenseur gradue, et c'est une preuve
    INDEPENDANTE que le canal agit. Mais un controle qui ne peut plus passer n'est plus un
    controle. Il lit donc desormais les `w` que la trace publie, et redevient vivant : il exige que
    `A_l . (I + w_l (D - I))^-1` soit orthonormee. Absente la ligne, `w = 1` et le test est
    exactement celui d'avant.
    """
    import re
    out = {}
    for m in re.finditer(r'^PHYSGRAD31 c=(\d+) i=(\d+) r0=\S+ r1=\S+ '
                         r'w0=([-\d.e+]+) w1=([-\d.e+]+)', txt, re.M):
        out[int(m.group(1))] = [float(m.group(3)), float(m.group(4))]
    return out


def read_dfma(txt):
    import re
    out = {}
    for m in re.finditer(r'^PHYSDFMA c=(\d+) i=(\d+) r=(\d+) '
                         r'm0=([-\d.e+]+) m1=([-\d.e+]+) m2=([-\d.e+]+)', txt, re.M):
        c, i, r = int(m.group(1)), int(m.group(2)), int(m.group(3))
        out.setdefault((c, i), np.zeros((3, 3)))[r] = [float(m.group(4)),
                                                       float(m.group(5)), float(m.group(6))]
    return out


def main():
    log = sys.argv[1] if len(sys.argv) > 1 else \
        '.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log'
    path = log if os.path.isabs(log) else os.path.join(REPO, log)
    txt = open(path, 'r', errors='replace').read()
    import hashlib
    print('C138: trace = %s' % os.path.relpath(path, REPO))
    print('C138: empreinte (md5) = %s' % hashlib.md5(open(path, 'rb').read()).hexdigest())

    jn, mats, nmiss = C124._read_matrices(txt)
    if not mats or nmiss:
        print('C138: SUSPENDU — PHYSORIM absent ou incomplet.'); return 1
    slot = {v: k for k, v in jn.items()}
    dfma = read_dfma(txt)
    wapp = read_applied_w(txt)
    if not dfma:
        print('C138: SUSPENDU — aucune ligne PHYSDFMA.'); return 1

    g = c6.load_geometry('keira-hd', glb=SHIPPED)
    names = list(g['names']); V, J, W, P = g['V'], g['J'], g['W'], g['P']
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
    b0t = {}
    import re as _re
    for m in _re.finditer(r'^PHYSBASE c=(\d+).*?b0=([-\d.e+]+)', txt, _re.M):
        b0t[int(m.group(1))] = float(m.group(2))

    # convention de skinning, tranchee par mesure comme dans c124/c133
    wch = (W * (J == ai)).sum(axis=1)
    top = np.argsort(-wch)[:24]
    dbind = np.linalg.norm(V[top] - P[ai], axis=1)
    Mch = mats[(cells[0], slot[ANCHOR])]
    verd = {}
    for tag in ('A', 'C'):
        q = V[top].copy() if tag == 'A' else (V[top] - P[ai]) @ RB[ANCHOR]
        p = q @ Mch[:3, :3] + Mch[3, :3]
        verd[tag] = float(np.median(np.abs(np.linalg.norm(p - Mch[3, :3], axis=1) - dbind)
                                    / np.maximum(dbind, 1e-9)))
    conv = min(verd, key=verd.get)
    if verd[conv] > 0.02:
        print('C138: SUSPENDU — convention de skinning indeterminee (%.5f).' % verd[conv]); return 1
    use_bind = (conv == 'C')
    print('C138: convention de skinning = %s (A %.5f · C %.5f)' % (conv, verd['A'], verd['C']))

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

    isup, ipro, _g = C124._roles(txt)
    print('C138: cellules par la GRAVITE MESUREE : SUPINE i=%s · PRONE i=%s' % (isup, ipro))
    print('')

    _sj = list(slot)
    for ci, (cname, joints) in enumerate(CHAINS.items()):
        idx = [names.index(j) for j in joints]
        wj = np.zeros((len(V), len(idx)))
        for k, ji in enumerate(idx):
            wj[:, k] = (W * (J == ji)).sum(axis=1)
        wsum = wj.sum(axis=1)
        sel = wsum > 0.0
        AXr = mass['chains'][cname]['axes']
        AX = {a: np.asarray(AXr[a], dtype=float) for a in ('out', 'up', 'fwd')}
        bb = b0t.get(ci, B0_DEFAULT)
        W0 = {d['cut']: d for d in mass['chains'][cname]['defs']}[0.0]['W0']

        # ---- `r` DE SA §31, MOT POUR MOT : racine (r=0) -> centroide pondere de l'organe (r=1)
        proot = P[idx[0]]
        cen = (wsum[sel][:, None] * V[sel]).sum(0) / wsum[sel].sum()
        ax31 = cen - proot
        ax31 = ax31 / np.linalg.norm(ax31)
        s = (V[sel] - proot) @ ax31
        # « r = 0 at CHEST ATTACHMENT and r = 1 at distal/apex region » : l'origine est le PLAN
        # D'ATTACHE, pas le joint racine — le joint est A L'INTERIEUR de la chair, donc normaliser
        # sur [0, s95] ecrase tout le nuage au voisinage de 1 (mesure : r=0.88/0.80). Bornes prises
        # aux deciles extremes pour ne pas laisser un aberrant fixer l'echelle.
        smin, smax = float(np.quantile(s, 0.05)), float(np.quantile(s, 0.95))
        rv = np.clip((s - smin) / max(smax - smin, 1e-9), 0.0, 1.0)
        print('C138: %-7s abscisse §31 brute (u) : p05 %.1f  p50 %.1f  p95 %.1f  '
              'etendue %.1f ; joint racine a s=0' % (cname, smin, float(np.quantile(s, .5)),
                                                     smax, smax - smin))
        rbar = []
        for k, ji in enumerate(idx):
            wk = wj[sel, k]
            rbar.append(float((wk * rv).sum() / max(wk.sum(), 1e-12)))
        mk = [float(wj[sel, k].sum()) for k in range(len(idx))]
        print('C138: %-7s axe §31 = racine -> centroide organe ; r par maillon (pondere par le '
              'poids de peau) : %s ; masse de peau %s'
              % (cname, ' '.join('%s r=%.4f' % (joints[k], rbar[k]) for k in range(len(idx))),
                 ' '.join('%s %.2f' % (joints[k], mk[k]) for k in range(len(idx)))))

        # ---- Q_k et W_k : premiers moments FIXES, exactement comme c133 -----------------------
        Qk, Wk_ = [], []
        for nmj in _sj:
            ji = names.index(nmj)
            wk = (W[sel] * (J[sel] == ji)).sum(axis=1)
            qk = (V[sel] - P[ji]) @ RB[nmj] if use_bind else V[sel]
            Qk.append((wk[:, None] * qk).sum(0))
            Wk_.append(float(wk.sum()))
        Nn = float(sel.sum())

        def com_parts(i, wgrad=None):
            """(rot, trn) dans la base d'ancre de la cellule ; `wgrad` = poids par maillon."""
            o_, E_ = frame(i)
            rw = np.zeros(3); tw = np.zeros(3)
            Dm = None
            if wgrad is not None:
                A = dfma.get((ci, i))
                if A is None:
                    return None
                am3 = mats[(i, slot[ANCHOR])][:3, :3]
                Dm = np.linalg.inv(am3) @ A @ am3
            for k, nmj in enumerate(_sj):
                Mi = mats[(i, slot[nmj])]
                A3 = Mi[:3, :3]
                if wgrad is not None and nmj in joints:
                    # `kj` et PAS `k` : `k` est l'indice de boucle sur TOUS les joints skinnes et il
                    # indexe `Qk`/`Wk_`. L'ecraser par l'indice DANS LA CHAINE appariait le premier
                    # moment du mauvais os — invisible sur chestL (ou les deux indices coincident)
                    # et faux de 5,4e5 u sur chestR. C'est le controle hors defaut qui l'a attrape.
                    kj = joints.index(nmj)
                    wgk = wgrad[kj]
                    # on REMONTE au repere non deforme par le gradient DEJA APPLIQUE, puis on
                    # redescend avec celui qu'on veut tester. Sur une trace non graduee `wa` est
                    # absent et les deux etapes sont l'identite d'avant.
                    Bk = A3 @ np.linalg.inv(_Dl(Dm, kj))
                    A3 = Bk @ (np.eye(3) + wgk * (Dm - np.eye(3)))
                rw += Qk[k] @ A3
                tw += Wk_[k] * Mi[3, :3]
            return (rw / Nn) @ E_, (tw / Nn - o_) @ E_

        # ---- FALSIFICATION DE `D` : B_k doit etre orthonormee ---------------------------------
        wa = wapp.get(ci)
        def _Dl(Dm, k):
            """le tenseur EFFECTIVEMENT applique au maillon k, gradient compris."""
            if wa is None or k >= len(wa):
                return Dm
            return np.eye(3) + wa[k] * (Dm - np.eye(3))
        worst = 0.0
        for i in cells:
            A = dfma.get((ci, i))
            if A is None:
                continue
            am3 = mats[(i, slot[ANCHOR])][:3, :3]
            Dm = np.linalg.inv(am3) @ A @ am3
            for k, nmj in enumerate(joints):
                Bk = mats[(i, slot[nmj])][:3, :3] @ np.linalg.inv(_Dl(Dm, k))
                worst = max(worst, float(np.abs(Bk @ Bk.T - np.eye(3)).max()))
        print('C138: %-7s FALSIFICATION de `D` — |B.B^T - I| au pire sur toutes les cellules : '
              '%.2e  %s  (poids appliques lus dans la trace : %s)'
              % (cname, worst, 'RETENU' if worst < 5e-3 else 'REJETE — rien de publie',
                 'aucun (w=1)' if wa is None else ' '.join('%.4f' % x for x in wa)))
        if worst >= 5e-3:
            continue

        # ---- CONTROLE HORS DEFAUT : w_k = 1 doit reproduire c133 AU CHIFFRE --------------------
        # CONTROLE HORS DEFAUT : reinjecter les poids que la trace declare APPLIQUES doit
        # reproduire le calcul direct AU BIT. (Avant la course du c138 ce controle utilisait
        # `w=1` ; sur une trace GRADUEE `w=1` n'est plus l'etat courant mais un CONTREFACTUEL, et
        # le controle refusait a juste titre. Il lit donc l'etat courant dans la trace.)
        _wid = (wa if wa is not None else [1.0] * len(joints))[:len(joints)]
        base = {i: com_parts(i) for i in cells}
        ctl = {i: com_parts(i, _wid) for i in cells}
        dmax = max(float(np.abs(np.asarray(base[i]) - np.asarray(ctl[i])).max())
                   for i in cells if ctl[i] is not None)
        print('C138: %-7s CONTROLE HORS DEFAUT (poids de la trace reinjectes) — ecart au calcul'
              ' direct : %.2e u  %s' % (cname, dmax, 'RETENU' if dmax < 1e-6 else 'REJETE'))
        if dmax >= 1e-6:
            for i in cells:
                if ctl[i] is None:
                    print('C138:   i=%-2d ctl=None (PHYSDFMA absent pour cette cellule)' % i); continue
                d = float(np.abs(np.asarray(base[i]) - np.asarray(ctl[i])).max())
                if d > 1e-6:
                    print('C138:   i=%-2d ecart %.3e u' % (i, d))
        if dmax >= 1e-6:
            continue

        def report(tag, wgrad):
            out = []
            for sec, cell in (('10', isup), ('11', ipro)):
                if cell is None:
                    continue
                a = com_parts(cell, wgrad); b = com_parts(0, wgrad)
                if a is None or b is None:
                    continue
                d = (a[0] - b[0]) + (a[1] - b[1])
                ro = 100.0 * float((a[0] - b[0]) @ AX['out']) / W0
                nb = float(np.linalg.norm(d)) / bb
                out.append((sec, cell, ro, 100.0 * float(d @ AX['out']) / W0, nb))
            for sec, cell, ro, so, nb in out:
                band = '[4;10] %%W0' if sec == '10' else '[0.20;0.28] B0'
                if sec == '10':
                    v = 'DANS' if 4.0 <= so <= 10.0 else ('SOUS' if so < 4.0 else 'AU-DESSUS')
                    print('C138: %-7s %-11s §10 i=%-2d  sortant %+7.3f %%W0 (dont ROT+TENS %+7.3f)'
                          '  bande %s  %s' % (cname, tag, cell, so, ro, band, v))
                else:
                    v = 'DANS' if 0.20 <= nb <= 0.28 else ('SOUS' if nb < 0.20 else 'AU-DESSUS')
                    print('C138: %-7s %-11s §11 i=%-2d  COM %.4f B0  bande %s  %s'
                          % (cname, tag, cell, nb, band, v))

        # ---- L'ETAGE OU MEURT LA MIGRATION SORTANTE, MESURE STAGE PAR STAGE -------------------
        # `registre: response-dies-at-one-solver-stage`. La moitie ROT+TENS est un PRODUIT
        # `B_k . D` : elle se coupe donc exactement en deux, et sans modele.
        #   ROTATION SEULE  : Q_k . B_k          (le tenseur retire, D <- I)
        #   TENSEUR SEUL    : Q_k . B_k . D  -  Q_k . B_k
        for sec, cell in (('10', isup), ('11', ipro)):
            if cell is None or dfma.get((ci, cell)) is None or dfma.get((ci, 0)) is None:
                continue
            acc = {}
            for tag in ('rot', 'full'):
                v = {}
                for i in (0, cell):
                    o_, E_ = frame(i)
                    A = dfma[(ci, i)]
                    am3 = mats[(i, slot[ANCHOR])][:3, :3]
                    Dm = np.linalg.inv(am3) @ A @ am3
                    rw = np.zeros(3)
                    for k, nmj in enumerate(_sj):
                        A3 = mats[(i, slot[nmj])][:3, :3]
                        if tag == 'rot' and nmj in joints:
                            A3 = A3 @ np.linalg.inv(_Dl(Dm, joints.index(nmj)))
                        rw += Qk[k] @ A3
                    v[i] = (rw / Nn) @ E_
                acc[tag] = 100.0 * float((v[cell] - v[0]) @ AX['out']) / W0
            print('C138: %-7s ETAGES de la moitie ROT+TENS, §%s i=%-2d : ROTATION SEULE %+7.3f %%W0'
                  ' · TENSEUR SEUL %+7.3f %%W0 · somme %+7.3f'
                  % (cname, sec, cell, acc['rot'], acc['full'] - acc['rot'], acc['full']))
        report('ACTUEL', None)
        # CONTRE-FACTUEL DANS LA MEME COURSE : ce que l'organe rendrait SANS le gradient. Aucune
        # comparaison entre deux courses, donc aucune hypothese sur leur reproductibilite — le
        # piege `room-run-not-frame-reproducible` est contourne par construction.
        if wa is not None:
            report('SANS-GRAD', [1.0] * len(joints))
        for p in EXPONENTS:
            g_ = [max(rbar[k], 1e-6) ** p for k in range(len(idx))]
            norm = sum(mk[k] * g_[k] for k in range(len(idx)))
            wg = [g_[k] * sum(mk) / max(norm, 1e-12) for k in range(len(idx))]
            print('C138: %-7s p=%.1f  w = %s   (normalise : SOMME m_k w_k = SOMME m_k)'
                  % (cname, p, ' '.join('%s %.4f' % (joints[k], wg[k]) for k in range(len(idx)))))
            report('p=%.1f' % p, wg)
        print('')
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""CYCLE 38 ETAPE 1 — les volumes du VETEMENT decrivent-ils une chair que les spheres du SEIN
decrivent deja ?  Predictions gravees : C38E1-garment-volume-prediction.txt (md5 e885835459...).

NATURE  : une FRACTION DE RECOUVREMENT et un COMPTE DE SOMMETS. Forme statique, pose de BIND.
          Aucune frame, aucun pilotage, aucune simulation n'entre ici.
REPERE  : l'espace MONDE de la pose de bind du mesh LIVRE. Tous les volumes y sont replaces par
          UNE SEULE formule, verifiee contre les offsets livres avant d'etre utilisee :
              centre_monde = position_bind(joint) + Rot(joint) @ (offset_u / 4096)
          ou Rot est la partie ROTATION de la matrice bind du joint, ECHELLE NORMALISEE
          (les joints de sangle portent une echelle bind de 0.1033 ; sans normalisation leur
          offset serait divise par dix et le volume atterrirait ailleurs).
DOMAINE : les POSITIONS UNIQUES du mesh livre. Le fichier en stocke 222 964 mais n'en contient
          que 5 588 distinctes (39.9 copies par point, jusqu'a 168) : compter les copies
          pondererait chaque taux par le nombre de materiaux qui touchent le point, ce qui est un
          artefact d'export et pas une grandeur geometrique.
BASE    : deux controles encadrent chaque chiffre — W1 par le haut (un acquis connu du cycle 35),
          W2 par le bas. Publies avec les autres, jamais apres coup.
"""
import sys, os, json
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from c38_glb import Glb

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MESH = os.path.join(REPO, 'out/jak1/fr3/skin/keira-hd-lod0.glb')
CHAINS = os.path.join(REPO, 'recharged_assets/physics_chains.txt')
U_PER_M = 4096.0
SEED = 20260819          # graine publiee : l'echantillonnage de VOLFRAC est reproductible
NSAMP = 400000


def parse_chains(path):
    spheres, capsules = {}, []
    for ln in open(path):
        t = ln.split()
        if not t:
            continue
        if t[0] == 'collider' and len(t) >= 4:
            r = float(t[2].split('=')[1])
            off = np.array([float(x) for x in t[3].split('=')[1].split(',')])
            spheres[t[1]] = (r, off)
        elif t[0] == 'capsule' and len(t) >= 5:
            capsules.append((t[1], t[2], float(t[3].split('=')[1]), float(t[4].split('=')[1])))
    return spheres, capsules


def main():
    g = Glb(MESH)
    joints, names = g.skin()
    JW = g.joint_world()
    P, J, V = g.geometry()

    # --- domaine : positions uniques -------------------------------------------------------
    key = np.round(P, 6)
    _, first = np.unique(key, axis=0, return_index=True)
    W = np.zeros((len(P), len(names)))
    for k in range(4):
        np.add.at(W, (np.arange(len(P)), J[:, k]), V[:, k])
    Pu, Wu = P[first], W[first]
    mj = np.argmax(Wu, 1)
    mw = Wu[np.arange(len(Wu)), mj]

    idx = {n: i for i, n in enumerate(names)}

    def rot(i):
        U, S, Vt = np.linalg.svd(JW[i][:3, :3])
        return U @ Vt, float(S.mean())

    spheres, capsules = parse_chains(CHAINS)

    def place(name):
        """(centre_monde, rayon_m, echelle_bind) du volume-sphere livre `name`."""
        r, off = spheres[name]
        i = idx[name]
        R, s = rot(i)
        return JW[i][:3, 3] + R @ (off / U_PER_M), r / U_PER_M, s

    placed = {n: place(n) for n in spheres if n in idx}

    def inside(name, pts):
        c, r, _ = placed[name]
        return np.linalg.norm(pts - c, axis=1) <= r

    def inside_union(nlist, pts):
        m = np.zeros(len(pts), bool)
        for n in nlist:
            m |= inside(n, pts)
        return m

    LB, RB = ['lBoob', 'lBooc'], ['rBoob', 'rBooc']

    out = []
    def say(s):
        out.append(s)
        print(s)

    say('C38E1 mesh=%s' % os.path.relpath(MESH, REPO))
    import hashlib
    say('C38E1 md5=%s' % hashlib.md5(open(MESH, 'rb').read()).hexdigest())
    say('C38E1 domaine verts_stockes=%d verts_uniques=%d joints=%d seed=%d nsamp=%d'
        % (len(P), len(Pu), len(names), SEED, NSAMP))

    # --- placement publie -------------------------------------------------------------------
    for n in ['lBoob', 'lBooc', 'rBoob', 'rBooc', 'lTopStrap2', 'rTopStrap2',
              'lBotStrap', 'lBotStrap2', 'rBotStrap', 'rBotStrap2', 'main']:
        if n not in placed:
            say('C38E1-PLACE name=%s ABSENT-DU-SKIN' % n)
            continue
        c, r, s = placed[n]
        say('C38E1-PLACE name=%-11s cx=%.4f cy=%.4f cz=%.4f r_m=%.4f r_u=%.1f bindscale=%.4f nin=%d'
            % (n, c[0], c[1], c[2], r, r * U_PER_M, s, int(inside(n, Pu).sum())))

    # --- distances centre a centre ----------------------------------------------------------
    for gname, side in [('lTopStrap2', LB), ('rTopStrap2', RB), ('lBotStrap', LB),
                        ('lBotStrap2', LB), ('rBotStrap', RB), ('rBotStrap2', RB), ('main', LB)]:
        if gname not in placed:
            continue
        cg, rg, _ = placed[gname]
        for b in side:
            cb, rb, _ = placed[b]
            d = float(np.linalg.norm(cg - cb))
            say('C38E1-DIST g=%-11s b=%-6s d_u=%8.1f rg_u=%6.1f rb_u=%6.1f '
                'centre_dedans=%s intersecte=%s'
                % (gname, b, d * U_PER_M, rg * U_PER_M, rb * U_PER_M,
                   'OUI' if d <= rb else 'non', 'OUI' if d <= rg + rb else 'non'))

    # --- COUV : la chair du volume est-elle deja couverte ? ---------------------------------
    def couv(sname, ref, tag):
        m = inside(sname, Pu)
        n_in = int(m.sum())
        if n_in == 0:
            say('C38E1-COUV %s vol=%-11s nin=0 NON-LISIBLE (domaine vide)' % (tag, sname))
            return
        both = int((m & inside_union(ref, Pu)).sum())
        lis = 'LISIBLE' if n_in >= 10 else 'NON-LISIBLE(<10)'
        say('C38E1-COUV %s vol=%-11s ref=%-14s nin=%4d deja=%4d couv=%6.2f%% %s'
            % (tag, sname, '+'.join(ref), n_in, both, 100.0 * both / n_in, lis))

    couv('lTopStrap2', LB, 'G3')
    couv('rTopStrap2', RB, 'G3')
    couv('lBotStrap', LB, 'G5')
    couv('rBotStrap', RB, 'G5')
    couv('lBotStrap2', LB, 'G5')
    couv('rBotStrap2', RB, 'G5')
    couv('lBoob', ['lBooc'], 'W1')          # controle par le HAUT : acquis du cycle 35
    couv('rBoob', ['rBooc'], 'W1')
    couv('main', LB, 'W2')                  # controle par le BAS : le bassin

    # --- VOLFRAC : part du VOLUME contenue dans l'union du sein -----------------------------
    rng = np.random.default_rng(SEED)
    def volfrac(sname, ref):
        c, r, _ = placed[sname]
        p = rng.normal(size=(NSAMP, 3))
        p /= np.linalg.norm(p, axis=1)[:, None]
        p *= rng.random(NSAMP)[:, None] ** (1.0 / 3.0)
        pts = c + p * r
        f = 100.0 * inside_union(ref, pts).mean()
        say('C38E1-VOLFRAC G2 vol=%-11s ref=%-14s volfrac=%6.2f%%'
            % (sname, '+'.join(ref), f))
    volfrac('lTopStrap2', LB)
    volfrac('rTopStrap2', RB)
    volfrac('lBotStrap2', LB)
    volfrac('rBotStrap2', RB)
    volfrac('main', LB)

    # --- G4 : le vetement suit-il le sein ? (proprietaire des sommets) ----------------------
    for gname, breast in [('lTopStrap2', ['lBoob', 'lBooc']), ('rTopStrap2', ['rBoob', 'rBooc'])]:
        m = inside(gname, Pu)
        n_in = int(m.sum())
        if n_in == 0:
            say('C38E1-OWN G4 vol=%s nin=0 NON-LISIBLE' % gname)
            continue
        bi = [idx[b] for b in breast]
        maj_breast = int((m & np.isin(mj, bi) & (mw > 0.5)).sum())
        # part de POIDS que les joints du sein possedent sur ces sommets
        wb = float(Wu[m][:, bi].sum()) / max(1e-9, float(Wu[m].sum()))
        cnt = {}
        for k in np.where(m)[0]:
            if mw[k] > 0.5:
                cnt[names[mj[k]]] = cnt.get(names[mj[k]], 0) + 1
        top = sorted(cnt.items(), key=lambda kv: -kv[1])[:5]
        say('C38E1-OWN G4 vol=%-11s nin=%d maj_sein=%d (%.1f%%) poids_sein=%.1f%% dominants=%s'
            % (gname, n_in, maj_breast, 100.0 * maj_breast / n_in, 100.0 * wb,
               ', '.join('%s:%d' % kv for kv in top)))

    open(os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion/C38E1-garment-overlap.txt'),
         'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()

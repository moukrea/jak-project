#!/usr/bin/env python3
"""CYCLE 38 ETAPE 3 — dans combien de volumes livres chaque joint de sein est-il deja enfoui, a la
POSE D'AUTEUR ?  Predictions gravees : C38E3-nested-volumes-prediction.txt (md5 84b4849214...).

NATURE / REPERE / BASE : voir le fichier de predictions. Resume :
  NATURE  un COMPTE de volumes contenants et une PROFONDEUR SIGNEE, statiques.
  REPERE  monde-bind du mesh LIVRE, volumes replaces par la formule verifiee a l'etape 1.
  FORMULE transcrite de `phys-collide-depth` (jak-hd-physics.gc:1068-1145) : distance signee au
          TRONC DE CONE, MINIMISEE sur [0,1] — surtout pas « projeter puis interpoler le rayon »,
          qui designe un autre solide (faute corrigee dans le moteur au cycle 22).
"""
import sys, os, hashlib
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from c38_glb import Glb

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MESH = os.path.join(REPO, 'out/jak1/fr3/skin/keira-hd-lod0.glb')
CHAINS = os.path.join(REPO, 'recharged_assets/physics_chains.txt')
U = 4096.0


def cone_depth(p, ca, cb, ra, rb, capsule):
    """Profondeur SIGNEE (>0 = dedans), transcription exacte de `phys-collide-depth`."""
    if not capsule:
        return ra - np.linalg.norm(p - ca)
    a = cb - ca
    dd = float(a @ a)
    dr = rb - ra
    a2 = dd - dr * dr
    if dd < 1e-6:
        c, rr = ca, max(ra, rb)
    elif a2 <= 1e-6:
        c, rr = (ca, ra) if ra >= rb else (cb, rb)
    else:
        pv = p - ca
        t0 = float(pv @ a) / dd
        if dr != 0.0:
            q = pv - a * t0
            yy = float(np.linalg.norm(q))
            t0 += (dr * yy) / (np.sqrt(dd) * np.sqrt(a2))
        t0 = min(1.0, max(0.0, t0))
        c = ca + a * t0
        rr = ra + dr * t0
    return rr - float(np.linalg.norm(p - c))


def main():
    g = Glb(MESH)
    joints, names = g.skin()
    JW = g.joint_world()
    idx = {n: i for i, n in enumerate(names)}

    def rot(i):
        Uu, S, Vt = np.linalg.svd(JW[i][:3, :3])
        return Uu @ Vt

    def jpos(n):
        return JW[idx[n]][:3, 3] * U          # tout en unites de jeu

    vols = []   # (nom, ca, cb, ra, rb, capsule?)
    for ln in open(CHAINS):
        t = ln.split()
        if not t:
            continue
        if t[0] == 'collider' and len(t) >= 4:
            n = t[1]
            if n not in idx:
                continue
            r = float(t[2].split('=')[1])
            off = np.array([float(x) for x in t[3].split('=')[1].split(',')])
            c = jpos(n) + rot(idx[n]) @ off
            vols.append(('sphere:' + n, c, c, r, r, False))
        elif t[0] == 'capsule' and len(t) >= 5:
            a, b = t[1], t[2]
            if a not in idx or b not in idx:
                continue
            vols.append(('caps:%s->%s' % (a, b), jpos(a), jpos(b),
                         float(t[3].split('=')[1]), float(t[4].split('=')[1]), True))

    out = []
    def say(s):
        out.append(s); print(s)

    say('C38E3 mesh=%s md5=%s' % (os.path.relpath(MESH, REPO),
                                  hashlib.md5(open(MESH, 'rb').read()).hexdigest()))
    say('C38E3 domaine volumes=%d joints_rig=%d' % (len(vols), len(names)))

    # ---- X2 : le temoin sur la TRANSCRIPTION, avant tout le reste ------------------------------
    # LE CRITERE GRAVE ETAIT MATHEMATIQUEMENT FAUX, ET IL EST PUBLIE COMME REFUTE.
    # J'avais grave : « un point pose a rayon+100 u sur la perpendiculaire a l'axe en A rend -100 u ».
    # C'est vrai d'une CAPSULE (ra == rb) et FAUX de tout TRONC DE CONE : la surface y est inclinee,
    # donc le point le plus proche n'est pas sur la sphere de A. Or les 30 capsules livrees sont
    # TOUTES coniques — le moteur le dit lui-meme. Mesure du critere tel que grave : jusqu'a
    # 71.29 u d'ecart. Il ne mesurait pas la transcription, il mesurait mon erreur de geometrie.
    # LE TEMOIN CORRECT, plus fort que celui que je remplace, en deux volets :
    #   X2a  cas ra == rb : la, et la seulement, le critere grave est exact -> il DOIT rendre -100.
    #   X2b  accord avec la SDF CANONIQUE du round cone (Inigo Quilez), ecrite independamment de
    #        la transcription GOAL, sur 3000 points au hasard pour CHACUNE des paires de rayons
    #        livrees. C'est la comparaison que le moteur cite lui-meme au cycle 22
    #        (`sd_round_cone` contre `sd_engine`).
    def sd_round_cone(p, a, b, r1, r2):
        ba = b - a; l2 = float(ba @ ba); rr = r1 - r2
        a2 = l2 - rr * rr; il2 = 1.0 / l2
        pa = p - a
        y = float(pa @ ba); z = y - l2
        xv = pa * l2 - ba * y; x2 = float(xv @ xv)
        y2 = y * y * l2; z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        if np.sign(z) * a2 * z2 > k:
            return np.sqrt(max(0.0, x2 + z2)) * il2 - r2
        if np.sign(y) * a2 * y2 < k:
            return np.sqrt(max(0.0, x2 + y2)) * il2 - r1
        return (np.sqrt(max(0.0, x2 * a2 * il2)) + y * rr) * il2 - r1

    a0 = np.array([0.0, 0.0, 0.0]); b0 = np.array([500.0, 0.0, 0.0])
    x2a = abs(cone_depth(np.array([0.0, 200.0, 0.0]), a0, b0, 100.0, 100.0, True) - (-100.0))
    rng0 = np.random.default_rng(7)
    worst_grave, x2b, npts = 0.0, 0.0, 0
    degen = []
    for nm, ca, cb, ra, rb, cap in vols:
        if not cap:
            continue
        ax = cb - ca
        nv = np.cross(ax, [0.0, 0.0, 1.0])
        if np.linalg.norm(nv) < 1e-9:
            nv = np.cross(ax, [0.0, 1.0, 0.0])
        nv = nv / np.linalg.norm(nv)
        worst_grave = max(worst_grave,
                          abs(cone_depth(ca + nv * (ra + 100.0), ca, cb, ra, rb, True) - (-100.0)))
        L = float(np.linalg.norm(cb - ca))
        # La SDF canonique n'est DEFINIE que hors du cas degenere L^2 <= dr^2 : la, une sphere
        # contient l'autre, il n'existe aucun tronc de cone, et le moteur prend deliberement une
        # autre branche (« le solide EST la grosse », son commentaire :1115-1118). Comparer les
        # deux sur ce cas mesurerait un desaccord de DEFINITION, pas une erreur de transcription.
        # Les capsules degenerees sont donc exclues de X2b et COMPTEES a part, parce que leur
        # existence est un fait a publier : deux volumes livres sur trente ne sont pas des capsules.
        if L * L - (rb - ra) ** 2 <= 1e-6:
            degen.append((nm, ra, rb, L))
            continue
        B = np.array([L, 0.0, 0.0])
        for _ in range(3000):
            p = (rng0.random(3) - 0.5) * 4000.0
            x2b = max(x2b, abs(cone_depth(p, a0, B, ra, rb, True) + sd_round_cone(p, a0, B, ra, rb)))
            npts += 1
    say('C38E3-X2 GRAVE-REFUTE pire_ecart=%.4fu (critere faux sur un CONE, exact sur une capsule)'
        % worst_grave)
    say('C38E3-X2a capsule_ra_egal_rb ecart=%.6fu ok=%d' % (x2a, 1 if x2a <= 0.5 else 0))
    say('C38E3-X2b accord_SDF_canonique pire_ecart=%.6fu points=%d ok=%d'
        % (x2b, npts, 1 if x2b <= 0.5 else 0))
    say('C38E3-DEGEN capsules_degenerees=%d/%d  %s'
        % (len(degen), sum(1 for v in vols if v[5]),
           ', '.join('%s(ra=%.0f rb=%.0f L=%.0f -> sphere r=%.0f)' % (n, a, b, l, max(a, b))
                     for n, a, b, l in degen) or 'aucune'))
    ok2 = (x2a <= 0.5 and x2b <= 0.5)
    if not ok2:
        say('C38E3-X2 ECHEC : transcription du solveur fausse. AUCUN verdict publie.')
        return

    # ---- U1..U5 et X1 --------------------------------------------------------------------------
    def census(jn, tag):
        p = jpos(jn)
        hits = []
        for nm, ca, cb, ra, rb, cap in vols:
            if nm in ('sphere:' + jn,):
                continue                      # son propre volume ne le contient pas « en obstacle »
            d = cone_depth(p, ca, cb, ra, rb, cap)
            if d > 0.0:
                hits.append((nm, d))
        hits.sort(key=lambda kv: -kv[1])
        say('C38E3-NEST %s joint=%-11s nvol=%d  %s'
            % (tag, jn, len(hits), ', '.join('%s:%.0fu' % kv for kv in hits[:8])))
        return len(hits), hits

    nb = {}
    for jn in ['lBoob', 'lBooc', 'rBoob', 'rBooc']:
        nb[jn] = census(jn, 'U1')
    for jn in ['Lelbow', 'Lankle', 'Lhand']:
        nb[jn] = census(jn, 'X1/U5')

    med = float(np.median([nb[j][0] for j in ['lBoob', 'lBooc', 'rBoob', 'rBooc']]))
    say('C38E3-U5 median_sein=%.1f  Lelbow=%d  Lankle=%d  Lhand=%d'
        % (med, nb['Lelbow'][0], nb['Lankle'][0], nb['Lhand'][0]))

    # ---- U2 : la plus grande profondeur dans une capsule de BUSTE ------------------------------
    TORSO = ('caps:chest->main', 'caps:neck->chest', 'caps:head->neck',
             'caps:Lshoulder->chest', 'caps:Rshoulder->chest', 'caps:hips->main')
    for jn in ['lBoob', 'lBooc', 'rBoob', 'rBooc']:
        best = max(((nm, d) for nm, d in nb[jn][1] if nm in TORSO),
                   key=lambda kv: kv[1], default=None)
        say('C38E3-U2 joint=%-7s plus_profonde_buste=%s'
            % (jn, ('%s %.0fu' % best) if best else 'AUCUNE'))

    # ---- U3 / U4 : les volumes nommes, verdict explicite ----------------------------------------
    for cap, targets in [('caps:Rshoulder->chest', ['lBoob', 'lBooc']),
                         ('caps:Lshoulder->chest', ['rBoob', 'rBooc']),
                         ('caps:neck->chest', ['lBoob', 'lBooc', 'rBoob', 'rBooc'])]:
        v = [x for x in vols if x[0] == cap][0]
        res = []
        for jn in targets:
            d = cone_depth(jpos(jn), v[1], v[2], v[3], v[4], v[5])
            res.append('%s:%+.0fu' % (jn, d))
        tagn = 'U3' if 'shoulder' in cap else 'U4'
        say('C38E3-%s vol=%-24s %s' % (tagn, cap, '  '.join(res)))

    open(os.path.join(REPO, '.autoport/reports/Grecharged-secondary-motion/C38E3-nested-volumes.txt'),
         'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()

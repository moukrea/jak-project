#!/usr/bin/env python3
"""probe_mesh_vs_capsule_fidelity.py — LES QUATRE CHIFFRES QUE L'OWNER RECLAME DEPUIS DES JOURS.

D'OU VIENT LA QUESTION, MOT POUR MOT (DIRECTIVES, « SUGGESTION TECHNIQUE DE L'OWNER — COLLIDERS
DERIVES DU MESH, PAS DU RIG ») :

    « Pourquoi deriver du rig et pas du mesh en suivant ses deformations avec plus ou moins
      d'accuracy en fonction de la precision demandee (reduire les tris du mesh collider en
      fonction du niveau de precision) plutot que des capsules ? Je sais pas si c'est mieux,
      c'est une suggestion. »

Les DIRECTIVES exigent QUATRE chiffres avant de trancher : fidelite, cout par frame, deformation,
niveaux. Aucun n'avait ete produit. Ce script produit ceux qui se calculent HORS LIGNE et dit
explicitement lesquels ne s'y calculent pas — il ne tranche pas, il chiffre.

TROIS MESURES INDEPENDANTES DESIGNENT DEJA CETTE REPONSE, et c'est pour ca qu'on la chiffre :
  * les lunettes clipent avec les seins MEME A L'ARRET (6e passe de l'owner : « donc c'est pas
    juste les capsules de collision qui bougent pas, mais plutot mes capsules de collision qui
    sont pas bonnes ») ;
  * le pan de pantacourt est AVALE par le mollet (11e passe : « comme si son pantacourt
    s'arretait aux genoux ») ;
  * `.autoport/reports/Grecharged-secondary-motion/chain-volume-capture.txt` : les languettes de
    genou sont geometriquement incapables de quitter la capsule de cuisse.

------------------------------------------------------------------------------------------------
LES TROIS QUESTIONS DE LA SPEC 7, REPONDUES AVANT D'ECRIRE LA MESURE
------------------------------------------------------------------------------------------------

MESURE A — FIDELITE DE L'UNION DES 48 VOLUMES LIVRES
  NATURE   : une DISTANCE SIGNEE, en unites de jeu (4096 u = 1 m). Ni une amplitude, ni une
             variance, ni une frequence : le defaut decrit par l'owner est une FORME qui n'est pas
             epousee. Pour chaque sommet du mesh, la distance signee au bord de l'UNION des 48
             volumes. POSITIF = la vraie surface DEBORDE de l'union (une chaine qui passe la ne
             rencontre rien : c'est « ca clipe »). NEGATIF = l'union AVALE la vraie surface (c'est
             le sein enfoui sous une sphere trop grosse, la languette enfouie dans la cuisse).
  REPERE   : le monde a la POSE DE BIND du rig (`geo['P']`, tire des matrices inverse-bind du GLB,
             en unites de jeu) — le repere ou le generateur mesure ses rayons et ou le moteur pose
             ses volumes quand aucune animation ne joue. Aucune position simulee n'y entre : on
             mesure la FORME de l'obstacle, pas son mouvement.
  LECTURE QUAND LE DEFAUT EST ABSENT : 0.0000 des deux cotes, et 0 % de sommets dehors. Un
             collider qui epouse exactement la forme a sa surface confondue avec celle du mesh.
             C'est exactement ce que rend le CONTROLE NEGATIF ci-dessous.

MESURE B — ECART D'UN COLLIDER ISSU DU MESH DECIME
  NATURE   : une DISTANCE EUCLIDIENNE NON SIGNEE point -> triangle, unites de jeu. De chaque
             sommet de la vraie surface au triangle le plus proche de la surface decimee. Elle dit
             de combien la surface simplifiee s'est ECARTEE de la vraie.
  REPERE   : le meme, monde a la pose de bind. Les deux mesures sont donc directement comparables,
             c'est le point de tout l'exercice.
  LECTURE QUAND LE DEFAUT EST ABSENT : 0.0000. Le CONTROLE NEGATIF l'exige sur le mesh COMPLET.

MESURE C — COMPTE D'OPERATIONS PAR FRAME
  Ce n'est PAS une mesure : c'est de l'arithmetique sur le fichier de donnees et sur la structure
  de boucle du moteur (references de ligne donnees). Etiquetee comme telle partout ou elle sort.
  Aucun device n'est dans la boucle de ce script et aucune implementation mesh n'existe : la
  publier comme un temps serait une invention.

MESURE D — SKINNING
  NATURE   : des COMPTES (sommets a re-transformer, influences osseuses par sommet). Les
             influences sont MESUREES sur le mesh (nombre de poids non nuls par sommet), pas
             supposees.

------------------------------------------------------------------------------------------------
LES DEUX CONTROLES — SANS EUX LES CHIFFRES NE VALENT RIEN. Le script SORT EN 1 s'ils ne tirent pas.
------------------------------------------------------------------------------------------------
  CONTROLE NEGATIF (borne basse d'erreur) : le mesh COMPLET pris comme collider doit rendre 0.
      Deux etages, parce qu'un seul ne prouverait rien.
      ETAGE 1 : des points SUR la surface (sommets, barycentres interieurs, milieux d'aretes)
        doivent rendre 0 contre tout le mesh. Une routine qui rendrait TOUJOURS zero passerait
        cet etage — d'ou l'etage 2.
      ETAGE 2 : pour CHAQUE triangle, trois points dont la distance A CE TRIANGLE vaut une valeur
        CONNUE par construction geometrique, un dans chacune des trois familles de regions de
        Voronoi (face, arete, sommet). Ils verifient que la routine rend la distance EXACTE et
        que chacune de ses branches est juste. Si l'un ne rend pas sa valeur, la distance est
        fausse et tout le reste du fichier est nul.
  CONTROLE POSITIF (borne haute) : UNE SEULE sphere englobant tout le personnage doit rendre un
      `inside_max` enorme, de l'ordre de la demi-hauteur du personnage. Il donne l'echelle contre
      laquelle lire les 48 volumes actuels : sans lui, « inside_max = 0.21 m » n'a pas d'echelle.

------------------------------------------------------------------------------------------------
CE QUE CE SCRIPT NE FAIT PAS. Il ne modifie aucun volume livre, ne « corrige » aucun rayon,
n'implemente pas le collider mesh et ne conclut pas sur ce qu'il faut faire. Il imprime des
nombres, et il nomme ce qui manque.

Rejeu :  python3 .autoport/probe_mesh_vs_capsule_fidelity.py
"""
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.abspath(os.path.join(HERE, '..')), 'scripts', 'shell'))

import physics_keira_gen2 as g                      # noqa: E402  (le generateur EST la source du rig)
import probe_chain_volume_capture as cvc            # noqa: E402  (meme lecture du fichier de donnees)
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor   # noqa: E402

UNITS = 4096.0
OUT_REL = '.autoport/reports/Grecharged-secondary-motion/mesh-vs-capsule-fidelity.txt'
ROOM_REL = '.autoport/reports/Grecharged-secondary-motion/keira-room-table.txt'

BUDGETS = (48, 200, 500, 1000, 2000)
EPS_ZERO = 1e-6          # unites de jeu : au-dela, la distance a la surface elle-meme n'est pas 0
NORMAL_PROBE = 137.0     # decalage connu le long de la normale, unites de jeu (33 mm)

# structure de boucle du solveur, relevee dans goal_src/jak1/pc/jak-hd-physics.gc — chaque nombre
# porte sa ligne. Rien ici n'est estime.
LOOP_COLLIDE_CALLS = 8 + 3     # :3116-3118 (8 tours) + :3144-3146 (3 tours de finition)
LOOP_SWEEPS = 3                # argument `sweeps` passe a phys-collide-chain, :3118 et :3146
DEPTH_PER_VOLUME = 3           # floors + floorc + dep, :1925-1931
RETREAT_CALLS = 3              # phys-retreat-chain, une fois par tour de finition, :3145
RETREAT_STEPS = 13             # (dotimes (it 13)), :2439


# ==================================================================================================
# 1. LE MESH : SOMMETS, TRIANGLES, POIDS
# ==================================================================================================
def load_triangles(geo):
    """Les triangles du modele, reindexes sur `geo['V']`.

    `physics_c6_volumes._gather_model_vertices` ne garde que les sommets que les primitives de CE
    fichier indexent (le buffer POSITION couvre tout le pool merc du niveau) et les renumerote par
    ordre croissant d'indice global. On refait exactement le meme tri pour que les indices de
    triangle designent les memes sommets que ceux que tout le reste du script mesure."""
    js, bufs = read_glb(geo['path'])
    binc = consolidate_buffers(js, bufs)
    used = set()
    prims = []
    for mesh in js.get('meshes', []):
        for pr in mesh.get('primitives', []):
            if pr.get('mode', 4) != 4:
                raise SystemExit('primitive non-triangulaire dans %s' % geo['path'])
            idx = read_accessor(js, binc, pr['indices']).reshape(-1)
            used.update(idx.tolist())
            prims.append(idx.reshape(-1, 3))
    gidx = np.fromiter(sorted(used), dtype=np.int64)
    remap = -np.ones(int(gidx.max()) + 1, dtype=np.int64)
    remap[gidx] = np.arange(len(gidx))
    F = np.concatenate([remap[p] for p in prims], axis=0)
    if F.min() < 0 or F.max() >= len(geo['V']):
        raise SystemExit('les indices de triangle ne retombent pas sur les sommets du modele')
    return F


def drop_degenerate(V, F):
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    return F[area > 1e-9], int((area <= 1e-9).sum())


# ==================================================================================================
# 2. DISTANCE POINT -> TRIANGLE, EXACTE, ET SON ACCELERATION PAR GRILLE
# ==================================================================================================
def tri_d2(p, a, b, c):
    """Carre de la distance de points aux triangles (a,b,c). Decomposition en regions de Voronoi
    (face / trois aretes / trois sommets) : c'est la forme exacte, pas une projection sur le plan
    qui serait fausse des que le point se projette hors du triangle.

    `p` doit se diffuser sur `a` : soit (1,3) — un point contre T triangles — soit (T,3) — le
    point i contre le triangle i, appariement utilise par le controle negatif."""
    ab = b - a
    ac = c - a
    ap = p - a
    d1 = (ab * ap).sum(1)
    d2 = (ac * ap).sum(1)
    bp = p - b
    d3 = (ab * bp).sum(1)
    d4 = (ac * bp).sum(1)
    cp = p - c
    d5 = (ab * cp).sum(1)
    d6 = (ac * cp).sum(1)
    va = d3 * d6 - d5 * d4
    vb = d5 * d2 - d1 * d6
    vc = d1 * d4 - d3 * d2
    den = va + vb + vc
    s = np.where(np.abs(den) < 1e-30, 1.0, den)
    q = a + ab * (vb / s)[:, None] + ac * (vc / s)[:, None]

    def seg(u, uv, num, dn):
        t = np.where(np.abs(dn) < 1e-30, 0.0, num / np.where(np.abs(dn) < 1e-30, 1.0, dn))
        return u + uv * np.clip(t, 0.0, 1.0)[:, None]

    q = np.where(((vc <= 0) & (d1 >= 0) & (d3 <= 0))[:, None], seg(a, ab, d1, d1 - d3), q)
    q = np.where(((vb <= 0) & (d2 >= 0) & (d6 <= 0))[:, None], seg(a, ac, d2, d2 - d6), q)
    q = np.where(((va <= 0) & ((d4 - d3) >= 0) & ((d5 - d6) >= 0))[:, None],
                 seg(b, c - b, d4 - d3, (d4 - d3) + (d5 - d6)), q)
    q = np.where(((d1 <= 0) & (d2 <= 0))[:, None], a, q)
    q = np.where(((d3 >= 0) & (d4 <= d3))[:, None], b, q)
    q = np.where(((d6 >= 0) & (d5 <= d6))[:, None], c, q)
    return ((p - q) ** 2).sum(1)


class TriGrid(object):
    """Grille uniforme sur les triangles. Chaque triangle est insere dans TOUTES les cellules que
    sa boite englobante recouvre, donc le point le plus proche d'un triangle est toujours dans une
    cellule que ce triangle occupe. La recherche par anneaux croissants s'arrete des que la
    meilleure distance trouvee est <= r*h : tout point d'une cellule au-dela de l'anneau r est a
    au moins r*h du point de requete. La reponse est donc EXACTE, pas approchee."""

    def __init__(self, V, F, h):
        self.a, self.b, self.c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
        self.h = float(h)
        lo = np.minimum(np.minimum(self.a, self.b), self.c)
        hi = np.maximum(np.maximum(self.a, self.b), self.c)
        self.org = lo.min(axis=0) - self.h
        c0 = np.floor((lo - self.org) / self.h).astype(np.int64)
        c1 = np.floor((hi - self.org) / self.h).astype(np.int64)
        cells = {}
        for t in range(len(self.a)):
            for i in range(c0[t, 0], c1[t, 0] + 1):
                for j in range(c0[t, 1], c1[t, 1] + 1):
                    for k in range(c0[t, 2], c1[t, 2] + 1):
                        cells.setdefault((i, j, k), []).append(t)
        self.cells = {k: np.asarray(v, dtype=np.int64) for k, v in cells.items()}

    def _ring(self, ci, r):
        got = []
        for i in range(ci[0] - r, ci[0] + r + 1):
            for j in range(ci[1] - r, ci[1] + r + 1):
                for k in range(ci[2] - r, ci[2] + r + 1):
                    if r > 0 and max(abs(i - ci[0]), abs(j - ci[1]), abs(k - ci[2])) < r:
                        continue
                    arr = self.cells.get((i, j, k))
                    if arr is not None:
                        got.append(arr)
        return got

    def nearest(self, p):
        ci = np.floor((p - self.org) / self.h).astype(np.int64)
        best = np.inf
        for r in range(0, 256):
            got = self._ring(ci, r)
            if got:
                idx = np.unique(np.concatenate(got))
                best = min(best, float(tri_d2(p[None, :], self.a[idx], self.b[idx],
                                              self.c[idx]).min()))
            if best < np.inf and best <= (r * self.h) ** 2:
                break
        return float(np.sqrt(best))

    def candidates(self, p, radius):
        """Nombre de triangles qu'une phase large sur CETTE grille remettrait a la phase etroite
        pour une requete « quels triangles sont a moins de `radius` de p ». C'est une MESURE du
        cout de la structure d'acceleration sur les points de requete reels, pas un facteur
        suppose."""
        lo = np.floor((p - radius - self.org) / self.h).astype(np.int64)
        hi = np.floor((p + radius - self.org) / self.h).astype(np.int64)
        got = []
        for i in range(lo[0], hi[0] + 1):
            for j in range(lo[1], hi[1] + 1):
                for k in range(lo[2], hi[2] + 1):
                    arr = self.cells.get((i, j, k))
                    if arr is not None:
                        got.append(arr)
        return 0 if not got else int(len(np.unique(np.concatenate(got))))


def grid_for(V, F, mult=2.0):
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    ext = (np.maximum(np.maximum(a, b), c) - np.minimum(np.minimum(a, b), c)).max(axis=1)
    return TriGrid(V, F, max(float(np.median(ext)) * mult, 1.0))


def nearest_all(grid, pts):
    return np.array([grid.nearest(pts[i]) for i in range(len(pts))])


# ==================================================================================================
# 3. LES VOLUMES LIVRES : DISTANCE SIGNEE EXACTE, ET LE PREDICAT DU MOTEUR
# ==================================================================================================
def sd_round_cone(P, a, b, r1, r2):
    """DISTANCE SIGNEE EUCLIDIENNE EXACTE a la capsule conique — l'enveloppe convexe des deux
    spheres (a,r1) et (b,r2), c'est-a-dire le solide que la ligne `capsule A B radius= radius2=`
    designe. Trois regions : les deux calottes et le tronc de cone tangent."""
    ba = b - a
    l2 = float(ba @ ba)
    if l2 < 1e-9:
        return np.linalg.norm(P - a, axis=1) - max(r1, r2)
    rr = r1 - r2
    a2 = l2 - rr * rr
    if a2 <= 1e-9:                      # une sphere contient l'autre : le solide EST la plus grosse
        cc, rc = (a, r1) if r1 >= r2 else (b, r2)
        return np.linalg.norm(P - cc, axis=1) - rc
    il2 = 1.0 / l2
    pa = P - a
    y = pa @ ba
    z = y - l2
    xp = pa * l2 - ba[None, :] * y[:, None]
    x2 = (xp * xp).sum(1)
    k = np.sign(rr) * rr * rr * x2
    out = (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1
    cap_b = np.sign(z) * a2 * (z * z * l2) > k
    cap_a = (~cap_b) & (np.sign(y) * a2 * (y * y * l2) < k)
    out = np.where(cap_b, np.sqrt(x2 + z * z * l2) * il2 - r2, out)
    out = np.where(cap_a, np.sqrt(x2 + y * y * l2) * il2 - r1, out)
    return out


def sd_engine(P, a, b, r1, r2):
    """LE PREDICAT DU MOTEUR, A LA LETTRE (`phys-collide-depth`, jak-hd-physics.gc:1144-1184) :
    parametre serre sur [0,1], rayon INTERPOLE LINEAIREMENT, profondeur = rr - d. Le signe rend
    donc exactement l'ensemble que le moteur traite comme « dedans ». Pour une capsule a rayons
    egaux c'est aussi la distance euclidienne ; pour une capsule conique, non — d'ou les deux
    tables, et l'ecart entre elles est publie."""
    ab = b - a
    dd = float(ab @ ab)
    if dd < 1e-9:
        return np.linalg.norm(P - a, axis=1) - r1
    t = np.clip((P - a) @ ab / dd, 0.0, 1.0)
    proj = a[None, :] + t[:, None] * ab[None, :]
    return np.linalg.norm(P - proj, axis=1) - (r1 + (r2 - r1) * t)


def volume_geometry(vols, idx_of, P, ibms):
    """(a, b, r1, r2, kind, label) par volume, a la pose de bind."""
    out = []
    for v in vols:
        j = idx_of[v['ja']]
        a = P[j] + cvc.world_off(ibms, j, v['off'])
        if v['kind'] == 'sphere':
            out.append((a, a, v['ra'], v['ra'], 'sphere', 'sphere:' + v['ja']))
        else:
            out.append((a, P[idx_of[v['jb']]], v['ra'], v['rb'], 'capsule',
                        '%s->%s' % (v['ja'], v['jb'])))
    return out


def union_sd(V, vg, engine=False):
    best = np.full(len(V), np.inf)
    for a, b, r1, r2, kind, _lab in vg:
        if kind == 'sphere':
            d = np.linalg.norm(V - a, axis=1) - r1
        elif engine:
            d = sd_engine(V, a, b, r1, r2)
        else:
            d = sd_round_cone(V, a, b, r1, r2)
        best = np.minimum(best, d)
    return best


# ==================================================================================================
# 4. DECIMATION — GROUPEMENT SUR GRILLE REGULIERE, DETERMINISTE, ECRITE ICI
# ==================================================================================================
def decimate(V, F, h, org):
    """Groupement des sommets sur une grille reguliere de pas `h`. Le representant d'une cellule
    est la MOYENNE de ses sommets (deterministe, aucun tirage). Les triangles dont deux sommets
    tombent dans la meme cellule disparaissent, les doublons sont retires, les triangles d'aire
    nulle aussi. Aucune dependance externe : scipy / trimesh / open3d ne sont pas installes.

    RESERVE DECLAREE, ET ELLE JOUE CONTRE LE MESH : ce decimateur est le plus simple qui soit. Un
    decimateur a erreur quadratique (QEM) place ses sommets pour minimiser l'ecart au lieu de les
    moyenner, et fait mieux a budget egal. L'ecart publie pour le mesh decime est donc une borne
    SUPERIEURE de ce qu'un mesh decime laisse — jamais une borne inferieure."""
    key = np.floor((V - org) / h).astype(np.int64)
    uq, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    n = len(uq)
    Vd = np.zeros((n, 3))
    cnt = np.zeros(n)
    np.add.at(Vd, inv, V)
    np.add.at(cnt, inv, 1.0)
    Vd /= cnt[:, None]
    Fd = inv[F]
    Fd = Fd[(Fd[:, 0] != Fd[:, 1]) & (Fd[:, 1] != Fd[:, 2]) & (Fd[:, 0] != Fd[:, 2])]
    srt = np.sort(Fd, axis=1)
    _u, first = np.unique(srt, axis=0, return_index=True)
    Fd = Fd[np.sort(first)]
    a, b, c = Vd[Fd[:, 0]], Vd[Fd[:, 1]], Vd[Fd[:, 2]]
    Fd = Fd[0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1) > 1e-9]
    return Vd, Fd, inv


def decimate_to_budget(V, F, budget, org, span):
    """Le plus petit pas de grille dont le mesh decime tient dans `budget` triangles. Bisection sur
    le pas, 60 tours, deterministe. On publie TOUJOURS le compte reellement obtenu."""
    lo, hi = 1.0, float(span)
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        _Vd, Fd, _inv = decimate(V, F, mid, org)
        if len(Fd) > budget:
            lo = mid
        else:
            hi = mid
    Vd, Fd, inv = decimate(V, F, hi, org)
    return Vd, Fd, inv, hi


# ==================================================================================================
# 5. PARTITION DU MESH EN PARTIES DU CORPS
# ==================================================================================================
PART_RULES = [
    ('tete',             lambda n: n == 'head'),
    ('cou',              lambda n: n == 'neck'),
    ('cheveux',          lambda n: ('hair' in n.lower()) or ('bang' in n.lower())),
    ('oreilles',         lambda n: 'ear' in n.lower()),
    ('lunettes',         lambda n: n.startswith('goggles')),
    ('torse',            lambda n: n in ('chest', 'main')),
    ('bassin',           lambda n: n in ('hips', 'belt')),
    ('poitrine',         lambda n: n in ('lBoob', 'rBoob')),
    ('bras',             lambda n: any(k in n for k in ('shoulder', 'Shoulder', 'elbow', 'Elbow',
                                                        'hand', 'Hand', 'thumb', 'Thumb', 'index',
                                                        'Index', 'middle', 'Middle', 'ring', 'Ring',
                                                        'pinky', 'Pinky', 'Glove'))),
    ('cuisse',           lambda n: n in ('Lthigh', 'Rthigh')),
    ('genou',            lambda n: n in ('Lknee', 'Rknee')),
    ('mollet-pied',      lambda n: n in ('Lankle', 'Rankle', 'Lball', 'Rball')),
    ('bretelle-haut',    lambda n: 'TopStrap' in n),
    ('bretelle-bas',     lambda n: 'BotStrap' in n),
    ('languette-genou',  lambda n: 'KneeFlap' in n),
    ('pantacourt',       lambda n: 'pantFlap' in n),
    ('sangle-cheville',  lambda n: 'anklestrap' in n),
    ('sangle-orteil',    lambda n: 'toeStrap' in n),
    ('masque-torche',    lambda n: n in ('mask', 'maskstrap', 'torch')),
]

# Les pieces que le mesh ne fait dominer par AUCUN sommet : leur geometrie est portee en poids
# partage (le sein est domine par `chest`, le pan de pantacourt par `Rknee`/`Lknee`). Une partition
# par joint dominant est donc AVEUGLE a exactement les pieces dont l'owner parle. On les mesure en
# plus, par SELECTION DE POIDS — selections qui se recouvrent, c'est dit et assume.
WEIGHT_PARTS = [
    ('poitrine G  (w>0.25 lBoob)',   ['lBoob'], 0.25),
    ('poitrine D  (w>0.25 rBoob)',   ['rBoob'], 0.25),
    ('pantacourt G (w>0.05)',        ['LpantFlap'], 0.05),
    ('pantacourt D (w>0.05)',        ['RpantFlap'], 0.05),
    ('languette-genou G (w>0.05)',   ['lKneeFlap'], 0.05),
    ('languette-genou D (w>0.05)',   ['rKneeFlap'], 0.05),
    ('bretelle-haut (w>0.05)',       ['lTopStrap', 'lTopStrap2', 'rTopStrap', 'rTopStrap2'], 0.05),
    ('bretelle-bas (w>0.05)',        ['lBotStrap', 'lBotStrap2', 'rBotStrap', 'rBotStrap2'], 0.05),
    ('lunettes (w>0.05)',            ['gogglesBase', 'gogglesMid', 'gogglesLeft', 'gogglesRight'],
                                     0.05),
]


def part_of(name):
    for lab, test in PART_RULES:
        if test(name):
            return lab
    return 'autre:' + name


def weight_select(geo, joints, idx_of, thr):
    J, W = geo['J'], geo['W']
    sel = np.zeros(len(W), dtype=bool)
    for jn in joints:
        j = idx_of.get(jn)
        if j is None:
            continue
        for c in range(J.shape[1]):
            sel |= (J[:, c] == j) & (W[:, c] > thr)
    return np.flatnonzero(sel)


# ==================================================================================================
# 6. LA COURSE DE LA SALLE, POUR LE TAUX DE DECLENCHEMENT DU RECUL
# ==================================================================================================
SELFCOL_RX = re.compile(r'^\s*selfcol\s+(\S+)\s+.*?retreat=(\d+)')
CONTACT_RX = re.compile(r'^\s*chain\s+(\S+)\s+links=(\d+).*?contact_frames=(\d+)')


def parse_room(path):
    """`retreat=` par chaine et la longueur de la course. Le nombre de frames n'est pas imprime en
    clair : `contact_frames` est borne par le total et six chaines y sont a 100 %, donc son maximum
    EST le total. C'est une lecture, pas une hypothese — elle est publiee comme telle."""
    if not os.path.exists(path):
        return None, {}, 0
    retreat, frames = {}, 0
    for line in open(path, encoding='utf-8', errors='replace'):
        m = SELFCOL_RX.match(line)
        if m:
            retreat[m.group(1)] = int(m.group(2))
        m = CONTACT_RX.match(line)
        if m:
            frames = max(frames, int(m.group(3)))
    return path, retreat, frames


# ==================================================================================================
def main():
    repo = g.REPO
    out_path = os.path.join(repo, OUT_REL)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out = []

    def emit(s=''):
        out.append(s)
        print(s)
        sys.stdout.flush()

    fail = []

    # ---- chargement ---------------------------------------------------------------------------
    names, parent, _doc = g.load_rig(os.path.join(repo, g.RIG_REL))
    geo = g.load_mesh(g.MODEL)
    if list(geo['names']) != names:
        raise SystemExit('la liste de joints du GLB ne correspond pas au rig json')
    idx_of = {n: i for i, n in enumerate(names)}
    V, P, ibms, J, W = geo['V'], geo['P'], geo['ibms'], geo['J'], geo['W']
    F_raw = load_triangles(geo)
    F, ndeg = drop_degenerate(V, F_raw)
    chains, vols = cvc.parse_chains(os.path.join(repo, cvc.CHAINS_REL))
    vg = volume_geometry(vols, idx_of, P, ibms)
    ncaps = sum(1 for v in vols if v['kind'] == 'capsule')
    nsph = len(vols) - ncaps

    sd_cone = union_sd(V, vg, engine=False)
    sd_eng = union_sd(V, vg, engine=True)
    dom = J[np.arange(len(J)), np.argmax(W, axis=1)]
    prop = np.array([names[d] in ('mask', 'maskstrap', 'torch') for d in dom])
    height_all = float(V[:, 1].max() - V[:, 1].min())
    height_body = float(V[~prop, 1].max() - V[~prop, 1].min())

    emit('# mesh-vs-capsule-fidelity — les quatre chiffres exiges avant de trancher la suggestion')
    emit('# de l\'owner : « deriver du mesh en suivant ses deformations plutot que des capsules ».')
    emit('# rig    : %s (%d joints, pose de bind)' % (g.RIG_REL, len(names)))
    emit('# mesh   : %s (%d sommets, %d triangles, %d d\'aire nulle retires)'
         % (geo['src'], len(V), len(F), ndeg))
    emit('# donnees: %s (%d chaines, %d volumes = %d capsules + %d spheres)'
         % (cvc.CHAINS_REL, len(chains), len(vols), ncaps, nsph))
    emit('# unite  : unite de jeu. Toute longueur imprimee en metres est cette unite / 4096.')
    emit('# TAILLE MESUREE DU PERSONNAGE (pose de bind, axe Y) : %.4f m corps seul, %.4f m avec le'
         % (height_body / UNITS, height_all / UNITS))
    emit('#          masque et la torche (deux accessoires portes par `mask`/`maskstrap`/`torch`).')
    emit('#          Envergure X %.4f m, epaisseur Z %.4f m — la pose de bind a les bras ecartes.'
         % ((V[:, 0].max() - V[:, 0].min()) / UNITS, (V[:, 2].max() - V[:, 2].min()) / UNITS))
    emit('')

    # ---- convention de repere du decalage : une MESURE, pas un choix ---------------------------
    emit('-- CHECK 0 : DANS QUEL REPERE LES `offset=` SONT-ILS ECRITS ? -----------------------')
    emit('   Discriminant : le generateur a ecrit chaque `offset` comme le CENTROIDE mesure de la')
    emit('   geometrie du joint. On compare le centre recalcule au centroide mesure, sous les deux')
    emit('   conventions possibles. Quatre joints de bretelle portent une echelle de 9.68 dans leur')
    emit('   matrice inverse-bind : la convention se lit donc dans le chiffre, elle ne se choisit pas.')
    worst = {'normalisee': (0.0, '-'), 'brute': (0.0, '-')}
    for v in vols:
        if v['kind'] != 'sphere':
            continue
        j = idx_of[v['ja']]
        n = 0
        ii = np.array([], dtype=np.int64)
        for thr in (0.5, 0.25, 0.05):
            n, _w, ii = g.influence(geo, j, thr)
            if n >= 8:
                break
        if n == 0:
            continue
        cmes = V[ii].mean(axis=0)
        M = np.linalg.inv(ibms[j])
        cand = {'normalisee': P[j] + cvc.world_off(ibms, j, v['off']),
                'brute': P[j] + (M[:3, :3] @ (np.asarray(v['off'], dtype=float) / UNITS)) * UNITS}
        for k, cc in cand.items():
            e = float(np.linalg.norm(cmes - cc))
            if e > worst[k][0]:
                worst[k] = (e, v['ja'])
    emit('   convention NORMALISEE (echelle d\'os retiree, celle de `to_bone_local`) : pire ecart '
         '%.2f u (%s)' % (worst['normalisee'][0], worst['normalisee'][1]))
    emit('   convention BRUTE      (inverse de l\'IBM telle quelle)                  : pire ecart '
         '%.2f u (%s)' % (worst['brute'][0], worst['brute'][1]))
    emit('   -> tout le reste du script utilise la NORMALISEE : elle retombe sur les centroides')
    emit('      mesures a moins d\'une unite, l\'autre a plusieurs centaines.')
    emit('')

    # ==============================================================================================
    # CONTROLE NEGATIF
    # ==============================================================================================
    emit('== CONTROLE NEGATIF (borne basse) : LE MESH COMPLET COMME COLLIDER DOIT RENDRE 0 =====')
    emit('   Il ne suffit pas de le tester sur les SOMMETS : un sommet est un coin de ses propres')
    emit('   triangles, sa distance est nulle par construction et ne prouverait rien de la routine.')
    emit('   Deux etages, donc.')
    emit('')
    emit('   ETAGE 1 — DES POINTS SUR LA SURFACE, distance a TOUT le mesh, doit valoir 0.')
    gridF = grid_for(V, F)
    a3, b3, c3 = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    bary = np.array([0.25, 0.35, 0.40])
    S_face = a3 * bary[0] + b3 * bary[1] + c3 * bary[2]
    S_edge = np.concatenate([(a3 + b3) * 0.5, (b3 + c3) * 0.5, (a3 + c3) * 0.5], axis=0)[::3]
    for lab, pts in (('sommets du mesh', V),
                     ('points barycentriques INTERIEURS (0.25/0.35/0.40)', S_face),
                     ('milieux d\'aretes (1 sur 3)', S_edge)):
        d = nearest_all(gridF, pts)
        e = float(np.abs(d).max())
        ok = e <= EPS_ZERO
        emit('   %-52s n=%6d  max|d| = %.3e u   %s' % (lab, len(pts), e, 'OK' if ok else 'ECHEC'))
        if not ok:
            fail.append('controle negatif etage 1 : %s rend %.3e u au lieu de 0' % (lab, e))
    emit('')
    emit('   ETAGE 2 — DES POINTS A DISTANCE CONNUE D\'UN TRIANGLE DONNE. Un zero ne prouve pas')
    emit('   qu\'une distance est juste : une routine qui rendrait toujours 0 passerait l\'etage 1.')
    emit('   On construit donc, pour CHAQUE triangle, trois points dont la distance A CE TRIANGLE')
    emit('   vaut exactement %.0f u par construction geometrique, un dans chacune des trois'
         % NORMAL_PROBE)
    emit('   familles de regions de Voronoi, et on compare a la routine, triangle par triangle :')
    emit('     FACE   : centroide + %.0f u le long de la normale — la projection tombe dans le'
         % NORMAL_PROBE)
    emit('              triangle, le point le plus proche est le centroide.')
    emit('     ARETE  : milieu de AB + %.0f u dans le PLAN, perpendiculaire a AB, du cote oppose'
         % NORMAL_PROBE)
    emit('              a C — le pied de la perpendiculaire est le milieu, il est dans le segment.')
    emit('     SOMMET : A + %.0f u le long de la bissectrice sortante en A. Ce point verifie'
         % NORMAL_PROBE)
    emit('              (p-A).(B-A) <= 0 et (p-A).(C-A) <= 0 pour TOUT triangle non degenere,')
    emit('              donc son point le plus proche est A exactement.')
    cen = (a3 + b3 + c3) / 3.0
    nrm = np.cross(b3 - a3, c3 - a3)
    nrm = nrm / np.linalg.norm(nrm, axis=1)[:, None]
    Pf = cen + nrm * NORMAL_PROBE
    ab3 = b3 - a3
    uab = ab3 / np.linalg.norm(ab3, axis=1)[:, None]
    perp = (c3 - a3) - (((c3 - a3) * uab).sum(1))[:, None] * uab      # vers C, dans le plan
    perp = perp / np.linalg.norm(perp, axis=1)[:, None]
    Pe = (a3 + b3) * 0.5 - perp * NORMAL_PROBE                        # du cote OPPOSE a C
    uba = (a3 - b3) / np.linalg.norm(a3 - b3, axis=1)[:, None]
    uca = (a3 - c3) / np.linalg.norm(a3 - c3, axis=1)[:, None]
    bis = uba + uca
    nb = np.linalg.norm(bis, axis=1)
    good = nb > 1e-9                       # A, B, C alignes en A : la bissectrice n'existe pas
    bis = bis / np.where(nb < 1e-9, 1.0, nb)[:, None]
    Pv = a3 + bis * NORMAL_PROBE
    for lab, pts, sel in (('region FACE', Pf, np.ones(len(F), dtype=bool)),
                          ('region ARETE (AB)', Pe, np.ones(len(F), dtype=bool)),
                          ('region SOMMET (A)', Pv, good)):
        d = np.sqrt(tri_d2(pts[sel], a3[sel], b3[sel], c3[sel]))
        e = float(np.abs(d - NORMAL_PROBE).max())
        ok = e <= 1e-6 * NORMAL_PROBE
        emit('   %-52s n=%6d  max|d-%.0f| = %.3e u   %s'
             % (lab, int(sel.sum()), NORMAL_PROBE, e, 'OK' if ok else 'ECHEC'))
        if not ok:
            fail.append('controle negatif etage 2 : %s rend %.3e u d\'ecart a %.0f'
                        % (lab, e, NORMAL_PROBE))
    emit('')
    emit('   OBSERVATION, PAS UNE GATE : les memes points de FACE, mesures contre TOUT le mesh,')
    d = nearest_all(gridF, Pf[::3])
    emit('   rendent min %.2f / median %.2f / max %.2f u au lieu de %.0f. C\'est correct et c\'est'
         % (float(d.min()), float(np.median(d)), float(d.max()), NORMAL_PROBE))
    emit('   attendu : Keira porte des pieces MINCES a double face (verre de lunettes, bretelles,')
    emit('   pans de tissu) ou %.0f u traversent de part en part et la surface la plus proche est'
         % NORMAL_PROBE)
    emit('   l\'autre face. En faire une gate d\'egalite serait une gate fausse — elle a d\'ailleurs')
    emit('   ete ecrite ainsi d\'abord, elle a tire, et c\'est ce qui a fait trouver le cas.')
    emit('')

    # ==============================================================================================
    # CONTROLE POSITIF
    # ==============================================================================================
    emit('== ARMEMENT DES CONTROLES : ILS DOIVENT POUVOIR ECHOUER =============================')
    emit('   Un controle qu\'aucun defaut ne fait monter ne prouve rien. On INJECTE donc trois')
    emit('   defauts, en memoire, sans toucher au code livre, et on verifie que le compteur monte.')
    emit('')
    dplane = np.abs(((Pf - a3) * nrm).sum(1))
    armed = [
        ('routine qui rend TOUJOURS 0',
         float(np.abs(np.zeros(len(F)) - NORMAL_PROBE).max()),
         'l\'etage 2 monte a l\'ecart maximal possible : la distance FACE est lue 0 au lieu de %.0f'
         % NORMAL_PROBE),
        ('projection sur le PLAN seule, lue sur la region ARETE',
         float(np.abs(np.abs(((Pe - a3) * nrm).sum(1)) - NORMAL_PROBE).max()),
         'la faute classique : JUSTE sur la face (%.1e u d\'ecart) et fausse partout ailleurs'
         % float(np.abs(dplane - NORMAL_PROBE).max())),
        ('projection sur le PLAN seule, lue sur la region SOMMET',
         float(np.abs(np.abs(((Pv - a3) * nrm).sum(1)) - NORMAL_PROBE).max()), ''),
    ]
    for lab, err, note in armed:
        emit('   ARME  %-58s ecart max = %8.2f u' % (lab, err))
        if note:
            emit('         %s' % note)
    n_rise = sum(1 for _l, e, _n in armed if e > 1e-3 * NORMAL_PROBE)
    emit('   -> %d/%d defauts injectes font MONTER le controle negatif. Il discrimine.'
         % (n_rise, len(armed)))
    if n_rise != len(armed):
        fail.append('armement : %d/%d defauts injectes seulement font monter le controle negatif'
                    % (n_rise, len(armed)))
    emit('')

    emit('== CONTROLE POSITIF (borne haute) : UNE SEULE SPHERE ENGLOBANT TOUT LE PERSONNAGE ====')
    cs = (V.min(axis=0) + V.max(axis=0)) * 0.5
    dc = np.linalg.norm(V - cs, axis=1)
    rs = float(dc.max())
    sd_one = dc - rs
    in_one = np.maximum(-sd_one, 0.0)
    inside_max_one = float(in_one.max())
    frac_out_one = float((sd_one > 0).mean())
    half = 0.5 * height_all
    ratio = inside_max_one / half
    ok = (0.5 <= ratio <= 1.5) and frac_out_one == 0.0
    emit('   sphere : centre = milieu de la boite englobante, rayon = %.4f m (le plus loin des'
         % (rs / UNITS))
    emit('            %d sommets). Elle englobe donc tout par construction.' % len(V))
    emit('   inside_max = %.4f m   fraction dehors = %.1f %%' % (inside_max_one / UNITS,
                                                                 100.0 * frac_out_one))
    emit('   demi-hauteur du personnage = %.4f m  ->  inside_max / demi-hauteur = %.2f   %s'
         % (half / UNITS, ratio, 'OK' if ok else 'ECHEC'))
    emit('   C\'EST L\'ECHELLE CONTRE LAQUELLE LIRE LES 48 VOLUMES : un obstacle qui ignore')
    emit('   completement la forme enfouit la surface d\'environ une demi-hauteur de personnage.')
    if not ok:
        fail.append('controle positif : inside_max/demi-hauteur = %.2f, hors de [0.5, 1.5] '
                    '(ou fraction dehors non nulle : %.3f)' % (ratio, frac_out_one))
    ratio48 = float(np.maximum(-sd_cone, 0.0).max()) / half
    emit('   ET LA FENETRE DISCRIMINE : la meme grandeur, calculee sur les %d volumes livres, vaut'
         % len(vols))
    emit('   %.4f m, soit %.2f de demi-hauteur — %.0f fois moins, tres au-dessous de la borne 0.5.'
         % (float(np.maximum(-sd_cone, 0.0).max()) / UNITS, ratio48, ratio / max(1e-9, ratio48)))
    emit('   La fenetre [0.5, 1.5] n\'accepte donc pas n\'importe quel collider : elle separe')
    emit('   « une sphere qui ignore la forme » de « 48 volumes qui la suivent grossierement ».')
    emit('')

    # ==============================================================================================
    # CHIFFRE 1 — FIDELITE DES 48 VOLUMES LIVRES
    # ==============================================================================================
    emit('== CHIFFRE 1 / FIDELITE — LES 48 VOLUMES LIVRES, PRIS EN UNION ========================')
    outc = np.maximum(sd_cone, 0.0)
    inc = np.maximum(-sd_cone, 0.0)
    oute = np.maximum(sd_eng, 0.0)
    ine = np.maximum(-sd_eng, 0.0)

    def trip(x):
        return (float(x.max()), float(np.percentile(x, 95)), float(np.percentile(x, 50)))

    emit('   Deux lectures, publiees toutes les deux parce qu\'elles ne disent pas la meme chose :')
    emit('     GEOMETRIQUE — distance euclidienne exacte au solide « enveloppe convexe des deux')
    emit('                   spheres », c\'est-a-dire au volume que la ligne de donnees designe.')
    emit('     MOTEUR      — le predicat de `phys-collide-depth` a la lettre (rayon interpole sur')
    emit('                   le parametre serre) : l\'ensemble que le moteur traite comme dedans.')
    emit('   Pour une capsule a rayons EGAUX les deux coincident ; les 24 capsules livrees sont')
    emit('   TOUTES coniques, donc l\'ecart existe et il est chiffre plus bas.')
    emit('')
    emit('   %-12s %10s %10s %10s   %10s %10s %10s   %9s'
         % ('lecture', 'out_max', 'out_p95', 'out_p50', 'in_max', 'in_p95', 'in_p50', 'dehors'))
    for lab, o, i, sd in (('GEOMETRIQUE', outc, inc, sd_cone), ('MOTEUR', oute, ine, sd_eng)):
        om, o95, o50 = trip(o)
        im, i95, i50 = trip(i)
        emit('   %-12s %10.4f %10.4f %10.4f   %10.4f %10.4f %10.4f   %8.1f %%'
             % (lab, om / UNITS, o95 / UNITS, o50 / UNITS,
                im / UNITS, i95 / UNITS, i50 / UNITS, 100.0 * float((sd > 0).mean())))
    emit('   (metres. Les percentiles portent sur TOUS les %d sommets, la part « dedans » comptant'
         % len(V))
    emit('    0 dans la colonne `out` et reciproquement — meme convention que probe_union_cover.py,')
    emit('    sans quoi les chiffres ne seraient pas comparables a la mesure anterieure.)')
    emit('   moyenne du depassement sur les seuls sommets DEHORS : %.4f m (GEOMETRIQUE)'
         % (float(outc[outc > 0].mean()) / UNITS if (outc > 0).any() else 0.0))
    emit('   ecart entre les deux lectures : max |geo - moteur| = %.1f u (%.4f m) ; %d sommets sur'
         % (float(np.abs(sd_cone - sd_eng).max()), float(np.abs(sd_cone - sd_eng).max()) / UNITS,
            int(((sd_cone > 0) != (sd_eng > 0)).sum())))
    emit('   %d changent de cote entre les deux. Le solide et ce que le moteur en teste ne sont'
         % len(V))
    emit('   donc PAS le meme ensemble — c\'est une propriete du moteur, pas une approximation de')
    emit('   ce script, et elle est signalee sans etre corrigee ici (aucun `.gc` n\'est touche).')
    emit('')
    emit('   CONFRONTATION AVEC L\'ORDRE DE GRANDEUR DEJA MESURE. Les DIRECTIVES citent 50,4 % de')
    emit('   sommets dehors (p95 0.2176 m, max 0.6064 m), releve sur 33 volumes par')
    emit('   `probe_union_cover.py`. Ce script, sur les %d volumes livres aujourd\'hui, lit'
         % len(vols))
    emit('   %.1f %% dehors, p95 %.4f m, max %.4f m. Meme grandeur, meme repere, meme mesh : les'
         % (100.0 * float((sd_cone > 0).mean()), float(np.percentile(outc, 95)) / UNITS,
            float(outc.max()) / UNITS))
    emit('   deux se recoupent. Rien a chercher de ce cote.')
    emit('')

    # ---- par partie du corps -------------------------------------------------------------------
    emit('   -- OU L\'APPROXIMATION COUTE : PARTITION PAR JOINT DOMINANT (aucun double comptage) --')
    emit('   %-18s %6s %8s %10s %10s %10s %10s'
         % ('partie', 'nv', 'dehors', 'out_max', 'out_p95', 'in_max', 'in_p95'))
    labs = np.array([part_of(names[d]) for d in dom])
    rows = []
    for lab in sorted(set(labs.tolist())):
        m = labs == lab
        o, i = outc[m], inc[m]
        rows.append((float((sd_cone[m] > 0).mean()), lab, int(m.sum()),
                     float(o.max()), float(np.percentile(o, 95)),
                     float(i.max()), float(np.percentile(i, 95))))
    for frac, lab, nv, om, o95, im, i95 in sorted(rows, key=lambda r: -r[3]):
        emit('   %-18s %6d %7.1f %% %10.4f %10.4f %10.4f %10.4f'
             % (lab, nv, 100.0 * frac, om / UNITS, o95 / UNITS, im / UNITS, i95 / UNITS))
    emit('')
    emit('   -- LES PIECES QUE LA PARTITION NE PEUT PAS VOIR, MESUREES PAR SELECTION DE POIDS ----')
    emit('   Aucun sommet du mesh n\'a `lBoob`, `rBoob`, `LpantFlap` ni `RpantFlap` pour joint')
    emit('   DOMINANT : le sein est domine par `chest`, le pan de pantacourt par le genou. Une')
    emit('   partition par joint dominant est donc structurellement aveugle a exactement les deux')
    emit('   pieces dont l\'owner parle depuis six passes. Ces selections-la se RECOUVRENT entre')
    emit('   elles et avec le tableau ci-dessus ; c\'est assume, elles ne servent pas a totaliser.')
    emit('   %-30s %6s %8s %10s %10s %10s'
         % ('piece (selection)', 'nv', 'dehors', 'out_max', 'out_p95', 'in_max'))
    for lab, joints, thr in WEIGHT_PARTS:
        sel = weight_select(geo, joints, idx_of, thr)
        if len(sel) == 0:
            emit('   %-30s %6d   (aucun sommet au-dessus du seuil)' % (lab, 0))
            continue
        o, i, sd = outc[sel], inc[sel], sd_cone[sel]
        emit('   %-30s %6d %7.1f %% %10.4f %10.4f %10.4f'
             % (lab, len(sel), 100.0 * float((sd > 0).mean()), float(o.max()) / UNITS,
                float(np.percentile(o, 95)) / UNITS, float(i.max()) / UNITS))
    wsel = {lab: weight_select(geo, js_, idx_of, thr) for lab, js_, thr in WEIGHT_PARTS}
    emit('')
    emit('   CE QUE CES TROIS LIGNES DISENT DES TROIS DEFAUTS QUE L\'OWNER SIGNALE — des nombres,')
    emit('   pas une interpretation, et chacun se rattache a une phrase datee des DIRECTIVES :')
    sg = wsel['lunettes (w>0.05)']
    emit('   * LUNETTES (« elles clipent avec ses seins, et meme en idle », 6e passe) : %.0f %% de'
         % (100.0 * float((sd_cone[sg] > 0).mean())))
    emit('     leur geometrie est HORS de l\'union des %d volumes, jusqu\'a %.4f m (%.0f mm) dehors.'
         % (len(vols), float(outc[sg].max()) / UNITS, 1000.0 * float(outc[sg].max()) / UNITS))
    sp = np.union1d(wsel['pantacourt G (w>0.05)'], wsel['pantacourt D (w>0.05)'])
    emit('   * PANTACOURT (« le bas clipe a l\'interieur de ses mollets », 11e passe) : %.0f %% de sa'
         % (100.0 * float((sd_cone[sp] > 0).mean())))
    emit('     geometrie est dehors, jusqu\'a %.0f mm — aucun volume ne se trouve devant elle.'
         % (1000.0 * float(outc[sp].max()) / UNITS))
    sb = np.union1d(wsel['poitrine G  (w>0.25 lBoob)'], wsel['poitrine D  (w>0.25 rBoob)'])
    emit('   * POITRINE (« une sphere au joint ne peut pas epouser un sein », 6e passe) : le defaut')
    emit('     est de l\'autre signe — seulement %.0f %% dehors, mais AVALEE jusqu\'a %.0f mm sous la'
         % (100.0 * float((sd_cone[sb] > 0).mean()), 1000.0 * float(inc[sb].max()) / UNITS))
    emit('     surface de l\'union. Un lien qui vise cette surface s\'arrete %.0f mm trop tot.'
         % (1000.0 * float(inc[sb].max()) / UNITS))
    emit('')

    # ==============================================================================================
    # CHIFFRE 1 bis — LE MESH DECIME
    # ==============================================================================================
    emit('== CHIFFRE 1 bis / FIDELITE — UN COLLIDER ISSU DU MESH DECIME =========================')
    emit('   Decimation ecrite dans ce fichier : groupement des sommets sur une grille reguliere,')
    emit('   representant = moyenne de la cellule. Deterministe, aucun tirage, aucune dependance.')
    emit('   Le pas de grille est cherche par bisection pour tenir dans le budget ; c\'est le')
    emit('   NOMBRE DE TRIANGLES REELLEMENT OBTENU qui est publie, jamais le budget vise.')
    emit('')
    emit('   %6s %7s %9s %8s %8s   %10s %10s %10s'
         % ('budget', 'tris', 'sommets', 'pas_mm', 'utilises', 'ecart_max', 'ecart_p95',
            'ecart_p50'))
    org = V.min(axis=0) - 1.0
    span = float((V.max(axis=0) - V.min(axis=0)).max())
    dec = {}
    for budget in BUDGETS:
        Vd, Fd, inv, h = decimate_to_budget(V, F, budget, org, span)
        used = np.unique(Fd)
        gd = grid_for(Vd, Fd)
        d = nearest_all(gd, V)
        # sens inverse : la surface decimee s'eloigne-t-elle de la vraie ? (elle peut boucher un
        # creux : le sens sommet->decime seul ne le verrait pas)
        ad, bd, cd = Vd[Fd[:, 0]], Vd[Fd[:, 1]], Vd[Fd[:, 2]]
        Sd = (ad + bd + cd) / 3.0
        drev = nearest_all(gridF, Sd)
        dec[budget] = dict(V=Vd, F=Fd, inv=inv, h=h, used=used, d=d, drev=drev, grid=gd)
        emit('   %6d %7d %9d %8.1f %8d   %10.4f %10.4f %10.4f'
             % (budget, len(Fd), len(Vd), h / UNITS * 1000.0, len(used),
                float(d.max()) / UNITS, float(np.percentile(d, 95)) / UNITS,
                float(np.percentile(d, 50)) / UNITS))
    emit('   (ecart = distance point->triangle du sommet de la VRAIE surface au triangle le plus')
    emit('    proche de la surface DECIMEE, en metres. `sommets` = cellules non vides ; `utilises`')
    emit('    = celles qu\'un triangle survivant reference — ce sont elles qu\'il faudrait skinner.)')
    emit('')
    emit('   SENS INVERSE (centroide de chaque triangle decime -> vraie surface). Il attrape ce que')
    emit('   le sens direct ne voit pas : une surface decimee qui bouche un creux ou deborde.')
    emit('   %6s %10s %10s %10s' % ('budget', 'rev_max', 'rev_p95', 'rev_p50'))
    for budget in BUDGETS:
        r = dec[budget]['drev']
        emit('   %6d %10.4f %10.4f %10.4f'
             % (budget, float(r.max()) / UNITS, float(np.percentile(r, 95)) / UNITS,
                float(np.percentile(r, 50)) / UNITS))
    emit('')

    # ==============================================================================================
    # A BUDGET COMPARABLE
    # ==============================================================================================
    emit('== A BUDGET COMPARABLE : LAQUELLE LAISSE LE MOINS D\'ECART A LA VRAIE SURFACE ? ========')
    emit('   La grandeur commune est « de combien la surface du collider s\'ecarte de la vraie')
    emit('   surface, mesuree aux sommets de celle-ci ». Pour les capsules c\'est |distance signee|')
    emit('   a l\'union ; pour le mesh decime, la distance au triangle le plus proche. Meme repere,')
    emit('   memes points de mesure, meme unite.')
    emit('   RESERVE, et elle joue CONTRE le mesh : |distance signee| est EXACTE pour un sommet')
    emit('   dehors, et une BORNE INFERIEURE pour un sommet dedans (la distance au bord de l\'union')
    emit('   est au moins celle au bord du volume le plus profond). Le chiffre des capsules est')
    emit('   donc, si quoi que ce soit, sous-estime.')
    emit('')
    absc = np.abs(sd_cone)
    emit('   %-34s %8s %10s %10s %10s'
         % ('representation', 'prim.', 'ecart_max', 'ecart_p95', 'ecart_p50'))
    emit('   %-34s %8d %10.4f %10.4f %10.4f'
         % ('48 volumes livres (capsules+spheres)', len(vols), float(absc.max()) / UNITS,
            float(np.percentile(absc, 95)) / UNITS, float(np.percentile(absc, 50)) / UNITS))
    for budget in BUDGETS:
        d = dec[budget]['d']
        emit('   %-34s %8d %10.4f %10.4f %10.4f'
             % ('mesh decime, budget %d' % budget, len(dec[budget]['F']),
                float(d.max()) / UNITS, float(np.percentile(d, 95)) / UNITS,
                float(np.percentile(d, 50)) / UNITS))
    emit('')
    iso = dec[48]
    emit('   LECTURE, EN NOMBRES ET SANS AVIS :')
    emit('   * A NOMBRE DE PRIMITIVES EGAL (%d volumes contre %d triangles), les capsules gagnent :'
         % (len(vols), len(iso['F'])))
    emit('     ecart max %.4f m contre %.4f m, p95 %.4f contre %.4f. Une capsule couvre un membre'
         % (float(absc.max()) / UNITS, float(iso['d'].max()) / UNITS,
            float(np.percentile(absc, 95)) / UNITS, float(np.percentile(iso['d'], 95)) / UNITS))
    emit('     entier, %d triangles ne couvrent pas un corps.' % len(iso['F']))
    for budget in BUDGETS[1:]:
        d = dec[budget]['d']
        if float(np.percentile(d, 95)) < float(np.percentile(absc, 95)):
            emit('   * LE PREMIER BUDGET OU LE MESH PASSE DEVANT SUR p95 est %d triangles : p95 %.4f m'
                 % (len(dec[budget]['F']), float(np.percentile(d, 95)) / UNITS))
            emit('     contre %.4f m pour les 48 volumes, soit %.1f fois moins d\'ecart.'
                 % (float(np.percentile(absc, 95)) / UNITS,
                    float(np.percentile(absc, 95)) / max(1e-9, float(np.percentile(d, 95)))))
            break
    for budget in BUDGETS[1:]:
        d = dec[budget]['d']
        if float(d.max()) < float(absc.max()):
            emit('   * ET SUR LE MAX (le chiffre qui decide d\'un clip visible) des %d triangles :'
                 % len(dec[budget]['F']))
            emit('     %.4f m contre %.4f m, soit %.1f fois moins.'
                 % (float(d.max()) / UNITS, float(absc.max()) / UNITS,
                    float(absc.max()) / max(1e-9, float(d.max()))))
            break
    emit('')

    # ==============================================================================================
    # CHIFFRE 2 — COUT PAR FRAME
    # ==============================================================================================
    emit('== CHIFFRE 2 / COUT PAR FRAME — ESTIMATION ARITHMETIQUE, NON MESUREE SUR DEVICE =======')
    emit('   AUCUN DEVICE N\'EST DANS LA BOUCLE DE CE SCRIPT ET AUCUN COLLIDER MESH N\'EXISTE. Ce')
    emit('   qui suit est un COMPTE D\'OPERATIONS tire du fichier de donnees et de la structure de')
    emit('   boucle du moteur, chaque facteur portant sa reference de ligne. Ce n\'est pas un temps,')
    emit('   ce n\'est pas une extrapolation de temps, et ca ne remplace pas une course sur le Redmi.')
    emit('')
    nlink_tot = 0
    nlink_sim = 0
    per_chain = []
    for ch in chains:
        n = len(ch['joints'])
        rlk = max(0, min(ch['rootlock'], max(0, n - 1)))
        nlink_tot += n
        nlink_sim += n - rlk
        own = 0
        jset = set(ch['joints'])
        for v in vols:
            if v['ja'] in jset or (v['jb'] is not None and v['jb'] in jset):
                own += 1
        per_chain.append((ch['name'], n, rlk, n - rlk, own))
    pairs_own = sum(sim * (len(vols) - own) for _nm, _n, _r, sim, own in per_chain)
    emit('   Tire du fichier de donnees, sans aucune valeur en dur :')
    emit('     chaines = %d   liens declares = %d   liens SIMULES (l >= rootlock, :1786) = %d'
         % (len(chains), nlink_tot, nlink_sim))
    emit('     volumes = %d' % len(vols))
    emit('     -> tests volume<->lien par PASSE = %d x %d = %d'
         % (nlink_sim, len(vols), nlink_sim * len(vols)))
    emit('     -> apres l\'exclusion structurelle chaine<->ses propres volumes (`phys-col-own?`,')
    emit('        :1735-1740) : %d paires reellement evaluees par passe.' % pairs_own)
    emit('')
    emit('   L\'UNITE EST LE TEST PRIMITIF : « un lien contre UNE primitive », que la primitive soit')
    emit('   un volume ou un triangle. C\'est la seule unite dans laquelle les deux representations')
    emit('   se comparent sans arbitrage. Le cout UNITAIRE, lui, differe et il est donne a part.')
    emit('')
    emit('   COMBIEN DE PASSES PAR FRAME (structure de boucle relevee, pas supposee) :')
    emit('     phys-collide-chain appelee %d fois par chaine et par frame  (:3116-3118 et :3144-3146)'
         % LOOP_COLLIDE_CALLS)
    emit('     chaque appel : 1 passe de SELECTION sur toutes les primitives (:1827), puis %d'
         % LOOP_SWEEPS)
    emit('       balayages (:1856) ou SEULE la primitive decideuse travaille (DECISION 1, :1861-1866)')
    emit('     -> tests primitifs par frame = %d x [ %d (selection) + %d x %d (balayages) ]'
         % (LOOP_COLLIDE_CALLS, pairs_own, nlink_sim, LOOP_SWEEPS))
    prim_today = LOOP_COLLIDE_CALLS * (pairs_own + nlink_sim * LOOP_SWEEPS)
    emit('        = %d tests primitifs par frame, hors recul.' % prim_today)
    emit('')
    room_path, retreat, frames = parse_room(os.path.join(repo, ROOM_REL))
    ret_prim = 0.0
    if room_path and frames > 0:
        tot_ret = sum(retreat.values())
        rate = tot_ret / float(frames)
        ret_prim = rate * RETREAT_STEPS * len(vols)
        emit('   LE RECUL, ET SON TAUX DE DECLENCHEMENT EST MESURE, PAS SUPPOSE :')
        emit('     source : %s' % os.path.relpath(room_path, repo))
        emit('     %d reculs sur %d frames de course = %.2f recul/frame (toutes chaines confondues).'
             % (tot_ret, frames, rate))
        emit('     Chaque recul = %d pas de dichotomie (:2439) ; chaque pas est un phys-link-pen qui'
             % RETREAT_STEPS)
        emit('     reparcourt les %d primitives (:2116) : %d tests primitifs par recul.'
             % (len(vols), RETREAT_STEPS * len(vols)))
        emit('     -> %.0f tests primitifs par frame imputables au recul, soit %.0f %% du reste.'
             % (ret_prim, 100.0 * ret_prim / max(1.0, prim_today)))
    else:
        emit('   LE RECUL : aucune table de salle lisible, le taux de declenchement n\'est pas')
        emit('   disponible. Le compte ci-dessus EXCLUT donc le recul — c\'est dit, pas avale.')
    total_today = prim_today + ret_prim
    emit('')
    emit('   AUJOURD\'HUI, TOTAL : %.0f TESTS PRIMITIFS PAR FRAME.' % total_today)
    emit('   Cout unitaire, pour ne pas confondre un test et un test : dans le moteur actuel un')
    emit('   test primitif coute %d appels a `phys-collide-depth` (floors + floorc + dep,'
         % DEPTH_PER_VOLUME)
    emit('   :1925-1931), soit %.0f appels par frame. Un test point->triangle coute une evaluation'
         % (total_today * DEPTH_PER_VOLUME))
    emit('   de distance point-triangle. Ces deux couts unitaires ne sont PAS egaux et ce script ne')
    emit('   pretend pas savoir leur rapport sur ARM : c\'est la mesure device qui manque.')
    emit('')
    emit('   MESH DECIME, EN FORCE BRUTE, MEME STRUCTURE DE BOUCLE : la passe de selection parcourt')
    emit('   les triangles au lieu des volumes, les balayages ne travaillent que sur le triangle')
    emit('   decideur. Le recul n\'est PAS compte ici (il dependrait de l\'implementation) — c\'est')
    emit('   dit, et ca joue en faveur du mesh.')
    emit('   %6s %7s %16s %16s %11s'
         % ('budget', 'tris', 'tests/frame', 'vs auj.', 'x'))
    for budget in BUDGETS:
        nt = len(dec[budget]['F'])
        tf = LOOP_COLLIDE_CALLS * (nlink_sim * nt + nlink_sim * LOOP_SWEEPS)
        emit('   %6d %7d %16d %16.0f %11.1f'
             % (budget, nt, tf, total_today, tf / max(1.0, total_today)))
    emit('')
    emit('   MESH DECIME, AVEC UNE STRUCTURE D\'ACCELERATION. L\'hypothese est declaree : une GRILLE')
    emit('   UNIFORME de pas egal au pas de decimation, chaque triangle insere dans les cellules')
    emit('   que sa boite englobante recouvre. Le facteur n\'est PAS prete : il est MESURE en')
    emit('   comptant, pour les %d points de requete REELS (le centre du volume que chaque lien' % nlink_sim)
    emit('   simule porte a la pose de bind) et son rayon de lien, combien de triangles la phase')
    emit('   large rendrait. C\'est la seule partie de ce chiffre qui soit une mesure.')
    qpts, qrad, qlab = [], [], []
    for ch in chains:
        n = len(ch['joints'])
        rlk = max(0, min(ch['rootlock'], max(0, n - 1)))
        radii = ch['radii'] if ch['radii'] else [0.0] * n
        for l, jn in enumerate(ch['joints']):
            if l < rlk:
                continue
            kk = idx_of[jn]
            rl = radii[l] if l < len(radii) else 0.0
            off = (0.0, 0.0, 0.0)
            for v in vols:
                if v['kind'] == 'sphere' and v['ja'] == jn:
                    rl, off = v['ra'], v['off']
                    break
            qpts.append(P[kk] + cvc.world_off(ibms, kk, off))
            qrad.append(rl)
            qlab.append('%s/link%d' % (ch['name'], l))
    qpts = np.asarray(qpts)
    qrad = np.asarray(qrad)
    emit('   %6s %7s %9s %12s %12s %12s %10s'
         % ('budget', 'tris', 'pas_mm', 'cand_moy', 'cand_max', 'tests/frame', 'x vs auj.'))
    accel = {}
    for budget in BUDGETS:
        gd = dec[budget]['grid']
        cand = np.array([gd.candidates(qpts[i], qrad[i]) for i in range(len(qpts))], dtype=float)
        tf = LOOP_COLLIDE_CALLS * (float(cand.sum()) + nlink_sim * LOOP_SWEEPS)
        accel[budget] = (float(cand.mean()), float(cand.max()), tf)
        emit('   %6d %7d %9.1f %12.1f %12d %12.0f %10.1f'
             % (budget, len(dec[budget]['F']), gd.h / UNITS * 1000.0, cand.mean(), int(cand.max()),
                tf, tf / max(1.0, total_today)))
    emit('   (cand_moy = triangles candidats par lien et par requete de phase large. `tests/frame`')
    emit('    applique la MEME structure de boucle que ci-dessus : %d appels x [ candidats + %d x %d ].'
         % (LOOP_COLLIDE_CALLS, nlink_sim, LOOP_SWEEPS))
    emit('    Le cout de la phase large elle-meme — les lectures de cellule — n\'est PAS compte : il')
    emit('    est petit devant, mais il n\'est pas nul, et le pretendre serait une invention.)')
    gd = dec[BUDGETS[-1]]['grid']
    cand = np.array([gd.candidates(qpts[i], qrad[i]) for i in range(len(qpts))], dtype=float)
    order = np.argsort(-cand)[:4]
    emit('   Les liens les plus couteux a %d triangles (rayon de lien x candidats) :'
         % len(dec[BUDGETS[-1]]['F']))
    for i in order:
        emit('     %-18s rayon de lien %5.0f u  ->  %4d triangles candidats'
             % (qlab[i], qrad[i], int(cand[i])))
    emit('   `cand_moy` N\'EST PAS MONOTONE en fonction du budget, et ce n\'est pas du bruit : le pas')
    emit('   de la grille suit la taille des triangles, donc un mesh grossier a des cellules ENORMES')
    emit('   et une requete y ramene une grosse FRACTION d\'un petit ensemble. Le pas de grille est')
    emit('   un parametre libre qu\'on n\'a pas optimise ; l\'optimiser ferait baisser ces chiffres,')
    emit('   pas monter. Ils sont donc a lire comme un plafond de cette hypothese-la.')
    emit('')
    emit('   CE QUE CE CHIFFRE NE DIT PAS, ET IL FAUT LE DIRE : un test point->triangle et un test')
    emit('   point->capsule n\'ont pas le meme cout unitaire, un acces a une grille n\'a pas le meme')
    emit('   cout qu\'un acces a un tableau contigu de 48 volumes, et le Redmi n\'a pas le meme')
    emit('   comportement de cache qu\'un x86. LE RAPPORT DE TEMPS NE SE DEDUIT PAS DE CE RAPPORT')
    emit('   D\'OPERATIONS. Il demande une implementation et une course sur le device : ni l\'une')
    emit('   ni l\'autre n\'existe, et c\'est le chiffre 2 qui MANQUE.')
    emit('')

    # ==============================================================================================
    # CHIFFRE 3 — DEFORMATION / SKINNING
    # ==============================================================================================
    emit('== CHIFFRE 3 / DEFORMATION — CE QU\'IL FAUT RE-TRANSFORMER A CHAQUE FRAME ==============')
    nnz = (W > 0).sum(axis=1)
    emit('   MESURE SUR LE MESH (pas supposee) : influences osseuses par sommet, sur %d sommets.'
         % len(W))
    hist = np.bincount(nnz, minlength=5)
    emit('     moyenne = %.4f   repartition : 1 os %d sommets, 2 os %d, 3 os %d, 4 os %d'
         % (float(nnz.mean()), int(hist[1]), int(hist[2]), int(hist[3]), int(hist[4])))
    emit('     (le GLB porte 4 canaux JOINTS_0/WEIGHTS_0 ; la somme des poids vaut 1 a %.1e pres.)'
         % float(np.abs(W.sum(axis=1) - 1.0).max()))
    emit('')
    nsph_off = sum(1 for v in vols
                   if v['kind'] == 'sphere' and any(abs(x) > 0.0 for x in v['off']))
    ncap_off = sum(1 for v in vols
                   if v['kind'] == 'capsule' and any(abs(x) > 0.0 for x in v['off']))
    emit('   COTE CAPSULES, AUJOURD\'HUI. Les extremites d\'une capsule SONT des joints du rig :')
    emit('   le squelette les a deja transformees, la physique ne paie que la lecture. Le seul')
    emit('   travail propre est le report du decalage des volumes qui en ont un')
    emit('   (`phys-col-centre`, :1634-1643 — un produit vecteur-matrice quand l\'offset est non nul),')
    emit('   fait une fois par frame par `phys-snapshot-colliders!` (:1646, appelee :2671).')
    emit('     volumes a decalage non nul : %d spheres + %d capsules = %d produits vecteur-matrice'
         % (nsph_off, ncap_off, nsph_off + ncap_off))
    emit('     points a re-transformer proprement : %d (2 extremites x %d volumes) — mais ils sont'
         % (2 * len(vols), len(vols)))
    emit('     LUS dans le squelette, pas recalcules. Le cout marginal de la representation actuelle')
    emit('     est donc de %d produits vecteur-matrice par frame.' % (nsph_off + ncap_off))
    emit('')
    emit('   COTE MESH DECIME. Chaque sommet du collider doit etre SKINNE a chaque frame : une')
    emit('   combinaison de ses matrices osseuses. Le nombre d\'os par cellule est MESURE sur les')
    emit('   sommets qu\'elle regroupe (union de leurs os a poids non nul).')
    emit('   %6s %9s %10s %12s %12s %14s %12s'
         % ('budget', 'sommets', 'utilises', 'os_moyen', 'os_max', 'produits/frame', 'x capsules'))
    for budget in BUDGETS:
        d = dec[budget]
        inv = d['inv']
        used = d['used']
        used_set = set(used.tolist())
        bones_per = []
        for cl in used:
            mem = np.flatnonzero(inv == cl)
            bs = set()
            for c in range(J.shape[1]):
                bs.update(J[mem, c][W[mem, c] > 0.0].tolist())
            bones_per.append(len(bs))
        bones_per = np.asarray(bones_per, dtype=float)
        prod = float(bones_per.sum())
        emit('   %6d %9d %10d %12.2f %12d %14.0f %12.1f'
             % (budget, len(d['V']), len(used), bones_per.mean(), int(bones_per.max()),
                prod, prod / max(1.0, nsph_off + ncap_off)))
        d['bones_per'] = bones_per
    emit('   (produits/frame = somme des os influents sur les cellules utilisees : le cout exact')
    emit('    d\'un skinning lineaire sans troncature. Un moteur qui tronque a 4 influences comme')
    emit('    le GLB paierait au plus 4 par sommet ; les deux bornes sont donnees pour que le')
    emit('    choix se lise dans le chiffre, pas dans une preference.)')
    for budget in BUDGETS:
        d = dec[budget]
        cl4 = float(np.minimum(d['bones_per'], 4.0).sum())
        emit('     budget %5d : borne tronquee a 4 influences = %.0f produits/frame (%.1f x capsules)'
             % (budget, cl4, cl4 / max(1.0, nsph_off + ncap_off)))
    emit('')
    emit('   ET C\'EST LA QUE SE JOUE LA SUPERIORITE QUE L\'OWNER DECRIT : un mesh skinne SUIT la')
    emit('   deformation, une capsule ne le peut pas. Ce que ce script ne peut PAS chiffrer, faute')
    emit('   d\'implementation : de combien l\'ecart mesure ci-dessus se degrade sur une pose')
    emit('   EXTREME (bras leve, buste plie). A la pose de bind les deux representations sont a')
    emit('   leur meilleur ; hors bind, la capsule se degrade et le mesh skinne, par construction,')
    emit('   non. Ce chiffre-la MANQUE, et il faut une course pour l\'avoir.')
    emit('')

    # ==============================================================================================
    # CHIFFRE 4 — NIVEAUX
    # ==============================================================================================
    emit('== CHIFFRE 4 / NIVEAUX — LE CURSEUR DE PRECISION QUI EXISTE DEJA =====================')
    emit('   Le fichier de donnees porte trois niveaux (`[levels]` : level 0 / 1 / 2, le 1 etant')
    emit('   celui que l\'owner joue). La correspondance ci-dessous est proposee UNIQUEMENT sur les')
    emit('   chiffres du CHIFFRE 1 ; elle ne prejuge pas du cout device, qui n\'est pas mesure.')
    emit('   Reference d\'echelle : le personnage mesure %.4f m (corps seul, pose de bind).'
         % (height_body / UNITS))
    emit('')
    emit('   %-8s %-28s %10s %10s %12s %12s'
         % ('niveau', 'representation', 'ecart_max', 'ecart_p95', 'max_mm', 'p95_mm'))
    emit('   %-8s %-28s %10.4f %10.4f %12.1f %12.1f'
         % ('bas', '%d volumes (aujourd\'hui)' % len(vols), float(absc.max()) / UNITS,
            float(np.percentile(absc, 95)) / UNITS, 1000.0 * float(absc.max()) / UNITS,
            1000.0 * float(np.percentile(absc, 95)) / UNITS))
    mid_b = 500 if 500 in dec else BUDGETS[len(BUDGETS) // 2]
    hi_b = BUDGETS[-1]
    for lvl, b in (('moyen', mid_b), ('haut', hi_b)):
        d = dec[b]['d']
        emit('   %-8s %-28s %10.4f %10.4f %12.1f %12.1f'
             % (lvl, 'mesh decime, %d triangles' % len(dec[b]['F']), float(d.max()) / UNITS,
                float(np.percentile(d, 95)) / UNITS, 1000.0 * float(d.max()) / UNITS,
                1000.0 * float(np.percentile(d, 95)) / UNITS))
    emit('')
    emit('   CE QUE L\'ECART RESIDUEL VAUT A L\'ECHELLE DU PERSONNAGE (%.2f m) :' % (height_body / UNITS))
    emit('     bas   : %.1f mm au pire, soit %.1f %% de sa taille' %
         (1000.0 * float(absc.max()) / UNITS, 100.0 * float(absc.max()) / height_body))
    for lvl, b in (('moyen', mid_b), ('haut', hi_b)):
        d = dec[b]['d']
        emit('     %-5s : %.1f mm au pire, soit %.1f %% de sa taille'
             % (lvl, 1000.0 * float(d.max()) / UNITS, 100.0 * float(d.max()) / height_body))
    emit('   Repere utile : le rayon de lien des lunettes est %.0f u (%.1f mm) et celui du pan de'
         % (196.0, 1000.0 * 196.0 / UNITS))
    emit('   pantacourt %.0f u (%.1f mm) — un ecart de collider superieur a ces rayons ne peut pas'
         % (429.0, 1000.0 * 429.0 / UNITS))
    emit('   etre rattrape par le rayon du lien, il se voit.')
    emit('')

    # ==============================================================================================
    emit('== LES QUATRE CHIFFRES, EN UNE LIGNE CHACUN ==========================================')
    b500, b2000 = dec[500], dec[2000]
    emit('   1 FIDELITE   48 volumes : %.1f %% des %d sommets DEHORS de l\'union, depassement max'
         % (100.0 * float((sd_cone > 0).mean()), len(V)))
    emit('                %.4f m / p95 %.4f m ; enfouissement max %.4f m / p95 %.4f m.'
         % (float(outc.max()) / UNITS, float(np.percentile(outc, 95)) / UNITS,
            float(inc.max()) / UNITS, float(np.percentile(inc, 95)) / UNITS))
    emit('                Mesh decime : %d tris -> ecart max %.4f / p95 %.4f ; %d tris -> %.4f / %.4f.'
         % (len(b500['F']), float(b500['d'].max()) / UNITS,
            float(np.percentile(b500['d'], 95)) / UNITS, len(b2000['F']),
            float(b2000['d'].max()) / UNITS, float(np.percentile(b2000['d'], 95)) / UNITS))
    emit('                A 48 primitives contre 48, les CAPSULES gagnent (%.4f contre %.4f de max).'
         % (float(absc.max()) / UNITS, float(dec[48]['d'].max()) / UNITS))
    emit('                Des %d triangles, le MESH gagne (%.4f contre %.4f de max, %.1f x moins).'
         % (len(dec[200]['F']), float(dec[200]['d'].max()) / UNITS, float(absc.max()) / UNITS,
            float(absc.max()) / max(1e-9, float(dec[200]['d'].max()))))
    emit('   2 COUT       %.0f tests primitifs/frame aujourd\'hui. Mesh en force brute : x%.1f a %d'
         % (total_today, LOOP_COLLIDE_CALLS * (nlink_sim * len(b500['F'])
                                               + nlink_sim * LOOP_SWEEPS) / total_today,
            len(b500['F'])))
    emit('                triangles, x%.1f a %d. Avec grille uniforme mesuree : x%.1f et x%.1f.'
         % (LOOP_COLLIDE_CALLS * (nlink_sim * len(b2000['F']) + nlink_sim * LOOP_SWEEPS)
            / total_today, len(b2000['F']), accel[500][2] / total_today,
            accel[2000][2] / total_today))
    emit('                ESTIMATION ARITHMETIQUE, NON MESUREE SUR DEVICE.')
    emit('   3 DEFORMATION %.4f influence osseuse par sommet (mesuree). Capsules : %d produits'
         % (float(nnz.mean()), nsph_off + ncap_off))
    emit('                vecteur-matrice/frame. Mesh : %d sommets a skinner a %d tris, %d a %d tris.'
         % (len(b500['used']), len(b500['F']), len(b2000['used']), len(b2000['F'])))
    emit('   4 NIVEAUX    bas = %d volumes, ecart max %.0f mm ; moyen = %d tris, %.0f mm ; haut ='
         % (len(vols), 1000.0 * float(absc.max()) / UNITS, len(b500['F']),
            1000.0 * float(b500['d'].max()) / UNITS))
    emit('                %d tris, %.0f mm. Personnage mesure : %.2f m.'
         % (len(b2000['F']), 1000.0 * float(b2000['d'].max()) / UNITS, height_body / UNITS))
    emit('')

    emit('== CE QUE J\'AI SUPPOSE, ET CE QUI MANQUE =============================================')
    emit('   SUPPOSITIONS, toutes declarees :')
    emit('   1. Tout est mesure a la POSE DE BIND. C\'est le seul repere ou le fichier de donnees')
    emit('      est directement lisible, et c\'est le meilleur cas des deux representations.')
    emit('   2. La decimation est un groupement sur grille avec representant = moyenne. C\'est le')
    emit('      decimateur le plus simple ; un QEM ferait mieux a budget egal, donc les chiffres du')
    emit('      mesh sont une borne SUPERIEURE de son ecart.')
    emit('   3. La structure d\'acceleration supposee est une grille uniforme au pas de decimation.')
    emit('      Le nombre de candidats qu\'elle rend est MESURE sur les points de requete reels ; le')
    emit('      cout des lectures de cellule n\'est pas compte.')
    emit('   4. Le nombre de passes du solveur par frame est lu dans le source (11 appels x')
    emit('      (1 selection + 3 balayages)) et suppose INCHANGE si le collider changeait de nature.')
    emit('   5. Le taux de declenchement du recul vient de la derniere course de la salle ; il')
    emit('      depend des animations jouees et n\'est pas une constante du moteur.')
    emit('   6. Les 6 triangles d\'aire nulle du GLB sont retires : ils n\'ont pas de surface et')
    emit('      casseraient la distance point->triangle.')
    emit('')
    emit('   CE QUI MANQUE, ET QUI NE SE CALCULE PAS HORS LIGNE :')
    emit('   a. LE COUT PAR FRAME EN TEMPS, sur le Redmi. Il demande une implementation du collider')
    emit('      mesh ; elle n\'existe pas et ce script ne l\'ecrit pas. Le rapport d\'operations')
    emit('      publie ici n\'est PAS un rapport de temps.')
    emit('   b. LA FIDELITE HORS POSE DE BIND. C\'est l\'argument central de l\'owner (« en suivant')
    emit('      ses deformations ») et il ne se mesure qu\'en jouant les animations : de combien')
    emit('      l\'ecart des capsules se degrade quand elle se penche, et de combien celui du mesh')
    emit('      skinne ne se degrade pas.')
    emit('   c. LE COUT DE CONSTRUCTION/MISE A JOUR de la grille d\'acceleration quand le collider')
    emit('      bouge (il bouge a chaque frame, puisqu\'il est skinne). C\'est un cout par frame que')
    emit('      ce script ne modelise pas du tout.')
    emit('   d. L\'EFFET SUR LES DEFAUTS QUE L\'OWNER VOIT. Un meilleur collider est une hypothese de')
    emit('      correction, pas une correction : seule une course, puis son oeil, le disent.')
    emit('')

    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
    print('\n-> %s' % out_path)

    if fail:
        print('', file=sys.stderr)
        for s in fail:
            print('CONTROLE NON CONCLUANT : %s' % s, file=sys.stderr)
        print('Les chiffres ci-dessus ne valent rien tant que les deux controles ne tirent pas.',
              file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

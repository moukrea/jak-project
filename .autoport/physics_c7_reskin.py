#!/usr/bin/env python3
"""Cycle 7 — WEIGHT TRANSFER: give a physics joint authority over the geometry it represents.

Owner, 2026-08-07 07:50: Keira's chest "bouge un peu plus, mais elle est beaucoup plus FLASQUE
[...] et ne bouge PAS ASSEZ."  Cycle 6 answered that by raising the amplitude, and made it worse.
The skin-weight audit (.autoport/physics_c7_skinmap.py) says why, in the donor's own skinning
table and without any visual judgement:

    keira-hd  rBoob   90 verts, total weight 15.5, STRONGEST vertex 0.408, mean 0.172
              lBoob   94 verts, total weight 18.2, STRONGEST vertex 0.408, mean 0.193
              chest  1207 verts, total weight 854.7 — dominant on every one of those vertices

Not one breast vertex is majority-owned by the joint the solver moves.  Whatever the solver does
to rBoob reaches the screen at ~17% strength, and it reaches it UNEVENLY: the few vertices near
the centre carry 0.41 and the rim carries 0.02, so raising the amplitude moves the middle and
leaves the edge behind.  That is precisely "flasque" — a local dimple instead of a volume.  No
stiffness, damping, mass or firmness value can change it, which is why two cycles of tuning
produced "aucune difference".

So the fix is where the defect is: in the WEIGHTS.  For every vertex the artist already gave some
of the physics joint, this raises that share and takes it back from the body bone, KEEPING THE
ARTIST'S OWN SPATIAL PROFILE — the vertex the artist weighted most stays the one weighted most.
The breast then moves as a volume, and the base still blends into the chest, because a breast is
attached to a chest.

    s        = w_target / max(w_target)        the artist's normalised profile, untouched in shape
    w_target'= cap * s**shape                  re-scaled so the peak reaches `cap`
    the gain is taken from `from=` joints in proportion to what they hold, then the vertex is
    renormalised to sum 1.

`shape` < 1 widens the shoulder of the profile (more of the breast moves together), `shape` = 1
is a pure rescale.  `grow=` optionally dilates the support first, for a donor whose painted patch
is too small to be a volume at all.

This is the "injection d'os + transfert de poids" the phase prompt anticipated for stock rigs,
applied here to a joint that already exists but was painted decoratively.  Nothing else in the
model changes: same joints, same positions, same triangles.

Usage (called from scripts/shell/build_enhanced_models.sh between prep and hd_merc_swap):
  python3 .autoport/physics_c7_reskin.py --model keira-hd --in prepped.glb --out prepped.glb
  python3 .autoport/physics_c7_reskin.py --audit          # print what the config would do
"""
import argparse
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts', 'shell'))
from retarget_hd_models import (read_glb, consolidate_buffers, read_accessor,  # noqa: E402
                                append_accessor, write_glb, gc_glb, skin_info)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CFG = os.path.join(REPO, 'recharged_assets', 'physics_reskin.txt')
UNITS = 4096.0


def load_cfg(path=CFG):
    """-> {model: [dict(target, donors, cap, shape, grow)]}

    PAS DE FICHIER = PAS DE REGLE, et c'est un etat legitime : le depart propre du 2026-08-11
    (`f86d919800`, TABLE RASE) a supprime `recharged_assets/physics_reskin.txt`. `main()` sait
    deja traiter « aucune regle » — il recopie l'entree telle quelle (« no rule — passthrough »).
    Or l'ouverture etait INCONDITIONNELLE et levait FileNotFoundError avant tout filtrage, donc
    exit != 0, donc `scripts/shell/build_enhanced_models.sh:233` tuait TOUT le bake HD. Le mesh
    livre ne pouvait plus etre reconstruit depuis l'arbre : la paire livree n'etait pas
    reproductible, et aucune correction de ponderation n'aurait pu devenir visible."""
    out, cur = {}, []
    if not os.path.exists(path):
        return out
    for ln in open(path, errors='ignore'):
        ln = ln.split('#')[0].strip()
        if not ln:
            continue
        m = re.match(r'^\[model ([^\]]+)\]$', ln)
        if m:
            cur = m.group(1).split()
            for x in cur:
                out.setdefault(x, [])
            continue
        f = ln.split()
        if f[0] not in ('transfer', 'grade', 'redistribute') or not cur:
            continue
        kv = dict(x.split('=', 1) for x in f[2:] if '=' in x)
        r = dict(kind=f[0],
                 target=f[1],
                 donors=[d for d in kv.get('from', '').split(',') if d],
                 cap=float(kv.get('cap', 0.9)),
                 shape=float(kv.get('shape', 1.0)),
                 grow=float(kv.get('grow', 0.0)),
                 # `transfer` only: TERME SPATIAL. Abscisse curviligne minimale, le long de la
                 # polyligne de `chain=`, en dessous de laquelle la regle ne prend RIEN (racine=0,
                 # pointe=1). Defaut 0.0 = aucun effet, comportement d'avant bit-pour-bit.
                 #
                 # POURQUOI IL A FALLU L'AJOUTER (2026-08-13, mesure du 4e passage plus haut dans
                 # recharged_assets/physics_reskin.txt) : `new = cap*(wt/p90)**shape` n'a AUCUN terme
                 # spatial, donc l'operateur ne distingue un sommet de RACINE d'un sommet de MILIEU
                 # que par le poids peint. Or le support peint de `backHair2`/`Lmidhairb`/`Rmidhairb`
                 # couvre TOUTE la meche, racine comprise (backHair2 : 0.195 en d1 contre 0.374 en
                 # d5). Sept configurations ont ete passees dans l'operateur reel (shape 0.12/0.40/
                 # 0.55 concaves, 1.50/2.50/4.00 convexes) : les concaves DESANCRENT (80 bascules
                 # dont 42 a la racine, s<0.10), les convexes saturent et raidissent la falaise.
                 # La conclusion ecrite alors etait « le seul levier reellement spatial est le CHOIX
                 # DU JOINT CIBLE » — c'est vrai de l'operateur d'alors, pas de l'operateur possible.
                 # `smin=` EST ce levier spatial : il laisse lever le milieu SANS lever la racine.
                 smin=float(kv.get('smin', 0.0)),
                 # `grade` only: la marche de poids maximale toleree entre deux sommets VOISINS.
                 # 0.45 et pas 0.50 : `tear` compte des que la marche DEPASSE 0.50, et viser 0.50
                 # pile laissait la renormalisation repasser au-dessus du seuil (mesure : 59 aretes
                 # restantes, toutes a 0.500). 0.45 est aussi la marche de `backhair`, la jonction
                 # qui ne casse pas — on se cale sur la sante mesuree, pas sur le seuil de la gate.
                 step=float(kv.get('step', 0.45)),
                 # `grade` only: ce que le cote HAUT d'une arete trop raide peut ceder au maximum.
                 # Necessaire parce que l'ancrage plafonne le cote bas a 0.50 : sans ca une arete
                 # 1.00/0.00 ne peut pas descendre sous une marche de 0.50. 0.10 = un sommet garde
                 # au moins 90 % de sa propriete.
                 drop=float(kv.get('drop', 0.10)),
                 # `grade` only: TOUS les joints dont le poids SOMME est la grandeur qui dechire.
                 # `tear` se mesure sur cette somme, donc `grade` doit la graduer ELLE : graduer un
                 # joint isole mesurait autre chose que le defaut (2026-08-12, rmidhair 82 -> 68).
                 chain=[c for c in kv.get('chain', '').split(',') if c],
                 # ABSCISSE DE REFERENCE de `smin=`. Par defaut elle se lit sur la polyligne de
                 # `chain=` ; or les regles `grade` de milieu de meche ont un `chain=` qui DEMARRE
                 # au maillon du milieu (`chain=backHair2,backHair3,backHair4`), donc leur s=0
                 # tombe a mi-meche et `smin=0.30` n'y voudrait plus dire « 30 % le long de la
                 # meche ». `sarc=` nomme la polyligne COMPLETE racine->pointe, celle que publie
                 # `probe_skin_profile.py`, pour qu'un seuil garde le sens que la sonde lui donne.
                 sarc=[c for c in kv.get('sarc', '').split(',') if c],
                 # LARGEUR DE LA RAMPE au-dessus de `smin`. 0.0 = coupure NETTE (comportement
                 # d'avant, bit-pour-bit).
                 #
                 # POURQUOI ELLE EXISTE (2026-08-13, mesure). Une coupure nette EST une marche : en
                 # levant le milieu au-dessus de `smin` et rien en dessous, `smin` FABRIQUE une
                 # discontinuite de poids exactement a `smin`. Cuisson mesuree : `tear_mov` 0 -> 21
                 # (backhair), 0 -> 15 (lmidhair), 0 -> 31 (rmidhair), aretes cassees a
                 # s=0.16..0.50, c'est-a-dire SUR la frontiere. Et `grade`, dont c'est le metier de
                 # refermer ces marches, portait le meme `smin` : il lui etait donc interdit
                 # d'entrer la ou la marche venait d'apparaitre. Les deux termes se contredisaient.
                 #
                 # Une RAMPE supprime la contradiction a la source : le gain monte progressivement
                 # de 0 a `smin` jusqu'a 1 a `smin+sramp`, donc il n'y a plus de marche a refermer.
                 # C'est la FORME du controle approuve : le profil mobile de `lbang` monte 0.15 (d3)
                 # -> 0.48 (d4) -> 0.97 (d6), une transition etalee sur ~0.25 d'abscisse, jamais un
                 # saut. On copie une forme mesuree sur l'echantillon que l'owner valide.
                 sramp=float(kv.get('sramp', 0.0)),
                 # `redistribute` only : poids SOMME minimal sur la chaine pour qu'un sommet soit
                 # considere comme appartenant a la meche. Meme seuil que le `GATE` de
                 # `probe_skin_profile.py`, pour que la regle et la sonde parlent des memes sommets.
                 gate=float(kv.get('gate', 0.05)),
                 # `redistribute` only : BANDE D'ANCRAGE. Le maillon 0 (verrouille par `rootlock=1`)
                 # detient SEUL toute la peau sous cette abscisse ; les maillons libres se partagent
                 # ce qui reste, au-dela. 0.0 = pas de bande (partition sur la meche entiere).
                 #
                 # POURQUOI (mesure du 2026-08-13 22:45). Sans bande, la partition rend le maillon 0
                 # majoritaire seulement AU VOISINAGE de s=0 : des que l'abscisse depasse celle du
                 # premier joint libre, la racine passe au maillon 1 et la nuque SE DECOLLE —
                 # `backhair` d1 0.00 -> 0.11, `lmidhair` d3 0.14 -> 0.39. Or `rootlock=1` dit
                 # exactement le contraire : cette peau est SOUDEE a l'os porteur (SPEC 2, acquis
                 # FERME par l'owner : « les cheveux de la nuque sont bien ancres la ou ils doivent
                 # l'etre »). La bande n'est pas un reglage, c'est l'expression de `rootlock`.
                 hold=float(kv.get('hold', 0.0)),
                 iters=int(kv.get('iters', 8)))
        for x in cur:
            out[x].append(r)
    return out


def _redistribute(r, J, W, idx, P, bind_pos):
    """REPARTIT le poids de la chaine ENTRE ses joints, selon l'abscisse. Mute J/W en place.

    POURQUOI CET OPERATEUR EXISTE (2026-08-13, apres trois cuissons mesurees). `transfer` et `grade`
    travaillent tous les deux A PARTIR du poids peint par l'artiste : l'un vise
    `cap*(wt/p90)**shape`, l'autre diffuse la marche existante. Aucun des deux ne peut SUPPRIMER la
    frontiere binaire du donneur — ils ne font que la deplacer — et toute coupure spatiale qu'on
    leur ajoute FABRIQUE une marche a l'endroit de la coupure (mesure : `tear_mov` 0 -> 21/15/31,
    aretes cassees a s=0.16..0.56, exactement sur la frontiere).

    Celui-ci ne rustine pas la peinture : il la RECALCULE le long de la meche.

    L'INVARIANT QUI REND LE DESANCRAGE IMPOSSIBLE : le poids SOMME de la chaine sur un sommet
    (`ws`) est CONSERVE. On ne touche jamais au partage tete/meche — donc la peau soudee au crane le
    reste, `cov` ne bouge pas, et le seul degre de liberte est : lequel des maillons de la chaine
    porte ce poids. A l'abscisse 0 la partition donne tout au maillon 0, celui que `rootlock=1`
    verrouille : la racine reste soudee (SPEC 2, et c'est l'acquis que l'owner a FERME).

    L'INVARIANT QUI REND LA DECHIRURE IMPOSSIBLE : la partition est une fonction CONTINUE de
    l'abscisse (interpolation lineaire entre les positions des joints, en pose de bind). La fraction
    mobile varie donc continument le long de la meche. Il n'y a plus de marche a refermer parce
    qu'il n'y a plus de frontiere — au lieu d'en deplacer une.

    EFFET DE BORD UTILE : l'interpolation lineaire ne rend que DEUX joints non nuls par sommet, donc
    la regle ne peut pas saturer les 4 creneaux d'influence.
    """
    rep = []
    joints = [j for j in r['chain'] if j in idx]
    if len(joints) < 2:
        rep.append(f"  !! {r['target']}: moins de 2 joints de `chain=` dans ce rig"
                   f" — regle REFUSEE plutot qu'appliquee a moitie")
        return rep
    grp = [idx[j] for j in joints]

    ws = np.zeros(len(W))
    for c in range(J.shape[1]):
        ws += np.where(np.isin(J[:, c], grp), W[:, c], 0.0)
    vi = np.nonzero(ws > r['gate'])[0]
    if not len(vi):
        rep.append(f"  -- {r['target']}: aucun sommet au-dessus de gate={r['gate']:.2f}")
        return rep

    pts = np.asarray([bind_pos(j) for j in joints], dtype=float)
    seg = pts[1:] - pts[:-1]
    seglen = np.linalg.norm(seg, axis=1)
    total = float(seglen.sum())
    if total <= 1e-9:
        rep.append(f"  !! {r['target']}: polyligne de longueur nulle — regle REFUSEE")
        return rep
    cum = np.concatenate([[0.0], np.cumsum(seglen)])
    tk = cum / total                                   # abscisse de chaque JOINT
    # BANDE D'ANCRAGE : on comprime TOUTE la polyligne des noeuds dans [hold, 1]. Le maillon 0 tient
    # alors seul alors tout ce qui est sous `hold` (branche `s < tk[0]` plus bas), et son influence
    # decroit ENSUITE continument jusqu'au premier maillon libre — pas de saut, donc pas de couture.
    if r['hold'] > 0.0:
        tk = r['hold'] + (1.0 - r['hold']) * tk

    # Abscisse de chaque sommet — meme construction que `probe_skin_profile.py:arc_param`, la mesure
    # qui reproduit le verdict de l'owner : on projette sur CHAQUE segment, parametre borne a [0,1],
    # on garde le plus proche.
    V = P[vi]
    best_d = np.full(len(vi), np.inf)
    s = np.zeros(len(vi))
    for k in range(len(seg)):
        L2 = float(seg[k] @ seg[k])
        if L2 <= 1e-12:
            continue
        t = np.clip(((V - pts[k]) @ seg[k]) / L2, 0.0, 1.0)
        d = np.linalg.norm(V - (pts[k] + t[:, None] * seg[k]), axis=1)
        m = d < best_d
        best_d[m] = d[m]
        s[m] = (cum[k] + t[m] * seglen[k]) / total

    # PARTITION DE L'UNITE, lineaire par morceaux : un sommet a l'abscisse d'un joint lui appartient
    # entierement, entre deux joints il se partage lineairement. C'est la forme qu'a une peau bien
    # peinte, et c'est la plus simple qui soit continue.
    A = np.zeros((len(vi), len(joints)))
    for a in range(len(joints) - 1):
        lo, hi = tk[a], tk[a + 1]
        last = (a == len(joints) - 2)
        m = (s >= lo) & (s <= hi) if last else (s >= lo) & (s < hi)
        if not m.any():
            continue
        u = (s[m] - lo) / (hi - lo) if (hi - lo) > 1e-12 else np.zeros(int(m.sum()))
        A[m, a] += 1.0 - u
        A[m, a + 1] += u
    A[s < tk[0], 0] = 1.0                              # au-dessus de la racine
    A[s > tk[-1], -1] = 1.0                            # au-dela de la pointe
    rs = A.sum(axis=1)
    A = A / np.where(rs < 1e-12, 1.0, rs)[:, None]

    moved = 0.0
    for i, v in enumerate(vi):
        keep = [(int(J[v, c]), float(W[v, c])) for c in range(J.shape[1])
                if int(J[v, c]) not in grp and W[v, c] > 0.0]
        new = [(grp[k], float(ws[v]) * float(A[i, k])) for k in range(len(joints))
               if A[i, k] > 1e-6]
        rows = keep + new
        if len(rows) > J.shape[1]:                     # ne peut pas arriver avec 2 joints non nuls,
            rows.sort(key=lambda x: -x[1])             # mais on ne laisse pas un depassement muet
            rows = rows[:J.shape[1]]
        before = {int(J[v, c]): float(W[v, c]) for c in range(J.shape[1])}
        J[v, :] = 0
        W[v, :] = 0.0
        for c, (jj, wv) in enumerate(rows):
            J[v, c] = jj
            W[v, c] = wv
        tot = W[v].sum()
        if tot > 1e-12:
            W[v] /= tot
        moved += sum(abs(w - before.get(j, 0.0)) for j, w in rows) * 0.5

    after = np.zeros(len(joints))
    for c in range(J.shape[1]):
        for k, g in enumerate(grp):
            after[k] += float(np.where(J[:, c] == g, W[:, c], 0.0).sum())
    tot = after.sum() if after.sum() > 1e-12 else 1.0
    free = after[1:] / (after[1:].sum() if after[1:].sum() > 1e-12 else 1.0)
    rep.append(f"  {r['target']:<10} redistribue verts={len(vi)} masse deplacee={moved:.1f}"
               f" — part des segments LIBRES: "
               + " ".join(f"{100.0 * x:.1f}%" for x in free)
               + f" (pire {100.0 * free.max():.1f}%)")
    return rep


def _grade(r, J, W, idx, ed, sarc=None):
    """GRADUATION DE JONCTION sur le poids SOMME d'une chaine.  Mute J/W en place.

    LES TROIS QUESTIONS DE LA SPEC 7, repondues avant d'ecrire la mesure :

      NATURE — une FORME de discontinuite, pas une amplitude : une MARCHE de poids entre deux
        sommets VOISINS.  C'est mot pour mot ce que l'owner decrit le 2026-08-12 : « des polygones
        qui bougent et des polygones voisins parfaitement statiques, causant la geometrie qui
        casse ».  Un scalaire par chaine ne peut pas la voir.
      REPERE — l'arete du mesh, sur le poids SOMME de TOUS les joints de la chaine.  C'est la
        correction de fond de ce cycle : `grade` travaillait par JOINT alors que `tear` se mesure
        sur la somme, donc il bornait la marche de `Rmidhaira` pendant que celle de
        `Rmidhaira + Rmidhairb` restait a 1.0 — d'ou 82 -> 68 au lieu de 0.  On graduait une
        grandeur qui n'etait pas celle qui dechire.
      LIGNE DE BASE — `backhair`, attache au MEME crane, ne casse pas et sa marche max vaut 0.451.
        La jonction saine existe deja dans le mesh : on la copie, on ne l'invente pas.

    DEUX INVARIANTS, et le second est celui qui a fait rejeter la regle jak-hd a l'epoque :
      1. on ne remonte QUE le cote bas d'une arete trop raide, jamais on ne baisse le cote haut —
         baisser le haut retirerait du mouvement, et le mouvement est ce que l'owner reclame ;
      2. un sommet qui n'appartenait PAS majoritairement a la chaine ne peut pas le devenir.
         Plafond dur a 0.50 : la rangee montee reste a moitie tenue par `head`, donc la meche
         reste SOUDEE au crane (SPEC 2).  C'est exactement le basculement (« 1 sommet de cuir
         chevelu pur au-dela de 0.5 ») pour lequel ce correctif n'a pas ete livre au cycle
         precedent — il est desormais interdit par construction, pas tolere.
    """
    rep = []
    grp = [idx[j] for j in (r['chain'] or [r['target']]) if j in idx]
    if not grp:
        rep.append(f"  !! {r['target']}: aucun joint de chaine present dans le rig")
        return rep
    if not ed:
        rep.append(f"  !! {r['target']}: aucune arete lisible — `grade` mesure un VOISINAGE,"
                   f" il ne peut pas travailler sans les triangles")
        return rep

    n = len(W)
    ws = np.zeros(n)
    for c in range(J.shape[1]):
        ws += np.where(np.isin(J[:, c], grp), W[:, c], 0.0)

    # Le receveur du gain, par sommet : le joint de la chaine qui tient DEJA le plus de poids ici.
    # On renforce l'attribution de l'artiste au lieu d'inventer un ancrage.
    recv = np.full(n, -1, dtype=np.int64)
    best = np.zeros(n)
    for c in range(J.shape[1]):
        m = np.isin(J[:, c], grp) & (W[:, c] > best)
        recv = np.where(m, J[:, c], recv)
        best = np.where(m, W[:, c], best)

    # Gauss-Seidel sur les aretes, ordre TRIE donc deterministe (un set n'a pas d'ordre stable et
    # le resultat d'un bake doit etre reproductible).
    #
    # POURQUOI LE COTE HAUT DESCEND UN PEU, alors que le cycle precedent l'interdisait.
    # Les deux bornes du probleme sont incompatibles si on ne touche QUE le cote bas :
    #   - `tear` compte une arete des que la marche depasse 0.50 ;
    #   - l'ancrage (invariant 2) interdit au cote bas de depasser 0.50.
    # Une arete 1.00 / 0.00 se termine donc au mieux a 0.50 / 0.50 — marche 0.50, et c'est
    # EXACTEMENT ce qui a ete mesure : 59 aretes restantes, toutes a une marche de 0.500, que la
    # renormalisation fait repasser d'un cheveu au-dessus du seuil.  Ne remonter que le bas ne peut
    # pas fermer ce defaut, c'est arithmetique.
    # On autorise donc le cote haut a ceder au plus `drop` (0.10 par defaut) : un sommet a 1.00
    # descend a 0.95, garde 95 % de sa propriete — le mouvement qu'il perd est negligeable et il
    # est CHIFFRE dans le rapport — et l'arete se ferme a 0.45.  C'est un echange mesure, pas un
    # suppresseur : rien n'est retire ailleurs que sur la rangee de bordure elle-meme.
    edl = sorted(ed)
    new = ws.copy()
    for _ in range(r['iters']):
        moved = 0.0
        for (u, v) in edl:
            hi, lo = (u, v) if new[u] > new[v] else (v, u)
            d = new[hi] - new[lo] - r['step']
            if d <= 0.0:
                continue
            # invariant 2 : pas de bascule en majorite pour un sommet qui n'y etait pas.
            ceil_lo = 1.0 if ws[lo] >= 0.5 else 0.5
            take = max(0.0, min(new[lo] + d, ceil_lo) - new[lo])
            new[lo] += take
            d -= take
            cut = 0.0
            if d > 1e-12:                      # le bas est bloque par l'ancrage : le haut cede
                cut = max(0.0, min(d, new[hi] - max(0.0, ws[hi] - r['drop'])))
                new[hi] -= cut
            moved += take + cut
        if moved <= 1e-9:
            break
    new = np.clip(new, 0.0, 1.0)

    delta = new - ws
    gain = np.maximum(delta, 0.0)

    # TERME SPATIAL, MEME SEMANTIQUE QUE SUR `transfer` : sous l'abscisse, la regle est INERTE —
    # elle ne prend rien ET ne donne rien. `smin=0.0` par defaut => comportement d'avant
    # bit-pour-bit. Il a fallu l'ajouter a `grade` AUSSI parce que `grade` est une DIFFUSION :
    # couper le `transfer` a s=0.30 ne suffit pas, la marche qu'il cree a la frontiere est ensuite
    # rediffusee VERS LA RACINE par le Gauss-Seidel (mesure 2026-08-13 : avec le seul `transfer`
    # coupe, le profil MOBILE de backhair monte de 0.00 a 0.08 a son PREMIER decile, c'est-a-dire
    # dans la bande d'ancrage que l'owner a explicitement FERMEE).
    if r['smin'] > 0.0:
        if sarc is None:
            rep.append(f"  !! {r['target']}: smin= demande mais l'abscisse n'a pas pu etre"
                       f" construite (sarc=/chain= ne presente pas 2 joints de ce rig) —"
                       f" regle REFUSEE plutot qu'appliquee a moitie")
            return rep
        blocked = int(((sarc < r['smin']) & (np.abs(delta) > 1e-9)).sum())
        k = (np.clip((sarc - r['smin']) / r['sramp'], 0.0, 1.0) if r['sramp'] > 0.0
             else (sarc >= r['smin']).astype(float))
        delta = delta * k
        gain = np.maximum(delta, 0.0)
        rep.append(f"  .. {r['target']}: spatial smin={r['smin']:.2f}"
                   f" rampe={r['sramp']:.2f} — {blocked} sommet(s) sous l'abscisse laisses INTACTS")

    if not (np.abs(delta) > 1e-9).any():
        rep.append(f"  -- {r['target']}: jonction deja graduee (aucune marche > {r['step']})")
        return rep

    # Un sommet souleve qui ne porte encore aucun joint de la chaine adopte le receveur de son
    # voisin le plus fort : le poids vient de la, c'est donc ce joint qui doit le porter.  Borne
    # par le plafond 0.50, la manoeuvre ne peut pas detacher le sommet du corps.
    nbr = {}
    for (u, v) in edl:
        nbr.setdefault(u, []).append(v)
        nbr.setdefault(v, []).append(u)
    for _ in range(4):
        orphan = np.nonzero((gain > 1e-9) & (recv < 0))[0]
        if not len(orphan):
            break
        for vi in orphan:
            cand = [(new[x], recv[x]) for x in nbr.get(int(vi), []) if recv[x] >= 0]
            if cand:
                recv[vi] = max(cand)[1]

    don = [idx[d] for d in r['donors'] if d in idx]
    lifted, took, given, eased = 0, 0.0, 0.0, 0
    for vi in np.nonzero(np.abs(delta) > 1e-9)[0]:
        if delta[vi] > 0:
            t = int(recv[vi])
            if t < 0:
                continue
            slot = -1
            for c in range(J.shape[1]):
                if J[vi, c] == t:
                    slot = c
                    break
            if slot < 0:                   # pas encore de creneau : on prend le plus leger
                slot = int(np.argmin(W[vi]))
                J[vi, slot] = t
                W[vi, slot] = 0.0
            avail = [(c, W[vi, c]) for c in range(J.shape[1])
                     if J[vi, c] in don and W[vi, c] > 0]
            pool = sum(w for _, w in avail)
            g = min(float(gain[vi]), pool)
            if g <= 0:
                continue
            for c, w in avail:
                W[vi, c] -= g * (w / pool)
            W[vi, slot] += g
            lifted += 1
            took += g
        else:
            # Le cote haut cede : le poids repart vers les donneurs, proportionnellement a ce que
            # les joints de la chaine tiennent ici. Borne par `drop`, donc au plus 10 % de propriete.
            mine = [(c, W[vi, c]) for c in range(J.shape[1])
                    if J[vi, c] in grp and W[vi, c] > 0]
            pool = sum(w for _, w in mine)
            g = min(-float(delta[vi]), pool)
            if g <= 0:
                continue
            for c, w in mine:
                W[vi, c] -= g * (w / pool)
            back = [c for c in range(J.shape[1]) if J[vi, c] in don]
            if not back:                   # aucun donneur present : on prend le creneau le plus leger
                c0 = int(np.argmin(W[vi]))
                J[vi, c0] = don[0] if don else J[vi, c0]
                back = [c0]
            for c in back:
                W[vi, c] += g / len(back)
            eased += 1
            given += g

    tot = W.sum(axis=1, keepdims=True)
    W[:] = np.where(tot > 0, W / np.maximum(tot, 1e-12), W)

    after = np.zeros(n)
    for c in range(J.shape[1]):
        after += np.where(np.isin(J[:, c], grp), W[:, c], 0.0)
    flipped = int(((ws < 0.5) & (after > 0.5 + 1e-6)).sum())
    step_before = max((abs(ws[u] - ws[v]) for (u, v) in edl
                       if ws[u] > 0 or ws[v] > 0), default=0.0)
    step_after = max((abs(after[u] - after[v]) for (u, v) in edl
                      if after[u] > 0 or after[v] > 0), default=0.0)
    lost = float(np.maximum(ws - after, 0.0).sum())
    rep.append(f"  {r['target']:<10} graded verts={lifted} marche max {step_before:.3f}->"
               f"{step_after:.3f} poids pris a {','.join(r['donors'])}={took:.1f} "
               f"rendu={given:.2f} sur {eased} sommet(s) (propriete perdue={lost:.2f}) "
               f"bascules>0.5={flipped}")
    # Invariant 2 viole = detachement de la meche : c'est le defaut jak-hd rejete, il doit crier.
    if flipped:
        rep.append(f"  !! {r['target']}: {flipped} sommet(s) ont bascule en majorite vers la meche"
                   f" — la meche se detache du crane, SPEC 2 l'interdit")
    return rep


def apply_model(js, binc, rules, verbose=True):
    """Rewrite WEIGHTS_0 in place for every primitive.  Returns a list of report lines."""
    names, ibms, _ = skin_info(js, binc)
    idx = {n: i for i, n in enumerate(names)}
    rep = []

    def bind_pos(jname):
        """Bind-pose world position of a joint, in GAME UNITS — same space as `P`.

        The inverse bind matrix maps world -> joint, so its inverse is the joint's bind world
        transform and its translation is the joint's bind position. `skin_info` returns the IBMs
        already un-column-majored, and glTF metres become game units by the same UNITS factor `P`
        uses, so the two are directly comparable.
        """
        return np.linalg.inv(ibms[idx[jname]])[:3, 3] * UNITS

    def arc_abscissa(chain_joints, Pv):
        """Curvilinear abscissa of every vertex along the chain's joint polyline (root 0, tip 1).

        Same construction as `.autoport/probe_skin_profile.py:arc_param`, which is the measurement
        that reproduces the owner's verdict on this defect: project onto EVERY segment with the
        parameter clamped to [0,1], keep the nearest segment, and return the cumulative length up
        to it plus the in-segment part, divided by the total. Building it the same way is what
        lets a rule be written against a decile the probe publishes.
        """
        pts = [bind_pos(j) for j in chain_joints if j in idx]
        if len(pts) < 2:
            return None
        pts = np.asarray(pts)
        seg = pts[1:] - pts[:-1]
        seglen = np.linalg.norm(seg, axis=1)
        total = float(seglen.sum())
        if total <= 0.0:
            return None
        cum = np.concatenate([[0.0], np.cumsum(seglen)])
        best_d = np.full(len(Pv), np.inf)
        best_s = np.zeros(len(Pv))
        for k in range(len(seg)):
            L2 = float(seg[k] @ seg[k])
            if L2 <= 0.0:
                continue
            t = np.clip(((Pv - pts[k]) @ seg[k]) / L2, 0.0, 1.0)
            proj = pts[k] + t[:, None] * seg[k]
            d = np.linalg.norm(Pv - proj, axis=1)
            take = d < best_d
            best_d[take] = d[take]
            best_s[take] = (cum[k] + t[take] * seglen[k]) / total
        return best_s

    # Aretes du mesh, par jeu d'attributs. `grade` en a besoin : c'est un defaut de VOISINAGE
    # (« des polygones qui bougent et des polygones voisins parfaitement statiques »), donc il se
    # mesure et se corrige sur les aretes, pas sur des sommets pris isolement. On les collecte pour
    # TOUTES les primitives qui partagent le meme jeu d'attributs, car la boucle ci-dessous n'en
    # traite qu'une seule et les autres reutilisent son resultat.
    edges_by_key = {}
    for mesh in js.get('meshes', []):
        for pr in mesh.get('primitives', []):
            if 'indices' not in pr or int(pr.get('mode', 4)) != 4:
                continue
            at = pr['attributes']
            ind = np.asarray(read_accessor(js, binc, pr['indices'])).reshape(-1)
            e = edges_by_key.setdefault((at['JOINTS_0'], at['WEIGHTS_0']), set())
            for i in range(0, (len(ind) // 3) * 3, 3):
                a, b, c = int(ind[i]), int(ind[i + 1]), int(ind[i + 2])
                for u, v in ((a, b), (b, c), (a, c)):
                    e.add((u, v) if u < v else (v, u))

    # every primitive shares one attribute set in a prepped glb, but do not assume it
    #
    # LE CACHE DOIT PORTER LES DEUX ACCESSEURS, ET C'EST LA CAUSE DE `hair-skinning`.
    # `_grade` et `transfer` MUTENT `J` (ils volent le creneau le plus leger : `J[vi, slot] = t`),
    # donc le `W` neuf n'a de sens QUE contre le `J` neuf. Ce cache ne rendait que `WEIGHTS_0` :
    # la premiere primitive d'une cle recevait bien les deux accesseurs neufs, TOUTES LES SUIVANTES
    # recevaient le poids neuf contre la table de joints PERIMEE. Le poids gradue atterrissait alors
    # sur le joint que l'ancienne table portait dans ce creneau — `prejoint`.
    # MESURE SUR LE MESH LIVRE (out/jak1/fr3/skin/keira-hd-lod0.glb, md5 8af2f36d) :
    #     J=3  W=35  27 primitives (LE CORPS, ce qui rend) : prejoint 85 sommets, masse 17.81
    #     J=34 W=35   1 primitive                          : prejoint  0 sommets, masse  0.00
    # Ces 85 sommets sont autour des jonctions cuir chevelu/meche : ils restent immobiles pendant
    # que leurs voisins bougent — mot pour mot le defaut que l'owner decrit (« des polygones qui
    # bougent et des polygones voisins parfaitement statiques, causant la geometrie qui casse »).
    # Et c'est pour ca que chaque correctif de peau mesurait vert : la mesure lisait la primitive 0,
    # la seule dont la table etait juste.
    seen = {}
    for mesh in js.get('meshes', []):
        for pr in mesh.get('primitives', []):
            at = pr['attributes']
            key = (at['JOINTS_0'], at['WEIGHTS_0'])
            if key in seen:
                at['JOINTS_0'], at['WEIGHTS_0'] = seen[key]
                continue
            J = read_accessor(js, binc, at['JOINTS_0']).astype(np.int32)
            W = read_accessor(js, binc, at['WEIGHTS_0']).astype(np.float64)
            P = read_accessor(js, binc, at['POSITION']).astype(np.float64) * UNITS

            for r in rules:
                if r['kind'] == 'redistribute':
                    # Il ne partage la queue d'aucun des deux autres : il ne vise pas un joint
                    # unique (`transfer`) et il ne diffuse pas une marche existante (`grade`) — il
                    # REPARTIT un poids somme conserve entre les joints de la chaine.
                    rep.extend(_redistribute(r, J, W, idx, P, bind_pos))
                    continue
                if r['kind'] == 'grade':
                    # `grade` travaille sur le poids SOMME de la chaine et distribue le gain sur un
                    # receveur qui varie par sommet : il ne peut pas partager la queue de `transfer`,
                    # qui suppose un joint cible unique.
                    g_sarc = None
                    if r['smin'] > 0.0:
                        g_sarc = arc_abscissa(r['sarc'] or r['chain'] or [r['target']], P)
                    rep.extend(_grade(r, J, W, idx, edges_by_key.get(key), g_sarc))
                    continue
                t = idx.get(r['target'])
                if t is None:
                    rep.append(f"  !! target joint {r['target']} not in rig — skipped")
                    continue
                wt = np.zeros(len(W))
                for c in range(J.shape[1]):
                    wt += np.where(J[:, c] == t, W[:, c], 0.0)
                sup = wt > 0
                if not sup.any():
                    rep.append(f"  !! {r['target']}: no vertex carries this joint — nothing to grow")
                    continue
                wmax = float(np.quantile(wt[sup], 0.90))
                if wmax <= 1e-6:
                    wmax = float(wt.max())

                # optional spatial dilation of the support, for a patch too small to be a volume
                if r['grow'] > 0:
                    S = P[sup]
                    for vi in np.nonzero(~sup)[0]:
                        d = S - P[vi]
                        if float((d * d).sum(axis=1).min()) <= r['grow'] ** 2:
                            wt[vi] = 1e-6      # joins the support at the very bottom of the profile
                    sup = wt > 0

                # Reference the profile on a high QUANTILE, not the max.  Normalising by the max
                # lets a single fully-owned vertex define the scale: jak-hd's MhairA peaks at 0.99
                # on one vertex while its mean is 0.364, so cap*(w/0.99)**shape landed BELOW the
                # existing weight almost everywhere and the transfer moved nothing (measured:
                # authority 0.364 -> 0.367).  p90 is robust to that outlier and still well inside
                # the patch the artist painted.
                s = np.clip(wt / wmax, 0.0, 1.0)
                new = np.where(sup, r['cap'] * s ** r['shape'], 0.0)
                gain = np.maximum(new - wt, 0.0)

                # TERME SPATIAL. Sans lui l'operateur ne peut pas lever le MILIEU d'une meche sans
                # lever sa RACINE, parce qu'il ne les distingue que par le poids peint et que le
                # support de ces joints couvre toute la meche. `smin=0.0` par defaut => aucun effet.
                if r['smin'] > 0.0:
                    sarc = arc_abscissa(r['sarc'] or r['chain'] or [r['target']], P)
                    if sarc is None:
                        rep.append(f"  !! {r['target']}: smin= demande mais chain= ne presente pas"
                                   f" 2 joints de ce rig — regle refusee plutot qu'appliquee a moitie")
                        continue
                    blocked = int(((sarc < r['smin']) & (gain > 0)).sum())
                    k = (np.clip((sarc - r['smin']) / r['sramp'], 0.0, 1.0) if r['sramp'] > 0.0
                         else (sarc >= r['smin']).astype(float))
                    gain = gain * k
                    rep.append(f"  .. {r['target']}: spatial smin={r['smin']:.2f}"
                               f" rampe={r['sramp']:.2f} — {blocked} sommet(s) sous l'abscisse"
                               f" exclus du gain")

                if not (gain > 0).any():
                    rep.append(f"  -- {r['target']}: already at or above the target profile")
                    continue

                # a vertex may not have the target joint in its 4 slots yet (after grow=)
                slot = np.full(len(W), -1, dtype=np.int64)
                for c in range(J.shape[1]):
                    slot = np.where((J[:, c] == t) & (slot < 0), c, slot)
                need = (gain > 0) & (slot < 0)
                if need.any():
                    # steal the lightest slot
                    lightest = np.argmin(W, axis=1)
                    for vi in np.nonzero(need)[0]:
                        c = int(lightest[vi])
                        J[vi, c] = t
                        W[vi, c] = 0.0
                        slot[vi] = c

                # take the gain from the donors, proportionally to what they hold
                don = [idx[d] for d in r['donors'] if d in idx]
                took = np.zeros(len(W))
                for vi in np.nonzero(gain > 0)[0]:
                    avail = [(c, W[vi, c]) for c in range(J.shape[1])
                             if J[vi, c] in don and W[vi, c] > 0]
                    pool = sum(w for _, w in avail)
                    g = min(gain[vi], pool)
                    if g <= 0:
                        continue
                    for c, w in avail:
                        W[vi, c] -= g * (w / pool)
                    W[vi, slot[vi]] += g
                    took[vi] = g

                tot = W.sum(axis=1, keepdims=True)
                W = np.where(tot > 0, W / np.maximum(tot, 1e-12), W)
                after = W[np.arange(len(W)), np.maximum(slot, 0)]
                m0, m1 = float(wt[sup].mean()), float(after[sup].mean())
                rep.append(
                    f"  {r['target']:<10} verts={int(sup.sum())} p90 {wmax:.3f} "
                    f"mean {m0:.3f}->{m1:.3f} dominant {int((wt >= 0.5).sum())}->"
                    f"{int((after * sup >= 0.5).sum())} "
                    f"weight moved off {','.join(r['donors'])} = {took.sum():.1f}")
                # A rule that does not measurably move ownership is a rule that lies in the file.
                # Loud, not silent: the bake greps for '!!' and fails.
                if m1 - m0 < 0.05:
                    rep.append(f"  !! {r['target']}: transfer moved ownership by only "
                               f"{m1 - m0:+.3f} — the rule is inert, fix or drop it")

            acc_j = append_accessor(js, binc, J.astype(np.uint8), 5121, 'VEC4')
            acc_w = append_accessor(js, binc, W.astype(np.float32), 5126, 'VEC4')
            at['JOINTS_0'] = acc_j
            at['WEIGHTS_0'] = acc_w
            # LES DEUX, jamais le poids seul : voir le commentaire du cache plus haut. `J` a ete
            # MUTE par les regles, donc `acc_w` n'a de sens que contre `acc_j`.
            seen[key] = (acc_j, acc_w)
    return rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', required=True)
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--report', default='')
    a = ap.parse_args()

    cfg = load_cfg()
    rules = cfg.get(a.model, [])
    if not rules:
        print(f'[reskin] {a.model}: no rule — passthrough')
        if a.inp != a.out:
            open(a.out, 'wb').write(open(a.inp, 'rb').read())
        return 0

    js, bufs = read_glb(a.inp)
    binc = consolidate_buffers(js, bufs)
    rep = apply_model(js, binc, rules)
    binc = gc_glb(js, binc)
    write_glb(a.out, js, binc)
    txt = f'[reskin] {a.model}  {len(rules)} rule(s)\n' + '\n'.join(rep)
    print(txt)
    if a.report:
        open(a.report, 'w').write(txt + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())

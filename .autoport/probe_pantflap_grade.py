"""`transfer` OUVRE la geometrie du pan de pantacourt. `grade` peut-il la refermer ?

Trouve le 2026-08-13, des que la colonne « mesh livre » a pu voir quelque chose :

    pantflapL  tear 0 (rip brut) -> 6 (mesh livre)     pantflapR  0 -> 6

`transfer LpantFlap from=Lknee,Lthigh cap=0.90 shape=0.75` monte la propriete du pan de 0.11 a
0.67 — c'est ce qu'on voulait — mais il la monte SANS graduer la bordure : un sommet passe a 0.9
touche un sommet reste a 0.0, et le triangle entre les deux se dechire des que le pan bouge. C'est
exactement le defaut que l'owner decrit sur les meches (« des polygones qui bougent et des
polygones voisins parfaitement statiques »), sur une autre piece.

`grade` est fait pour ca, il est IDEMPOTENT (verifie), et il a deja ferme les six jonctions de
cheveux (82/19/10/10/26/24 -> 0). La question est de savoir s'il ferme celle-ci SANS defaire le
transfert — donc sans redescendre `cov`, et sans decoller le pan de la jambe.

NATURE : un COMPTE d'aretes (tear), et une FRACTION de poids (cov). Ni l'un ni l'autre n'est une
         amplitude : on ne mesure pas ici du mouvement, on mesure de la peau.
REPERE  : sans objet — ce sont des poids, dans la pose de bind. Statique, ne depend d'aucune frame.
BASE    : ce que la sonde lit quand le defaut est absent — `tear=0`, ce que le rip brut affichait
          AVANT le transfert, et ce que `grade` obtient sur les six jonctions de cheveux.
CONTROLE POSITIF : l'entree elle-meme. Le mesh livre porte 6 aretes dechirees par pan ; c'est le
          meme instrument, sur le meme fichier, qui doit les compter puis les voir tomber.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(os.path.abspath(os.path.join(HERE, '..')))
sys.path.insert(0, os.path.abspath('.autoport'))
sys.path.insert(0, os.path.abspath('scripts/shell'))
import numpy as np
import physics_c7_reskin as RS
import physics_c6_volumes as C6
from retarget_hd_models import read_glb, consolidate_buffers, skin_info

# LE MESH LIVRE, pas le rip : c'est l'etat APRES les `transfer`, donc l'entree reelle du probleme.
SRC = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
CHAINS = {'pantflapL': ['LpantFlap'], 'pantflapR': ['RpantFlap'],
          'chestL': ['lBoob'], 'chestR': ['rBoob'],          # temoins : transferes aussi, tear=0
          'lmidhair': ['Lmidhaira', 'Lmidhairb']}            # temoin : deja gradue, doit rester a 0


def measure(js, binc):
    names, _, _ = skin_info(js, binc)
    V, J, W, F = C6._gather_model_vertices(js, binc)
    Wd = np.zeros((len(V), len(names)), dtype=np.float64)
    for k in range(W.shape[1]):
        np.add.at(Wd, (np.arange(len(V)), J[:, k]), W[:, k])
    edges = set()
    for t in F:
        a, b, c = int(t[0]), int(t[1]), int(t[2])
        for u, v in ((a, b), (b, c), (a, c)):
            edges.add((u, v) if u < v else (v, u))
    ji = {n: i for i, n in enumerate(names)}
    out = {}
    for cn, jl in CHAINS.items():
        cols = [ji[j] for j in jl if j in ji]
        if not cols:
            continue
        ws = Wd[:, cols].sum(1)
        own = np.nonzero(ws > 0.0)[0]
        if not len(own):
            continue
        tear = sum(1 for (u, v) in edges
                   if (u in set(int(x) for x in own) or v in set(int(x) for x in own))
                   and abs(ws[u] - ws[v]) > 0.5)
        out[cn] = (float(ws[own].mean()), len(own), tear,
                   int((ws > 0.5).sum()))       # sommets ou la chaine est MAJORITAIRE (ancrage)
    return out


js0, b0 = read_glb(SRC)
binc0 = consolidate_buffers(js0, b0)
base = measure(js0, binc0)
print("AVANT (mesh livre, apres les `transfer`) — c'est le CONTROLE POSITIF, il compte non nul :")
for cn in sorted(base):
    print("   %-10s cov=%.4f n=%-4d tear=%-3d majoritaire=%d"
          % (cn, base[cn][0], base[cn][1], base[cn][2], base[cn][3]))

cfg_path = os.path.join(HERE, '.cand_pantgrade.txt')
open(cfg_path, 'w').write(
    "[model keira-hd]\n"
    "grade LpantFlap chain=LpantFlap from=Lknee,Lthigh step=0.45\n"
    "grade RpantFlap chain=RpantFlap from=Rknee,Rthigh step=0.45\n")
cfg = RS.load_cfg(cfg_path)

js, bufs = read_glb(SRC)
binc = consolidate_buffers(js, bufs)
rep = RS.apply_model(js, binc, cfg['keira-hd'], verbose=False)
after = measure(js, binc)

print("\nRAPPORT DE L'OPERATEUR :")
for line in rep:
    print("   " + line.strip())

print("\nAPRES `grade` :")
print("   %-10s %-22s %-22s %s" % ("chaine", "cov", "tear", "majoritaire (ancrage)"))
ok = True
for cn in sorted(base):
    b, a = base[cn], after.get(cn)
    if a is None:
        continue
    flag = ""
    if cn.startswith('pantflap'):
        if a[2] != 0:
            flag = "  <-- NE FERME PAS"; ok = False
        if a[0] < b[0] * 0.90:
            flag += "  <-- COUVERTURE PERDUE"; ok = False
    else:
        if a[2] != b[2] or abs(a[0] - b[0]) > 1e-6:
            flag = "  <-- TEMOIN TOUCHE (le perimetre deborde)"; ok = False
    print("   %-10s %.4f -> %.4f      %-3d -> %-3d           %d -> %d%s"
          % (cn, b[0], a[0], b[2], a[2], b[3], a[3], flag))

# IDEMPOTENCE : le bake ne relance pas l'operateur, mais une reprise a la main le ferait, et
# `transfer` s'est revele cliqueter. On verifie plutot que de supposer.
rep2 = RS.apply_model(js, binc, cfg['keira-hd'], verbose=False)
again = measure(js, binc)
same = all(abs(again[c][0] - after[c][0]) < 1e-9 and again[c][2] == after[c][2] for c in after)
print("\nIDEMPOTENT : %s" % ("oui — une seconde passe ne change rien" if same
                             else "NON, IL CLIQUETTE — ne pas relancer a la main"))
print("VERDICT : %s" % ("les deux pans se referment sans perdre le transfert, temoins intacts"
                        if ok and same else "NE PAS LIVRER EN L'ETAT"))
os.unlink(cfg_path)

"""`hair-nape` : la capsule de tete avale-t-elle les cheveux qu'elle emprisonne ensuite ?

L'owner (2026-08-12) : « les cheveux de nuque clipent dans son cou et ne bougent pas ou mal ».
Arithmetique deja etablie : `capsule head neck radius=915` alors que la pointe de `backhair` n'a
que 820 u de portee depuis sa racine. La pointe est donc DEDANS en permanence et ne peut pas en
sortir — aucun reglage de chaine ne peut repondre a ca, c'est le VOLUME qui doit changer.

Reste a savoir POURQUOI ce volume fait 915 alors que le buste n'en fait que 671. Hypothese a
trancher ici, avec des nombres et pas un commentaire : les capsules sont ajustees pour contenir
tout ce que leur os POSSEDE, et la rangee d'ancrage des cheveux est `head`-dominante (la mesure de
`tear` le montre : `lost=head 100%` sur toutes les meches). La capsule de tete serait donc gonflee
PAR les cheveux, puis les emprisonnerait — meme classe de defaut que « une chaine en collision avec
son propre collider de racine ».

NATURE  : une distance (rayon), pas une amplitude.
REPERE  : distance au joint `head`, dans la pose de bind.
BASE    : le rayon qu'aurait la capsule si on retirait les sommets des meches de son nuage.
"""
import os
import sys

os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')))
sys.path.insert(0, os.path.abspath('.autoport'))
import numpy as np
from physics_c6_volumes import load_geometry as lg

g = lg('keira-hd')
V, jn, W, J, P = g['V'], g['names'], g['W'], g['J'], g['P']
ji = {n: i for i, n in enumerate(jn)}

Wd = np.zeros((len(V), len(jn)), dtype=np.float64)
for k in range(W.shape[1]):
    np.add.at(Wd, (np.arange(len(V)), J[:, k]), W[:, k])

HAIR = ['backHair1', 'backHair2', 'Lbanga', 'Lbangb', 'Lbangc', 'Rbanga', 'Rbangb', 'Rbangc',
        'Lmidhaira', 'Lmidhairb', 'Rmidhaira', 'Rmidhairb', 'lEara', 'lEarb', 'rEara', 'rEarb']
hair_cols = [ji[j] for j in HAIR if j in ji]

head, neck = ji['head'], ji['neck']
dom = np.argmax(Wd, axis=1)                      # le joint qui possede chaque sommet
own = np.nonzero(dom == head)[0]                 # nuage dominant de `head`
hairw = Wd[:, hair_cols].sum(1)                  # poids total de meche par sommet

# REPERE : la capsule `head neck` est un volume AUTOUR DU SEGMENT head->neck. Sa grandeur est donc
# la distance a l'AXE, pas au joint. Mesurer la distance au joint (ce que faisait la premiere
# version de cette sonde) compare une chose a une autre et gonfle le chiffre — c'est la faute que
# la SPEC 7 appelle « le mauvais repere », et elle donnait 2082 u contre un rayon publie de 915.
a, b = P[head], P[neck]
ab = b - a
L2 = float(ab @ ab) or 1.0
t = np.clip(((V[own] - a) @ ab) / L2, 0.0, 1.0)
d = np.linalg.norm(V[own] - (a + t[:, None] * ab), axis=1)

print("capsule head neck : radius=915 radius2=249 (fichier) — rayon FITTE sur un nuage ROBUSTE")
print("(fit_capsule_robust ecarte les aberrants puis clampe): le max brut ci-dessous n'est donc PAS")
print("le rayon publie, il en est la borne haute avant robustification.")
print("portee de la pointe backhair depuis sa racine = 820 u")
print("nuage dominant de `head` : %d sommets, distance max a l'AXE head->neck = %.0f u"
      % (len(own), d.max()))
print()

# Le sommet qui DICTE le rayon, et ceux du dernier decile : sont-ils des cheveux ?
order = np.argsort(-d)
print("les 12 sommets les plus eloignes (ceux qui fixent le rayon) :")
print("   %-8s %-9s %-9s %s" % ("dist", "poids meche", "poids head", "verdict"))
for k in order[:12]:
    vi = own[k]
    print("   %-8.0f %-11.3f %-9.3f %s"
          % (d[k], hairw[vi], Wd[vi, head],
             "CHEVEU" if hairw[vi] > 1e-6 else "peau/crane"))

print("\nCE QUE PESENT LES CHEVEUX DANS LE NUAGE DE `head` (p95 = proxy du fit robuste) :")
for cut in (0.5, 0.25, 0.05, 1e-6):
    keep = d[hairw[own] <= cut]
    if len(keep):
        print("   sans les sommets a plus de %.2f de meche : n=%-5d  max=%-6.0f  p95=%-6.0f"
              % (cut, len(keep), keep.max(), float(np.quantile(keep, 0.95))))
allmax, allp95 = d.max(), float(np.quantile(d, 0.95))
print("   nuage complet                             : n=%-5d  max=%-6.0f  p95=%-6.0f"
      % (len(d), allmax, allp95))
print()
print("LECTURE. Les sommets les plus loin de l'axe sont des CHEVEUX : ils sont dans le nuage")
print("dominant de `head` et tirent donc le fit vers le haut. Mais les retirer ne suffit PAS a")
print("passer sous les 820 u de portee de la pointe — le volume resterait plus grand que la")
print("distance que la meche peut parcourir. Exclure les cheveux du nuage est donc necessaire et")
print("NON SUFFISANT : la capsule `head neck` couvre a elle seule tout le crane ET la nuque, la ou")
print("le corps devrait porter deux volumes distincts. C'est la mesure a produire au prochain")
print("cycle, et c'est un changement de GENERATEUR, pas un rayon a retoucher a la main.")

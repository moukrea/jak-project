DIRECTIVES v775512c234
# Rejeu local essai11 — référence et interface candidat

Compilation (exit0):

```sh
g++ -std=c++17 -O2 -Wall -Wextra -Werror -I. .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-blur-replay.cpp -o .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-blur-replay -lEGL -lGLESv2
```

Référence exécutée (exit0):

```sh
python3 .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-replay.py --shader .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-reference.frag --output .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-reference
```

Candidat : même commande, remplacer --shader par son chemin et --output par un nouveau notes/attempt11-NOM. Aucun changement du lecteur attempt10-profile.py, du binaire natif, des critères ou des populations. Les commandes internes exactes sont dans attempt11-reference/commands.json.

SHA256 shader source de référence : 221e6700852584ae59bfbc3b40b083628ad61e0ad8c1bcb2a9d61deaa680b0ae

| Mode local | Bande ridge3 (pixels) | Largeur max | Côtés valides/manquants |
|---|---:|---:|---:|
| ssao | 12 | 3 | 29/1 |
| hbao | 2 | 1 | 29/1 |
| gtao | 7 | 2 | 29/1 |

Les trois modes gardent exactement 250 pixels mur +175 toit et15contacts de la référence bras3, projection et segment physique identiques. Chaque étage est mesuré par le lecteur natif existant.

Entrées estimator R8 et profondeur D24 des archives after ;8passes blur puis4ridge, directions/matrices archivées. Sorties sous répertoire distinct, manifest explicitement dérivé localement pour le lecteur existant. Aucun proof.txt produit, archive et preuve appareil intactes.

Pilote local :
```
GL_VENDOR=Intel
GL_RENDERER=Mesa Intel(R) UHD Graphics (CML GT2)
GL_VERSION=OpenGL ES 3.2 Mesa 25.3.6
```

Les différences avec le GPU appareil ne sont pas une régression du candidat : référence/candidat doivent être comparés sur CE pilote. Les erreurs inter-pilotes connues de1..2quantums peuvent être amplifiées par ridge. Ce résultat ne valide aucun appareil, aucun verdict owner, ni les cinq acquis.

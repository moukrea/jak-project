DIRECTIVES v775512c234
# Reproduction locale uniquement
Les commandes build/rejeu/invariants finaux et leurs exit codes sont dans attempt12-build-delivery.json.
Les commandes internes des quatre rejeux sont dans attempt11-a12-{reflect,contract,ray,delivery}/commands.json.
Les scripts existants exigent un nom de sortie attempt11* neuf, d'où ce préfixe pour l'essai12.

```sh
python3 .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-replay.py --shader CHEMIN_SOURCE --output .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-a12-NOM_NEUF
python3 .autoport/reports/ao-prepass-tie-alpha/notes/attempt12-analyze.py --replay CHEMIN_REJEU --output .autoport/reports/ao-prepass-tie-alpha/notes/attempt12-NOM_NEUF.json
g++ -std=c++17 -O2 -Wall -Wextra -Werror -I. .autoport/reports/ao-prepass-tie-alpha/notes/attempt12-fold-phases.cpp -o .autoport/reports/ao-prepass-tie-alpha/notes/attempt12-fold-phases -lEGL -lGLESv2
.autoport/reports/ao-prepass-tie-alpha/notes/attempt12-fold-phases .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-a12-ray-invariants/vertex.glsl .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-a12-ray-invariants/reference.glsl .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-a12-ray-invariants/candidate.glsl
.autoport/reports/ao-prepass-tie-alpha/notes/attempt12-fold-phases .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-a12-delivery-invariants/vertex.glsl .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-a12-delivery-invariants/reference.glsl .autoport/reports/ao-prepass-tie-alpha/notes/attempt11-a12-delivery-invariants/candidate.glsl
```
Phases : compilation et deux exécutions exit0 ; les valeurs imprimées disqualifient ray malgré exit0.
Le banc ne produit aucun verdict de porte. Les scripts/lecteurs du harnais ne sont pas modifiés.

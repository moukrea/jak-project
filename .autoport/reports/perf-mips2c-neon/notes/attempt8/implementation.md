# Correction localisée du candidat essai 7

DIRECTIVES vaff5c1afea

Correction appliquée dans `corrected-sparticle.cpp`, issu exactement de
`../attempt7/candidate-sparticle.cpp` : seule la boucle `r11 *= r15.w`
sous `if (!bc)` est remplacée par la publication de vf11/vf15, l'appel
`c->vmul_bc(DEST::xyz, BC::w, vf11, vf11, vf15)`, puis la reprise de vf11.
Les autres opérations, branches, writebacks et accès mémoire sont conservés.

`corrected.patch` compare au `../attempt7/before-sparticle.cpp` ;
`correction-only.patch` compare au candidat essai 7 (un hunk).
`block-parity.cpp` reprend le banc essai 7 avec le seul bloc de `after`
extrait de la source corrigée. `before`, `seed`, `main` et le code hors du contenu de `after` sont
identiques. Seule exception documentaire hors fonction : le commentaire
`after source sha256` désigne désormais `corrected-sparticle.cpp`.
Les empreintes actuelles sont dans `correction.sha256`.

Vérification structurelle Python : remplacement unique et réversible,
bloc extrait identique, code extérieur de `after` identique avec la seule
exception documentaire SHA décrite ci-dessus ; résultats dans
`correction-diff-verification.json`, diff du banc dans
`block-parity-correction-only.patch`. Aucun build ni test exécuté.
Aucune modification du moteur livré, des validateurs ou de `proof.txt`.
Non prouvé : parité d'exécution, code machine produit, gain de performance.
Aucune autre correction appliquée ; aucun écart à la spec.

DIRECTIVES v708c60642a

## Constat avant édition, lecture des sources36 conservées
- Portail36 `batches/essai36-portal-wait/20260908T121810-4074478/engine.log` : le nom de l'intern fautif se récupère des mots little-endian aux lignes18227–18228, tampon X0=X19=0x7f001a7be0 : `lurkerworm-strike\0`. Le handoff36 le disait inconnu. Le site est le tampon sym_name de symlink_v3, klink.cpp191–201 avant édition.
- La faute lib+0x721584 est STUR W8,[X9,#-4], instruction b81fc128 (ligne19618) ; W20 chargé depuis symbol_slot et X9 sont nuls. Aucune preuve de concurrence : les recherches du crash handler sont postérieures et ne peuvent établir le producteur antérieur.
- Deux sondages épuisés peuvent retourner zéro sans candidat ; printf tamponné rend l'absence du warning insuffisante. Une recherche d'un symbole existant efface aussi le global temporaire. Les traces ajoutées séparent ces possibilités sans corriger le comportement.
- Ciel36 `batches/essai36-sky-entry/20260908T120812-4062840/engine.log` : PC_GOAL0x268920c, X7=0, cellule décodée EE0x1490ec depuis 90fed610/9103b210/b9400207. Pool nk pourtant présent à frame1 (ligne2265,0x1dcb44,2304 records) et après crash (17980,slot0x146984).
- Le KERNEL.CGO conservé `notes/essai36/menu-build/before/iso-arm64/KERNEL.CGO` porte l'objet gkernel à0xf3c0, relocation default0x1f3, références top-level0x1ba8/0x1bac : ADRP X16 / ADD X16 / STR W9,[X16]. La branche NOP des STR[X14] hors plage de common/klink.cpp ne s'applique pas à cette initialisation. Aucun correctif de cette branche justifié ici.
- Le pool principal global n'est pas libéré explicitement par la transition relevée ; l'identité de la cellule default et le moment de son éventuelle mutation restent à mesurer.

## Vérifications hors appareil
- `build/goalc-test --gtest_filter=Kernel.HashTable` : binaire préexistant, code0,1test passé43ms. Baseline seulement, pas test de la future modification.
- `tests/test_hdr_batches.log` :249tests passés76,16s, code0. Cela ne prouve aucune image du jeu.

## Limites rendu conservées
- Le shader courant atteint1 dès entrée1.05 et vaut0.9875 à1 pour genou0.95. Les événements nuages34 conservent des valeurs HDR au-delà de1 ; leurs compteurs white ne démontrent pas un écrêtage physique du tampon avant tonemap.
- Soleil34 événements248→249 lf1749 : maximaR1.265625→2.890625,G1.017578→2.183594, moyenneB inchangée. Ceci situe les dépassements avant courbe, mais les agrégats ne comptent pas les nuances devenues identiques. Aucun réglage artistique ou ablation éco ajouté.

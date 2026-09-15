# Candidat intégration particules 3D

DIRECTIVES vaff5c1afea

Transformation bornée au bloc `block_18` avant les quatre `sqc2` de
`sp_process_block_3d::execute` dans `game/mips2c/jak1_functions/sparticle.cpp`.
Sept chargements deviennent des `memcpy` vers des `Mips2c_vf` locaux, avec
les sept assertions d’alignement conservées. Calculs dans l’ordre source,
multiplications et additions séparées ; hypothèse de compilation :
`-ffp-contract=off`. Aucun SIMD explicite ajouté.

Les copies finales publient vf8..14 et vf17..19 ; vf15 est publié seulement
si le branchement de damping est pris. Son initialisation copie les 128 bits
complets de `gpr_src(v1)`, après les `lwc1`/`mfc1` d’origine : les lanes hautes
ne sont pas reconstruites. vf11.w et vf9.xyz restent intacts. vf16 est lu
seulement, vf0 provient de `vf_src(vf0)`, `bc` conserve sa valeur d’origine.
Les quatre `sqc2` restent inchangés, après publication des registres.

Aucun build lancé, conformément à la consigne du manager. Non prouvé :
parité bit à bit, réduction du travail machine, gain en jeu. Le manager
prépare le banc sur sources avant/après ; compilation réservée au testeur.

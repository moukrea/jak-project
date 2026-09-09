# Les noyaux VU0 emules (os, joints, particules) calculent en vectoriel

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
mips2c_private.h:887-896 : chaque op VU est une boucle scalaire 4 lanes avec branche de masque par lane, sans SIMD ; sur arm64 chaque store fait gnd_oob_check avec un load atomique (:50-58, 393-440). Noyaux chauds par image (allowlist mips2c_table_jak1_arm64.cpp:696-1010) : cspace<-parented-transformq-joint! (par joint, tous les acteurs vivants), bones-mtx-calc (par acteur dessine), sp-launch-particles-var, familles shadow et ocean.

## Livrable
Lot 1 : gnd_oob_check compile hors du build quand la prop n'est pas armee. Lot 2 : NEON (arm64) et SSE (x86) sur les trois noyaux les plus chauds selon goal_bucket_ms_*, bit-identiques (hd-mtx-check-all, A/B x86, ripple.cpp intact ou bit-identique car l'eau lit ripple-find-height). mips2c_parity_defects = ecarts bit a bit entre chemin scalaire et vectoriel sur 600 images + (refset_replay_maxdiff != 0). Gain publie par seau.

## Preuve exigee
`mips2c_parity_defects == 0` dans `reports/perf-mips2c-neon/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-mips2c-neon device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel et a la pose ; goal_busy_ms baisse.

## Hors perimetre
Aucun changement de resultat, meme au dernier bit. Ne touche a aucune feature validee.

# Handoff — perf-mips2c-neon (essai 12, 2026-09-16) — DIRECTIVES vaff5c1afea — courses eae4df44 20260916T193732Z (arme) / 20260916T194858Z (ablation)
## ETABLI (mesure)
1. LA PARITE N'EST PLUS VIDE. `mips2c_parity_defects` 5 -> 1 : `bit_defects=0`,
   `missing_kernels=0`, `parity_frames=600`, `parity_incomplete=0`. 26 243 209 operations
   comparees bit a bit EN JEU (joints 23017023, collide 2997628, particules 228558), zero
   ecart. Le point restant est le terme de rejeu d'images, et lui seul.
2. LA CAUSE DES 11 ECHECS ETAIT UN EMPLACEMENT MORT : `Kernel::Bones` visait `bones-mtx-calc`,
   jamais execute (*use-new-bones*), et `frames` exige les TROIS noyaux dans la MEME image.
   Remplace par `Collide` = (method 32) + (method 29) collide-cache, 61 appels/image.
3. LE GAIN EST NEGATIF, MESURE. Alternance des deux regimes par blocs de 30 images DANS LA
   MEME course, oracle eteint, bras apparies a 0,11 % en appels : 1026 ns/appel scalaire
   contre 1250 vectoriel (+21,8 %), +66 134 ns/image. Cause chiffree : deux memcpy, un masque
   de voies et un `vmaxvq_u32` par operation, contre une boucle scalaire deja vectorisee par
   le compilateur.
4. BIT-IDENTITE STRUCTURELLE du multiply-add : c97bdb859a a mis les cinq TU a
   `-ffp-contract=off` (0 FMA a llvm-objdump sur les objets arm64 livres), donc le bras
   vectoriel garde `vmulq` PUIS `vaddq`. Banc autonome porte de 13 a 27 primitives :
   1 976 832 cas par mode, x86 et aarch64/QEMU, zero divergence.
5. LE 255 DU REJEU ETAIT UNE SENTINELLE. Plan ramene a `legacy`, seule vue a porter des
   references Android : `refset_missing` 2 -> 0, `refset_steps` 3 -> 1, et
   `refset_replay_maxdiff` publie 233, l'ecart REEL, egal a `refset_d_origine_h09`.
## TENTE, ET POURQUOI CA N'A PAS SUFFI
* Rendre le gain positif : NON tente — un gabarit moins couteux (sans test de non-finitude,
  ou par blocs 4x4) serait le candidat fusionne que le contrat interdit (essais 7/8/9).
* Diagnostiquer le 233 : hors perimetre ; il fallait d'abord le rendre LISIBLE, c'est fait.
## RESTE
* ARBITRAGE, pas du code : garder le raccordement (porte a 1, parite prouvee, l'appareil paie
  0,24 % d'image) ou le retirer (aucune regression, parite vide, porte a 5). Le contrat dit les
  deux. Levier du retrait : `perf_instruments.cpp:54`, `vector_enabled`.
* Regle de l'owner applicable telle quelle : gain mesure <= 0, l'item s'archive.

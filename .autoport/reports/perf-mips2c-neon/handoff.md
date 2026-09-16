# Handoff — perf-mips2c-neon (essai 11, 2026-09-16) — DIRECTIVES vaff5c1afea

## ETABLI (mesure)
1. LA PORTE EST HORS D'ATTEINTE, et la cause n'est pas la vectorisation.
   `mips2c_parity_defects = bit_defects + missing_kernels + (frames<600) + terme_refset`
   (perf_instruments.cpp:112). Le terme refset vaut 1 : l'appareil eae4df44 ne porte QUE
   les huit `hHH.png` de la hutte ; `beach-start-h09.png`, la vue que `proof_env` demande
   explicitement, n'existe pas. Et la seule vue presente compare a `refset_d_origine_h09=233`
   sur 57597 pixels de 57600 (99,995 %) — deja maxdiff=165 le 07/09. Fournir ces references
   ou recapturer est INTERDIT par le contrat. Detail et trois issues de perimetre :
   `notes/attempt11/refset-diagnostic.md`.
2. Le comparateur de parite n'a AUCUN consommateur depuis 60fe160771 (`grep -rn '#include
   "game/mips2c/vu_simd.h"' game/ common/ goalc/` = 0) : d'ou missing_kernels=3 et frames=0,
   soit 4 des 5 points de la porte.
3. `VuSimd` ne sait remplacer ni `vmadda_bc` ni `vmadd_bc`, l'operation VU dominante de 4 des
   8 noyaux les plus chauds (82 + 37 sites).
4. PLAFOND DU GAIN : tout mips2c coute ~342 us/image NET (822606 publiees moins 480146
   d'instrument — une lecture d'horloge coute 454 ns sur ce Redmi) contre goal_busy_ms=15.517
   dont 12,7 ms d'attente du rendu : 2,3 % au maximum. `mips2c_hot1/2/3` est un classement
   INSTRUMENTE — il classe les fonctions les plus APPELEES, pas les plus cheres.
5. 1153 multiply-add fusionnes dans les objets arm64 jak1 livres, dont 296 dans joint.cpp.
   Table + controles positif et negatif : `notes/attempt11/fma-census.md`.

## TENTE, ET POURQUOI CA N'A PAS SUFFI
* Filtre de vantage (refset.cpp:2984) : ABANDONNE — ferait passer refset_missing de 2 a 1 sans
  debloquer, et le reglage est documente comme prenant des continue-points ; 4 items l'epinglent.
* Raccorder VuSimd aux trois noyaux actifs : NON FAIT (voir 3). Le contrat point 2 ordonne de
  retirer les ajouts speculatifs sans benefice etabli ; le rearmer sans mesure serait cela meme.

## RESTE
* Trancher le perimetre de la porte (voir 1) — c'est le blocage, pas le code.
* 781 FMA sur onze autres TU (TIE, ciel, eau, ondes) : dans FINDINGS.txt.

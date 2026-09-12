# Le soudage de normales tourne a chaque chargement de niveau pour un consommateur supprime

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SIGNALEMENT DU 12/09 (reports/dead-cover-and-legends/FINDINGS.txt). Tout l'appareil de soudage des normales et de reparation de positivite de `common/custom_data/MeshConsolidate.cpp` (~2650-3470) existe pour garantir un invariant, `dot(N_v, outward(f)) > 0`, dont le SEUL consommateur moteur etait le tessellateur `tfrag3_tess.tese`, SUPPRIME.
Le fichier reste compile (common/CMakeLists.txt:39, android/CMakeLists.txt:864) et appele a CHAQUE chargement de niveau (loader/Loader.cpp:779-799). C'est donc du temps processeur paye a chaque transition, sur un appareil qui plafonne a ~44 img/s et que le tueur de memoire visite.
L'invariant ne survit que dans les outils HORS LIGNE `tools/tess_audit/` et `tools/tess_sign/`, qui ne tournent pas dans le jeu. Le worker precedent n'avait le droit que de corriger les legendes ; dire si le calcul lui-meme doit partir est le travail de cet item.

## Livrable
`mesh_consolidate_waste_ms_x100` = 0 : plus une milliseconde de chargement depensee pour un invariant que rien ne consomme dans le moteur.
1. LE COUT D'ABORD, avant de retirer quoi que ce soit : publier le temps passe dans cet appareil par chargement de niveau, mesure sur l'appareil, AVANT et APRES. Un gain non chiffre n'est pas un gain.
2. RECENSER LES CONSOMMATEURS au point d'appel, pas par une liste de noms : publier le compte de lecteurs de l'invariant dans le binaire LIVRE. Un zero doit venir d'une mesure, pas d'un grep.
3. Les outils hors ligne gardent leur chemin : publier un temoin qui dit que `tools/tess_audit` et `tools/tess_sign` compilent et produisent encore le meme resultat.
4. Aucun maillage livre ne change : empreinte des fr3 produits identique avant et apres, publiee. Si elle change, l'item s'arrete et le dit.

## Preuve exigee
`mesh_consolidate_waste_ms_x100 == 0` dans `reports/mesh-consolidate-without-consumer/proof.txt`.
Le proof se produit par `lib/proof_run.sh mesh-consolidate-without-consumer device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible a l'oeil. Le gain se voit sur le temps de chargement des niveaux..

## Hors perimetre
Ne touche pas aux outils hors ligne eux-memes. Ne change aucun asset livre.

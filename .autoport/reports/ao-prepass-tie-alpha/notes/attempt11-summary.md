DIRECTIVES v775512c234
# Essai11 — candidat local de reconstruction, résultat PARTIEL
## Cause reprise
Les archives essai10 et attempt10-residual-ssao.md établissent la dilution par le flou.
La nouvelle lecture de profondeur donne au mur pente5,84e-6/px, au toit52,45e-6/px.
Au mur(100,550), sigma581,29e-6 conserve quasiment tous les taps malgré le pli.
La table alpha antérieure notes/alpha-table.tsv et sa causalité restent acquises, aucune prepasse changée.
## Choix
Le noyau centré et les huit passes de flou restent identiques. La reconstruction finale
conserve la règle historique de maximum strict ; elle ajoute une enveloppe concave calculée
avec les moyennes des voisins déjà filtrés à1/2texels de chaque côté.
Pentes unilatérales, exclusion ciel, convexité immédiate et écart cumulatif2% ; aucun seuil de sonde modifié.
## Comparaison même pilote Intel/Mesa
Référence : attempt11-reference/summary.json. Livré : attempt11-delivered/summary.json.
Même425pixels (250mur/175toit),15contacts physiques ; géométrie/projection/populations figées bras3.
SSAO cumul/max12/3→0/0,29côtésvalides,1manquant,0censuré.
HBAO cumul/max2/1→0/0,28côtésvalides,1manquant,1censuré (29valides initialement).
GTAO cumul/max7/2→0/0,29côtésvalides,1manquant,0censuré.
Ces zéros décrivent UNIQUEMENT les largeurs préfixes mesurables, aucune suppression complète démontrée.
À(100,550), SSAO[141,138,135,133,131,130]→[133,138,135,133,131,130] : pic intérieur+1 subsiste.
GTAO[167,165,162,160,159,158]→[160,165,162,160,159,158] ; HBAO[167,164,162,161,160,160]→[160,164,162,161,160,160].
Le lecteur s'arrête au premier pixel suffisamment sombre ; il ne compte pas ce pic secondaire.
## Variantes non retenues, archives conservées
attempt11-candidate : minimum voisins sans moyenne,2côtés censurés et SSAO3/max3.
attempt11-filter-candidate : minimum de trois fenêtres lissées dans le flou,3/max2 dans chaque mode ; HBAO empire.
attempt11-wide-candidate : stencil3,4côtés censurés dans chaque mode ; non retenu.
attempt11-final-candidate précède les gardes cumulatives/convexes ; mesures identiques au livré sur contact.
## Tests et livraison
Sources/bancs/commandes : attempt11-replay-commands.md, attempt11-delivered-invariants/commands.md.
GLES et GLSL410 compilés/liés exit0 ;16comparaisons de480000pixels référence/livré bit-identiques.
Phases4x4 R8/R32F sur plans horizontal/incliné : range0. Constantes/ciel conformes aux bancs.
La silhouette finie synthétique mélange déjà dans la référence (~0,502), candidat identique ; pas de conformité inventée.
Build incrémental Android exit0 : attempt11-build-delivered.log ; seul shader embarqué à rebâtir, aucun C++ source changé.
Shader exact testé, blob et libgk vérifiés : attempt11-delivery.json, empreintes et profils numériques.
Aucun APK repack/installé, aucun appareil touché, aucun proof_run, aucun lancement du validateur.
## Limites
La reconstruction peut propager l'assombrissement dans ses quatre passes ; coût GPU supplémentaire non mesuré.
Aucune mesure shrubs, image complète couleur OFF, acquis/stabilité ou qualité appareil de cet essai.
L'écart Intel/Redmi connu interdit de remplacer la preuve appareil par ces résultats locaux.
Le plan9/9 et le plan6/6 restent clos ; proof.txt reste la production historique de l'essai10.
Comparaison globale locale : les8sorties blur sont bit-identiques ; sortie finale modifie11666/10877/11220pixels,1/1/2éclaircis vs référence, maxassombrissement61/50/51octets. Source : attempt11-delivery.json.

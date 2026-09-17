# Handoff — ao-prepass-tie-alpha (essai 19, 2026-09-17)
DIRECTIVES vb025076084
Porte PASSEE (`ao_tie_prepass_defects=0`, eae4df44, md5 049695f3). Garde-fou pour qui relancera la
preuve ; detail dans `report.txt` et `notes/attempt19-plancher.md` (captures : `notes/attempt19/`).
## ETABLI
- Les 862 de l'essai 18 etaient a 98,5 % le PLANCHER de l'instrument : deux captures du tick 1400,
  MEME binaire et MEME source de shader, different de 848 a 923 px sur 480 000, toujours dans les
  deux memes quads semi-transparents ; hors d'eux, 479 077 px bit-identiques (7 captures, 3 binaires).
- La PREMIERE course apres une installation d'APK n'est pas comparable aux suivantes : 51 903 px
  d'ecart (10,8 %) contre ~900 a chaud. L'instrument la refuse et le publie.
- Deux fuites d'horloge murale corrigees (cap du vent, sillage de Jak) ; compteurs identiques
  d'une course a l'autre : elles n'etaient PAS la cause des deux quads.
## CE QUE COUTE UN REBUILD — a lire avant de relancer
Un binaire neuf invalide deux etats persistes sur l'appareil, indexes par son hash : la reference
de la sonde statique et le registre du plancher couleur. Sequence minimale, SIX courses :
  1. `device`        ON #1 a froid apres l'installation ; la sonde ECRIT sa reference (sa clause
                     couleur echoue, c'est normal)
  2. `device --off`  reference=1, fente A (a chaud)
  3. `device --off`  reference=2, fente B -> echantillon de plancher 1
  4. `device --off`  reference=1, fente A -> echantillon de plancher 2
  5. `device --off`  reference=0, la clause couleur
  6. `device`        ON #2 : la sonde COMPARE, le contrat somme tout dans proof.txt
`debug.opengoal.ao.tie.reference` se pose dans `proof_props`, jamais a la main. SANS rebuild,
`device` puis `--off` suffisent. `ao_probe_compared=0` + `ao_static_defects=1` = premiere course
sur ce binaire, PAS une regression ; `reference_floor_too_large` / `_pair_incomparable` = registre
absent, trop jeune ou pollue.
## RESTE
1. Ce qui est DESSINE dans les deux quads instables : inconnu (la capture n'a qu'un masque binaire
   TIE ; un stencil de famille le nommerait en une course). Inscrit dans FINDINGS.txt.
2. Le residu des 2 123 autres aretes qualifiees, village1-out et beach : toujours sans verdict.

# Le ciel et le halo cessent d'ecreter les couleurs a 1,0

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD `reports/hdr-plan/PLAN.md` — OBLIGATOIRE, c'est le contrat. Owner 11/09, sur « ou juger le HDR » : « bah c'est moi qui vais juger de toute facons donc tu devrais rien en avoir a cogner, tu peux pas voir le rendu final par des yeux ». Donc : la machine prouve le MECANISME et epingle son regime ; le JUGEMENT du rendu appartient a l'owner. Aucun appareil code en dur, aucun choix de materiel cible. Chantier A du plan (§7.1). Owner : « pour les couleurs du ciel j'ai l'impression qu'on peut taper plus que 8 bits parce que c'est des couleurs [...] on a de la richesse a gratter ». Il a raison : ces formats sont NOS choix, pas des contraintes.

## Livrable
`hdr_src_clamped_stages` = 0 : aucun etage du chemin de scene n'ecrete une couleur flottante a 1,0. Le ciel (melange GPU et CPU) et le halo (sonde et ses cinq reductions) passent en flottant. Publier le denominateur `hdr_plan_s2_sources_seen` a cote du compte — un zero doit se lire « aucun ecretage » et jamais « rien inspecte ». Publier aussi `hdr_overbright_px` MESURE DANS LE HALO : il doit devenir non nul, sinon rien n'a change. Mesurer le cout en cadence et en memoire sur le Redmi AVANT/APRES : c'est le premier travail du chantier, le plan ne l'a pas chiffre.

## Preuve exigee
`hdr_src_clamped_stages == 0` dans `reports/hdr-source-range/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-source-range device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : mesure d'entrees ; owner_test=false.

## Hors perimetre
Ne touche ni a l'occlusion ambiante, ni aux palettes, ni au coeur de l'ombrage : ces trois-la appartiennent a la refonte de l'eclairage et seraient refaits.

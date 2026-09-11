# La courbe se regle sur ce que la scene contient vraiment

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD `reports/hdr-plan/PLAN.md` — OBLIGATOIRE, c'est le contrat. Owner 11/09, sur « ou juger le HDR » : « bah c'est moi qui vais juger de toute facons donc tu devrais rien en avoir a cogner, tu peux pas voir le rendu final par des yeux ». Donc : la machine prouve le MECANISME et epingle son regime ; le JUGEMENT du rendu appartient a l'owner. Aucun appareil code en dur, aucun choix de materiel cible. Chantier B du plan (§7.1). La statistique qui pilote la courbe est SOURDE : elle voit un pic de scene de 1617 la ou la sonde de pixels en voit 15094 — un facteur 9,3. La courbe se regle donc sur une image qu'elle ne voit qu'au neuvieme. Rien a voir avec l'ecran ni avec la profondeur du tampon : c'est la reduction qui moyenne au lieu de prendre le maximum.

## Livrable
`hdr_curve_input_deaf_ratio_x100` <= 120 : le rapport entre le pic vu par la sonde de pixels et le pic vu par la statistique qui pilote la courbe, sur les MEMES images. Aujourd'hui 933. AUCUN changement de courbe dans ce chantier — on corrige ce qu'elle recoit, pas ce qu'elle fait. Publier les deux pics separement et le nombre d'echantillons : le plan signale que l'analyse de scene ne tourne que sortie HDR ACTIVE, donc un zero d'echantillons doit se lire « pas mesure » et non « pas d'ecart ».

## Preuve exigee
`hdr_curve_input_deaf_ratio_x100 <= 120` dans `reports/hdr-curve-input/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-curve-input device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : entree de la courbe ; owner_test=false.

## Hors perimetre
Ne modifie pas la courbe elle-meme. Ne touche pas aux etages de la refonte de l'eclairage.

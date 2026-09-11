# Trois regimes de sortie explicites, et le jeu dit lequel il utilise

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD `reports/hdr-plan/PLAN.md` — OBLIGATOIRE, c'est le contrat. Owner 11/09, sur « ou juger le HDR » : « bah c'est moi qui vais juger de toute facons donc tu devrais rien en avoir a cogner, tu peux pas voir le rendu final par des yeux ». Donc : la machine prouve le MECANISME et epingle son regime ; le JUGEMENT du rendu appartient a l'owner. Aucun appareil code en dur, aucun choix de materiel cible. Chantier C du plan (§7.1). Owner 11/09 : « je vois aucune mention de HDR10/HLG in game juste HDR output On/Off ». Et son arbitrage du jour : quand aucune marge n'est accordee, la sortie HDR promet LE CONTENEUR et rien d'autre — et elle le DIT. Fabriquer une difference visible a marge nulle est ce qui a produit cinq refus.

## Livrable
`hdr_regime_defects` = 0, somme de termes publies SEPAREMENT : le regime est publie a chaque image ; en regime sans marge, l'image est IDENTIQUE AU BIT a la sortie SDR (`ui_maxdiff_vs_sdr` = 0) ; en regime avec marge, aucun pixel ne passe sous le niveau SDR ; aucun pixel sous le seuil declare n'est modifie ; et la ligne de menu porte le transport retenu (HDR10, HLG, scRGB) ainsi que le regime courant. Le blanc est PLACE, pas etire.

## Preuve exigee
`hdr_regime_defects == 0` dans `reports/hdr-output-regime/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-output-regime device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage Recharge : la ligne de sortie HDR dit quel transport et quel regime sont utilises, au lieu d'un simple Oui/Non.

## Hors perimetre
Ne fabrique aucune difference visible quand le systeme n'accorde pas de marge. C'est un regime, pas un effet.

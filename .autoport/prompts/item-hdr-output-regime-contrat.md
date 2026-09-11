# Trois regimes de sortie explicites, et le jeu dit lequel il utilise — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD `reports/hdr-plan/PLAN.md` — OBLIGATOIRE, c'est le contrat. Owner 11/09, sur « ou juger le HDR » : « bah c'est moi qui vais juger de toute facons donc tu devrais rien en avoir a cogner, tu peux pas voir le rendu final par des yeux ». Donc : la machine prouve le MECANISME et epingle son regime ; le JUGEMENT du rendu appartient a l'owner. Aucun appareil code en dur, aucun choix de materiel cible. Chantier C du plan (§7.1). Owner 11/09 : « je vois aucune mention de HDR10/HLG in game juste HDR output On/Off ». Et son arbitrage du jour : quand aucune marge n'est accordee, la sortie HDR promet LE CONTENEUR et rien d'autre — et elle le DIT. Fabriquer une difference visible a marge nulle est ce qui a produit cinq refus.

## Livrable — le contrat, en entier

`hdr_regime_defects` = 0, somme de termes publies SEPAREMENT : le regime est publie a chaque image ; en regime sans marge, l'image est IDENTIQUE AU BIT a la sortie SDR (`ui_maxdiff_vs_sdr` = 0) ; en regime avec marge, aucun pixel ne passe sous le niveau SDR ; aucun pixel sous le seuil declare n'est modifie ; et la ligne de menu porte le transport retenu (HDR10, HLG, scRGB) ainsi que le regime courant. Le blanc est PLACE, pas etire.
DEUX AVERTISSEMENTS REMONTES PAR LE CHANTIER B LE 11/09 (reports/hdr-curve-input/FINDINGS.txt), a trancher ICI et pas ailleurs :
A. L'ANCRE RESTE SOURDE. Seul `peak` passe au maximum ; `key` (log-moyenne) et `hi` (le centile qui place l'ancre) restent tires des tuiles MOYENNES. Ce chantier ne peut pas placer un sommet juste sur une ancre dont la surdite n'a jamais ete mesuree : publier l'ecart entre l'ancre tiree des moyennes et l'ancre tiree des maximums, puis dire laquelle est retenue et pourquoi.
B. LA CONDITION DE MARGE CHANGE DE SENS SOUS CE CHANTIER. Avec `xp = clampf(peak, 0.02, 4.0)` et un pic VRAI (~15 mesure) au lieu du pic sourd (~1,6), `room = cmax > xp*(1+kMinTopGain)` devient FAUX des que l'ecran n'accorde aucune marge (cmax = 1) : la sortie HDR retombe sur la branche identite-SDR a TOUTES les images. Le regime doit donc etre choisi par une condition qui reste vraie quand l'entree devient juste — sinon le chantier B eteint le HDR en le reparant.

## Hors perimetre

Ne fabrique aucune difference visible quand le systeme n'accorde pas de marge. C'est un regime, pas un effet.

## Ou l'owner regardera

Options > Recharged > Eclairage Recharge : la ligne de sortie HDR dit quel transport et quel regime sont utilises, au lieu d'un simple Oui/Non

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


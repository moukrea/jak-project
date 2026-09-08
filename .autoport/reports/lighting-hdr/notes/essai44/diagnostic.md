DIRECTIVES v3909a9767c

Essai44 : travail hors appareil, conformément à « preuve exigée SUR APPAREIL aucun appareil » dans le prompt reçu. Aucun lancement du validateur, réservé à l'orchestrateur.

## Rendu

La correction de shade.glsl de l'essai43 est conservée. Aucune nouvelle cause de blend fautif n'est établie par la revue indépendante portal_analysis.
Sources : notes/essai43-rendu/portal/engine.log lignes46544/60299, LF2521/3181 : maximum bleu après groupe15.3359375/17.234375, pixels nonfinis0 et canaux négatifs0. Avant groupe, lignes46541/60296 : maximum bleu1.384765625/1.447265625.
Les snapshots Sprite3.cpp1136–1164 encadrent le groupe entier ; ils ne décomposent pas la contribution de chaque fragment du disque ou des halos.
timing-and-witnesses.json conserve des alphas harddot maximaux ON.83137/.80000 et OFF.53333/.12549. Aucune identité temporelle n'est exigée, mais ces différences empêchent d'attribuer quantitativement tout écart au seul blend.
La configuration observée est curve0/exposition1/genou.95999998. Le shader monotone borne chaque canal à1 à partir d'environ1.04. L'aplatissement chromatique de forts canaux est une propriété de cette courbe, pas une faute arithmétique nouvelle démontrée.
Aucune modification de courbe, gain, blend ou effet n'est justifiée par ces seules traces. Les captures ON/OFF existantes ont été consultées pour situer les régions, jamais utilisées comme preuve visuelle.
Nuages/soleil : notes/essai41/diagnostic.md conserve déjà les essais négatifs de genou et leurs limites. Éco : notes/essai30/diagnostic.md conserve les pistes orbite/alpha/nommage non causales. Aucun rejeu.
Petites zones violettes du sol : notes/essai43-rendu/decision.md ne fournit pas leur attribution sémantique. Les rectangles chemin/entrée ne peuvent pas être promus en couverture owner.

## Défaut du jugement existant

Revue indépendante owner_judgment_review : check_owner_replacement protège les lignes clouds/sunset-sun et les acteurs10012/10013, mais omet actor1395/layer portal_disc.
Avant correction, un remplacement pouvait retirer une observation portail de selected puis du jugement, même en présence d'une perte régionale de détail ou d'un excès d'aplats que QUALITY plein cadre ne détecte pas.
Correction bornée demandée : protéger le jugement photométrique existant du disque, sans ajouter condition de blancsOFF, seuil, instrument, ni qualification owner du portail. La réparation d'une collecte reste autorisée avec région mesurable et configuration compatible.
Les tests synthétiques doivent reproduire le défaut avant le patch et couvrir la conservation après ; ils ne sont jamais preuve jeu.
Les nuages et le portail restent partiellement attribués ; le sol reste absent. Cette correction du helper ne remplace aucune des cinq corrections visuelles demandées.

## Vérification avant patch

Le test ciblé corrigé de son erreur de fixture reproduit19échecs et2succès attendus sur le helper antérieur (portal-replacement-before-fixture-fixed.log, exit_code=1). Le premier log portal-replacement-before.log contient aussi une erreur de fixture ; il ne constitue pas seul la reproduction retenue.

Après patch final :294tests réussis en82.90s, exit_code=0 (portal-replacement-after.log). Toutes modifications de tests précèdent cette suite. Revue indépendante tester et manager : garde limitée aux observations existantes actor1395/portal_disc, aucune modification des seuils ou de la qualification owner.

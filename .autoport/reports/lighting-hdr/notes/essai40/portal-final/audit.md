DIRECTIVES v708c60642a
Audit cohérent : correction alpha mesurée sur le portail ; porte globale toujours rouge.

Commande : `python3 .autoport/reports/lighting-hdr/notes/essai40/portal-final/audit-check.py`, rc 0. Lecture locale seulement ; aucun appareil, source ou validateur exécuté.

Les 21 SHA256 du manifest ont été recalculés, zéro écart. Lib build-final/appareil/manifest identique : 32d5e7e2e9f427d8ae87a41a0b5f400e3eb07b77c88d3f06ceabd02bc79229ea ; APK identique aussi.
Quatre échantillons, deux par bras : attentes tracées 54,494/109,762 s ON et 42,632/84,271 s OFF depuis repin ; toutes ≥10 s. Les lignes citées figurent dans engine.log scellé.
ROI portal_disc [147,42,173,79] : alpha maximal 1, aucun alpha >1 ou négatif dans les deux bras, avant et après sprites du candidat final. L'ancien candidat avait alpha maximal 2 et 87 pixels >1 ON : ces deux sens de « avant » restent distincts.
Luma ON/OFF 102,022/127,016 ; nearwhite 41,5/48,5 : atténuation restante, aucune validation des cinq cas.
proof.txt officiel identique à sa copie : crash=0, frames=4560, hdr_tonemap_defects=4, owner_regressions_passed=0, missing=5.
Restauration : SHA settings exact 78108670… égal sauvegarde/build-final ; PID 3726 aux deux lectures, propriétés debug vides, commandes rc0. Intervalle PID documenté par sleep(12) dans run.py ; aucune nouvelle observation appareil.

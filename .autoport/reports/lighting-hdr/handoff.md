# Handoff — lighting-hdr, essai45 hors appareil
DIRECTIVES v3909a9767c
## ÉTABLI
Correction43 shade.glsl non-PBR et garde44 de remplacement portail conservées ; aucun changement rendu/harnais45.
Acquis43 : pièce luma ON/OFF64.223/91.365→91.299/91.099 ; détail15.767/20.222→20.191/20.216 (notes/essai43-rendu/portal-comparison.json).
Preuve historique inchangée du8septembre18:26:35Z : defects4, missing338, owner required5/measured0/missing5/failed1/passed0. crash0 ne vaut que pour ce lot.
Empreinte et mtime proof préservés : notes/essai45/proof-preservation.json ; pas de nouveau replay.
Tests acquis44 :294 succès/82,90s ; intégrité acquis44 :5sources/37fichiers conformes, lib0f1a5b25e21ebb4a. Non rejoués45.
Revue45 statique : tfrag3/etie_base/tie_wind/shrub appellent shade une fois ; aucune modulation froide locale non-PBR supplémentaire trouvée.
Trace43 ground/composition :120événements/12samples/unjoined0, seulement ciel/sprites. owner-regions status=diagnostic_only, unattributed_cases contient sage-hut-ground.
## TENTÉ
Deux researchers Codex high, vérification manager ; notes/essai45/diagnostic.md. Aucun défaut nouveau attribué aux petites zones owner.
PBR pbr_fused.glsl559–577/677 conserve fshd_mul/FUS_COOL ; branche distincte explicitement conservée43. Activation sur zones owner non prouvée : ne pas appliquer automatiquement le patch non-PBR au PBR.
Chemin[0,137,35,152]/entrée[82,119,153,148] : violet270–330 absent dans mesures43 avant/après ; ces rectangles ne localisent pas le défaut.
Le helper associe ciel/sprites0/10012/10013/1395 ; aucune ROI sol ni séparation terrain/TIE/décal/ombre. Nouvelle paire identique insuffisante.
Restriction « aucun appareil » appliquée comme44 ; aucun appareil, build, déploiement, nouvelle mesure image, preuve ou validateur. Aucun patch spéculatif.
## RESTE
Superviseur : résoudre le cadrage appareil avant nouvel essai de collecte ; les mêmes données ne combleront pas attribution et couverture. Pas de nouvelle boucle hors appareil identique.
Minimum sol : localisation reproductible des petites zones owner et contribution/matériau, ROI comparable ON/OFF rattachée aux case/frame/options/hash ; les instruments actuels ne fournissent pas cette association.
Quand collecte autorisée : sol vraie hutte/pièce/portail prioritaires, puis nuages/soleil et éco ; pas de chantier HD/cache/allocateur/menu autonome.
Portail :10s animées tracées après chaque reset ; surplus du groupeSprite3 et alphas différents43 n’isolent pas les contributions, pas de blend/gain inventé.
Ne pas rejouer diagnostics négatifs nuages/soleil41, éco30 et portail44. Petites zones violettes encore sans attribution ; cinq cas tous non validés.
Final :21niveaux×8h/ciels/intérieurs/vraie hutte par lots compatibles, cinq cas, menuOFF/persistance, crash0 courant. Aucun mélange de lots incompatibles.
Préférence restaurée43 realtime-lighting?=#f ; tests43 forçaient RT=1. État appareil actuel inconnu45.
Rapport≤40lignes avec8lignes proof ; validateur orchestrateur, aucun owner-ok. Handoff44 complet dans notes/essai45/previous-handoff.md.

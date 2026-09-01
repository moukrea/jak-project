# Grecharged-foliage-wind3 — la brise : reparer la reference AVANT de calibrer

Retour owner mot pour mot : `.autoport/reports/Grecharged-foliage-wind2/owner-defects.txt`.

## Trois defauts, dont un qui n'est pas le notre
- **D1, le plus important** : la brise NATIVE est cassee, notre option ETEINTE. « les arbres
  qui sont sensés être animés par défaut font de légers twitchs sans animations ». Un
  commit precedent affirmait que « le vent d'origine tournait au quart de sa vitesse » : un
  correctif de VITESSE pose sur une animation qui ne JOUE PAS produit exactement des
  twitchs. Verifie d'abord que l'animation native joue, avant tout reglage.
- **D2** : « tous les arbres ne sont pas impactés », option allumee. Recenser.
- **D3** : « ils bougent comme s'il y avait une tempête c'est ridicule ». Il demandait une
  LEGERE brise.

## ORDRE IMPOSE
D1, puis D2, puis D3. Calibrer une amplitude sur une animation cassee, c'est calibrer sur
du bruit — et c'est probablement ce qui a produit la tempete.

## Format des marqueurs
    RESULT: FOLIAGE WIND SANE
    WINDNATIVE option=off arbres_animes=<n> arbres_total=<n> amplitude_moy=<f> joue=<0|1>
    WINDCOVER option=on arbres_avec_vent=<n> arbres_total=<n>
    WINDAMP option=on amplitude_avant=<f> amplitude_apres=<f> cible=<f>
Verifie :
- WINDNATIVE avec `joue=1` ET amplitude non nulle : la reference doit d'abord etre saine ;
- WINDCOVER : arbres_avec_vent == arbres_total ;
- WINDAMP : amplitude_apres <= cible, et cible nettement sous l'amplitude_avant (une brise,
  pas une tempete) — publier le rapport avant/apres.

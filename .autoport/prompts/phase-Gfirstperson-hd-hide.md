# Gfirstperson-hd-hide — masquer Jak et Daxter HD en vue premiere personne

## Le defaut, mot pour mot (owner 2026-08-28)

> « en caméra première personne on se retrouve (quand on utilise les modèles HD) à l'intérieur
> de la tête de Jak, et on voit aussi le modèle HD de Daxter... d'abord faut corriger le
> problème et faire comme avec les modèles originaux, les masquer en vue première personne. »

C'est une REGRESSION du chemin HD : avec les modeles d'origine, les deux sont masques. Le
correctif attendu est donc de REPRODUIRE le comportement d'origine, pas d'en inventer un.

## Ce qui est deja etabli — ne pas le re-chercher

- Le drapeau d'etat existe : `(state-flags first-person-mode)`, teste par exemple dans
  `goal_src/jak1/engine/game/powerups.gc:504` et `engine/target/logic-target.gc:630`.
- Aucun de ces sites ne touche au DESSIN : la recherche `first-person-mode` croisee avec
  draw/vis/hide/status ne rend RIEN. Le masquage d'origine passe donc par un autre chemin,
  a trouver (probablement `draw-control` / `process-drawable` cote target et sidekick).

## Methode imposee

1. **D'abord prouver ou se fait le masquage d'origine** : trouver la ligne qui, en modeles
   stock, empeche le dessin du target ET du sidekick en premiere personne. Publier le fichier
   et la ligne.
2. **Puis prouver pourquoi le chemin HD ne passe pas par la** : le modele HD est dessine par un
   autre chemin (retarget / merc HD). Publier la ligne qui dessine malgre le drapeau.
3. **Corriger au point ou les deux chemins se rejoignent**, pas en ajoutant un second test.
4. Verifier sur les DEUX personnages : Jak et Daxter.

## Ce que l'owner veut PLUS TARD (hors phase, ne pas l'implementer ici)

Une vraie vue premiere personne moderne : camera avancee pour voir mains et pieds, le corps qui
tourne avec la camera, et le stick gauche laisse au deplacement. **Noter ce que le correctif
d'aujourd'hui rendrait plus difficile** s'il fige quelque chose, mais ne pas le construire.

## Critere de reussite

En premiere personne, modeles HD actifs : ni Jak ni Daxter ne sont dessines. Le reste du rendu
est inchange. Preuve par trace, pas par capture d'ecran.

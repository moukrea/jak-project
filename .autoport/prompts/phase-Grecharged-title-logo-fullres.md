# Phase Grecharged-title-logo-fullres — crisp title logo at any render scale (Recharged, gated)

## Owner request (2026-07-09, verbatim, French)
"Je remarque que dans le HUD, on arrive a avoir des modèles 3D pleine résolution même si
le rendu en fond (le jeux lui même) est a un render scale bien inférieur... C'est absolument
génial parce que l'UI est super nette, et même ses modèles 3D ! On pourait pas faire de même
avec le logo Jak and Daxter de l'écran titre ? Ça doit être possible, ça serait beaucoup
plus cool qu'un logo mega pixélisé sur les téléphones pas ouf"

## Scope
- jak1 title screen: the Jak and Daxter LOGO (a 3D model — its main-joint was manipulated
  in Gtitle-pixelmatch/title-obs.gc) currently renders inside the world framebuffer, so a
  low dynamic render scale pixelates it on weaker phones.
- Wanted: render the logo at FULL device resolution regardless of the world render scale —
  the exact mechanism the HUD 3D icons already benefit from (the HUD/UI pass renders at
  native res while the 3D world renders scaled; study how hud-pc 3D-in-HUD icons and the
  UI buckets bypass the scaled FBO, and route the title-logo draw the same way).
- Toggle in Recharged Settings ("CRISP TITLE LOGO"-style row), default OFF = stock
  pipeline byte-identical (fork rule: OFF == original always).
- Watch the classic traps: bucket ordering vs sky/ocean behind the logo, depth vs the
  flythrough background, 4x3/16x9 placement (Gtitle-pixelmatch), and jak1's aspect handling.
- Device evidence: low render-scale forced + captures OFF (pixelated) vs ON (crisp) same
  beat; verify no regression on the title at scale 1.0 and in-game HUD unaffected.

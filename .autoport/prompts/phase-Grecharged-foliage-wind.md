# Phase Grecharged-foliage-wind — jak1 foliage wind wobble (Recharged, gated)

## Owner request (2026-07-09, verbatim, French)
"Dans Jak un, les feuilles des Palmiers et les shrubs sont complètement statiques, ça
pourrait valloir le coup d'essayer d'y introduire un peu de wobble, léger mouvement, etc.
pour que ça ait l'air de réagir à une légère brise. Ça rendrait le tout moins figé !
Bien sur un toggle supplémentaire dans les Recharged Settings !"

## Scope
- jak1 only. Palm leaves + shrubs (tfrag/shrub renderer families) get a LIGHT wind
  sway/wobble — subtle, "légère brise", not a storm. Goal: the world looks less frozen.
- New toggle in the existing Recharged Settings submenu (like recharged-hud?), default
  OFF. OFF must render byte-identical to stock (Recharged rule: OFF == original always).
- Recharged divergences live in the allowed layers (pc goal_src additions / renderer C++
  behind the toggle), never unconditionally in engine paths.
- Likely home: the shrub/tfrag GLES renderer (vertex-stage displacement by a time-driven
  sine keyed on world position), or the PC renderer's vertex path — pick the cheapest
  correct layer; measure perf on the Redmi (no regression when OFF, acceptable when ON).
- Device evidence: side-by-side captures OFF vs ON (same viewpoint, e.g. Sentinel Beach
  palms + Sandover shrubs) + a short screenrecord for the motion; mCurrentFocus=jak1.

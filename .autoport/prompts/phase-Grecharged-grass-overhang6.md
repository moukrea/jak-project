## WORK ECONOMY: MANAGER verifies via the OWNER'S REAL INSTALL FLOW; owner verbatim = the spec.

# Phase Grecharged-grass-overhang6 — ROUND 6. Owner REJECTED v5 on the Redmi and gave the EXACT design.

## Owner verdict + SPEC (2026-07-14 12:40, verbatim — THIS IS THE DESIGN, follow it literally)
"Le drappé d'overhang est complètement pourri ! Alors je te recadre un peu... Grâce à l'herbe sur les
plateformes, on sait 'où' s'arrête l'herbe 'droite', bah du coup, sur toute cette bordure (sans dépasser)
tu peux déjà commencer à faire en sorte que l'herbe commence à s'incliner vers le vide. Ensuite on sait
qu'il y a un peu de mesh qui descend toujours avec l'herbe verte plate (et pas l'overhang), tu peux placer
des brins de plus en plus penchés dessus, en suivant EXACTEMENT cette partie. Ensuite vient la partie où
la texture d'overhang est... Bah là faut au moins deux couches d'herbe pour faire du volume, animée, qui
tombe complètement vers le bas, recouvrant entièrement où serait la texture (alpha) de l'overhang natif ;
qu'on cache quand à proximité, restaure à distance (LOD). C'est toujours nul en l'état et pas du tout
exploitable, tu devrais te placer exactement près d'un bord pour voir (l'emplacement actuel de Jak sur le
Redmi fait face à une plateforme (même plusieurs). Faut que ça ait de la profondeur (épaisseur), que ce
soit believable !"

## The THREE-ZONE design (owner's words → geometry; zones are CONTINUOUS, one system)
ZONE 1 — walkable top, along the known grass boundary (the LOCKED rim data): blades progressively LEAN
  toward the void as they approach the edge — WITHOUT overhanging past it ("sans dépasser"). This is a
  lean gradient on EXISTING walkable blades near the rim, not new geometry past the lip.
ZONE 2 — the sub-lip mesh strip still textured with FLAT green grass (NOT the overhang alpha): place
  blades ON those tris, following EXACTLY that mesh part, with increasing lean (continuing zone 1's
  gradient toward fully bent).
ZONE 3 — where the native overhang ALPHA texture lives: AT LEAST TWO LAYERS of grass for VOLUME
  (thickness/depth — "believable"), ANIMATED (sway), falling fully DOWNWARD, ENTIRELY covering where the
  native alpha texture would be; alpha texture HIDDEN when near, RESTORED at distance (LOD crossfade —
  the v2 fringe-fade mechanism is the right tool, keep/reuse it).
The v5 rim-drape (blades hanging from bare lip edges over DIRT faces) was WRONG — kill or restrict it:
dirt/rock drop faces get NOTHING (no grass grows from dirt); the drape belongs where grass texture
(flat-green strip = zone 2) and the native fringe alpha (zone 3) exist.

## Verification (real install flow, owner vantage)
- Warp Jak to the OWNER'S CURRENT Redmi position (facing the platforms near training start — reuse the
  v5 realflow end position) and capture EXACTLY there, close to an edge, plus a side sweep.
- ON/OFF pairs at that vantage; zone continuity visible (upright→lean→bent→two-layer fall); alpha texture
  covered near / restored far; NO blades from dirt faces; OFF==stock; precompute path re-baked (GBK7);
  slim APK + external archive, sha==device, external-mode boot line, force-stop after.
Report RESULT + honest residuals. Max: max_turns 3000, max_retries 6.

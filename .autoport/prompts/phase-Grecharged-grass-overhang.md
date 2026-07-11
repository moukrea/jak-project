# Phase Grecharged-grass-overhang — 3D DROOPING grass over platform edges (Recharged, gated)

## DEPENDS ON: clean grass edges first (Grecharged-grass-poc round#15+ landed + owner-OK)
Do NOT start until the grass EDGE is clean (grass stops exactly at every rim, owner-confirmed). This
feature builds ON the round#15 rim/lip detection — it is meaningless until that is solid.

## Owner request (2026-07-11, verbatim)
"Une fois qu'on arrive à faire les bords proprement, j'ai envie de faire l'overhang avec l'herbe 3D,
l'herbe qui tombe vers le bas sur les bords (recouvrant la texture avec alpha d'overhang), ça serait top!
Bien sûr à distance pas de grass card pour ça, on laisse directement la texture au loin, le rendu serait
ultra quali."

## Idea
At platform edges, instead of grass simply STOPPING at the rim, spawn special 3D grass that DROOPS
DOWNWARD over the lip face, covering the game's own overhang ALPHA texture (the "grass fringe" drooping-
grass texture painted on edge/lip faces — reference set includes bch-grassfringe / tra-grass fringe).
Reuse the round#15 rim/lip data: the overhang-LIP triangles we currently EXCLUDE (to avoid floating)
become the PLACEMENT zone for drooping blades.

## Approach (reuse round#15, don't reinvent)
1. PLACEMENT: on the rim + lip faces (the excluded overhang-lip tris), place a distinct grass pass.
2. ORIENTATION: blades oriented DOWN + OUTWARD, gravity-biased downward curve (reuse the per-blade
   curvature, bias it down-over-the-lip), length tuned to cover the overhang texture strip. They hang
   over the drop by design (unlike the walkable-top grass which must NOT overhang) — so this pass is
   explicitly EXEMPT from the rim height-taper; it is the intended overhang.
3. LOD (owner): NEAR = 3D drooping overhang grass; FAR = the original alpha overhang TEXTURE only, NO
   grass cards. Crossfade at the LOD boundary so the 3D grass and the underlying alpha texture do NOT
   double-up (fade the 3D in as you approach / the texture stays; avoid a hard visible pop).
4. Detect the overhang/fringe surfaces by their grass-fringe TEXTURE ids (like tra-grass detection).

## Toggle (universal mandate)
Recharged Settings toggle (own row or a Grass Settings sub-option), persisted, OFF == byte-identical
stock (original flat alpha overhang texture only). Follows the grass ON/OFF but independently disableable.

## Verify (device eae4df44) — supervisor eyeballs
Edge close-ups (level.warp.pos to real rims): NEAR shows 3D grass draping down over the lip covering the
alpha texture, no double-up at the LOD seam; FAR shows the original texture with NO cards; walkable-top
grass still stops clean at the rim (not regressed); OFF == stock. deploy_verify + deploy_verify_assets
PASS. Redmi max-settings fps informational only. Force-stop after tests.

## Report (.autoport/reports/Grecharged-grass-overhang/report.txt) RESULT: GRASS OVERHANG <verdict>
placement on lip/rim, downward-droop orientation, near-3D/far-texture LOD + crossfade proof, toggle,
device edge captures near+far ON vs OFF.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched (renderer/pc layer); gold READ-ONLY.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.

# OVERHANG — PARKED 2026-07-15 (owner order after 11 failed rounds)
Final owner verdict on R11 (verbatim): "C'est à chier ! C'est même plus de l'herbe 3D mais des cartes
d'herbe, même pas bien disposées, même pas bien orientées... Parke, note tes échecs cuisants, désactive
par défaut et passe à l'occlusion ambiante. Vraiment de la grosse merde, en plus c'est très moche !"

## The spec that was never met (owner, 3 zones — still the design when resumed)
Z1 walkable-top lean gradient at the boundary, NO overshoot; Z2 blades ON the flat-green descending
mesh strip, following it EXACTLY, increasingly bent; Z3 >=2 ANIMATED layers of REAL 3D GRASS BLADES
falling fully down, ENTIRELY covering the native hang-alpha texture (hidden near / restored far),
believable thickness. Judged CAMERA AT THE EDGE at training.

## Attempt journal — what was tried and WHY it failed (do NOT retry these as-is)
- R1-R3 (phases overhang..overhang3): droop only on GRASS-TEXTURED fringe faces; per-tri classification.
  FAILED: dirt-faced terraces got nothing; per-tri seams; parametric arcs ignored mesh; diagonal bands
  (periodic placement rows: root-edge rows + 0.28m level-sets).
- R4 (overhang4): scatter (no rows), smooth vertex normals, per-blade comb, half-space clamps. Metrics
  (banding detector, tip-plane counters) went green BUT measured the wrong zones — false pass. LESSON:
  detectors must be calibrated on the OWNER's spot, and the whole grass system was hardcoded to
  'training' (see R7) so most owner looks saw NOTHING.
- R5 (overhang5): rim-drape from bare lip edges regardless of texture. FAILED: grass hanging from DIRT
  faces = wrong (grass doesn't grow from dirt). Root cause find kept: level allowlist (was hardcoded
  'training'); GBK bake version fallback works.
- R6 (overhang6): owner's 3-zone spec v1 (bit4 transition band, two-layer fall, near-hide crossfade).
  FAILED on his eye: clip-through at transition, brutal seams, bands.
- R7 rounds 8-11 (this phase):
  * R8: lawn-color inheritance (killed the dark-olive), 3 layers, cell-noise anti-eyeliner.
    REJECTED (my filter): dark rock seam at the lip junction; stringy detached tufts.
  * R9: root overlap under the lawn silhouette + contiguity. Passed my filter at MID distance —
    at the OWNER's distance (camera at edge) the widened blades (up to 2x-H, wmul 2.2) rendered as
    GIANT FLAT PLATES (5-10x lawn width). LESSON: acceptance distance = camera touching the edge.
  * R10: width pinned to lawn scale + 2x density + deeper gradient. At owner distance = uniform lumpy
    green ROLL hugging the lip (foam look). LESSON: solid-color quads NEVER read as grass art at close
    range on this engine/resolution, regardless of width/density tuning.
  * R11 (design pivot): zone-3 = textured CARDS sampling the native hang-alpha texels, 2-3 layers,
    sway. My filter passed (texel-native tufts, continuity, animation). OWNER REJECTED: "des cartes
    d'herbe, même pas bien disposées, même pas bien orientées" — cards betray the "3D grass" ask; the
    placement/orientation along the lip was visibly wrong to his eye.

## Dead ends (falsified — do not redo)
- Solid-color blade quads for the fall zone (any width/density/layers): plates -> strings -> foam.
- Grass from bare/dirt lip edges (R5). Per-tri zone flags (seams). Global drop-length constants.
- Judging at mid-distance; metrics not anchored to the owner's exact spot and zoom.
- The stiffness lever for wind-like sway (self-cancelling through the integrator — foliage-wind note).

## What SURVIVES (working, keep on resume)
- Level allowlist + per-level bakes (training+beach; village1 deferred). GBK7 bake infra + version
  fallback. Zone-1 lean + zone-2 comb on real surfaces (R10 state) looked acceptable.
- LIVE menu->disk->C++ toggle chain proven. OFF == stock byte-identical (draw-count only).
- The near-hide/far-restore crossfade of the painted strip (v2 machinery).

## Resume hints (untried directions)
1. REAL 3D blade geometry with per-blade texture UVs (thin blades sampling a grass-blade texel strip —
   not flat-color, not full cards): combines R10 thin-scale with R11 texel look.
2. Author a small set of TUFT MESHES (3-5 hand-shaped hanging clumps) instanced along the lip with
   orientation from the lip tangent + outward normal — believable silhouettes come from authored
   shapes, not procedural quads.
3. Consider modding the NATIVE strip: keep the painted texture but render it in 2-3 parallax layers
   with sway (cheapest path to "native look with depth").
Current state: recharged-grass-overhang? DEFAULT #f (parked); toggle still functional for testing.

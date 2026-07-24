# Phase Grecharged-mesh-consolidation — FIX EVERY MESH IN THE GAME (exhaustive, provable coverage)

ultrathink. This phase comes BEFORE any further PBR rendering polish (owner's explicit priority: "j'aimerais
qu'on fix vraiment tous les mesh du jeux avant ça... avant de fix le PBR et son rendu, car tout fixé assure
une meilleure qualité pour le futur"). The PBR rendering defects are recorded at the end for the NEXT phase.

## OWNER STATEMENT (2026-07-24 late)
"Il faut que tu trouves vraiment un moyen de TOUT COUVRIR SANS OUBLIS." Two DISTINCT defects (do not conflate):
- **(1) SOUDURES OUBLIÉES (forgotten welds)**: adjacent polygons whose shared edge was never welded — visible
  as SEE-THROUGH SLITS with tessellation (device/owner_final2/n_5.jpg) and as broken shading. "J'en ai vu
  plein d'autres" => coverage is incomplete, not a one-off.
- **(2) EFFET COUTURE (seam effect)**: a visible seam LINE along chunk boundaries — present at relief 0 AND
  relief 3, on GRASS and on SAND (n_1..n_4). Independent of the normal map. Likely a normal or BAKED VERTEX
  COLOR discontinuity across the boundary.
Scope: EVERY mesh of the game — ground (tfrag), walls/objects (tie), shrub/foliage, and any other renderable
geometry — in EVERY level, not just village1.

## THE COVERAGE PROOF (this is the core of the phase — "sans oublis" must be MEASURABLE)
Build an exhaustive topological AUDIT that runs over every level's geometry and reports, per system:
1. **OPEN EDGES**: edges referenced by exactly ONE triangle.
2. **COINCIDENT-BUT-UNSHARED EDGES** = the forgotten welds: an open edge whose two endpoints coincide (within
   epsilon) with the endpoints of ANOTHER open edge from a different triangle/chunk. Each such pair is a
   seam that SHOULD be welded and is not. **This count is the objective "omissions" metric. TARGET: ~0.**
3. **NORMAL DISCONTINUITY**: for coincident vertex groups, the max angle between member normals (report the
   histogram; gentle terrain seams must be ~0 after smoothing, genuine creases can stay).
4. **BAKED COLOR DISCONTINUITY**: for coincident vertex groups, the max per-channel delta of the baked vertex
   colour (this is defect 2's prime suspect — a per-chunk baked lighting step).
5. **UV FRAME COHERENCE**: already measured (57% incoherent before the world-axis fix) — keep reporting it.
Write all of it to a per-level report file readable off-device (files/mesh_audit.txt) AND to a desktop-side
audit run over ALL levels' fr3 (offline tool preferred: it can iterate every level without the device).

## THE FIXES (drive each metric to ~0, then prove it)
A. **Weld EVERY coincident-but-unshared edge pair** across chunks/buckets/trees/systems (tfrag+tie+shrub),
   position-based, whatever the texture (geometry continuity), keeping UV/colour splits as separate vertices
   but sharing position, normal (and displacement, see C).
B. **Kill the couture**: identify per-group whether the residual seam is a NORMAL delta or a BAKED COLOUR
   delta (metrics 3/4) and fix accordingly — average the normal over the group (already), and if the baked
   colour steps across the boundary, blend/average the baked vertex colour across the welded group (small,
   invisible to art, removes the lighting step).
C. **Seam-consistent displacement** (tessellation slits): coincident verts must displace IDENTICALLY —
   same height sample (world-derived lookup or group-averaged height) + matching tess edge factors.
D. **Normals correct everywhere**: orientation flood-fill over the welded topology + collision authority
   (walkable side = outward), so no inward-facing normals remain; report the count fixed and the residual.
E. Whole-game: the audit + fixes must run for EVERY level (generic load path or offline bake for all levels),
   with the audit numbers reported PER LEVEL so no level is silently skipped.

## PRECOMPUTE (owner's standing preference)
Once correctness is proven live, bake the whole consolidated result (weld map + normals + orientation +
seam displacement data) into a per-level sidecar committed + bundled, uploaded directly at load = zero
per-load cost; live computation stays as the fallback for un-baked levels (mods).

## EXIT (owner protocol)
Mechanical bar + "READY FOR OWNER VISUAL CHECK" + the AUDIT NUMBERS per level (coincident-but-unshared edges
~0, normal/colour discontinuity ~0). The supervisor A/B's live on the owner's Honor before any push.

## RECORDED FOR THE NEXT PHASE (PBR rendering polish — NOT this phase)
- Displacement appears in the WRONG DIRECTION in places on the same texture.
- In shadow / where the sun does not hit: rendering goes completely FLAT (no relief at all).
- The displacement itself reads flat despite tessellation/parallax — "un bump map glorifié avec un peu de
  normales"; needs real perceived depth (self-shadowing/occlusion, correct displacement sign, ambient-lit
  relief so it is not flat in shade).

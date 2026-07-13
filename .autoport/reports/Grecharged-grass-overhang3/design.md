# Grecharged-grass-overhang3 — ROUND 3 design note (committed BEFORE code, per mandate)

Owner verdict on round 2: "failure totale" — droop ignores the fringe mesh/relief, appears to sprout
from walls below the floor, no visible upright->droop progression, far too long, wrong blade scale.
Owner correction (2026-07-13 22:05): the v2 fringe-texture near-hide WORKS; the visible "wall drape"
is the TRANSITION BAND — curved tris textured with the FLAT grass texture (tra-grass) that wrap from
the walkable top down toward the fringe mesh, which the PoC classifies as floor and covers with
FULL-HEIGHT UPRIGHT blades.

## Root-cause reading of the code (verified in GrassBakeCore.cpp / grass.vert)

1. The lip classifier (`is_lip`, GBC:585-656) only considers tris with upness < UPNESS_LIP_MAX (0.55).
   Curved transition-band tris with upness 0.55..~0.95 stay WALKABLE and get full-height uprights.
   Their bases sit on the curl below the visual lip -> from the side they read as grass growing out of
   the wall under the floor. The rim height-taper only reaches 0.45 m from the rim seg (which itself
   sits mid-curl at the ~0.55-upness line), so most of the band keeps full height. This is the owner's
   "wall drape" — a BASE-population defect, untouched by any droop tuning.
2. Round-2 droop blades (expand() GBC:1401-1466, grass.vert `is_droop` branch) are placed barycentric
   with top-bias and shaped by a PARAMETRIC ARC (`u_droop_len` global scale, length from the face's
   vertical span clamped 0.30..0.95 m). Nothing ties the blade to its host tri's plane or extent ->
   ignores relief, overshoots the texture, and uses a length distribution unrelated to platform grass.

## Design (mandate items 1-6 + owner correction)

### A. Transition-tri classification (bake scan, new)
A placed walkable tri is flagged TRANSITION (BakeTri.flags bit4, GBK4) iff:
- upness (== normalized ny) < TRANS_UPNESS_HI (0.85; tilt steeper than ~32°), AND
- its centroid is within TRANS_TRI_NEAR_M (1.5 m XZ, Y-window 2.5 m) of a droop-rim segment
  (the GLOBAL rim hash subset that borders the droop zone — the edge-saga data, reused as mandated).
Genuinely flat tris (upness >= 0.85) and steep grass far from any rim are untouched ->
FLOORBELOW/FLOORGAP, the rim hash, rim_q, keep tables and all walkable placement stay BYTE-IDENTICAL
(edge stack LOCKED). Classification is scan-time only; expand() placement loop order, RNG streams and
instance counts are unchanged.

### B. Transition-band comb (no more full uprights on the curl)
Blades on transition tris keep their exact stock position/height/params but are TAGGED:
nspare = -(1 + tw), tw = clamp((0.85 - ny) / (0.85 - 0.45), 0..1) — tilt-derived comb weight,
0 at ~32° (near-flat, stays upright) -> 1 at >=63° (fully combed). Negative encoding keeps every
existing marker test (is_tail nsp>1.5, is_droop, is_trans) false, so the OFF path falls through to the
STOCK else-branch with bit-identical math. A new uniform `u_overhang` (0/1, from the existing
Recharged toggle) gates the comb: when ON, the blade's growth axis lerps from world-up toward the
IN-PLANE DOWN-SLOPE direction by tw. Down-slope is derived analytically from the instance face normal
(dsl = (n.x*n.y, n.y*n.y - 1, n.z*n.y) * inversesqrt(1 - n.y^2)) — pure mad math, NO normalize(mix())
(the ROUND#19 Adreno-618 wedge class). Trample/occ kept (it IS walkable grass). Cards of tagged blades
shrink by tw and lean the same way when ON; stock when OFF.
Result: the curl's grass lies along the surface, following mesh + relief by construction, and forms
the middle of the gradient. OFF == stock stays true (identical draw ranges + identical OFF math).

### C. Droop rebuilt: mesh-following rows ON the fringe tris (mandate 1-4)
Droop tri SELECTION is unchanged (lips + rim-guarded fringe faces — all grass-textured by the
allowlist; never bare wall faces). Placement/shape are new, all derived in expand() from the tri's own
geometry (no new serialized fields):
- In-plane down-slope unit dsl from the face normal; up-slope ROOT EDGE = the edge joining the two
  highest vertices along -dsl. Where the tri abuts the walkable rim this IS the shared rim edge ->
  blades root at the rim, as mandated.
- Blades are placed along the root edge (linear density DROOP_EDGE_DENS ~22/m, jittered, nudged ~2%
  into the tri), and for tall faces additional ROWS at ROW_STEP_M (0.28 m) down-slope offsets, each
  row clipped to the tri (max 6 rows) — the whole drape mesh is tiled with combed blades that follow
  its relief row by row.
- Per-blade LENGTH = min(species sample, 0.95 * exit distance) where exit distance is the exact
  in-plane ray-to-tri-edge distance from the root along dsl -> a blade NEVER extends past its host
  tri, i.e. never past the texture it covers (mandate 3; no global world-space drop constant —
  u_droop_len survives only as a live-tunable multiplier, default 1.0).
- SPECIES sample = the walkable formula BASE_H*(0.50+1.55*rand) and the standard width formula
  H*0.092*(1-0.66t)*nearf -> same blade species/scale as adjacent platform grass (mandate 4).
- Instance encoding: nspare=2.0 (droop marker kept), (nx,ny,nz) REPURPOSED to carry dsl (the droop
  shader branch never read the normal), h = capped length, yaw = facing jitter, gspare = NO_RIM.
- Shader droop branch rewritten: grow along dsl * (t*H*dlen) with a small gravity sag
  (-Y * 0.15*t^2*H) and gentle in-plane sway — pure mad math; the blade hugs the tri plane.

### D. Continuous gradient (mandate 5)
upright (flat top, LOCKED rim taper) -> round-2 transition twins (kept; their droop-lite target
re-aimed at the new comb shape: lean outward toward horizontal, no below-base drop) -> transition-band
comb (B, tw grows with tilt) -> rooted droop rows on the fringe mesh (C). One species, one continuous
arc over the lip; proven with a side-view close-up sweep.

### E. Fringe texture near-hide (mandate 6)
Kept exactly as round 2 (owner-confirmed working): u_fringe_fade on the two hang textures
(bch-grassfringe / bch-leafyground-hang-2x1), steepness-gated. Placement (C) runs on those same
textured tris (+ lips) -> suppression and droop are geometrically coherent. Far = original texture,
no cards (droop/twins still collapse in the card pass).

### F. Format/version & OFF==stock
GBK 3 -> 4 (semantic bump: flags bit4; identical byte layout otherwise; old bakes fall back to live
scan). OFF == stock: base range [0, droop_start) byte-identical placement, tags render through the
stock else-branch when OFF, u_overhang=0 and u_fringe_fade=0 multiply by exactly 1.0, tail not drawn.

## Verify (device eae4df44) — must include round-2's failure modes
(a) wide side/below vantage of a lip + wall: NO blade sprouting from the wall below the floor;
(b) close-up: droop hugs the fringe mesh relief; (c) OFF/ON pair at the same spot: droop extent ==
painted fringe extent; (d) side sweep: continuous upright->lean->comb->droop gradient; (e) blade scale
== adjacent platform grass; (f) OFF == stock incl. fringe texture. Re-bake + round-trip check + bundle
re-hash + deploy_verify + deploy_verify_assets; force-stop after every device window; x86 untouched.

## Constants (initial, tunable)
TRANS_UPNESS_HI=0.85, TRANS_UPNESS_LO=0.45, TRANS_TRI_NEAR_M=1.5 (ywin 2.5), DROOP_EDGE_DENS=22/m,
ROW_STEP_M=0.28, DROOP_MAX_ROWS=6, DROOP_MIN_LEN_M=0.07, DROOP_EXIT_SAFETY=0.95, DROOP_LEN_DEFAULT=1.0.

# Grecharged-grass-overhang4 — ROUND-4 DESIGN DELTA (committed BEFORE code, per mandate)

Owner verdict on round 3 (2026-07-14 00:15): "complètement loupé" — three defects:
(1) clip-through at the floor→overhang transition, (2) transition brutal/absent,
(3) weird diagonal bands on the overhang (confirmed on BOTH HONOR and Redmi, 01:00 update).
Owner addendum 00:25: eyeball reads are NOT evidence; every visual claim needs a metric.

## Investigation results (before this design was fixed)

**Objective banding detector built and calibrated** (.autoport/goverhang4_banding.py):
green-masked, high-passed luminance → TILE-AVERAGED 2D autocorrelation; score = prominence of
the first off-center local autocorr peak (a repeated parallel structure), with its stripe-normal
angle and period. On the owner-confirmed failing frames owner_bands_ref_01..11 (2400x1080, crop
400,260,2000,560 = the drape band, mask 43%, 7 tiles):
  BAND@WIN = 0.042..0.056 on ALL 11 frames, period locked at 48-53 px (one outlier peak 65 px).
That stable ~50 px periodicity IS the diagonal banding, quantified. Calibration caveat
(measured): the game's ground textures TILE, so ABSOLUTE detector values across different
vantages/crops are meaningless (an OFF lawn crop at another vantage reads 0.13 from texture
tiling alone). The valid discipline — exactly the owner's — is ON-vs-OFF DELTA at the SAME
vantage and SAME crop, tracking the calibrated 40-62 px period window (PERIOD_WIN).

**Band root cause — placement structure, not precision:**
- Precision AUDITED: shaders/preprocess.py injects a global `precision highp float/int/...`
  block into every Android shader; the generated build-android blob has 94 highp blocks and ZERO
  mediump qualifiers; grass.frag declares none locally. Rounds 1-2 ran the *same* precision
  environment with no bands; the bands appeared exactly when round 3 introduced structured droop
  placement. Precision is excluded by audit + history; the controlled ON/OFF experiment below
  settles it with numbers regardless (if bands survived a placement fix, precision would be back
  on the table — the fix gate is the metric, not this argument).
- Round-3 placement is periodic BY CONSTRUCTION, in four stacked ways:
  a. one dense root-edge row (22 blades/m) per fringe tri at its up-slope edge → stripes at TRI
     pitch on the long skinny fringe strips (~0.5 m ≈ the refs' ~50 px at that distance);
  b. level-set rows every ROW_STEP_M 0.28 m;
  c. per-FACE constant growth direction (dsl of the face normal) → grain switches as hard lines
     at every tri border;
  d. per-TRI comb weight (flags bit4, from the FACE normal) → whole triangles flip state.
  (a)+(b) are literal placement rows — the prompt's suspect 3a. Numbers: the bake-side spacing
  histogram (report) shows the 0.28 m peak before / flat after.

## The round-4 design (what changes vs round 3, and why each defect dies)

### Core change: per-blade continuous fields from SMOOTH vertex normals; no rows; no per-tri state
1. **Smooth vertex normals** (bake): quantized-position weld of the whole retained tri soup
   (walkable + curl band + lip + fringe), area-weighted average of adjacent face normals.
   Every per-blade quantity below interpolates these barycentrically at the blade base →
   CONTINUOUS across every tri border by construction. Kills (c)/(d) grain and state seams.
2. **Comb = per-BLADE continuous weight** (kills defect 2): for every placed walkable blade,
   w = tilt(n_smooth.y: ramp TRANS_UPNESS_HI→LO) * near(d_droop_rim: 1 inside 1.0 m → 0 at
   2.0 m). Both factors continuous → two adjacent blades can never jump states; no per-tri bit4
   classification feeds placement anymore. No threshold is representable as a line on the mesh.
3. **OFF == stock via TAIL REPLACEMENT** (not in-place comb): a tagged original keeps its exact
   stock bytes except nspare=-(1+w) (unread when OFF → stock else-branch bit-identical; walkable
   count/positions unchanged). When ON, the shader COLLAPSES tagged originals in the blade pass
   and the toggle-gated TAIL draws a replacement twin at the same base carrying what the
   original cannot: the SMOOTH normal in normal.xyz and w in nspare (5+w). At w→WMIN the
   replacement's math reduces exactly to the stock blade → the tag boundary is invisible.
   Round-3's separate "transition twins" class (straight horizontal chord through the curved
   lip = the main clip-through) is DELETED — the continuous comb field IS the transition.
4. **Surface-constrained comb/droop** (kills defect 1):
   - growth axis = lerp(stock up-axis, analytic in-plane down-slope of the SMOOTH normal, w);
   - root offset + NOFF*w along the smooth normal (blade sits ON the surface, not in it);
   - shader HALF-SPACE CLAMP: any vertex below the base's tangent plane is projected back onto
     it (d = dot(pos-base, n); d<0 → pos -= n*d) — sway/trample included, pure mads;
   - bake-side LENGTH CAP vs the actual neighborhood: each tail blade's rest tip is tested
     against every nearby tri PLANE (grid hash); length shrinks until the whole rest arc clears
     them (or the blade is dropped if < DROOP_MIN_LEN_M) → violations ≈ 0 BY CONSTRUCTION, and
     the counter proves it (reported as a number).
5. **Droop rows → area-uniform barycentric SCATTER** (kills defect 3): droop blades are placed
   like walkable ones (n = area * DROOP_AREA_DENS, hashed barycentric points) — no root-edge
   rows, no level-set rows, nothing periodic. Direction = per-blade smooth-normal down-slope
   (continuous drape over the curl), length = min(species sample, 0.95 * in-plane exit along its
   own direction, plane cap from 4). The below-plane vertical sag term is REMOVED (it pushed
   blades through multi-row drape meshes). Droop keeps nspare=2, NO_RIM, near-pass-only.
6. GBK4 → **GBK5** semantic bump (same byte layout, new field meanings); old bakes fall back to
   live scan; bundle VERSION re-derives from the new .grassbake content hash.

### Geometric self-checks (bake, reported as NUMBERS in report.txt)
- tip_plane_violations: rest-pose arc vs all nearby tri planes, count + rate → must be ~0.
- seam metric: max & p99 |Δw| and axis-angle delta over all tail-blade pairs < 0.06 m apart on
  DIFFERENT host tris; plus max w at the tag boundary (tagged vs untagged neighbors) → no jump.
- placement periodicity: pairwise down-slope spacing histogram of droop blades per tri,
  accumulated; peak/median ratio at 0.28 m BEFORE (rows) vs AFTER (scatter, must be ~flat).
  (--dump-instances added to tools/grass_bake to extract both generations.)

### Device evidence (same-vantage, same-crop, detector numbers)
- BEACH vantage reproducing the owner refs (warp candidates -1296.4 7.8 1033.4 /
  -1297.5 7.8 1035.0 / -1300 7.8 1018.0, from grass_r22/r21d scripts + training-actors.json;
  vantage accepted when the ref crop's green mask ≥ 0.25): ON-fixed vs OFF pair →
  BAND@WIN(ON-fixed) must sit at the OFF floor (the refs read 0.042-0.056 in that window).
- Close-range VIDEO orbit sweep (screenrecord) of a floor→overhang transition zone + same-
  vantage OFF pair; round-2/3 wall wide shot must stay clean (no regression).
- deploy_verify + assets chain, focus checks, force-stop hygiene — all per the LOCKED runbook.

### Knobs (owner residual tuning)
COMB_NEAR0/1_M (1.0/2.0), NOFF_M (0.03), DROOP_AREA_DENS (~130/m², clamped by DROOP_MAX),
TRANS_UPNESS_HI/LO kept; u_droop_len stays a live neutral multiplier. Edge stack LOCKED —
untouched: FLOORBELOW/FLOORGAP/rim hash/rim_q/keep tables, fringe near-hide (owner-validated),
walkable placement stream.

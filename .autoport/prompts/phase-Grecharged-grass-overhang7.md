## ONE TASK — the owner's words: "fini ce putain d'overhang !". Nothing else matters until this is done.

# Phase Grecharged-grass-overhang7 — ROUND 7. v6 (his 3-zone spec) is STILL "à chier" on his Redmi.

## Owner state (2026-07-14, verbatim)
- On v6: "Pareil pour le overhang, c'est toujours à chier" — tested DIRECTLY on the Redmi (not the
  GitHub APK; the Redmi has the current deploy).
- Priority: "à la limite je m'en cogne de [wind], initialement on était sur l'overhang, fini ce putain
  d'overhang !"
- CRITICAL cross-hint from the wind failure: with the wind CODE PROVEN ACTIVE (file-seeded boot), the
  owner's pixel-peeping saw ZERO movement ("parfaitement statique, ça bouge pas d'un chouilla") when
  toggling via the MENU. Suspect a broken live GOAL->C++ push / menu-toggle chain for Recharged
  settings — the same chain could mean the v6 overhang tail is NOT DRAWN in his sessions at all.

## Mandate — diagnose WHICH failure this is before fixing
STEP 1 (reproduce his experience, not a harness fantasy): on the Redmi, WITHOUT resetting his settings
file, boot the game exactly as he does (launcher icon path = plain am start, no props), reach his
vantage (training-start terraces / the position facing platforms), record 10s. Compare against the v6
realflow captures. Decide with evidence:
  (a) the v6 zones are NOT RENDERING in his sessions (draw-count/census line missing or tail=0) ->
      find the state/toggle/seeding difference between his boot and the harness boot (menu-toggle live
      push? seeding order? settings keys absent from his file? precompute bake mismatch?), fix THAT.
  (b) the zones RENDER but look bad -> capture close-up video, list the specific visual defects
      yourself (density, length, color, popping, layering), fix the look. His 3-zone spec (see
      phase-Grecharged-grass-overhang6.md) remains the design.
STEP 2: fix accordingly; STEP 3: prove via the owner flow: boot with HIS settings file as-is, toggle via
the MENU (cpad nav, not file edits) to verify the LIVE path works, 10s video at his vantage that a human
judges good, OFF==stock. Also verify the menu toggle actually flips the setting on disk (read the file
after menu save) — if the menu->file->C++ chain is broken anywhere, THAT is a phase-critical fix.
Report RESULT + the (a)/(b) verdict + evidence. Max: max_turns 3000, max_retries 6.

## OWNER ESCALATION (2026-07-14 18:45, verbatim) + supervisor device forensics
"sur le Redmi, c'est au niveau de Sandover, pas d'herbe ni rien..." — at SANDOVER (village1) there is
NO grass AT ALL right now (not even the owner-validated base lawn). All workers were killed; this phase
restarts alone.
Supervisor verified on the device: settings sane (recharged-grass? #t, precomputed? #t), the external
training.grassbake is byte-identical to the published archive (GBK7), APK = the published release build.
=> PRIME HYPOTHESIS: the grassbake only covers TRAINING. Sandover/village1 grass depends on the LIVE
scan path at level load — if a recent change (GBK7 loader / v6 zone code / foliage HEAD) broke or
disabled the live path for non-baked levels (e.g. precomputed?#t short-circuiting into nothing when no
bake exists for the level), village1 loses ALL grass while training/beach captures still look fine.
STEP 0 (before anything else): boot, warp village1, capture the [recharged-grass] census/PLACE-TIME
lines for that level — confirm whether placement runs at all there, and by which path. If the live path
is broken for non-baked levels, THAT is the phase's first fix (restores the owner-validated base grass
everywhere), then continue with the overhang verdict (a)/(b) work.

## SUPERVISOR FLAG on the round-7 fix (2026-07-14 19:05)
The root cause (grass hardcoded to 'training') is a MAJOR find — but the fix allowlists only
{training, beach}. The owner's STEP-0 report is at SANDOVER (village1): "au niveau de Sandover, pas
d'herbe ni rien". village1 MUST be in the allowlist too (bake it like beach: village1.grassbake GBK7),
or the owner's very next look reproduces the bug. General rule: the allowlist must cover every level
with grass textures the owner visits — training, beach, village1 at minimum; enumerate other tra-grass
levels (jungle? misty?) and either include them or list them as explicit deferred items in the report.
The owner-validated base lawn is supposed to be GAME-WIDE, not a two-level demo.

## OWNER RESCOPE (2026-07-14 19:15, verbatim — overrides the supervisor village1 flag)
"Mais on s'en fiche de Sandover pour l'instant, faut que tu fasses l'overhang sur le niveau
d'entraînement comme prévu ! Et faut of course régler le souci où tout est violet avant, parce que ça
devrait pas être le cas."
=> 1. PURPLE: handled — the supervisor deleted the corrupted round-2 enhanced fr3s from the device
   external folder and the toggle is #f; hd_fr3_path falls back to stock when the file is absent, so
   all-magenta is now impossible. Do NOT recreate any enhanced fr3 in this phase.
   2. SCOPE: the overhang work (his 3-zone spec, phase-...-overhang6.md) is judged on the TRAINING
   level (Geyser Rock) — his original plan. The {training,beach} allowlist you landed is fine; the
   village1/Sandover bake + game-wide allowlist audit = DEFERRED (note it in the report as follow-up,
   do not spend more time on it now).
   3. Deliverable: the 3 zones looking right AT TRAINING, at his vantage (facing the terraced
   platforms), via the real flow, menu-toggle path proven, 10s video. That's the whole phase.

## ROUND 8 INPUT — SUPERVISOR'S OWN READ of the owner's live view (2026-07-14 20:40, SUPERVISOR-OWNER-VIEW.png)
The owner rejected the current render; I captured his exact view and SEE the defects myself:
1. COLOR MISMATCH (the killer): the drape is dark olive/dull while the lawn above is bright green —
   it reads as dark mold pasted on the rock, with a hard tonal seam at the lip. The drape must inherit
   the WALKABLE TOP's ground color/brightness (sample the lawn tri's color, NOT the drop face; remove or
   drastically reduce the 0.82 inner-layer darkening and any dirt-face color sampling). Same grass,
   same green, continuous across the lip.
2. NO VOLUME: fall blades are thin, sparse, plastered flat against the face. Owner asked "au moins deux
   couches ... épaisseur ... believable": increase density + width + length variation, push the outward
   belly so the curtain visibly stands OFF the face, layered parallax must be visible at this distance.
3. "EYELINER" BAND: every ledge is outlined by a uniform dark strip — break the uniformity (length/
   density jitter along the lip, ragged silhouette) so ledges don't look outlined.
Acceptance for the next attempt: the SAME vantage (SUPERVISOR-OWNER-VIEW.png) re-captured, judged
first by the supervisor against these 3 points, then by the owner. Do not present anything that still
shows a dark uniform band.

## OWNER REMINDER (2026-07-14 21:00 — the 3-zone spec re-sent verbatim; it REMAINS the design, unmet)
(Same text as the round-6 spec: zone1 lean on the walkable boundary WITHOUT overshoot; zone2 blades ON
the descending flat-green mesh strip following it EXACTLY, increasingly bent; zone3 >=2 ANIMATED layers
falling fully down, ENTIRELY covering the native alpha texture, hidden near / restored at distance;
depth/thickness, believable. "C'est toujours nul en l'état".)
=> ENFORCEMENT ADDITIONS:
- EVERY evaluation capture must be taken CLOSE to an edge ("te placer exactement près d'un bord") — the
  Jak-on-Redmi position facing the platforms. Mid-distance shots hide zone continuity; they are NOT
  acceptance evidence.
- The report must include a ZONE-BY-ZONE self-assessment against the spec (zone1 present+no overshoot?
  zone2 following the strip exactly? zone3 two visible layers, animated, covering the alpha, thick?)
  with a close-up crop proving each, BEFORE the supervisor filter.

## SUPERVISOR FILTER — ROUND 8 REJECTED (2026-07-14 21:50, my own read of R8-zone-cropA/R8-crop-lip)
Round 8 fixed COLOR (lawn green, good) and improved volume, but FAILS my filter on two precise points:
1. LIP SEAM: a dark gap/liseré shows AT the lip between the zone-1 lean silhouette and the zone-3
   hanging curtain — the rock face is visible through the junction. The fall blades must ROOT slightly
   INSIDE/UNDER the lawn's overhanging silhouette (overlap the lip edge) so lawn->curtain is one
   continuous surface with ZERO exposed rock line along the lip.
2. STRINGY TUFTS: fall blades read as detached vertical strips floating off the face. Increase density
   along the lip (target: neighboring blades overlap at the root line), keep the width variation, and
   make roots contiguous so the curtain is a connected mass, not separated tongues.
Acceptance: re-capture R8-zone-cropA's exact framing; I must see (a) no rock line at the lip junction,
(b) a connected curtain. Then and only then it goes to the owner.

## ROUND 10 — SUPERVISOR CAPTURE AT THE OWNER'S TRUE JUDGING DISTANCE (OWNER-VIEW-R9-CLOSE.png, 07:05)
Owner: "toujours aussi moche, ça ressemble à rien, rien à voir avec ce que je t'ai demandé" + re-sent
his 3-zone spec. At HIS distance (extreme close-up at the terrace edge) I see exactly why:
1. FALL BLADES ARE GIANT FLAT PLATES: the R9 "1.5x wider + wmul up to 1.90" blades render as wide flat
   uniform-color quads — green shingles/scales plastered on the face, 5-10x the width of the lawn blades
   above. WRONG APPROACH: volume must come from MANY THIN blades in MULTIPLE layers, not fewer wide
   plates. Fall-blade width must be the SAME scale as the lawn blades; compensate with density
   (multiply per-lip count) and the 3 layers.
2. Per-blade FLAT color: lawn blades have a vertical gradient/texture feel; the fall plates are single
   flat greens — give fall blades the same shading treatment as lawn blades (gradient along the blade,
   subtle per-blade variation), never one flat quad color.
3. The native alpha strip is STILL VISIBLE between/behind the plates at this distance — the near-hide
   must actually cover the band at close range (check the fade distance vs the owner's typical camera
   distance at the edge).
ACCEPTANCE DISTANCE CHANGED: all judging crops at THIS zoom (OWNER-VIEW-R9-CLOSE.png framing — camera
touching the edge). My filter failed by judging at mid-distance; that stops now.

## ROUND 11 — DESIGN PIVOT (owner on R10 live: "toujours autant à CHIER"; my capture OWNER-VIEW-R10.png)
R10 at the owner's distance = a uniform lumpy green ROLL hugging the lip (foam glued on the edge). Ten
rounds prove the primitive is wrong: solid-color blade quads (any width/density) read as plates, strings
or foam — never as the game's grass art.
PIVOT (zone 3 only): use the game's OWN hang-alpha TEXTURE as the fall primitive — textured CARDS
sampling bch-grassfringe / bch-leafyground-hang-2x1 texels (alpha-cut, same texels the native strip
uses), hung from the lip in 2-3 offset layers with per-layer sway and length jitter. The near view then
shows EXACTLY the native art style (texel-identical tufts) with real depth from layering + animation —
"recouvrant entièrement où serait la texture" becomes literal: animated multi-layer copies of the strip
replacing the flat one. Zones 1-2 (thin lean/comb blades on real surfaces) stay as-is from R10.
Requirements: sample the same texture pages already resident (no new assets); alpha-test like the native
strip; per-layer UV offset/flip so layers don't ghost; keep the near-hide of the FLAT painted strip
(cards replace it, restored at far LOD). Judge at OWNER-VIEW framing (camera at the edge).
NOTE: supervisor kill for re-prompt — this does NOT count as a failed attempt (retry counter reset).

## OWNER DECISION (2026-07-15 09:30, verbatim — end-game protocol for this phase)
"En vrai si tu y arrives pas ce coup-ci, on parke et tu notes tes attempts histoire de pas retourner en
rond quand on reprend... Next subject: l'occlusion ambiante ! Mais finis ton itération avant quand même !
Et en cas d'échec, tu mets la feature d'overhang à off par défaut dans les recharged settings en
attendant qu'on y revienne."
=> Round 11 (textured cards) finishes normally. THEN:
- If the supervisor filter + owner PASS: normal close/ship.
- If it FAILS: (1) set recharged-grass-overhang? DEFAULT #f (pckernel-impl.gc default + fresh-install
  default; existing settings files: flip to #f in the shipped archive's defaults path — the owner's
  device files get flipped by the supervisor), build+deploy that, prove OFF==stock; (2) write
  .autoport/reports/Grecharged-grass-overhang7/PARKED.md = the full attempt journal (what was tried
  rounds 1-11, what failed and WHY, dead ends not to retry, the current best state, resume hints);
  (3) the phase closes as PARKED (honest), the pipeline moves to Grecharged-ambient-occlusion.

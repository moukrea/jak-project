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

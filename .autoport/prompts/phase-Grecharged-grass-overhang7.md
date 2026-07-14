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

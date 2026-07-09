## WORK ECONOMY (manager/worker delegation)
You are the MANAGER (claude-opus-4-8[1m], effort=xhigh): plan, decide, VERIFY subagent claims yourself
(read diffs/logs, look at device frames). Delegate to autoport-researcher (HUD/menu source + sprite
pipeline scans), autoport-implementer (edits to your exact spec), autoport-tester (build/device/screencap).

# Phase Grecharged-hud-jak1 — first "Recharged" feature: an OPTIONAL new HUD for Jak 1

## Project context — "Jak and Daxter: The Recharged Jak-pot"
This fork adds OPTIONAL modern enhancements, each toggleable so OFF = the original game unchanged.
This is the FIRST Recharged feature (see [[project_recharged_jakpot_vision]]). Unlike a port-fix, this
is an INTENTIONAL owner-desired divergence — new/gated/additive code is allowed. BUT the OFF path MUST
be byte-identical to the stock HUD (no regression). Prefer new files + pc/ layer + gated draw hooks;
minimize edits to stock engine ui/hud files. Both builds (x86 + Android) get it; verify on device eae4df44.

## 1. Menu: "Recharged Settings" with a "Recharged HUD" toggle
In Graphics Options, insert a NEW submenu row **"Recharged Settings"** (FR "Réglages rechargés")
positioned **immediately BEFORE "Advanced settings"** (currently row 11, name-overridden to "PS2
Options" — see goal_src/jak1/pc/progress-pc.gc). Inside "Recharged Settings", a single row for now:
**"Recharged HUD"** ON/OFF, persisted to pc-settings (default OFF), FR label "HUD Rechargé".
Follow the existing menu machinery exactly (Goptions-reorder ordering, live-length/min-target-fps
length machinery, pad+touch nav — length-driven). All GOAL menu edits in goal_src/jak1/pc/ ONLY.
A new persisted bool (e.g. `recharged-hud?`) drives the HUD at draw time.

## 2. The Recharged HUD (only when the toggle is ON; OFF = stock HUD, untouched)
Assets are in `recharged_assets/` (repo root) — they must be baked into the build + APK assets so they
load on device (add to the asset/texture pipeline like other custom textures; pick the resolution/
format the sprite renderer needs). Place each new element at the EXACT screen location of the stock
element it replaces.

(a) **HEART / health** — replace the sprite entirely (different logic from the stock heart):
    - health 100% -> `jak_heart_100`
    - health 66%  -> `jak_heart_66`
    - health 33%  -> `jak_heart_33` BLINKING on top of `jak_heart_0` (draw jak_heart_0, blink
      jak_heart_33 over it)
    - health 0%   -> `jak_heart_0`
    Map Jak's actual health value to these 4 buckets. Full sprite at the stock heart's exact position.

(b) **ECO ENERGY GAUGE** — be clever (this is the hard part):
    Assets: `jak_gauge_empty` (empty gauge base), `jak_gauge_{blue,red,yellow}_full` (full, per eco
    type), `jak_gauge_{blue,red,yellow}_end` (the tip piece, per type). Approach:
    - Draw the empty gauge base. Over it, draw the full-gauge sprite for the ACTIVE eco type, but
      MASKED to the current fill fraction (a mask/scissor/stencil that hides the non-full portion —
      cover the empty part with the empty sprite). The full sprite is authored on a FULL gauge; the
      mask reveals only the filled amount.
    - The `_end` TIP piece cleanly finishes the filled region: rotate the sprite on its own center to
      sit at the fill boundary (by default it sits at the full-gauge end). Position it at the current
      fill edge, rotated to match.
    Match the eco type (blue/red/yellow) to the active eco + the fill to the current eco amount.

(c) **POWER CELL (pile d'énergie)** and **SCOUT FLY / mecamouche (front view)** — use the REAL 3D
    MODEL instead of the stock flat sprite (nicer). Precursor ORBS likely already use their model —
    verify + leave as-is if so. Render the model in the HUD slot at the stock element's location.

(d) FONT — leave for a LATER phase (do NOT change fonts now).

## Verify (device eae4df44) — visual, honest
- Menu: navigate Graphics Options -> "Recharged Settings" appears before "Advanced settings";
  "Recharged HUD" toggles ON/OFF and persists across relaunch. Screencaps (mCurrentFocus=jak1).
- Toggle OFF: HUD is BYTE-IDENTICAL to stock (screencap A/B vs the pre-phase build — no regression).
- Toggle ON: heart shows the right sprite for each health bucket (incl. 33% blink over jak_heart_0);
  eco gauge fills correctly per type with a clean rotated tip + proper masking; power cell + scout fly
  use the 3D model. Screencaps at several health/eco states proving each mapping.
- x86 build unaffected on the OFF path; both builds compile; full CONSISTENT build; deploy_verify PASS.

## Report (`.autoport/reports/Grecharged-hud-jak1/report.txt`) `RESULT: RECHARGED HUD <what-lands>`
menu wiring, the gate, per-element implementation + the mask/tip technique, asset-pipeline wiring,
device screencaps (ON per state + OFF==stock A/B), what's deferred (font). Honest partial OK if some
element (e.g. 3D model in HUD) needs a follow-up — but the heart + gauge should land.

## Locks: ANDROID_SERIAL=eae4df44 only; OFF path == stock (no HUD regression); .autoport/gold READ-ONLY;
full CONSISTENT builds; grep -a on routed logcat; verify mCurrentFocus=jak1 before trusting frames.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.

## X86 PRE-PASS DONE (2026-07-08, commit b1799a4e8 — build on it, don't redo)
ALREADY LANDED + x86-verified: "RECHARGED SETTINGS" submenu (before Advanced, both desktop+android
arrays, MTF live-length bumped 14->15/11->12), persisted `recharged-hud?` bool (default OFF,
serialized like extra-hud?), EN/FR labels (text ids 1706/1707) following TEXT language, OFF path
byte-identical (nothing consumes the flag yet). Enum value `recharged-settings` appended in
progress-h.gc (engine file, append-only before max — documented intentional Recharged divergence).

## ENGINE-REALITY CORRECTION for section 2 (from the pre-pass findings)
The heart/eco-gauge are drawn by the ENGINE SPARTICLE system (hud-classes.gc: hud-health = 3
particles on textures hud-health01/02/03 in the `effects` tpage; hud-power = per-slice eco meter),
NOT flat sprite blits. custom_assets texture_replacements is BUILD-TIME 1:1 by name — it cannot ADD
the 11 new sprites nor be runtime-gated; do NOT use it (would break OFF byte-identity).
IMPLEMENT THE VISUALS in goal_src/jak1/pc/hud-classes-pc.gc as a new `hud-recharged-*` element that
reads `(-> *pc-settings* recharged-hud?)` (the file already reads extra-hud? at ~line 262): hide the
stock element when ON, draw the custom one. For the NEW sprite textures (11 PNGs in
recharged_assets/), pick a runtime-loadable path (new texture slots via the pc texture pipeline or a
small custom adgif/sprite draw in the pc HUD layer) — a renderer-side addition, budget for it.
GOOD NEWS: the POWER CELL already uses the REAL 3D MODEL in the HUD (hud-classes.gc:850,
*fuelcell-naked-sg*), and hud-classes-pc.gc already has the 3D-in-HUD machinery (hud-pc-make-icon /
manipy-spawn / dma-add-process-drawable-hud-with-hud-lights) — spec 2c (cell + scout-fly 3D) is a
small extension of that, and the heart/gauge belong in the same home.
REMAINING for this phase: the gated visuals (heart 4-state + 33% blink, gauge mask + rotated tip),
scout-fly 3D via the existing icon machinery, Android asset wiring, on-device verify (menu/toggle/
persistence + each health/eco state), per the original spec.

## OWNER CORRECTION (2026-07-08 ~17:30) — power cell: the REAL FULL model, not the "naked" one
The current HUD fuel-cell (*fuelcell-naked-sg*) looks like a LESSER sprite-ish version to the owner
("version amoindrie"). Spec 2c means the REAL full in-world fuel-cell model (with its proper
geometry/shine — the version you collect in-game), rendered in the HUD slot. Same for the scout fly:
the real front-view model. Upgrade the icon machinery's skeleton-group accordingly.

## OWNER QUALITY REVIEW of the x86 pass (2026-07-08 ~21:00) — MUST-FIX list for this phase
 1. **Asset cropping is WRONG**: do NOT auto-crop each PNG by its own alpha bounding box. The hearts
    all share ONE canvas; the gauge empty/red/blue/yellow FULL all share ONE canvas; and the `_end`
    TIPS are mostly-transparent BY DESIGN to overlay EXACTLY on the gauges — they must be cropped
    with the SAME pixel counts per side as the gauges (crop like the gauge, not by transparency),
    or the overlay alignment breaks.
 2. **Filtering**: the sprites render too CRISP/aliased ("comme s'il n'y avait pas de filtering") —
    apply proper sampling (bilinear/downsampling consistent with the rest of the HUD).
 3. **Heart visibility**: the heart shows CONSTANTLY — WRONG. It must follow the stock element's
    visibility rules; per the owner it should only be visible when health is at the LAST notch
    (match the stock heart's show conditions exactly).
 4. **Fuel-cell double-draw STILL present**: the real 3D cell renders OVER the sprite version — the
    stock element must actually be suppressed when recharged-hud? is ON (previous fix ineffective).
 5. **Position/scale parity**: heart + gauge must sit EXACTLY at the stock elements' position and
    scale (for now — no creative placement).
 6. **Precursor orb: REMOVE the ugly glow behind it** ("le glow dégueulasse") — doesn't fit.

## SUPERVISOR DIRECTIVE after 3 no-report attempts (2026-07-09 02:10) — REPORT-FIRST protocol
Three attempts died with work committed but NO report.txt (turns exhausted in builds). MANDATORY:
 1. FIRST ACTION of this attempt: create .autoport/reports/Grecharged-hud-jak1/report.txt as a
    living skeleton headed `STATUS: IN-PROGRESS` (do NOT write a RESULT: line until the END — the
    validator rejects skeleton RESULT lines) + section stubs, updated after EVERY milestone. Write
    the final `RESULT: RECHARGED HUD <what-lands>` line only when the device evidence is captured.
 2. Capture device evidence EARLY (menu + each HUD state screencap as soon as each element works,
    not batched at the end).
 3. You inherit 3 attempts of committed WIP (645cedca6, 78e442b1d, ad05e89d3) — audit what already
    works before redoing anything; the remaining gap may be small.

## ENDGAME DIRECTIVE (supervisor 2026-07-09 03:15 — attempts 5/6 stalled; scope is now MINIMAL)
Everything is implemented and committed across attempts 1-4 (+ the x86 visuals phase). DO ONLY THIS,
in order, nothing else:
 1. Build the CONSISTENT jak1 android chain if not fresh (cmake gk -> gradle assembleJak1Debug),
    install on eae4df44, deploy_verify PASS.
 2. Capture the device evidence: menu (Recharged Settings + toggle), HUD OFF (stock A/B), HUD ON at
    health 100/66/33-blink/0 and eco gauge fills (drive via the debug hooks), the 3D cell+fly icons
    visible + hidden states. Name files device-*.png. Verify mCurrentFocus=jak1 for each.
 3. Finalize the report: replace the STATUS line with the final `RESULT: RECHARGED HUD <what-lands>`
    + fill the evidence paths + honest residuals (anything from the owner's 6-point list not met).
NO refactors, NO new features, NO investigation beyond what step 2 reveals as broken (if something
IS broken on device, fix minimally or report it as residual — do not expand scope).

## OWNER PLAYTEST ROUND 2 (2026-07-09) — verbatim, fix ALL before re-gate
Owner quote (verbatim, French):
"Alors retour rapide sur le HUD, la jauge d'énergie bleue/rouge/jaune est trop petite par
rapport à la jauge qu'elle remplace, mais elle fonctionne exactement comme je voulais par
contre bien joué ! La pile d'énergie n'apparaît plus du tout par contre... Et pour la jauge
j'ai pas précisé mais quand active, en son centre (c'est troué exprès), j'aurais voulu qu'on
ait la 'particule' d'éco affichée comme indicateur de la sorte d'énergie en cours
d'utilisation, comme l'item en 3D qu'on peut collecter en jeu pour justement remplir cette
jauge, ça serait trop stylé ! D'ailleurs pour l'énergie 'vie' la verte à côté du cœur,
pareil, la vraie particule telle que les petites sphères d'eco verte qu'on peut ramasser au
lieu du sprite animé qui y ressemble (à côté du cœur, entre le cœur et le compteur texte
correspondant)."

Breakdown (do not reinterpret):
1. GAUGE TOO SMALL: the blue/red/yellow eco gauge is too small vs the stock gauge it
   replaces. Behavior is EXACTLY right (owner: "bien joué") — only SCALE it up to match the
   stock gauge's footprint. Do not touch fill/mask/tip logic.
2. POWER CELL REGRESSION: the fuel cell no longer appears AT ALL in the HUD (it used to,
   as the real full *fuel-cell-sg* 3D model). Restore it — real full model, single draw,
   stock position/scale (prior rounds' rules still apply).
3. NEW — GAUGE CENTER PARTICLE: the gauge center hole is intentional; when the gauge is
   ACTIVE, render there the 3D eco "particule" item — the same collectible eco item seen
   in-game that fills this gauge — as the indicator of which eco type is in use
   (blue/red/yellow accordingly). Use the existing 3D-in-HUD machinery
   (hud-pc-make-icon in goal_src/jak1/pc/hud-classes-pc.gc).
4. NEW — GREEN ECO PARTICLE BY THE HEART: same idea for health: replace the animated
   green sprite next to the heart with the REAL green eco small-sphere collectible
   (the pickup model), positioned between the heart and its text counter.
All still gated behind recharged-hud? — OFF stays 100% stock. Device evidence per item.

## OWNER LIVE REVIEW — round 2 addendum (2026-07-09, current Redmi build)
Owner quote (verbatim, French):
"Alors sur ce qu'il y a actuellement sur le Redmi, la pile d'énergie est bien dans le HUD,
mais bizarrement elle rend pas pareil que les piles d'énergie in game, son animation va
beaucoup trop vite, elle n'emet pas la lueur qu'elle emet ingame et elle a pas la même
teinte non plus !"

Breakdown (do not reinterpret): the HUD fuel cell must render IDENTICALLY to the in-game
collectible fuel cells:
a. ANIMATION SPEED: currently much too fast — match the in-game cell's spin/anim rate.
b. GLOW: the in-game cell emits a glow/lueur — the HUD one must emit it too.
c. TINT: the HUD cell's color tint differs — match the in-game tint exactly.
Likely cause family: the 3D-in-HUD icon path (hud-pc-make-icon) not carrying the same
anim clock / draw flags / lighting-tint env as the world entity — compare against the
in-game fuel-cell draw setup rather than tuning constants by eye.

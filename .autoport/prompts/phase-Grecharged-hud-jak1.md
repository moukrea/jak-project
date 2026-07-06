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

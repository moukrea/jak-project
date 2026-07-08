## WORK ECONOMY: MANAGER plans/verifies; delegate to researcher/implementer/tester. Parallelize.

# Phase Grecharged-hud-visuals-x86 (device:false) — the gated Recharged HUD visuals, x86-verified

Continuation of the landed pre-pass (b1799a4e8: menu+`recharged-hud?` toggle+labels, OFF byte-identical)
and the engine-reality findings — READ phase-Grecharged-hud-jak1.md sections "X86 PRE-PASS DONE",
"ENGINE-REALITY CORRECTION" and "OWNER CORRECTION power cell" first. This phase implements the VISUALS
on x86 only (NO device — device wiring/verify is the later Grecharged-hud-jak1 phase).

## Mandate (all gated on `(-> *pc-settings* recharged-hud?)`, home = goal_src/jak1/pc/hud-classes-pc.gc)
1. hud-recharged heart: hide stock hud-health when ON; draw the 4-state heart (jak_heart_100/66/33/0
   from recharged_assets/, 33 BLINKING over 0) at the stock position. Solve the new-sprite-texture
   loading path (new runtime texture slots via the pc texture pipeline or a custom adgif draw).
2. hud-recharged eco gauge: empty base + per-eco full sprite MASKED to fill + rotated _end tip at the
   fill edge (scissor/uv-clip technique documented).
3. Power cell + scout fly HUD icons: the REAL FULL models (owner: current *fuelcell-naked-sg* is a
   lesser version — use the proper in-world skeleton-groups) via the existing hud-pc-make-icon machinery.
4. OFF = byte-identical stock (A/B evidence).

## Verify (x86 desktop): drive health/eco via listener to hit every bucket (100/66/33-blink/0; each
eco color + fill levels); capture x86 window evidence if the session allows, else state-dump proof of
each branch + flag reads. `(mi)` clean; boots to play; OFF A/B identical.
## Report .autoport/reports/Grecharged-hud-visuals-x86/report.txt `RESULT: RHUD VISUALS X86 <status>`
per-element implementation + technique + evidence; honest partial OK with named blockers.
## Locks: no device commands; .autoport/gold READ-ONLY; engine goal_src edits minimal+documented.
## Max: max_turns 2400, max_retries 4. device: false, owner_verify: false.

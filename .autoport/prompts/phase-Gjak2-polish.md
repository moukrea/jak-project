## WORK ECONOMY: MANAGER plans/verifies; delegate researcher/implementer/tester. Parallelize.

# Phase Gjak2-polish — owner playtest round-2 fixes (2026-07-08 verbatim)

## The five items (device eae4df44, owner-verifiable each)
 1. **CROUCH-LOCK (owner retested — NOT just the L1/R1 button)**: after a few actions (even just
    two jumps) Jak ends up crouched and LOCKED in that stance whatever the input; jump works but he
    re-crouches on landing. Owner's lead: "ça me fait penser au bug de collisions dans Jak 1 qui
    accroupissait Jak très souvent". STRONG HYPOTHESIS (sibling of the Gjak2-movement root cause):
    the CEILING/stand-up collide probe (the query deciding whether Jak can stand) consumes a stack
    collide-tri-result that a still-noop'd/garbage-filling collide fn never writes -> the game
    permanently believes there's a ceiling -> forced duck. Audit the crouch/stand path's collide
    consumers exactly like the movement fix did (which fn fills its result? is it noop'd/garbage on
    arm64? state-dump the probe result our-x86 vs device mid-crouch-lock). ALSO still verify the
    overlay L1/R1-as-one-button mapping vs jak2's real bindings (secondary).
 2. **Cinematics ignore the aspect-ratio setting**: cutscenes render forced 16:9 while gameplay
    follows the configured aspect (fit-to-screen). Cutscenes must FOLLOW the setting too.
 3. **Graphics menu parity with jak1**: same OPTION ORDER as jak1's graphics page, and the
    "Options PS2"/"Advanced Settings" row named exactly as jak1 names it (match jak1's final label).
 4. **FPS counter option missing**: port jak1's FPS-counter toggle to jak2's menu.
 5. **Rift-gate glow: too bright ONLY before the metalheads emerge** (after that beat it's OK) —
    tune the pre-beat glow inputs (state-dump the glow size/interp vs x86 at that exact beat; the
    Ghalo/sun methodology).
## Verify: device screencaps/video per item (crouch-free play with the overlay incl. the L1/R1 button,
cutscene at 4:3 AND fit-to-screen, menu order+labels side-by-side vs jak1, FPS counter live, portal
beat A/B vs x86). mCurrentFocus=jak2; x86 unaffected; full consistent build; deploy_verify PASS.
## Report .autoport/reports/Gjak2-polish/report.txt `RESULT: JAK2 POLISH <n>/5`
## Locks: ANDROID_SERIAL=eae4df44; engine goal_src untouched (pc/ + glue only); gold READ-ONLY.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.

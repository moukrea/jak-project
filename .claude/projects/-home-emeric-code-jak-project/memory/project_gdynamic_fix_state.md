---
name: project_gdynamic_fix_state
description: Gdynamic-fix PASS — dynamic render scale now seeks the MAX scale holding target (regime-split fps-vs-busy) + runtime re-clamp
metadata:
  type: project
---

Gdynamic-fix PASS 2026-07-01 (commit bc651690e), validator green, device-verified, AWAITING OWNER PLAY-TEST.

Fixed two owner bugs in the adaptive render-scale controller (`goal_src/jak1/pc/pckernel-common.gc` `dynamic-render-scale-update`; pc/ only, engine + libgk UNCHANGED):
- **Bug 2 (headline): stuck at floor with headroom.** Prev attempt raised ONLY on frame-time headroom (`busy <= 0.80*budget`). **KEY INSIGHT: `busy` (pc-get-frame-busy-us = render_cpu_s / desktop render_game_frame CPU time) is ~SCALE-INDEPENDENT** — render scale changes GPU fill, not CPU draw/DMA work. In a big/draw-bound scene busy stays near the vblank budget even at the floor, so the busy-only raise gate never opens though fps sits well ABOVE a low target → parked at floor = worst quality.
- **Bug 1: runtime Min-Render-Scale raise not applied** (no re-clamp of the running scale to a raised floor).

Fix = **regime-split by the presentation cap** (`pc-get-active-display-refresh-rate`, default 60): REGIME 1 (target below cap) → CLIMB on fps>=target+3 (proportional +10/+6/+3, the core fix); REGIME 2 (target≈cap, vsync-capped, fps can't exceed cap) → keep the busy-headroom +4 probe (attempt-2 behaviour). DESCEND both regimes on fps<target-margin (1.0 below cap / 2.5 near cap), proportional -12/-8/-4, **NO busy gate** (busy blind to GPU-bound drops). RE-CLAMP: min/target change snaps scale into new [floor,100] + resets cooldowns. Anti-thrash kept (2nd-stage EMAs, dead-band, cooldowns, post-lower lockout, floor clamp, load hold). OFF=manual.

Verify: x86 goalc-REPL (`.autoport/gdfix_x86_repl.sh`) deterministically proved descend→re-clamp→climb→OFF (identical GOAL bytecode). Device eae4df44 (`.autoport/gdfix_run.sh`): descend_climb reproduced+fixed the owner bug — under GPU load 100%→45% then CLIMBS back 45→59% on fps headroom while busy 22ms > old-gate 20ms (old code STUCK). Geyser on this device runs ~40-60fps (NOT the 30 an old comment claimed). Related: [[project_gdynamic_renderscale_note]] if present; builds on [[feedback_state_dumps_x86_first_not_screenshots]] (x86-first proof).

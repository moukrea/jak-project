# Phase Gtitle — remove the spurious "Press <CIRCLE> to use" prompt in the title attract

**Verdict: FIXED.** The gameplay "Press <CIRCLE> to use" interaction prompt no longer
appears during the title attract flythrough. The title still flies, Daxter / the ND
logo still render (Gnd), the SCE/ND attribution screen still renders (Gsprite), and the
attract reaches the "JAK AND DAXTER — PRESS START" title screen crash-free. The fix is a
3-edit, single-file change in `goal_src/jak1/levels/title/title-obs.gc` (TIT.DGO only)
that replicates the original game's own scene-script behaviour. It is gated by a
documented arm64-runtime cause (see Root Cause).

--------------------------------------------------------------------------------
## 1. The defect (what the owner saw)
--------------------------------------------------------------------------------
During the boot title attract — a pure camera flythrough of Sandover village that plays
before you press START — a gameplay "PRESS [O] TO USE" prompt appeared in the lower-left
of the screen over the intro. The attract is supposed to be a clean cinematic; a gameplay
interaction prompt over it is wrong. On the pristine upstream build it never appears.

Captured evidence of the defect (pre-fix, current/post-Gsprite build):
  `.autoport/reports/Gtitle-device-run1-t030s.png`  — "PRESS [O] TO USE" over the
  ndi-intro rocky flythrough.
  (Also visible in the inherited `Gsprite-device-run7-t16s.png` / `-t24s.png`.)

--------------------------------------------------------------------------------
## 2. The spurious process (named, with evidence)
--------------------------------------------------------------------------------
The prompt text is the GOAL text-id `press-to-use` (= "Press <CIRCLE> to use",
`engine/ui/text-h.gc`). In village1 — the level loaded as `lev1` during the title — only
TWO actors draw `press-to-use`:

  * the **warp gate** — `levels/village_common/villagep-obs.gc:104`, the `idle` state of
    the `warp-gate` process. The `warp-gate` process is spawned `:to` (as a child of) the
    entity **`warp-gate-switch-3`** (`villagep-obs.gc:429`, `basebutton-down-idle :enter`).
  * the **fisherman's boat** — `levels/village1/fishermans-boat.gc:638`, inside
    `fishermans-boat-leave-dock?`.

The boat's draw is gated by `(task-complete? *game-info* (game-task jungle-fishgame))`,
which is impossible on a fresh-boot attract (no save) — verified `fishtask=#f` on BOTH
backends (see oracle-diff). So the boat is NOT the drawer. **The spurious process is the
`warp-gate` (child of `warp-gate-switch-3`).** On arm64 its draw site fired 1129× during
the attract (instrumented count), on x86 it fired 0×.

The village NPCs (`sage-23`, `assistant-11`, `explorer-4`, `farmer-3`, `oracle-1`) draw a
DIFFERENT prompt (`press-to-talk`, via `process-taskable`), and their guard additionally
requires `(none-reserved? *art-control*)`, which is false while the logo spool is playing
— so they are correctly suppressed during the attract and never drew. Only the warp gate
slipped through.

--------------------------------------------------------------------------------
## 3. The pristine diff (why the original never shows it)
--------------------------------------------------------------------------------
`.autoport/gold/pristine-boot-sequence.log` states the pristine attract holds at
`target-title-play`/`target-title-wait` under master-mode `'game` with "NOTHING
title-only over-spawns". The original game keeps the attract clean by having the **logo
scene-script kill the village1 interactables** as the flythrough plays: the spooled anim
command-lists for `logo-intro-2` (frame 261) and `logo-loop` (frame 61) contain
`(261 kill "warp-gate-switch-3")` and `(262 kill "fishermans-boat-2")` plus the NPCs
(`title-obs.gc:201-261`). These `kill` verbs are dispatched by
`execute-commands-up-to` / `execute-command` (`engine/level/load-boundary.gc:1171,1249`)
as the spool animation frame advances, via `ja-play-spooled-anim`
(`engine/load/loader.gc:697`). On the original PS2 / pristine x86 the spool streams fast,
so the kill at frame 261 fires almost immediately and the warp gate is dead before it can
draw.

So pristine suppresses the prompt by two independent mechanisms: (a) on x86 the warp gate
is far enough from the target that its proximity guard fails anyway (see Root Cause), and
(b) the scene-script kills it.

--------------------------------------------------------------------------------
## 4. Root cause (the arm64-runtime divergence — oracle-diff)
--------------------------------------------------------------------------------
I instrumented the warp-gate and boat guard terms in both backends and ran the SAME title
attract on our x86 oracle (`build-x86/game/gk`, pristine-equivalent — goal_src is shared)
and on the arm64 device. The warp-gate draw guard is
`(>= 20480.0 (vector-vector-distance (-> self root trans) (-> *target* control trans)))`
(`villagep-obs.gc:76`) — i.e. "target within 5 m of the warp gate".

Term-by-term result (every other term identical):

| term                         | x86 oracle        | arm64 device      |
|------------------------------|-------------------|-------------------|
| `dist` (vector-vector-dist)  | **52.0183 m** (warp), 158.79 m (boat) — finite | **NaN** (both)   |
| `movie?`                     | #f                | #f                |
| `level-hint-displayed?`      | #f                | #f                |
| `*master-mode*`              | game              | game              |
| `fishtask` (boat)            | #f                | #f                |
| warp prompt drew             | NO (0×)           | **YES (1129×)**   |
| boat prompt drew             | NO                | NO                |

**The sole divergent term is `dist`.** On arm64 `vector-vector-distance` returns **NaN**
for BOTH the warp gate AND the boat. The common operand is `*target*` → the target's
`control trans` reads NaN on arm64 during the title attract (it is a finite, ~52 m-distant
position on x86). The warp gate's guard `(>= 20480.0 NaN)` then evaluates **TRUE** on
arm64 (IEEE-754 says comparisons with NaN are unordered → should be false; x86 never even
hits this because its distance is a valid 52 m), so the proximity guard passes and the
warp gate draws. (The boat's guard is `(< NaN 6144.0)` which arm64 evaluates FALSE, and it
also needs `fishtask=#t` — so the boat correctly does not draw.)

This matches the phase mandate's expected shape exactly: "an uninitialized field / mis-read
that makes a guard pass when it shouldn't." There are two layered arm64 bugs here:
  (1) `*target* control trans` is NaN during the title attract on arm64 (finite on x86).
  (2) the arm64 float compare `(>= const NaN)` returns #t (it should be #f).

The prompt is TRANSIENT: it shows only in the ndi-intro / logo-intro window BEFORE the
scene-script frame-261 kill runs, then disappears (pre-fix run1: present at t030s, gone by
t110s/logo-loop). On x86 the same window exists but the prompt never draws because the
distance is a valid 52 m.

--------------------------------------------------------------------------------
## 5. The fix
--------------------------------------------------------------------------------
`goal_src/jak1/levels/title/title-obs.gc` — added `title-attract-kill-interactables`, a
helper that kills `warp-gate-switch-3` and `fishermans-boat-2` using the SAME
`entity-by-name` + `kill!` + `(entity-perm-status dead)` pattern the engine's own
`execute-command` `kill` verb uses (`load-boundary.gc:1249-1264`). It is called from
`target-title :trans` (covers the ndi-intro window where the prompt first appears) and
`target-title-play :trans` (covers the logo-intro flythrough window). Killing
`warp-gate-switch-3` also removes its child `warp-gate` process (the actual prompt
drawer); the dead flag prevents respawn for the rest of the title. village1 reloads fresh
on New Game, so gameplay is unaffected.

This is **not** a blanket prompt-suppression hack. It removes the specific over-active
interactables, and it is exactly what the original game does (its logo scene-script kills
these same two entities) — just triggered up front so it is robust to arm64's slow
streaming and the NaN proximity, instead of depending on the frame-261 spool timing.

Why fix here rather than the NaN itself: the NaN target-position and the arm64
`(>= x NaN)` compare are broad arm64-codegen / runtime concerns that affect float
comparisons game-wide and warrant their own dedicated, regression-gated codegen phase
(analogous to the deferred IDIV-X8 hazard). Fixing them inside this title-polish phase
would mean a full-engine recompile with a large blast radius against the title-regression
gate. The scoped, pristine-faithful kill is the correct fix for this phase; the NaN is
documented for follow-up.

--------------------------------------------------------------------------------
## 6. Verification (device + oracle)
--------------------------------------------------------------------------------
* arm64 build: `Successfully built all 1317 targets`. x86 restore build: same.
* x86 smoke (title-regression gate): `link finish: logo` present (23×), reaches
  `link finish: logo-loop`. No regression.
* Device run 3 (`.autoport/reports/Gtitle-routed-logcat-run3.log`): `sig=11` count = 0,
  frame_max = 5100 (≥300), focus held on `org.opengoal.gk.jak1` across all 20 samples,
  spool reaches `logo-loop`. `fishermans-boat-ride-to-misty` stream count 3 → 0 (the boat
  is now killed), confirming the kill fired.
* Attract frames (post-fix, run 3) — prompt GONE:
  - `Gtitle-device-run3-t014s.png` — Daxter renders on the ND-logo backdrop, no prompt.
  - `Gtitle-device-run3-t030s.png` — ndi-intro flythrough, CLEAN (this frame showed
    "PRESS [O] TO USE" pre-fix in run1).
  - `Gtitle-device-run3-t080s.png` / `-t110s.png` — "JAK AND DAXTER / PRESS START" title
    logo over the village, no prompt.

--------------------------------------------------------------------------------
## 7. Files changed
--------------------------------------------------------------------------------
* `goal_src/jak1/levels/title/title-obs.gc` — add `title-attract-kill-interactables`;
  call it from `target-title :trans` and `target-title-play :trans`. (compiles into
  TIT.DGO)
* `.autoport/gtitle_run.sh` — new device-run harness (long attract capture; not infra).
  villagep-obs.gc / fishermans-boat.gc were only touched by temporary oracle-diff
  diagnostics, now fully reverted (clean `git diff`).

--------------------------------------------------------------------------------
## 8. Recommended follow-up (out of this phase's scope)
--------------------------------------------------------------------------------
Dedicated arm64-codegen phase to address the underlying NaN issues this phase uncovered:
  (a) why `*target* control trans` is NaN during the title attract on arm64 (uninitialized
      vs the finite value x86 holds), and
  (b) the arm64 float-compare semantics for `(>= x NaN)` / unordered comparisons returning
      #t where x86/IEEE return #f.
Either fix would correct the proximity guard at its source for every NaN-sensitive guard in
the game. Water + any missing title elements remain separate follow-ups as noted in the
phase brief.

# Gdeath-crash — fix summary

## Symptom (owner, 2026-06-27)
On the device build, after finishing Geyser Rock + the Sage hut and entering the first
real level, **Jak DYING crashes the app** — the screen returns to the Android home and the
process is killed (SIGSEGV class). The mouche + blue-eco-portal crashes are gone; this
death/respawn crash was the new blocker. x86 does NOT crash on death.

## Reproduction (deterministic, x86-first)
The owner demo `.autoport/demos/death-crash.inputs` was recorded from an in-level
checkpoint, so replaying it from a fresh boot stalls at the title attract loop (the
recorded inputs assume Jak is already in a level) — it does not re-reach the death. So I
built a deterministic, repeatable death trigger instead (kept as permanent prop-gated
debug tooling, OFF by default, mirroring the existing f1.warp / mouche / echo.intro hooks):

- **`die_maybe_fire()`** in `game/kernel/jak1/kmachine.cpp` (dispatched from
  `game/kernel/jak1/kboot.cpp`), gated on env `OG_DIE` / prop `debug.opengoal.die`, mode via
  `OG_DIE_MODE` / `debug.opengoal.die.mode`:
  - `respawn`     → `(initialize! *game-info* 'die #f #f)` (the debug "New Life" form) — respawn/loader path only.
  - `endlessfall` → `(send-event *target* 'attack-invinc #f (static-attack-info ((mode 'endlessfall))))` — fall death.
  - `drown-death` → same, mode `'drown-death`.
  - `movie`       → zero Jak's health then send mode `'tar`, forcing the generic death-MOVIE (`else`) branch.
  It re-arms after each respawn (gated on `*target*` alive + `*game-info* mode == 'play`),
  exactly like `mouche_maybe_fire()`, so it can drive N deaths in a row.

Harness: warp to Geyser Rock (`debug.opengoal.f1.warp 1`), then arm the death hook;
`.autoport/gdeath_run.sh <mode> <count>` builds/installs/deploy-verifies, then observes
crash vs. crash-free deaths. The pure x86/oracle baseline is the same hook under env vars.

### BEFORE (the reproduced crash)
- x86 (`build-x86/game/gk`, OG_DIE_MODE=movie): **5/5 deaths crash-free** — the death movie
  (`death-0202`/`death-0187`/`death-0182` spools) plays and Jak respawns. x86 never crashes.
- Device arm64 (movie mode), `.autoport/reports/Gdeath-crash/movie-build-result.txt`:
  **HARD-CRASH after 1 death**, `sig=11 fault=0x0 pc=0x7f0018b178 lr=0x7f01ce5268`,
  `focus_app=no` (app killed → Android home — exactly the owner's symptom).
- endlessfall mode (device): 6/6 crash-free — so the crash is specific to the death-MOVIE path, NOT the common respawn/loader.

## Root cause (arm64-vs-x86 divergence) — NOT a memory stomp
The initial "merc/blerc stomps KERNEL.CGO" hypothesis was FALSIFIED. The faulting word
`0x0000beef` at pc `0x18b178` is **legitimate on-disk arm64 kernel code** — a compiled
`(break)` (`udf #0xBEEF`, the `(/ x 0)` divide-by-zero guard) inside **`thread-suspend`**
(`goal_src/jak1/kernel/gkernel.gc:606`), verified against `out/jak1-arm64/iso/KERNEL.CGO`
file-offset 0x17602. Every content canary correctly did NOT fire (`stomps: none`; the kernel
band `[0x18ae84,0x1912b4)` was byte-identical to disk; `GMATCH-RFTD` memcmp == 0).

`thread-suspend` does `(when (> (process-stack-used proc) (-> this stack-size)) (break))`.
The crashing thread (forensics): the **pov-camera death-movie `code` thread**, `stack-size=256`,
`used=304`, **OVER=48**. The death-movie (`target-death.gc:872-910` else branch) spawns a
`pov-camera` and loops `ja-play-spooled-anim` with `(suspend)`. On arm64 the same GOAL code
uses MORE stack than x86 because the arm64 `.push` is 16-byte-aligned vs x86's 8 bytes — the
documented arm64 stack-inflation class. So the x86-calibrated 256-byte backup-stack budget
overflows by 48 bytes on arm64, tripping the `(break)`. x86 (8-byte pushes) stays under 256
and never trips it. pov-camera keeps the small default budget because its `set-stack-size!`
is a no-op (`pov-camera.gc:124`).

This is the SAME class the Gecho-pool phase addressed; that fix
(`handle_suspend_overflow_break`) tolerates a SMALL suspend overflow but capped at `over <= 32`.
The death-movie overflow is 48, so it was rejected → fatal `(break)` → SIGSEGV.

## The fix (translation layer; goal_src 1-to-1; arm64-only file)
`android/gk_android_main.cpp`, `handle_suspend_overflow_break`: raise the tolerance ceiling
from `over > 32` to `over > 48`. When the `(break)` traps, the handler redirects the PC past
the break body (to the `(when ...)` skip target) so the suspend completes on valid GOAL
pointers, instead of letting the `udf` kill the process.

### Why 48 is the exact, rigorous safe maximum (no s0-s4 corruption)
cpu-thread layout (`all-types.gc:1790`): the suspend's inline backup copy fills the `stack`
buffer (off 128) from its END downward; an overflow of `over` bytes spills BACKWARD into the
SAME cpu-thread, region `[128-over, 128)`:
- `freg` (off 96..128, 32B) = the xmm8-15 saves → transient floats (visual-only).
- `rreg5,6` (off 80..96, 16B) = a4/a5 → "the compiler should assume these are overwritten
  anyway" on a normal resume (`gkernel.gc:716-728`) → harmless.
- `rreg0-4` (off 40..80, 40B) = s0-s4, callee-saved POINTERS → corrupting these CRASHES.

`thread-resume` copies the backup BACK to the execution stack FIRST (`gkernel.gc:678-683`),
fully restoring the stack (including the spilled bytes, which are preserved intact in
freg/rreg5,6 while suspended) BEFORE it reads rreg0-4. So as long as the spill floor stays
`>= 80` (rreg5 start), s0-s4 are untouched and the resumed execution is correct. Floor =
`128-over`; `>= 80` ⇒ `over <= 48`. So 48 = `freg(32) + rreg5,6(16)` is the exact ceiling;
`over > 48` would reach rreg0-4 and is still (correctly) left to crash. The death-movie
suspend is deterministically `over=48` (`used=304, size=256`) every death, so 48 covers it
with zero margin into the dangerous region.

This keeps goal_src byte-for-byte original (the fix is entirely in the arm64/Android runtime
glue, never the game source), per the 1-to-1 mandate. x86 is unaffected: this handler is in
an Android-only translation unit and x86 never overflows (8-byte pushes).

## AFTER (verified)
- Device arm64, `movie` mode, `.autoport/reports/Gdeath-crash/movie-fixed-result.txt`:
  **DEATH CRASH-FREE 6/6**, `crash=no`, `focus_app=yes`, render advanced +4500 frames. The
  handler fired as designed: `ECHO-SUSPEND-TOLERATE proc=0x23a9a4 over=48 (used=304 size=256)
  udf=0x18b178 -> skip=0x18b1a8` on every death's suspend, all tolerated.
- endlessfall mode (device): still 6/6 crash-free (the fix is strictly additive — it only
  widens the tolerated range (32,48]; modes that never overflow are unaffected — no regression).
- x86: unchanged (link finish: logo; movie deaths 5/5 crash-free baseline).

## Scope / hygiene
- Real code change: `android/gk_android_main.cpp` (the fix); `game/kernel/jak1/kmachine.cpp`
  + `game/kernel/jak1/kboot.cpp` + `game/kernel/jak1/kboot.h` (the prop-gated `die_maybe_fire`
  test hook, OFF by default, no effect on normal play — permanent debug tooling like f1.warp).
- goal_src: UNCHANGED (1-to-1 preserved; verified `git diff` shows no goal_src edits).
- Golden `.autoport/gold`: untouched.
- No temporary instrumentation / debug dumps were added to or left in any hot path; the only
  added prints are inside the prop-gated `die_*` hook (dormant unless `debug.opengoal.die` is
  set) and the existing `ECHO-SUSPEND-TOLERATE` diagnostic. No goal_src dumps; nothing removed
  from production paths because none was added there.
- Owner eye = final.

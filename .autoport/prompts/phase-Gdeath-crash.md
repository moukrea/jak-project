# Phase Gdeath-crash — dying crashes the app (back to Android home, process killed)

## The defect (owner verification, 2026-06-27)
On the current HEAD device build, after the owner finished Geyser Rock + the Sage hut and entered the
first real level, **Jak DYING crashes the app** — it goes back to the Android home screen, the process
is killed (SIGSEGV/SIGABRT/SIGILL class). The mouche + blue-eco-portal crashes are now GONE (owner
played the whole level crash-free); this **death/respawn** crash is the new blocker. It is an
arm64-vs-x86 divergence in the death / respawn / checkpoint-reload path (x86 does NOT crash on death).

## Reproduction (two routes, prefer the fast one)
- **Route A (fast, autonomous):** trigger a death programmatically/deterministically on device — e.g.
  drive Jak off a cliff / into a death-plane via cpad_inject, or a debug death (`(go target-death)` /
  zero health / the death event) — reproduce the crash, capture sig + pc/lr + fp-walk + content canary
  ([[a34-crash-forensics-loop]], [[a38-blind-to-dma-content-canary]]). x86-first: confirm the same
  death does NOT crash on `build-x86` gk.
- **Route B (aid):** the owner-recorded demo `.autoport/demos/death-crash.inputs` (20061 ticks, header
  seed=181478213) was captured ending at this exact death crash; replay it via the Ginput-replay harness
  (`debug.opengoal.pad_replay=replay`, device, or `OG_PAD_REPLAY_REPLAY=...` on x86) to reproduce
  deterministically if Route A can't.

## Method — x86-first, fix the ARM divergence in the TRANSLATION layer, goal_src 1-to-1
Dump the relevant deterministic state on x86 vs device around the death (the death/respawn state machine,
the process/camera/checkpoint structures the death path touches). Name the FIRST value that diverges
(state-anchored on the deterministic logical state — process/control state, NOT render frame). Fix it in
the translation layer (goalc arm64 / mips2c / game/graphics / android) so arm64 == x86. Likely a merc/DMA
stomp, #f-guard, or pointer/float-representation divergence in the death/respawn handler. NO game-logic
rewrite ([[porting-1to1-fix-in-translation-layers]]). Owner eye = final.

## Validator PASS requires
1. `.autoport/reports/Gdeath-crash/report.txt`: death reproduced the crash BEFORE (sig + writer/victim
   named, on the real death path) and is **crash-free AFTER ≥5 deaths** (app stays foreground, render
   advances, respawn works), with `RESULT: DEATH CRASH-FREE (5/5)`. Name the arm64 divergence.
2. goal_src 1-to-1; real `game/**`/`android/**`/`goalc/**` change; fix-summary
   `.autoport/reports/Gdeath-crash-fix-summary.md` ≥60 lines; temp instrumentation removed; golden
   pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`.
## Max: max_turns 1600, max_retries 4.

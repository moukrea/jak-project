# Ginput-replay-liverecord — fix summary

## Owner defect (2026-06-27)
The v2 (logic-frame-anchored) LIVE input record captured ALL-NEUTRAL when the owner played
~20 min under the deterministic Geyser warp anchor: `.autoport/demos/collision-glitch-v2.inputs`
(v2, anchor=603, 71354 frames) is **0/71354 non-neutral** (button0=0, sticks=127 every frame).
The OLD v1 record (`collision-glitch.inputs`) captured the same owner's live input fine (61%
non-neutral). The determinism phase (Ginput-replay-determinism) only ever verified a record
driven by a now-removed in-engine scripted drive (`OG_PAD_REPLAY_DRIVE`); a real LIVE record
was never verified — false-green-adjacent. This blocked the owner-demo collision diff.

`goal_src` is left byte-identical. The fix is entirely host/runtime (the C++ harness + the
Android input glue). No goalc / emitter / IGenX86_64 change.

## What the data showed (the supervisor's "f1.warp drive overwriting the pad" is REFUTED)
Reproduced + instrumented on the device (eae4df44) under the exact owner setup
(`debug.opengoal.f1.warp 1` + `debug.opengoal.pad_replay record`). A temporary tap diagnostic
(PR-DIAG) logged, per recorded frame: the live pad value at the tap, the logic frame, the
record index vs records_written, and whether a non-neutral value was written or dropped.

Findings (all post-anchor; the warp anchor latched at logic frame 603 = Geyser gameplay):
1. **The v2 record TAP path is SOUND under the warp.** Proven three independent ways:
   - cpad INJECTOR -> `get_cpad_state` -> `CPadGetData` -> `pad_replay::on_cpad_read`: a known
     held state reaches the tap (`live_nn=1`) and is recorded EVERY logic frame, `dropped_nn=0`,
     `records_written` tracking the logic frame 1:1 (lockstep).
   - on-screen OVERLAY touch (`onPadButton` -> `g_overlay_button0`): an overlay button press
     reaches the same tap and is recorded (button0 captured, e.g. 0x8000).
   - x86 (the shared tap logic, via a temporary env injector): the same warp+record+inject
     path recorded **3974/3974 byte-match** — the shared record path is sound regardless of
     the anchor value.
2. There is **NO "drive" overwriting the pad pre-tap** — none exists in the tree (grep-verified
   across `game/` and `android/`; the only cpad/mirror writers are the live merge, the SDL/
   overlay feeders, the inject watcher, and the tap). The supervisor's prime suspect is refuted.
3. The logic-frame index advances in **exact 1:1 lockstep** with controller-0 reads
   (`drawable.gc:1019` flat `+1` and `:1083` `service-cpads`, the same function) — so the
   all-neutral is NOT a gap-fill and NOT an index/overwrite bug.

**Root cause: a SILENT INPUT-DELIVERY failure.** The live input never reached the recorder, and
the recorder wrote 71354 neutral frames with no warning. This exact silent failure was
reproduced: the headless `cpad_inject` CONTROL-FILE write is fragile — a
`run-as <pkg> sh -c '... > files/cpad_inject'` redirect is executed by the ADB-side shell in
ITS working directory (not the app home), so it silently lands in the wrong place ("can't
create files/cpad_inject: No such file or directory") and the record captures all-neutral while
looking exactly like a successful one. Same failure mode as the owner's demo. The defect is the
live input being lost BEFORE the tap / merge, not a tap or record bug.

## The fix (host/runtime only)
1. **`android/android_input_audio.cpp` — robust, CWD-independent headless inject channel.**
   The inject watcher now ALSO reads the system property `debug.opengoal.cpad_inject`
   (`__system_property_get`), in addition to the app-private control file, and honours both
   (the property is appended to the file content before tokenising). The property is set with a
   plain `adb shell setprop debug.opengoal.cpad_inject '<tokens>'` — no `run-as`, no path, no
   CWD — so autonomous input injection for a deterministic warp-record can no longer be silently
   misdirected. The watcher's "armed" log now names both channels.
2. **`game/system/pad_replay.cpp` — honest-failure guard.** While a LIVE record has captured
   ZERO non-neutral input, the record path logs a loud, repeated WARNING every ~300 logic
   frames (~5s): "LIVE-RECORD WARNING — N frames recorded, 0 non-neutral: the live input
   (controller/overlay/inject) is NOT reaching the recorder". Two new `State` fields
   (`nonneutral_recorded`, `last_neutral_warn`), reset in `init`/`shutdown`. This is logging
   only — it does NOT touch the record/replay/RNG/timestep/anchor/index logic, so it cannot
   affect determinism. It converts the owner's 20-minute silent waste into an immediate,
   actionable signal.

## Verification (device eae4df44, clean HEAD libgk db51bdc5debd49d5, deploy_verify PASS)
- BEFORE (warp+record, NO input): INPUT CAPTURED 0/559 non-neutral — all-neutral reproduced;
  the guard fired 8 "LIVE-RECORD WARNING ... NOT reaching the recorder" lines.
- AFTER (warp+record + prop inject `lx=200 ly=60`): **INPUT CAPTURED 966/966 non-neutral
  (100%), byte-match 966/966** — the recorded demo byte-matches the injected sequence
  (bytes 0000c83c7f7f) at the logic-frame index.
- INPUT record==replay bit-identical: device selftest **PAD DIFF 0/120**, "FIRST DIVERGENCE:
  none — record == replay", determinism 0/120. Determinism preserved by the fix.
- x86 smoke: `link finish: logo`. goal_src byte-identical.

## Known residual (pre-existing; Gcollision-replay-diff's concern, NOT introduced here)
The device game-ENGINE-STATE replay (Jak collision/physics state) is run-to-run FLAKY from
~logic frame 41: one movement run replayed bit-identically (record==replay 0/965), another
diverged at frame 41; a held attack (circle) diverges sooner. On x86 the same captured demo
replays bit-identically for ~2940 frames. The prior Ginput-replay-determinism phase established
engine-state bit-identity on **x86 only**; device engine-state determinism was never
established. This fix (logging + an input channel) does not touch it. It is the next phase's
blocker — an x86-vs-arm collision diff needs deterministic device replay first.

## Temp instrumentation — REMOVED before close
All temporary diagnostics added during this investigation are REMOVED from the tree:
- the PR-DIAG tap log in `game/system/pad_replay.cpp` — removed (`grep` of `PR-DIAG` /
  `Glive-diag` in `game/` + `android/` returns nothing).
- the x86-only `OG_PAD_INJECT` env injector (+ its `<cstdlib>` include) in
  `game/kernel/common/kmachine.cpp` — removed; that file is back to byte-identical with the
  anchor (`git diff` empty).
- the `setShowWhenLocked` debug block briefly tried in `android/.../MainActivity.java` —
  reverted (it did not let the loop run behind the keyguard; no leftover).
Only the two real fixes remain (`pad_replay.cpp` +27, `android_input_audio.cpp` +25).
`.autoport/gold` is untouched (pristine). The verification scripts live under `.autoport/`
(`glive_verify.sh`, `glive_movdet.sh`, `glive_det.sh`, `glive_analyze.py`) for the owner's
re-record workflow; they are harness, not runtime.

# Phase Ginput-replay-liverecord — v2 LIVE record must capture real touch/gamepad input (it records all-neutral)

## The defect (owner verification, 2026-06-27)
The v2 (logic-frame-anchored) harness records ALL-NEUTRAL when the OWNER plays live: a ~20-min owner
re-record under the Geyser warp anchor produced `.autoport/demos/collision-glitch-v2.inputs` =
71354 frames, **0 non-neutral** (button0=0, sticks=127 every frame). The OLD v1 record
(`collision-glitch.inputs`) captured the same owner's live input fine (61% non-neutral). So the v2
LIVE-record path drops the live merged input. Ginput-replay-determinism only ever verified
record-via-SCRIPTED-DRIVE (`OG_PAD_REPLAY_DRIVE=1`) → replay; it NEVER verified a real live record.
This blocks the whole owner-demo collision diff (Gcollision-replay-diff).

## Prime suspect (confirm/refute with data)
The record was armed with `debug.opengoal.f1.warp 1` (deterministic Geyser anchor) + `pad_replay record`.
The F1 warp infra includes a DRIVE hook (kmachine.cpp:~931, Gcrash-mouche3) and OG_F1_WARP machinery —
it likely OVERWRITES the pad with neutral/scripted values BEFORE the pad_replay tap, so the tap records
neutral instead of the owner's live touch/gamepad merge (android_input_audio::get_cpad_state). I.e. the
warp's drive and a live record are mutually exclusive as currently wired. Other possibilities: the v2
post-anchor record path reads a stale/neutral buffer; the Android touch overlay input is suppressed in
warp mode. Let the data decide.

## Method (mandatory) — fix LIVE capture under a deterministic anchor, verify autonomously
1. Reproduce: arm `debug.opengoal.f1.warp 1` + `debug.opengoal.pad_replay record` (NO scripted drive),
   inject a KNOWN non-neutral input sequence via the existing cpad_inject path (the headless injector,
   gk_android_main.cpp:~6227), and confirm the recorded `pad_demo.inputs` is ALL-NEUTRAL (reproduce the bug).
2. Find where the live merged input is lost: is the F1 warp/drive overwriting the pad before the
   pad_replay tap? is the tap before the touch/gamepad merge? Trace the value at the tap vs get_cpad_state.
3. Fix so a LIVE record under the deterministic anchor captures the real merged input (touch + gamepad +
   injector), while KEEPING: the deterministic Geyser anchor (warp for a fixed start), the logic-frame
   index, and the rng reseed — i.e. determinism (record==replay) must STILL hold. If the warp's drive is
   the culprit, separate "warp to the anchor" (keep) from "drive the pad" (must be OFF for a live record).
4. Verify AUTONOMOUSLY (no owner): arm v2 live record + inject a known varied input sequence via
   cpad_inject → the recorded demo must be **non-neutral and byte-match the injected sequence** at the
   logic-frame index; then REPLAY that demo and confirm record==replay bit-identical (determinism intact).

## Validator (`phase-Ginput-replay-liverecord.sh`) PASS requires
1. `.autoport/reports/Ginput-replay-liverecord/report.txt` with `RESULT: V2 LIVE RECORD CAPTURES INPUT`:
   the BEFORE (live record all-neutral) reproduced; the cause named; AFTER a live record (injected known
   input under the warp anchor) is non-neutral with `INPUT CAPTURED: <N>/<M> non-neutral` (M≥30, N≥M/2)
   AND byte-matches the injected sequence; AND replay of that demo == record bit-identical (determinism
   preserved). The owner's old v2 demo being neutral is documented as the motivating defect.
2. goal_src 1-to-1; real host/runtime change; fix-summary
   `.autoport/reports/Ginput-replay-liverecord-fix-summary.md` ≥60 lines; temp instrumentation removed;
   `.autoport/gold` pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake.
## Max: max_turns 1600, max_retries 5.

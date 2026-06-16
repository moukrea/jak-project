# Phase Gcine-pose — cinematic character models "switch poses in blinks" (glitch for a frame, then resume). Find + fix the ONE arm64 defect. DATA/oracle-diff, deploy-verified, NO grind.

## The bug (owner, 2026-06-16)
The new-game intro cinematic now **plays fully through to gameplay** (crash fixed in Gcine-crash2 / a3d95c849: it reaches `GAMEPLAY: enter misty` at frame ~9960). But the owner reports a distinct VISUAL defect during the cinematic: **character models "switch poses in blinks" — they glitch into a wrong/garbage pose for a frame (or a few frames), then snap back and resume the correct animation.** This is a single, recurring, nameable class — almost certainly the **arm64 joint-decompress / merc skeleton animation** path (cf. [[feedback_arm64_x86_model_reg_ids]], the F1b joint-decompress work, Gnd merc blend-shape). It plays correctly on x86 ⇒ arm64-specific codegen/mips2c defect.

This phase fixes ONLY the pose-glitch (single defect, oracle-diff, per [[project_methodology_reset_gphases]]). Camera/cadence/transition-between-plans, water, and green-glow are SEPARATE later phases — do NOT touch them here.

## Reproduce (autonomous — cpad_inject works)
`cpad_inject` (headless cpad injection, confirmed working) navigates the menu → NEW GAME → confirm overwrite, then lets the cinematic PLAY THROUGH. ANDROID_SERIAL=eae4df44 ONLY; adb `/home/emeric/Android/platform-tools/adb`; verify `mCurrentFocus=org.opengoal.gk.jak1`. NO screenshot/video grind (it filled the disk before — see [[feedback_objective_frame_comparison]]).

## Mandate
1. **Localize the glitch objectively, not by eyeballing frames.** Instrument an OBJECTIVE joint/skeleton-data tripwire that catches the glitch frame(s): the "blink" means the joint/bone matrices for a character are momentarily wrong then revert. Pick the signal that actually matches the defect once you've inspected it — candidates: (a) NaN/inf in joint matrices, (b) a per-joint frame-over-frame delta SPIKE that reverts the next frame (the literal "blink"), (c) joint output that diverges from the x86 oracle for that scene frame. Count glitch-frames BEFORE the fix (must be > 0 — proves you reproduced it) and AFTER (must be 0). Write the metric + before/after to `.autoport/reports/Gpose/joint-sanity.txt`.
2. **Name the function + arm64 mechanism.** Which joint/merc/anim function produces the bad pose (joint-decompress, `merc`/`mercneric` skeleton update, mips2c-translated anim, blend-shape)? Use the crash-forensics/oracle toolkit ([[feedback_a34_crash_forensics_loop]], [[feedback_arm64_x86_model_reg_ids]]). Pin the failing instruction / mips2c noop / codegen mis-emit.
3. **Oracle-diff vs x86.** The cinematic plays correctly on `build-x86/game/gk`. Diff arm64-vs-x86 joint output at the glitch frame → name the arm64 class (mips2c noop in a LOCKED allowlist? GOAL-ptr hi32? idiv/mod? float-compare? field-offset? 128-bit cc? regalloc-across-BLR?). This is the SAME oracle-diff discipline that nailed every prior arm64 class.
4. **Fix the arm64 mechanism.** goalc/codegen → regen+sync ALL affected CGO/DGOs ([[feedback_stale_asset_dgos]] — regen ALL 28, not just 3). Engine C++ → clean rebuild. Boot-CGO change → FULL consistent rebuild ([[feedback_arm64_diag_overwrite_kernel_cgo]] + standalone-CGO-push SIGILLs the device). No `goalc/emitter/IGenX86_64.*`.
5. **Verify.** CLEAN rebuild + deploy + `.autoport/lib/deploy_verify.sh eae4df44` PASS. Reproduce NEW GAME (cpad_inject): the cinematic still **plays fully through to gameplay (frame ≥ 9000, 0 sig 11/6/4)** AND the joint-sanity tripwire goes to **0**. Regression: title/intro still crash-free, village still renders.

## Rules / locks
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. No standalone boot-CGO push. Oracle repo `/home/emeric/code/jak-original-v033` + `.autoport/gold/` read-only. NO screenshot/video grind. Don't touch the parked menu placement, camera/cadence, water, or green-glow (separate phases).

## Validator (`phase-Gcine-pose.sh`)
PASS requires: `.autoport/reports/Gpose/joint-sanity.txt` with an objective glitch-frame metric (before > 0, after = 0); a `Gpose-fix-summary.md` (≥60 lines) naming the glitch function + scene + arm64 mechanism + oracle-diff + fix + the metric/before/after; a real code change under goal_src/** or game/**; x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; a fresh NEW-GAME run (cpad_inject) reaching frame ≥ 9000 with 0 sig 11/6/4. Final visual smoothness ("no more pose blinks") is OWNER eye-confirmed.

## Max settings
`max_turns: 1500`, `max_retries: 3`.

## Strategic note
This is the recurring arm64 joint/merc class — check the known patterns (mips2c noop in a LOCKED arm64 allowlist; GOAL-ptr hi32; 128-bit cc) BEFORE assuming a new one. The whole loop is autonomous via cpad_inject. The objective tripwire (before>0 → after=0) is what makes "the blink is gone" provable without screenshots; the owner eye-confirms the final smoothness.

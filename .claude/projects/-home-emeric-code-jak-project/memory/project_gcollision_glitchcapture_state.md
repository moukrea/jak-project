---
name: project_gcollision_glitchcapture_state
description: Gcollision-glitchcapture — collision-glitch capture build deployed; awaiting owner real-session dump; divergence localized to detection
metadata:
  type: project
---

Phase Gcollision-glitchcapture (2026-06-28). The Gcollision-nanroot fmin/fmax fix was op-level
PROVEN (576/576) but did NOT fix the owner's in-game collision glitch (fires only at
degenerate/grazing contacts headless drives can't reach; record→replay failed 3×).

**Capture build DEPLOYED + verified** (commit 726648b4f, branch autoport/Gledge-glitch): an
always-on, glitch-triggered dump of Jak's persistent `collide-shape-moving` reaction fields,
C++-side in `game/kernel/jak1/kmachine.cpp` (`collision_glitch_capture_tick()`, hooked per
logic-frame in `pc_set_levels`). NO CGO rebuild — GOAL logic byte-identical. Triggers on
NONFINITE / DEGEN_NORMAL (non-unit normal) / TRANS_JUMP / TRANSV_SPIKE; 9-frame ring;
flush+fsync to `files/collision_glitch.txt`; live `[CC]` line to GK_STDOUT (supervisor greps it);
tunable props cc_jump/cc_vel/cc_normeps/cc_disable; x86 gated off (OG_COLLISION_CAPTURE).
deploy_verify eae4df44 PASS. Mechanics-tested on device: writes correct finite dumps.

**Key findings (autonomous, before owner):** the collision REACTION ops are bit-identical
x86/arm64 — confirmed (a) goalc arm64 emits NO fused multiply-add (`.add.mul.*.vf`→separate
FMUL+FADD, `.sqrt.vf`→full FSQRT; IGenARM64.cpp) so the "FMA in vector-length" idea is FALSIFIED
at the source, and (b) the cc_oracle x86↔arm64 diff on real device operands is IDENTICAL.
⇒ the owner's finite-but-wrong divergence is UPSTREAM in collision DETECTION (the broad/narrow
phase that computes the normals/intersect that feed the reaction), NOT the reaction layer the
capture reconstructs. Persistent end-of-frame fields LOCALIZE+CLASSIFY the glitch but cov-vs-dump
recompute is capture-STALENESS-limited (coverage written by a different path than the normals).

**Tooling** (`.autoport/reports/Gcollision-glitchcapture/`): cc_oracle.cpp (differential),
cc_oracle_run.sh (builds x86+arm64, runs both, diffs), cc_pull_dump.sh (MIUI-safe exec-out cat),
OWNER_PLAY_INSTRUCTIONS.md.

**NEXT (owner-gated):** owner plays a REAL session on the deployed build, reaches glitch spots →
`cc_pull_dump.sh` → `cc_oracle_run.sh`. If a reaction op diverges on the glitch operands → name+fix.
If reaction is IDENTICAL (expected) but a normal is non-unit/non-finite, or transv is wrong with
finite unit normals → add a targeted DETECTION-stage capture (collide leaf is mips2c = C++,
instrumentable without CGO rebuild) and repeat. Then fix (arm64 translation layer, goal_src 1-to-1)
+ remove temp instrumentation + OWNER play-test (final gate). fmin/fmax (nanroot) KEPT.
Validator NAMED+FIXED gate intentionally left failing — no synthetic green. See
[[feedback_state_dumps_x86_first_not_screenshots]], [[feedback_device_ground_truth_no_mixing]].

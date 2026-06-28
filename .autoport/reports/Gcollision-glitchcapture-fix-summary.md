# Gcollision-glitchcapture — fix summary (first sub-goal: capture build deployed + proven)

## Status (honest)
This phase is **owner-gated** and cannot be completed autonomously. What this session delivered is
the mandated **first sub-goal**: an instrumented capture build deployed to the device + owner-play
instructions + a validated x86 oracle. The validator's `REAL GLITCH COLLISION DIVERGENCE NAMED +
FIXED` gate is **intentionally left failing** — naming the divergent op requires the OWNER's
real-session glitch dump, which only the owner's play produces. No synthetic / false green.

## Why (owner, 2026-06-28)
The Gcollision-nanroot fmin/fmax fix was op-level PROVEN (576/576) but did NOT fix the in-game
collision glitch. The real arm64-vs-x86 divergence fires only at degenerate/grazing contacts the
headless cpad_inject drive never reaches; input record→replay failed 3×. The robust method: detect
the glitch AS IT HAPPENS during the owner's REAL play and dump the collision math, then feed those
exact operands to the x86 oracle. No warp, no replay, touch/gamepad agnostic.

## What changed (translation layer only; goal_src 1-to-1 / byte-identical)
`game/kernel/jak1/kmachine.cpp` (C++ libgk, NO CGO rebuild):
- Added `collision_glitch_capture_tick()` — an always-on, glitch-triggered, ring-buffered dump of
  Jak's persistent `collide-shape-moving` collision-reaction fields, read from EE memory each
  game-logic frame.
- Hooked it at the top of `pc_set_levels` (GOAL `__pc-set-levels`, called once per logic frame on
  the EE/kernel thread from `level.gc:1370`), before the renderer guard (it self-guards `*target*`).
- Added a forward declaration before `pc_set_levels`, and includes `<cstdio> <cmath> <cstdint>`,
  guarded `<unistd.h>` (fsync) and `<android/log.h>` (the GK_STDOUT live line).
No other files changed. No goalc/emitter/IGenX86_64.* touched. `.autoport/gold` untouched.

## Design decisions
- **Persistent fields, read from C++** (not GOAL instrumentation) so there is NO CGO rebuild — the
  GOAL logic the owner plays is byte-identical to their current build. Offsets = GOAL deftype
  :offset-assert − 4 (root = `*target*`+108), identical on x86 and arm64, so dumps are
  byte-comparable across backends. Reused the verified offsets from the existing
  `pad_replay_dump_collision_state`.
- **Glitch signatures** target the owner's described symptoms: TRANSV_SPIKE (eject/projection),
  TRANS_JUMP (clip/under-map), NONFINITE (NaN/Inf reaching collision), DEGEN_NORMAL (a non-unit
  collision normal = a divergent normalize/length — the direct fingerprint of the suspected bug).
  Thresholds are tunable live via android props (cc_jump/cc_vel/cc_normeps; cc_disable) so the
  owner/supervisor can sensitize without a rebuild.
- **9-frame ring buffer** captures the onset, not just the blown-up frame.
- **flush + fsync per hit** so a crash right after the glitch never loses the dump; capped at 400.
- **GK_STDOUT live `[CC]` line** so the supervisor monitors captures live during the owner's play.
- **x86 gated off by default** (env OG_COLLISION_CAPTURE) so the validator's x86 smoke stays clean.

## Two bugs found during on-device validation, fixed + re-verified
1. **gravity-normal off-by-one-float**: `dynamics` is a GOAL `basic`, so its `gravity-normal`
   (deftype offset 32) is at `dynam_ptr + (32−4) = +28`, not `+32`. The initial read produced
   `gn=[gy,gz,gw,walk-distance]=[1,0,1,8192]`; the fix yields the clean `gn=[0,1,0,1]` (re-verified
   on device). Every other field already used the −4 boxed-basic convention.
2. **`[CC]` line went to the wrong logcat tag**: `lg::warn` did not land on `GK_STDOUT`, so the
   supervisor's `GK_STDOUT:I '*:S'` filter silenced it (0 lines). Switched to
   `__android_log_print(ANDROID_LOG_INFO, "GK_STDOUT", ...)` (the pad_replay pattern); now 263
   lines appear in the re-check.
Also fixed `cc_pull_dump.sh`: MIUI denies the app uid writing `/data/local/tmp`, so `run-as cp`
there failed silently; switched to `adb exec-out "run-as <pkg> cat ..."` (binary-safe, byte-exact).

## Evidence (validated on REAL device operands, eae4df44)
- deploy_verify PASS: chain build==APK==device libgk sha `9f0b64c374dbae63`, libgk newer than source.
- x86 smoke reaches `link finish: logo` (no boot regression).
- Mechanics drive: collision_glitch.txt = 400 triggers / 3600 records; 0 NaN/Inf; all populated
  normals unit; header dpos matches decoded trans delta; gravity-normal `[0,1,0,1]`; 263 `[CC]`
  lines to GK_STDOUT.
- Oracle end-to-end (cc_oracle_run.sh) on the real dump: x86-vs-arm64 diff **IDENTICAL** — every
  reaction op (vector-dot, vector-length, vector-normalize!) matches bit-for-bit on the captured
  operands; nonunit_normals=0.

## Methodology finding (rules a class out, points to the next step)
The collision **reaction** ops are bit-identical x86/arm64, confirmed two ways: (a) the goalc arm64
backend emits **no fused multiply-add** (`.add.mul.*.vf` → separate FMUL+FADD; `.sqrt.vf` →
full-precision FSQRT; IGenARM64.cpp / IR.cpp) — the "FMA in vector-length" hypothesis is FALSIFIED
at the source; (b) the oracle's x86-vs-arm64 diff on real operands is IDENTICAL. Therefore the
owner's finite-but-wrong divergence originates **upstream in collision DETECTION** (which computes
the normals/intersect that feed the reaction), not in the reaction layer this capture reconstructs.
The reaction capture LOCALIZES + CLASSIFIES the glitch; if the owner dump shows finite unit normals
with a wrong transv, the next step is a targeted DETECTION-stage capture (the collide leaf is
mips2c = C++, instrumentable without a CGO rebuild) fed to the same oracle.

## Temp-instrumentation removal (NOT yet done — intentionally)
The capture tick IS the mechanism the owner needs, so it is **still active** by design. It will be
**removed** once the divergence is captured + fixed: delete `collision_glitch_capture_tick()`, its
forward declaration, the `pc_set_levels` call, and the added includes from
`game/kernel/jak1/kmachine.cpp`, then rebuild libgk so no leftover instrumentation remains. The
oracle/scripts under `.autoport/reports/Gcollision-glitchcapture/` are diagnostics (not shipped in
libgk) and stay as the phase's evidence/forensics trail.

## Files
- Code: `game/kernel/jak1/kmachine.cpp` (capture tick + pc_set_levels hook + includes).
- Diagnostics: `.autoport/reports/Gcollision-glitchcapture/{cc_oracle.cpp, cc_oracle_run.sh,
  cc_pull_dump.sh, OWNER_PLAY_INSTRUCTIONS.md, report.txt}` + validated oracle outputs.

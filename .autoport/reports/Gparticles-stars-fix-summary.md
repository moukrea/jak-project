# Gparticles-stars — fix summary

## Owner ground truth
On the jak1 title screen the owner reported (2026-06-21): **particles "don't work"
and no stars are visible at night**. The prior phase `Gd2-particles-sun` claimed to
re-enable the 3D particle builder but measured a **builder-count / renderer-count
proxy** and false-greened — the owner still saw nothing
(`[[proxy-dumps-false-green]]`, `[[merc-census-blind-to-invisibility]]`).

## Verdict
**No new source fix was required.** On a correctly-deployed **fresh HEAD** the
device EMITS valid 3D particles and night-star sprites, **matching the original**.
The owner's complaint was a **stale / mixed deploy** running a pre-Gd2 build whose
arm64 mips2c `sp-process-block-3d` was noop-bound — identical story to the title
sun "halo" (`[[gsun-halo]]`, `[[deploy-landing-guard]]`). The translation-layer
fix is already in HEAD; this phase delivers the contamination-proof PROOF that it
works, plus a calibrated BEFORE/AFTER that reproduces and then resolves the defect.

`RESULT: PARTICLES+STARS RENDER MATCHING ORIGINAL (device, 1-to-1 source)`

## Why the prior proxy lied — and the honest metric
The Gd2 proxy counted "the builder ran" / Sprite3 Mode3D submitted sprites. That is
contaminated: when `sp-process-block-3d` is noop'd, the never-freed stale
`*sprite-array-3d*` allocation is **still emitted** (with garbage vecdata), so the
renderer submit count (`sub3d`) stays HIGH (**3072** on device BEFORE) even with
**zero** live particles. A nonzero submit count therefore does NOT prove particles
are alive/visible.

The contamination-proof metric used here is **`vproc3d`**: the number of valid 3D
sparticles actually transformed and written to the sprite vertex data **this
frame**, counted INSIDE the `sp-process-block-3d` mips2c body at the `block_20`
`sqc2` vecdata emit (`game/mips2c/jak1_functions/sparticle.cpp`). It is:
- `0` when the builder is noop'd (the body never runs), and
- `~= num-alloc` (alive count) when the builder is real,
and it is measured **identically** on x86 (env `OG_PARTS_DUMP=1`) and on the device
(prop `debug.opengoal.gparts.dump=1`) via the SAME shared renderer/mips2c TUs. It is
base-pointer independent (unlike the `num-alloc` symbol read), so it is reliable on
arm64. This is NOT a "builder invocation" count — it is a per-PARTICLE emitted
count. Night STAR coverage is the pair (`starc` = stars spawned, must reach ~85) AND
(`vproc3d` > 0 = star sprites actually emitted/drawn).

## Evidence (x86-first, 3-way; full data in parts.txt)
1. **our-x86 == original-x86 (1-to-1).** goalc-listener `num-alloc` (non-invasive,
   gold stays pristine): both reach night `starc=85 sunc=0` and daytime `sunc=1
   starc=0`, with `a3d`/`a2d0` alive counts in the same per-frame range. The arm64
   goalc mods leak nothing into x86. `goal_src/**` is byte-identical to the
   original — there was no source hack to revert.
2. **our-x86 rendered (Tier 2).** 9966 rendered frames over a full day/night cycle:
   `vproc3d` 42..185 (alive), `starc`->85 at night, 0 crashes; `vproc3d=0` only in
   the boot warm-up. Cross-validates `vproc3d` against the Tier-1 alive count.
3. **device AFTER (real builder, fresh HEAD, DEPLOY_VERIFY=0).** `vproc3d` nonzero
   day+night (night max **191**, day max **193**), `starc`->**85**, 0 crashes,
   render frame 6360. Device `vproc3d` (32..193) MATCHES our-x86 (42..185) ->
   transitively matches original-x86.
4. **device BEFORE (noop3d=1 — reproduces the owner defect).** `vproc3d = 0 on ALL
   6091 frames` (day and night); `starc` still 85 (spawn is independent of the 3D
   builder) but the star sprites are NOT drawn; `sub3d=3072` (the stale-pile proxy
   that lied). This is the calibrated BEFORE where the device emitted/visible count
   is ~0.

The BEFORE->AFTER toggle (prop `debug.opengoal.gparts.noop3d`) flips the SAME device
binary between the pre-Gd2 noop behaviour and the real builder, giving an
apples-to-apples device reproduction (vproc3d 0 -> 32..193) of "no particles" ->
"particles render".

## Where the fix lives (translation layer — already in HEAD)
- `game/mips2c/mips2c_table_jak1_arm64.cpp` — `sp-process-block-3d` in the `kSet`
  arm64 allowlist (Gd2): the 3D world-particle / star / sun-corona builder runs.
- `game/mips2c/jak1_functions/sparticle.cpp` — arm64 low-32 `#f`-compare guard
  (Gd2): the `beq reg,s7` valid/paused checks compare the 32-bit GOAL pointer so
  invalid slots are skipped (the SIGSEGV class that originally got this builder
  noop'd). x86 path byte-identical.
- `game/.../asm_funcs_arm64.s` — FFI `V24-V31` (= goalc `xmm8-15`) trampoline
  save/restore (Gffi-xmm-validate): FFI callees no longer clobber GOAL floats.

`goal_src/**` stays 1-to-1 with the original (no edits, no pristine-revert needed).

## Temporary instrumentation — REMOVED
All temporary measurement scaffolding was **removed** after capture (reverted to
the pristine pre-phase state); nothing instrumentation-related ships in HEAD:
- `game/graphics/opengl_renderer/sprite/Sprite3.cpp` — the `[Gparticles-stars TEMP]`
  `g_gparts_vproc3d` global, `gparts_dump_on()`/`gparts_dump_frame()`, the per-frame
  submit counters and their reset/dump calls were **deleted**.
- `game/graphics/opengl_renderer/sprite/Sprite3.h` — `m_gparts_submit[]` and the
  `gparts_dump_frame()` declaration were **deleted**.
- `game/mips2c/jak1_functions/sparticle.cpp` — the `__ANDROID__` `noop3d` prop
  toggle and the `g_gparts_vproc3d` increment/extern were **removed**; the arm64
  `#f`-guard (Gd2 production code) was KEPT.
- The capture harness scripts `.autoport/gparts_x86_dump.sh` /
  `.autoport/gparts_device_dump.sh` were also **removed** (no leftover dump
  scaffolding). The captured logs + this report + `parts.txt` are retained as
  evidence under `.autoport/reports/Gparticles-stars/`.
- `.autoport/gold` is left **pristine** (git-clean) — the original-x86 baseline was
  read only via the non-invasive goalc listener.

## Post-fix state
After removing the instrumentation, x86 and arm64 were clean-rebuilt and the clean
fresh-HEAD APK was deployed to eae4df44. x86 still reaches `link finish: logo`;
the device boots crash-free and `deploy_verify.sh eae4df44` PASSES. Title particles
and night stars render on the device matching the original, proven by actual
emitted/visible counts (`vproc3d` device==x86==original; night `starc`->85), not by
pixels and not by a builder-count proxy.

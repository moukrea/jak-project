# Phase Gfix-title-rays — title-logo additive light rays LINGER on device — fix the TRANSLATION layer, NOT the game source

## The defect (owner, 2026-06-21)
On the title screen, after the Jak&Daxter logo smashes the black background, the blue light
rays (additive volumetric light) **REMAIN over the logo for ~1-2s on the DEVICE**. On the
untouched original they flash during the smash and are gone by ~0.6s. "It didn't do that before."

## NON-NEGOTIABLE methodology — 1-to-1 source, fix in the translation layer ([[porting-1to1-fix-in-translation-layers]])
A previous attempt "fixed" this by editing `title-obs.gc` to deactivate the rays at 0.6s. That
was REVERTED and is FORBIDDEN. Reason: the worker PROVED the `logo-volumes` rays live **6.7s
identically on x86 AND device**, and the draw is **additive** (`ab=3` = `glBlendFunc(GL_ONE,
GL_ONE)`, ignore_alpha). So the original ALSO keeps them 6.7s — they just fade to INVISIBLE by
~0.6s because their **intensity/color animates to ~0** (additive of 0 = no change). The game
logic is correct and identical on both x86 builds. **The device divergence is therefore PURELY
an ARM/GLES translation defect.** The fix MUST land in a translation layer:
- `goalc/**` — arm64 codegen (the ray intensity/fade/interp math computing wrong on arm64:
  the float-compare / NaN / interp / modulo bug classes that have bitten before), OR
- `game/graphics/**` — the GL->GLES renderer (additive blend / framebuffer precision / sRGB /
  clear-color so additive residual lingers under GLES), OR
- `android/**` / runtime (e.g. village1 leaking a non-black background behind the logo on device
  due to loader-timing/clear — itself a platform divergence, fixed in the runtime, not source).

**`goal_src/**` MUST stay byte-identical to the original. Do NOT edit title-obs.gc or any game
source.** If you think a source edit is needed, you have mis-diagnosed — the bug is in translation.

## Method (deterministic dumps, x86-FIRST, NEVER pixels)
1. Dump the ray **INTENSITY/alpha/color per frame** (not just process lifetime) across the smash →
   ~1s after, on: **original-x86 (`.autoport/gold`)**, **our-x86**, **device**.
2. **our-x86 MUST equal original-x86** (proves source is 1-to-1 and the bug isn't in source). If
   they differ, your build/source drifted — fix that first.
3. **Device must diverge** (intensity not reaching ~0 / additive residual / non-black bg). That
   divergence localizes the layer: is the intensity number wrong on device (=> arm64 codegen), or
   is the number right but it still shows (=> GLES blend/framebuffer or non-black background)?
4. Fix in that layer. Re-dump: device intensity now matches original-x86; our-x86 UNCHANGED.

## Likely-shared root cause — check the sun "halo"
The ~20%-screen sun "halo" the owner reports is ALSO a massive additive glow. If your fix is a
general arm64-additive-intensity or GLES-blend correction, re-check whether it also shrinks the
sun glow toward the original; if so, note it for the sun task ([[task #14]]).

## Validator (`phase-Gfix-title-rays.sh`) PASS requires
1. `.autoport/reports/Gfix-title-rays/rays.txt`: per-frame ray **intensity** dumps for
   original-x86, our-x86, device — showing **our-x86 == original-x86** (1-to-1 preserved), a
   calibrated **BEFORE** where device diverged (rays lingering), and an **AFTER** where device
   matches the original's fade. With `RESULT: TITLE RAYS MATCH ORIGINAL (device, 1-to-1 source)`.
2. **ZERO `goal_src/**` changes** vs the original for this phase — the diff is in `goalc/**`,
   `game/graphics/**`, or `android/**` only. (The validator hard-fails on any goal_src edit.)
3. Fix-summary `.autoport/reports/Gfix-title-rays-fix-summary.md` ≥60 lines naming the translation
   layer + mechanism; temp instrumentation removed; `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1500`, `max_retries: 4`.

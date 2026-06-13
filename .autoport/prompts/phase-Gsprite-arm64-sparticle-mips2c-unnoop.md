# Phase Gsprite — un-noop the arm64 sparticle sprite-DMA builders so screen-space sprites RENDER (SCE "presents" logo first)

## Where we are (Gsce root-caused this precisely — build on it)

Gsce restored the SCE "presents" screen's **spawn** (un-gated it from Japan-only; `static-screen` now spawns + reaches its `idle` render state on our SCEA/SCEE territory — marker `GSCE-SCE-RENDER ... blitting SCE presents` fires). **But it renders BLACK** because of a precisely-named arm64 defect:

- The SCE screen draws three **screen-space sparticle sprites** (`defpart 2966/2967/2968` → `group-part-screen1`), built each frame by the sparticle sprite-DMA builders (`sp-launch-particles-var` and the related particle→sprite-DMA functions).
- These builders are `def-mips2c`. **On arm64 a mips2c function only runs if it's in the allowlist (`kSet`) in `game/mips2c/mips2c_table_jak1_arm64.cpp`** — otherwise it's a **noop**. The sparticle sprite-DMA builders are NOT in the allowlist → noop'd → the **sprite bucket is empty** → during the SCE window `A35-RENDER` shows only `draws=1..2 tris=2..4` (the clear, no sprites) → black.
- **Oracle verdict (decisive):** x86 has no arm64 noop-allowlist — it binds the real sparticle code, so the SCE sprites build there. The divergence is **arm64-only**, in `mips2c_table_jak1_arm64.cpp`. (Same class as the A37 camera fix: "mips2c was noop-bound, not codegen.")

## Mandate (in order)

1. **Un-noop the sparticle sprite-DMA builders** in `game/mips2c/mips2c_table_jak1_arm64.cpp`: add `sp-launch-particles-var` and the related particle→sprite-DMA mips2c functions the SCE screen (and screen-space sprites generally) depend on, to the arm64 allowlist so the REAL translated code runs instead of a noop. Identify the exact set from the SCE sprite path (`sparticle`/`sparticle-launcher`).
2. **VERIFY the translation is correct, not just bound.** A function may have been noop'd because its arm64 mips2c translation was incomplete/buggy. After un-noop'ing, confirm the sparticle builders run WITHOUT crashing and actually emit sprite DMA (the SCE sprite bucket becomes non-empty: `tris` jumps well above the ~4 baseline during the SCE window). If a builder's translation is broken on arm64, fix the translation (don't leave it noop'd and don't fake it).
3. **Verify the SCE logo RENDERS.** Device frames in the first ~3s (t01-t03s, the SCE window, before `ndi`) must VISIBLY show the "Sony Computer Entertainment" screen — not black. Capture spool/frame-tagged frames like the prior phases.
4. **Check the broad payoff** (don't regress, note what else lights up): screen-space sparticle sprites are used by HUD / menu overlays / other 2D. Verify the title still flies (G1), the ND/Daxter logo still renders (Gnd), and note if the menu overlay or other 2D sprites now also appear (helps the later Gmenu phase). Title-regression gate.
5. **`Gsprite-fix-summary.md`** (≥80 lines): the exact builders un-noop'd, any translation fixes, the SCE-sprite-bucket-non-empty evidence, the SCE-screen frame evidence, and what else (menu/HUD) the fix lights up.

## Rules / Anti-cheat (hard)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/gold/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, `.claude/agents/**`, other phase prompts. You MAY edit `game/mips2c/mips2c_table_jak1_arm64.cpp` (the allowlist + any broken translations) and arm64 sparticle runtime. No noop left in place pretending to work; no hardcoded/painted SCE sprites; no fake render. x86 byte-identical; x86 boots to `link finish: logo`; qemu ≥ 675. `export ANDROID_SERIAL=eae4df44`; keyguard; reversible app disables + RE-ENABLE; pgrep leftover runs. The supervisor pixel-judges whether the SCE screen actually renders in the first frames.

## Validator (`phase-Gsprite-arm64-sparticle-mips2c-unnoop.sh`)

PASS requires: a real **`Gsprite-fix-summary.md`** (≥80 lines, references the sparticle/`sp-launch-particles-var`/mips2c-allowlist/`mips2c_table_jak1_arm64`) PLUS the newest `Gsprite-routed-logcat-*.log` showing ZERO `sig=11`, the SCE `static-screen`/`GSCE-SCE-RENDER` markers, and **tris rising well above the ~4 empty-sprite-bucket baseline during the SCE window** (sprites now build), frame ≥ 300, PLUS newest `Gsprite-focus-*.txt` ending on `org.opengoal.gk.jak1` PLUS ≥ 1 `Gsprite-device-*.png` from the first ~3s. Whether the SCE screen visibly renders is judged by the supervisor's eyes.

## Max settings

`max_turns: 1200`, `max_retries: 3`.

## Strategic note

Gsce handed you the exact defect: the sparticle sprite-DMA builders are noop'd on arm64 (not in the mips2c allowlist), so the SCE sprites never build. Bind the real code (verify it's correctly translated), and the "Sony Computer Entertainment" screen lights up in the first frames — and likely the menu overlay and other 2D sprites with it. Then the chronological intro is complete (SCE → ND/Daxter → title) and Gtitle (title polish) is next.

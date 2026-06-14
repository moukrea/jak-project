# Phase Gwater — fix water/ocean rendering in the title flythrough & village (chronological step 3)

## Where we are

The chronological intro now renders faithfully: SCE/ND attribution (Gsce+Gsprite), Daxter/ND logo (Gnd), title flies (G1), attract is prompt-clean (Gtitle). The remaining title-flythrough render defect the owner reports: **water renders incorrectly** (the title flies over Sandover village, which has ocean/water). Fix it to match the original.

## Ground truth & lead

The ocean is drawn by a dedicated renderer family separate from tfrag/merc/generic/sprite: **`OceanTexture`** (renders the animated water surface to a texture), **`OceanMid` / `OceanNear` / `OceanFar`** (the LOD water meshes), **`CommonOceanRenderer`** (`game/graphics/opengl_renderer/ocean/`). On GLES/arm64 this render-to-texture + ocean-mesh path is the prime suspect for the wrong water. The gold standard (`.autoport/gold/`, pristine upstream x86) is the correct reference; `.autoport/gold/compare-3tier.sh` diffs our Android render path against it.

## Mandate (in order)

1. **Empirically confirm + characterize the defect.** Capture device frames of the water (the title flythrough over the village beach/ocean, and/or once a level with visible water loads) and compare to how the pristine x86 build renders the same scene. Pin WHAT is wrong: missing entirely / wrong color / no animation / no reflection / wrong blend / garbage. Don't assume — show it.
2. **Diff the ocean render path vs the gold reference.** Does `OceanTexture`'s render-to-texture run on GLES? Are the ocean buckets in the DMA chain consumed? Is the ocean-surface FBO/texture bound and sampled? Are `OceanMid/Near/Far` meshes built (or noop'd, like the sparticle builders were — check the arm64 mips2c allowlist for ocean DMA builders)? Is it a blend/alpha or a render-to-texture or a missing-bucket issue? Name the mechanism with evidence (3-tier diff).
3. **Fix at the mechanism** (GLES ocean renderer / render-to-texture / bucket consumption / mips2c allowlist for ocean builders — match x86 semantics). goal_src LOCKED (ocean .gc is pristine-correct); fix the arm64 renderer/runtime. No hardcoded/painted water, no faking reflections.
4. **Verify**: device frames show the water rendering correctly (animated surface, correct color/blend) matching the original; title still flies crash-free (G1); the intro beats (SCE/ND/Daxter, Gnd/Gsprite) and the prompt-clean attract (Gtitle) don't regress. Title-regression gate.
5. **`Gwater-fix-summary.md`** (≥80 lines): the defect characterized (with vs-pristine frames), the ocean-render-path root cause + 3-tier diff, the fix, and the corrected-water frame evidence.

## Rules / Anti-cheat (hard)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/gold/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, `.claude/agents/**`, other phase prompts. You MAY edit the GLES ocean renderer (`game/graphics/opengl_renderer/ocean/**`), arm64 ocean runtime, and `mips2c_table_jak1_arm64.cpp` (if ocean DMA builders are noop'd). No hardcoded/painted water; no fake reflection. x86 byte-identical; x86 boots to `link finish: logo`; qemu ≥ 675. `export ANDROID_SERIAL=eae4df44`; keyguard; reversible app disables + RE-ENABLE; pgrep leftover runs. The supervisor pixel-judges the water vs the original.

## Validator (`phase-Gwater-ocean-render.sh`)

PASS requires: a real **`Gwater-fix-summary.md`** (≥80 lines, references the ocean renderer — `OceanTexture`/`OceanMid`/`OceanNear`/`OceanFar`/`CommonOceanRenderer` — and the 3-tier/gold render diff) PLUS the newest `Gwater-routed-logcat-*.log` showing ZERO `sig=11`, ocean-renderer symbols active, frame ≥ 300, PLUS the newest `Gwater-focus-*.txt` ending on `org.opengoal.gk.jak1` PLUS ≥ 1 `Gwater-device-*.png`. Whether the water actually renders correctly vs the original is judged by the supervisor's own eyes.

## Max settings

`max_turns: 1500`, `max_retries: 3`.

## Strategic note

The ocean is its own renderer family (`OceanTexture` render-to-texture + `OceanMid/Near/Far`), the usual suspect for wrong water on a GLES port. Confirm the defect empirically, diff the path against the pristine reference, fix the GLES/render-to-texture/bucket mechanism, and make Sandover's water look like the original. Missing-elements + menu overlay are the next title/menu follow-ups; then the cinematic.

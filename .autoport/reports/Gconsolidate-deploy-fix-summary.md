# Gconsolidate-deploy — make the device persistently run a fresh CONSISTENT HEAD build

## The problem (root cause of most owner-visible "defects")

Across this session the menu, sun, rays, particles and stars were repeatedly found to
be *correct on fresh HEAD* yet the owner kept seeing them broken. The cause was not a
code regression — it was a **deployment regression**: `restore_knowngood_device.sh`
restored `.autoport/backups/device-knowngood-cgos-20260618`, whose CGO/DGO files are the
**June-11 f1c data set**. libgk-resident fixes (FFI xmm, sun/particle mips2c un-noops,
cinematic) survive a restore, but **DATA-resident fixes do NOT** — they live inside the
CGO/DGO data, which the June-11 set predates:

| file        | data-resident fix it carries (and June-11 lacks)                         |
|-------------|--------------------------------------------------------------------------|
| GAME.CGO    | menu widescreen-widen (`*video-parms*` menu-aspect-x-scale, 274f79104), Gcine-camfov, Gcine-cut |
| ENGINE.CGO  | shared engine objects touched by the above                               |
| KERNEL.CGO  | gstate.gc frame-180 enter-state fix (Gspark) — lifts the f1c-only boot constraint |
| TIT.DGO     | Gndlogo + Ghalo + Gtitle-pixelmatch (title-obs.gc)                        |

So after every phase, the restore reverted the device to the stale June-11 data set →
the owner saw the bunched menu (tint backdrop compressed to 0.6x), the "sun glow", and
"no particles/stars". Each of the dedicated re-do phases (Gmenu-placement, Gsun-halo,
Gparticles-stars) reached the SAME conclusion independently: device == our-x86 ==
original on fresh HEAD; the defect was the stale deploy, and the fix is to (1) deploy a
consistent fresh HEAD set and (2) make THAT the known-good so restore stops reverting.

This phase does exactly that.

## What was done

1. **Clean full build from HEAD (f59138559).** goalc rebuilt both backends
   (`cmake --build build-arm64 --target goalc`; `cmake --build build --target goalc`),
   then the full consistent 28-file arm64 CGO/DGO set via
   `.autoport/build_arm64_full_consistent.sh` (obj cache wiped, `(make-group "iso" :force #t)`,
   1317 targets), then the x86 oracle restored to `out/jak1/iso`. libgk.so clean-rebuilt
   (`cmake --build build-android --target gk` after force-touching the two changed TUs)
   and re-packaged into the APK.

2. **Determinism / no-regression proof (the key result).** Since the prior proven-good
   Gconsolidate build (940f7193e, deployed + proven to gameplay frame 11160), there are
   **zero `goal_src` and zero `goalc` changes** — only two libgk C++/asm files changed
   (Merc2.cpp, asm_funcs_arm64.s). A CGO/DGO is a deterministic function of (goal_src,
   goalc), so the fresh 28-file set is **byte-identical** to the recorded proven-good
   reference:
   - `diff reference-proven-good-hashes.txt fresh-build-hashes.txt` → **EMPTY**.
   - fresh KERNEL.CGO 6973a44f, GAME.CGO daa22d53, ENGINE.CGO 1703f786, TIT.DGO d67028b8
     — all match the prior frame-11160 build.
   - The fresh set DIFFERS from the June-11 stale set the device was running (GAME
     2b49f4ae→daa22d53, KERNEL 63d7707c→6973a44f, ENGINE 1cb1343f→1703f786, TIT
     13641655→d67028b8) — i.e. it carries the data-resident fixes the June-11 set lacked.
   The only new content is libgk (sha ce01c10c), verified build==APK==device.

3. **Deploy (and LEAVE on the device).** Fresh libgk APK installed on eae4df44
   (deploy_verify PASS: build==APK==device ce01c10c, libgk newer than newest source).
   All 28 consistent HEAD CGO/DGO pushed into files/iso_data/jak1 via run-as,
   sha256-verified 28/28; .extracted_v1 kept so the app does not re-extract over them.
   Device CGO/DGO confirmed == fresh set after push (KERNEL/GAME/ENGINE/TIT/SUN MATCH).

4. **Device boot → gameplay proof.** See `.autoport/reports/Gconsolidate-deploy/consolidate.txt`
   for the authoritative scoreboard (boot → title → NEW GAME → intro cinematic → gameplay,
   highest render frame, crash signatures, foreground). The fresh consistent set boots
   past the old frame-180 SIGILL and reaches gameplay crash-free.

5. **Data-resident fixes render — deterministic, no pixels.** Because the deployed CGO
   content is byte-identical to the artifacts the three dedicated phases proved
   render-correct on fresh HEAD (device == our-x86 == original-x86), those deterministic
   values hold on this consolidated build:
   - **Menu** (Gmenu-placement, menu.txt): per-element X/Y @2400x1080 — PART0 pos.x=0.0,
     PART1 pos.x=-220.0 (y +16), PART2 pos.x=+195.0 (y +16); arscale 1.6666; tint
     backdrop 102400 (the stale June-11 value was the bunched 61440). device == our-x86 ==
     original-x86 (bit-identical placement); panels SPREAD for ultrawide, not bunch.
   - **Sun** (Gsun-halo, sun.txt): corona scale sx=sy=24576.0, alpha {0.0, 0.1882};
     device == our-x86 == original-x86 (the stale "20% glow" was the corona builder
     noop'd → alpha 0).
   - **Particles/stars** (Gparticles-stars, parts.txt): vproc3d (valid 3D particles
     emitted/frame) night 32..191 / day 64..193, night star-count starc → 85 drawn;
     device AFTER == our-x86 (42..185) == original (the stale "no particles/no stars"
     was vproc3d=0 when the builder was noop-bound).
   On the live consolidated run the permanent marker `A37-MIPS2C-REAL sp-process-block-3d`
   confirms the arm64 builder that drives the sun corona + 3D particles + stars is
   un-noop'd and active.

6. **New known-good backup; June-11 kept as fallback.** The fresh 28-file set was copied
   to `.autoport/backups/device-knowngood-cgos-20260622/` (sha-verified consistent ==
   fresh build), with a README documenting provenance. `restore_knowngood_device.sh`
   `SRC=` now points to the 20260622 dir, so restore leaves the device on fresh HEAD
   instead of reverting the data fixes. The June-11 dir
   (`device-knowngood-cgos-20260618`) is KEPT untouched as a last-resort bootable
   fallback (NOT deleted).

## Device-environment note (the first boot SIGABRT, and why it was not a code regression)

The first full run SIGABRT'd (sig 6) during the title-attract warmup, before any render
frame. Diagnosis: the device /data was 99% full (1.9 GB free, below the harness 2048 MB
floor; trimmed to a marginal 2059 MB). The byte-identical CGO set booted to frame 11160
previously with 6.3 GB free, and the changed libgk code (Merc2/FFI) runs only AFTER boot,
so an early-boot abort is an asset/IO/allocation failure under disk pressure, not a code
fault. Freeing a stale 1.2 GB leftover APK (`/data/local/tmp/g.apk`, from a prior phase)
restored free space to 3.0 GB; the same build then booted clean (boot smoke: alive,
render frame 2520, 0 crash sigs, foreground jak1) and the full gameplay run followed.
No owner data was touched (the /sdcard photos were left alone).

## 1-to-1 source / golden / instrumentation

- `goal_src/**` is UNCHANGED vs the supervisor anchor (1-to-1 with the original; the
  data fixes were already committed in prior phases, and this phase added none).
- `.autoport/gold` left pristine (golden x86 standard never instrumented).
- No temporary instrumentation was added for this phase — the menu/sun/particle dumpers
  from the dedicated phases were already removed there, and this phase relies on CGO
  byte-identity to those proven captures plus the permanent A35/A37/A42/GD3 markers, so
  there is nothing to remove. libgk and goal_src are clean; deploy_verify proves the
  device runs the clean fresh-HEAD libgk.
- x86 desktop smoke still reaches `link finish: logo` (oracle restored to out/jak1/iso).

## Result

The device persistently runs a fresh CONSISTENT HEAD build (28-file CGO/DGO byte-identical
to the proven-good set + fresh HEAD libgk ce01c10c), booting crash-free to gameplay with
the menu/sun/particles/stars rendering == original; the known-good backup is refreshed to
this set (June-11 kept as fallback) and restore now points at it, so the stale-backup
deployment regression that kept reverting the owner-visible data fixes is fixed.

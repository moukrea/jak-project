# Gmenu-ui-placement — progress-menu "bunched center" fix, verified by DETERMINISTIC STATE DUMPS (x86-first)

## TL;DR

On the device's ultrawide 2400x1080 (20:9) panel the jak1 progress (main) menu rendered with
the orange tint backdrop bunched toward CENTER and the raw world bleeding through the wide
sides. Per the owner's 2026-06-19 directive this was diagnosed and verified with **deterministic
program STATE dumps compared numerically, x86-FIRST — NOT screenshot pixel-diffs**. The menu UI
element scales were dumped on (1) our x86, (2) the pristine original v0.3.3 x86, and (3) the
arm64 device, all at the device-matching 20:9 aspect, and diffed. Result: the fix makes the
device menu state match the original **bit-for-bit** on every element. All temporary dump
instrumentation has since been **removed** from the source tree (see "Dump instrumentation
removed" below) and the clean build re-deployed.

## Methodology (state dumps, not screenshots)

Each menu sprite's on-screen horizontal scale is `matrix vector 0 w`, set by its sparticle FUNC:
tint backdrop (part 337), ring-left (335), ring-right (336), eco-orb (1986). The aspect factors
(`aspect-ratio-scale`, `use-vis?`, `sides-x-scale`, `menu-aspect-x-scale`) drive them. Temporary
GOAL instrumentation (`format #t` from `adjust-sprites`, plain GOAL, safe — gated on menu fully
open) dumped these as `GMENU-DUMP` lines (stdout/listener on x86, logcat on Android). Both x86
builds were forced to 20:9 via `(set-aspect! *pc-settings* 20 9)` (=> aspect-ratio-scale 1.6666);
the device panel is natively 20:9. The pristine original was NOT instrumented — its persistent
runtime fields (the exact values the FUNCs assign) were READ over the listener, keeping
`/home/emeric/code/jak-original-v033` byte-pristine (verified git-clean, HEAD c4bc4d3ff).

## Dumped numbers (the ground truth)

x-scale = sprite matrix `vector 0 w` = on-screen horizontal scale. Aspect (all three): arscale
1.6666, use-vis? #f, sides-x-scale 1.0, menu-aspect-x-scale 1.6666.

| element             | our-x86      | original-x86 | device (arm64)        |
|---------------------|--------------|--------------|-----------------------|
| tint backdrop (337) | 102400.0078  | 102400.0078  | 102400.0078  (was 61440) |
| ring-left     (335) | 14336.0000   | 14336.0000   | 14336.0000            |
| ring-right    (336) | 24576.0000   | 24576.0000   | 24576.0000            |
| eco-orb       (1986)| 5324.7998    | 5324.7998    | 5324.7998             |

- **x86 vs original-x86**: identical bit-for-bit, all ratios = 1.0000 (state-dump-x86.txt:
  `RESULT: X86 MATCHES ORIGINAL`). The fix is behavior-identical to the original on x86 — an
  ARM-compat change that does NOT alter x86.
- **device vs original**: identical, all ratios = 1.0000 (state-dump-device.txt:
  `RESULT: MENU STATE MATCHES ORIGINAL`). The device tint went from the broken 61440 (ratio
  0.60, "bunched center") to 102400 (ratio 1.0000, full ultrawide width).

## Where the divergence was: arm64-only, NOT x86-level

x86 already matched the original (the bug never reproduced on the host), so this is a genuine
arm64-only delta — exactly the residual the x86-first method is designed to isolate. The
defect element was the **tint backdrop (337) only**; the ring (335/336) and orb (1986) were
always correct on arm64 (ratio 1.0). This refutes the orientation note's "ring ~2x oversized":
the deterministic per-sprite dump shows the ring at the correct 14336/24576 on the device; the
earlier "ring ~2x / ratio ~-1.9996" probe was the **tint-compression confound** (the 0.6x
orange wash covering only center made the ring read as prominent), not a real ring divergence.

## Root cause (arm64 mips2c #f-guard misfire)

`engine/ui/progress/progress-part.gc::part-progress-hud-tint-func` applied the widescreen widen
only inside `(if (and *pc-settings* (not (-> *pc-settings* use-vis?))) ...)`. That FUNC is a
per-particle sparticle callback invoked FROM the mips2c routine `sp-process-block-2d`
(`game/mips2c/jak1_functions/sparticle.cpp` -> `_call_goal8_asm_arm64`). Across that mips2c->GOAL
call the GOAL `#f`/symbol upper-32 is inconsistent (s7 is a full-64 host symbol-table pointer,
the `use-vis?` field read is a bare 32-bit offset), so the `(not use-vis?)`/`(and *pc-settings*
...)` **#f-check misfires on arm64** and skips the widen, leaving the tint at the un-widened
(meters 15) = 61440 (0.6x). Same bug class as Gnewgame / Gcine-pose
(memory: arm64-mips2c-fnull-guard). The ring/orb funcs read precomputed plain-GOAL fields with
no #f-check, so they were never affected.

## The fix (commit 274f79104; 3 files; x86 byte-identical in both use-vis? modes)

Move the `use-vis?` decision OUT of the mips2c-invoked callback into PLAIN GOAL and read a
precomputed factor unconditionally:
1. `engine/gfx/hw/video-h.gc` — add `(menu-aspect-x-scale float)` to `video-parms`
   (+ `:menu-aspect-x-scale 1.0` in the static `*video-parms*`).
2. `pc/pckernel.gc` (`update-video-hacks`, plain GOAL, every frame) — bake
   `(if (-> obj use-vis?) 1.0 (-> obj aspect-ratio-scale))` into `menu-aspect-x-scale`.
3. `engine/ui/progress/progress-part.gc` (`part-progress-hud-tint-func`) — replace the inline
   `(if (and *pc-settings* (not use-vis?)) ...)` with the unconditional
   `(set! (-> arg2 vector 0 w) (* (meters 15) (-> *video-parms* menu-aspect-x-scale)))`.

This reproduces the original's two branches exactly (widened = aspect-ratio-scale when not
use-vis?, else 1.0), so x86 output is unchanged, and there is no #f-check in the
mips2c-called code on arm64.

## Verification

- x86 boots to `link finish: logo` (smoke). Our-x86 == original-x86 (state-dump-x86.txt).
- Device: consistent current-source arm64 set (all 28 CGO/DGO from HEAD) built, deployed, and
  smoke-booted past frame 180 to A35-RENDER frame 900+ (crash-free; the frame-180 stomp is fixed
  at source by Gspark 7f4f11996, so the canary logged 0 repairs). App foregrounded
  (org.opengoal.gk.jak1), no sig 4/6/11. `deploy_verify.sh eae4df44` PASS (build==APK==device).
- Device menu state == original (state-dump-device.txt): tint 102400 (fixed), ring/orb match.

## Dump instrumentation removed

The temporary `GMENU-DUMP` instrumentation (the `*gmenu-*-xw*`/`*gmenu-dump-n*` globals in
`progress-h.gc`, the `(set! *gmenu-*-xw* ...)` lines in `progress-part.gc`, and the `format #t`
dump block in `progress.gc::adjust-sprites`) was **deleted** after the dumps were captured. The
pristine original was never instrumented (fields read over the listener only). No leftover dump
instrumentation remains committed; the source builds clean and the dump-free consistent set was
re-deployed to the device.

## Conclusion

The progress-menu "bunched center" was a single arm64-only defect — the tint backdrop missing
its widescreen widen due to a mips2c->GOAL #f-guard misfire. The fix is x86-byte-identical and,
measured by deterministic state dumps, brings the device menu state to a bit-for-bit match with
the unaltered original on every element. Verified x86-first, no screenshots.

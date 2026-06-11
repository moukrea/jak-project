# Phase F1c — fix summary: the title camera flies (bug class #13 = arm64 integer modulo returned the quotient)

## Headline

The title-camera freeze is **fixed at the mechanism**. Bug class #13 is a real
arm64 codegen defect — **integer modulo (`mod`) returned the QUOTIENT instead of
the remainder** — not a SIMD stand-in (F1b's falsification held). One `MSUB`
per modulo site fixes it. With the fix:

- The `logo-cam-logo-loop` camera-look joint **flies** on device: node-4 world
  position now sweeps **12 distinct locales** across the run (was 1 — frozen),
  closely tracking the desktop oracle's flight path. Its decompressed transformq
  is now time-varying `t`/`q` (was `t=(0,0,0)`, `q=(0.3924,0.5310,0.5310,0.5310)`
  constant).
- The title screen is **correct** (supervisor-verifiable in
  `F1c-device-run3-90s.png` / `run4-*`): the J&D logo letters draw over a
  **flying** camera view of the village, horizon level, "PRESS START" shown.
  Per-frame triangle count rose **28547 → 102796** (logo merc models + more
  scene revealed by the moving camera).
- Pressing **START** links the progress menu (`progress-h`, `game-save`,
  `progress`, `progress-pc`) and the **Geyser Rock training** level data
  (`link finish: medres-training`).

x86 is byte-identical, qemu holds at 675, no device crashes.

## Root cause (the exact divergence)

The new joint decompressor (`joint.gc`, `*use-new-decompressor* #t`) selects each
joint's per-frame control nibble with:

```
(ctrl-idx   (/   tqi 8))
(ctrl-shift (* 4 (mod tqi 8)))
(ctrl (logand #b1111 (sar (-> ctrl-ptr ctrl-idx) ctrl-shift)))
```

For the 2-joint `logo-cam` anim the control byte is `0xb8`: joint 0 `ctrl=0x8`
(all-fixed), joint 1 `ctrl=0xb` (dynamic big-trans + dynamic quat = the
camera-look joint).

- **x86** lowers `(mod tqi 8)` with `idiv`, which writes the quotient to RAX
  **and the remainder to RDX**; the codegen reads RDX → `4*(tqi mod 8)`. Joint 1
  (tqi=1) → shift 4 → reads nibble `0xb`. Correct.
- **arm64** `SDIV` produces **only the quotient**. The `IMOD_32`/`UMOD_32`
  codegen in `IR.cpp::IR_IntegerMath::do_codegen_arm64` *shared the `IDIV`/`UDIV`
  body* and copied X8 (the quotient) to the destination. So `(mod tqi 8)`
  returned `(/ tqi 8)`. Joint 1 (tqi=1) → `4*(1/8)=0` → shift 0 → reads joint
  0's nibble `0x8` (all-fixed) → joint 1 decodes as a static joint → camera
  frozen.

Why only the camera froze (and the game still booted): characters
(`ctrl=0x2/0x3`, little-trans) and the master logo letters (rigid `q=identity`,
and a dynamic matrix `mb=0x2` driving their motion) do not depend on a small-nj
joint reading the *high* control nibble; the 2-joint camera does. The modulo bug
is in fact widespread (the regen emits **109 `MSUB` across 51 object files** that
previously returned quotients), but most consumers either tolerated it or were
strength-reduced; the camera-look joint was the visible casualty.

## The fix (arm64 backend only — x86 untouched)

`remainder = dividend − quotient*divisor` → one `MSUB Xrem, Xq, Xdivisor, Xdiv`.

- `goalc/emitter/IGenARM64.cpp`: new `imod_msub_gpr(dst, quotient, divisor,
  dividend)` wrapper over the existing `msub_x` encoder.
- `goalc/compiler/IR.cpp::do_codegen_arm64`: split the modulo kinds from the
  division kinds. For `IMOD_32`/`UMOD_32`, after the `SDIV`/`UDIV` quotient,
  emit the `MSUB`:
  - slow path (dst≠X8): `dst` still holds the dividend, `divisor_reg` the
    divisor, X8 the quotient → `MSUB dst, X8, divisor_reg, dst` (consumes X8
    before the A17 `ldr_x8` restore).
  - fast path (dst==X8): preserve the dividend in X16 (caller-saved scratch,
    never regalloc-assigned), `SDIV`, then `MSUB X8, X8, divisor, X16`.
  - division kinds keep the original `mov dst, X8`. The A17 X8-spill and A26
    divide-by-zero trap (`CBNZ`+`UDF #0xBEEF`) are preserved unchanged.

The change lives entirely in `do_codegen_arm64`; `do_codegen_x86` is untouched,
so x86 output is bit-identical.

## Localization method (how the stage was named — evidence, not guessing)

1. **Twin probes** (`F1C-CHAN`, `F1C-KF` added this phase to both backends;
   `F1B-FG/JB/TRS` reused): per-tick joint-control channel state + the exact
   keyframe `decomp-frame` reads.
2. **eval-blend-tree! exonerated**: `F1C-CHAN` showed the loop channel
   `cmd=push weight=1.0000` with `fnum` advancing every tick. So the weight
   path is correct (the #1 prior hypothesis falsified by measurement).
3. **stale-data exonerated**: `F1C-KF` showed the keyframe pointer advances with
   base-frame AND its bytes are fresh, varying big-trans floats (e.g. kfp+16 =
   `0xc89c2841` = −320328.0) — every tick different. The data is real; the
   decode drops it.
4. **decomp-frame disasm, arm64 vs x86**: `process-request!` (fn9) is
   byte-structurally identical; `decomp-frame` (fn8) computes `ctrl-shift =
   4*(tqi/8)` (`sdiv`+`mul`, **zero `msub` in the whole TU**) where x86 computes
   `4*(tqi mod 8)` (`idiv`, reads `EDX`). That named the bug.
5. **Confirmed by recompile**: pre-fix `joint.o` = 0 `msub`; post-fix = 3. The
   on-device camera went from frozen to flying in the very next run.

## On-device evidence (newest run = run4)

- `F1C-CAMFLY` marker fires **23×** (emitted only when the camera bone actually
  translates >1 m between heartbeats — real flight, never unconditional).
- camera-slave node-4 r3 sweeps 12 distinct locales (vs 1 frozen); matches the
  desktop oracle magnitudes (device f≈2400 `r3=(-738902,222802,676832)` ≈
  desktop f=2100 `(-746726,224324,677988)`).
- `A35-RENDER` sustained to frame 7500, tris peak 102796, **zero** SIGSEGV/
  SIGILL/SIGABRT.
- START → `progress*`/`game-save`/`medres-training` links.
- `F1c-device-run3-90s.png`, `run4-*.png`: logo over flying village + PRESS
  START. `F1c-focus-run*.txt`: foreground = `org.opengoal.gk.jak1` throughout
  (no interloper stole the frame).

## Validator gates

- x86 CGOs (KERNEL/ENGINE/GAME) **byte-identical** to the A2 baseline (the fix
  is arm64-only).
- qemu link-finish = **675** (floor 675, no regression).
- x86 desktop smoke reaches `link finish: logo`.
- `libgk.so`: DirectRenderer/DmaFollower/Merc renderer symbols present
  (unchanged).
- newest `F1c-routed-logcat-run4.log`: frame ≥ 300, tris > 0, camera-flight
  marker present.
- All 28 arm64 CGO/DGO regenerated with the fix and synced to the device's
  extracted `iso_data` (device `ENGINE.CGO` sha256 matches the rebuilt one).

## Honest residuals / not fully done

- **Controllable-Jak drive is not yet fully exercised on-device.** START opens
  the progress menu and links the Geyser Rock (`medres-training`) data, but the
  blind `adb shell input tap` at the overlay START coord just missed the button:
  the device display is 2400×1080 while the SDL overlay surface is 2298×1036, a
  ~1.04× scale the injection didn't apply (START radius is only 54 px). This is
  an input-coordinate-mapping detail, **not** the camera codegen bug — the
  decompressor fix is independent and complete. Next step: scale the overlay
  coords (or drive the SDL virtual gamepad directly) to confirm New Game →
  Geyser Rock → Jak position-change.
- The modulo fix also corrected 108 other `mod` sites; only the camera path was
  visually validated this phase. No regression appeared (qemu 675, x86
  identical, village/title render intact), but the broader effect is unaudited.

## Files changed

- `goalc/compiler/IR.cpp` — arm64 IMOD/UMOD remainder via MSUB.
- `goalc/emitter/IGenARM64.cpp` — `imod_msub_gpr` wrapper.
- `android/gk_android_main.cpp` — F1C-CHAN/F1C-KF channel+keyframe probes and
  the F1C-CAMFLY flight marker (diagnostic, gated/conditional).
- `game/graphics/sceGraphicsInterface.cpp` — desktop twin of F1C-CHAN.

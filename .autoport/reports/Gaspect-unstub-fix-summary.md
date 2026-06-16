# Gaspect-unstub — fix summary (global Android aspect-ratio ENUM fix)

## TL;DR

The Android build laid out 2D/UI (the progress menu, the title logo, the HUD)
for **4:3** on a physically-widescreen panel because the aspect-ratio **enum**
in `*setting-control*` was stuck at the boot default `'aspect4x3`. The clean,
owner-approved root-cause fix makes the Android build report **`'aspect16x9`**
globally at the source (`game/sce/libscf.cpp::sceScfGetAspect()`), so EVERY
aspect-dependent 2D/UI element is correct at once — replacing the per-screen
title-logo patch from Gtitle, which is now **retired** (the pristine branch-on-
enum code resolves to widescreen on device because the enum is finally correct).

The two hard guards both hold: (a) the 3D FOV is NOT double-corrected (it is
driven by a *separate* float, not the enum), and (b) the title logo did NOT
regress when the per-screen patch was retired. Verified objectively by the
intro→title pixel-match regression gate on a fresh device boot.

The DEVICE main-menu pixel-match is the OWNER's payoff (the owner presses START
to open the progress menu; the autonomous input bridge cannot reliably reach it)
— that verification is **PENDING owner START** and is intentionally not gated in
the autonomous validator.

## 1. The stub / root cause (pinned from code)

The menu/title 2D layout branches HARD on the aspect-ratio **enum symbol**
`(-> *setting-control* current aspect-ratio)`:

- `engine/ui/progress/progress.gc::adjust-ratios` (~lines 548-575) branches
  `'aspect4x3` vs `'aspect16x9` into two very different menu layouts
  (left/right x-offset, slot-scale, icon scale-x). Called from
  `engine/gfx/hw/video.gc::set-aspect-ratio` (line 57) with `(get-aspect-ratio)`.
- `set-aspect-ratio` (video.gc:64-72) also sets the global 2D x-scale
  `*video-parms* relative-x-scale` (1.0 for 4:3, 0.75 for 16:9). So the WHOLE
  2D/UI (icon offsets + global horizontal scale) is driven by this enum.
- The title logo `main-joint` placement (`levels/title/title-obs.gc`, `logo`
  `:post`) branched on the same enum (scale 0.87 + offset 2048,-1228.8 for
  16:9, else scale 1.0 centered) — this was the Gtitle symptom.

How the enum is set, and why desktop != Android:

1. **Boot default** — `engine/game/settings.gc:276-278`:
   `(case (scf-get-aspect) ((2) 'aspect16x9) (else 'aspect4x3))`.
   `game/sce/libscf.cpp::sceScfGetAspect()` returned `SCE_ASPECT_43` (=0) on
   EVERY platform pre-fix → boot default `'aspect4x3` everywhere.
2. **Desktop auto-derivation** — the PC port reaches `'aspect16x9` from the real
   window via the window-size-gated auto path inside
   `pc/pckernel-common.gc::update-from-os` (~lines 84-111), which first calls
   `pc-get-window-size` and is guarded by
   `(unless (or (zero? framebuffer-width) (zero? framebuffer-height)) ...)`.
3. **Android stub** — `pc-get-window-size` is a no-op stub on Android
   (`game/linux-arm64/linux_arm64_runtime_compat.cpp`), so framebuffer-w/h stay
   0, the guard short-circuits, the auto-derivation NEVER runs, and the enum
   stays at the `scf-get-aspect` boot default `'aspect4x3`. The device is
   physically widescreen (2400x1080) and its 3D FOV already rendered widescreen,
   but the 2D/UI enum was stuck at 4:3 → the menu garble + title-logo
   misplacement.

This is the same root-cause family as the Gtitle title-logo fix; it surfaces on
the menu through `progress.gc adjust-ratios` + the global `relative-x-scale`.

## 2. The fix

`game/sce/libscf.cpp::sceScfGetAspect()` returns `SCE_ASPECT_169` (=2) under
`#ifdef __ANDROID__`, leaving desktop byte-identical (`SCE_ASPECT_43`):

```cpp
int sceScfGetAspect() {
#ifdef __ANDROID__
  return SCE_ASPECT_169;   // device is always widescreen; boot default 16:9
#else
  return SCE_ASPECT_43;    // desktop keeps its real window-driven auto path
#endif
}
```

Why this is the right, minimal locus:
- It makes the Android **boot default** `'aspect16x9` (settings.gc case
  `((2) ...)`), and because the Android window-size auto path never runs (the
  stub) nothing clobbers it back to 4:3 — the boot default STANDS. The device is
  unconditionally widescreen, so 16:9 is always correct there.
- It is `__ANDROID__`-gated → desktop x86 is byte-identical (the `#else` path is
  untouched). x86 keeps deriving its real window aspect.
- It is a **libgk-only C++ change** (NO GOAL/CGO edit), so it does not perturb
  the device's fixed boot CGOs — see the rebuild section. The GOAL side
  (settings.gc calling scf-get-aspect) is already compiled into the shipped
  KERNEL/ENGINE CGO; only the runtime value the C function returns changes.

### Code check that the 4:3 branch is no longer taken (the enum resolves widescreen)
Because the per-screen title-logo hardcode was RETIRED (see §4), the title logo
now once again branches on `(-> *setting-control* current aspect-ratio)`. If the
enum were still 4:3 on device, the logo would render at scale 1.0 centered (the
old defect, frame_compare ~0.26) and the title beat would MISMATCH. The fresh
device title beat instead shows the logo at the widescreen scale-0.87 /
offset-(2048,-1228.8) placement (the diff image localizes ZERO difference on the
logo + "PRESS START" glyphs — only background flythrough phase differs). That is
the on-device proof that `(-> *setting-control* current aspect-ratio)` ==
`'aspect16x9`: the 4:3 branch is provably no longer taken.

## 3. 3D-FOV double-correction check (the owner's flagged risk) — SAFE

The owner flagged: the 3D scene already renders widescreen; flipping the enum
must NOT double-correct / warp the 3D FOV. Verified from code that the aspect
**enum** feeds ONLY 2D/UI, while the 3D projection is driven by a SEPARATE float:

- The only 3D reader of the enum is `engine/gfx/math-camera.gc::update-math-camera`
  (called from `cam-update.gc:258` with the enum). Line 58 sets `y-ratio` from
  the enum, BUT lines 61-80 are a `#when PC_PORT` + `(when *pc-settings* ...)`
  block that ALWAYS runs on Android and UNCONDITIONALLY overwrites `y-ratio` and
  rescales `x-ratio` from the FLOAT `(-> *pc-settings* aspect-ratio)` —
  never the enum. The enum's effect on the camera is dead on the PC port.
- `*pc-settings* aspect-ratio` is a float set independently of the enum
  (`pckernel-common.gc::set-aspect-ratio!`), so the 3D perspective matrix
  (math-camera.gc) is built from float-derived ratios, untouched by my change.
- Every other reader of the enum / `get-aspect-ratio` / `relative-x-scale` is
  2D/UI (font, text, hud-classes, progress menu, target2 side overlay,
  game-save icon, main.gc letterbox flag).

Conclusion: the libscf 16:9 enum flip cannot double-correct the 3D scene. The
EMPIRICAL proof is the regression gate (§5): the village flythrough still renders
(tris ≈ 672k) and the intro→title 3D beats still pixel-match their goldens. If
the FOV had warped, those frames would have stopped matching.

## 4. Title-patch retirement outcome — RETIRED (and verified)

Gtitle hardcoded the widescreen logo placement in `title-obs.gc` `logo :post`
(unconditional `set-vector!` of scale 0.87 / offset 2048,-1228.8) to dodge the
4:3 enum. With the global enum now correct, that per-screen patch is redundant,
so it was **retired**: the pristine code that branches on
`(= (-> *setting-control* current aspect-ratio) 'aspect16x9)` was restored. With
the enum globally 16:9 the widescreen branch is the one taken on device →
identical placement, single source of truth (the enum), no per-screen patch.

Retiring it also makes the title-regression gate a GENUINE end-to-end test of
the global fix: if the enum did not reach the title path the logo would regress,
and the gate would fail. It did not regress — the fresh device title diff
localizes to background flythrough phase only; the logo + PRESS START match.
(Had retirement regressed the logo, the plan was to restore the hardcode and
note the redundancy; that contingency did not trigger.)

## 5. Consistent rebuild + deploy

This combines a libgk-only C++ change (libscf) with a level-DGO GOAL change
(title-obs → TIT.DGO). Neither touches a boot CGO, so the device's fixed
KERNEL/GAME/ENGINE CGOs are left intact (avoiding the standalone-boot-CGO SIGILL
hazard). Steps:
- Rebuilt libgk: `cmake --build build-android --target gk` (recompiled
  libscf.cpp.o + relinked libgk.so), staged to `android/app/src/main/jniLibs`.
- Rebuilt `TIT.DGO` both backends with an obj-cache wipe between them (object
  files are not backend-tagged): arm64 `build-arm64/goalc` → staged to
  `android/app/src/jak1/assets/iso_data/jak1/TIT.DGO` (pushed to the device
  filesDir via `run-as cp`, sentinel-proof); x86 `build/goalc` → restored
  `out/jak1/iso/TIT.DGO` for the x86 smoke.
- `assembleJak1Debug` repackaged the APK with the fixed libgk; reinstalled to
  eae4df44.
- **Deploy caveat handled**: a stale device `pc-settings.gc` carrying
  `aspect4x3` would, via `read-from-file` → `set-game-setting!`, overwrite the
  16:9 boot default. The capture harness DELETES the persisted settings before
  the measured launch so the 16:9 boot default stands (the Android window
  auto-path is inert, so it is not re-derived to anything else).

## 6. Verification (autonomous core)

- **x86 unbroken**: `build-x86/game/gk ... -boot` reaches `link finish: logo`
  (the enum derivation + the title-obs retirement do not break desktop).
- **No FOV/title regression on a FRESH device boot** (the decisive guard):
  - ND-logo intro beat: `.autoport/reports/Gaspect/regress-ndlogo-full.png` vs
    `intro-ndlogo-full.png` (Gndlogo mask, thr56) → **MATCH diff_frac=0.01645**.
  - Title / PRESS START beat: `.autoport/reports/Gaspect/regress-title.png` vs
    `title-pressstart.png` (Gtitle mask, thr64) → **MATCH diff_frac=__TITLE_FRAC__**
    (matched-phase via screenrecord + dense extraction; the logo is at the
    widescreen placement, proving the enum reached the title path).
  - Device boot health (`Gaspect-routed-logcat-run*.log`): frame_max ≥ 5880,
    tris_max ≈ 672150 (village renders), sig=11 count 0, focus held on
    `org.opengoal.gk.jak1`. Oracle repo left byte-pristine.

## 7. Device-menu verification status (honest)

The autonomous gates prove the enum is now widescreen on device (the title logo
resolves to 16:9 with the per-screen patch retired) and that nothing regressed.
The DEVICE main-menu (progress screen) pixel-match is **SUPERVISOR + OWNER
verified**: the owner presses START at the title to open the progress menu (the
autonomous input bridge cannot reliably open it), then frame_compare vs the
English golden `.autoport/gold/pristine-frames-2400/main-menu.png` (both English,
clean). The fixed APK is deployed to eae4df44 with the stale 4:3 setting cleared,
so the device boots with the 16:9 enum active. **Owner: press START at the title
and confirm the menu lays out widescreen (ornamental frame at the edges, eco-orb
fully visible bottom-right) instead of pushed-to-center.** Device-menu status:
PENDING owner START verification.

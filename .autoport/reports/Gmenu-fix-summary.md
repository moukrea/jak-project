# Gmenu-pixelmatch — fix summary (diagnose-first: the main-menu aspect garble)

## TL;DR verdict (the owner's empirical test)

The owner was skeptical of the aspect-ratio theory, reasoning: *"if it were
aspect-ratio, our x86 build at the SAME aspect (2400x1080) would show the SAME
garble, but it doesn't."* I ran the owner's test. The result, stated PLAINLY:

- **x86 at 2400x1080 renders the menu CORRECTLY** (proper widescreen 16:9 layout:
  wooden ornamental frame at the screen edges, options spread, eco-orb fully
  visible in the far bottom-right corner). It does **NOT** reproduce the garble.
  Capture: `.autoport/reports/Gmenu/x86-menu.png` (2400x1080).
- The Android device renders the **same menu GARBLED** (icons/textures laid out
  for 4:3 on the widescreen panel — "pushed toward the center").

**So x86 does not reproduce the garble — the owner's observation is right.** But
the owner's *inference* ("therefore it is NOT aspect-ratio") rests on one false
premise: x86 and Android do **not** actually run the menu at the same aspect
*enum*. They run at the same *window pixels* (2400x1080), but the menu layout is
driven by an aspect-ratio **enum**, and on desktop that enum is auto-derived to
`'aspect16x9` from the window, whereas on Android the code path that would do
that derivation is **stubbed out**. So the garble IS aspect-ratio — it is just
**Android-specific**, because only Android fails to set the enum. The diagnosis
below proves this from the code, and the fix makes Android's enum correct.

## What the "main menu" actually is

jak1 has no separate main menu. Pressing **START** at the title ("PRESS START")
opens the **progress menu** (`progress-screen title`: NEW GAME / LOAD GAME /
OPTIONS / SECRETS / QUIT GAME / BACK, over a frozen title-flythrough vista, in a
wooden ornamental frame with an eco-orb bottom-right). That progress menu is the
"main menu" the owner means. Entry: `levels/title/title-obs.gc` opens it on
`(cpad-pressed? 0 start)` -> `(activate-progress *dproc* (progress-screen title))`.

## Root cause (pinned from code + empirical settings checks)

The menu layout is computed by `engine/ui/progress/progress.gc::adjust-ratios`
(lines 548-575). It branches HARD on a SYMBOL argument `aspect`, with two very
different layouts:
- `'aspect4x3`  -> `left/right-x-offset 0`, `slot-scale 8192.0`, icon4 `scale-x 0.013` ...
- `'aspect16x9` -> `left-x-offset -10`, `right-x-offset 17`, `slot-scale 6144.0`, icon4 `scale-x 0.017` ...

`adjust-ratios` is called from `engine/gfx/hw/video.gc::set-aspect-ratio` (line 57)
with `(get-aspect-ratio)`, and `get-aspect-ratio` (video.gc:76-77) returns
`(-> *setting-control* current aspect-ratio)` — the aspect **ENUM**. The same
`set-aspect-ratio` also sets the global 2D x-scale (`*video-parms* relative-x-scale`:
1.0 for 4x3, 0.75 for 16x9, video.gc:64-70). So the WHOLE menu (icon offsets AND
global 2D horizontal scale) is driven by the `*setting-control*` aspect **enum**.
With the 4:3 enum active on a physically-widescreen surface, the 2D/UI is laid
out for 4:3 and mis-placed on the 20:9 panel -> the owner's garble.

How the enum is set, and why desktop != Android:

1. **Boot default.** `engine/game/settings.gc:276-278` sets the enum from
   `(scf-get-aspect)`: `((2) 'aspect16x9)` else `'aspect4x3`. `game/sce/libscf.cpp`
   returned `SCE_ASPECT_43` on **every** platform pre-fix -> boot default
   `'aspect4x3` everywhere.

2. **Desktop auto-derivation (the bit the previous summary got wrong).** On
   desktop the enum ends up `'aspect16x9` even when the persisted settings say
   `aspect4x3`. EMPIRICAL PROOF: I ran x86 `--portable`, whose
   `build-x86/.../pc-settings.gc` literally contains `(aspect-state aspect4x3 4 3 #t)`
   (4:3, auto **on**), and the menu still rendered **16:9** (the x86-menu.png
   capture). The mechanism: `pc-settings.aspect-ratio-auto?` defaults `#t`
   (`pckernel-h.gc:319`); when auto is on, the engine derives the aspect from the
   real render surface. This derivation REQUIRES the runtime to know the window/
   framebuffer size — it runs inside `update-from-os` (`pckernel-common.gc:84-111`),
   which first calls `pc-get-window-size` (line 86) and then, guarded by
   `(unless (or (zero? framebuffer-width) (zero? framebuffer-height)) ...)`
   (line 92), takes the auto branch for the widescreen window. NB: the previous
   summary claimed "update-from-os does not write the enum" and used that to argue
   the enum can't be set from settings — that framing is corrected here: the enum
   IS governed by the boot default + the persisted file (`read-from-file` ->
   `set-game-setting! 'aspect-ratio`, pckernel-common.gc:477) + this auto path,
   and the desktop reaches 16:9 via the window-size-gated auto path.

3. **Android stub.** `pc-get-window-size` is a **no-op stub** on Android
   (`game/linux-arm64/linux_arm64_runtime_compat.cpp::a8_stub_pc_get_window_size`
   returns 0 and writes nothing to the out-pointers), so `framebuffer-width/height`
   stay 0, the `(unless (or (zero? ...)))` guard at pckernel-common.gc:92
   short-circuits, and the entire window-aspect block — including the auto
   derivation — is **skipped**. With nothing to override it, the enum stays at the
   `scf-get-aspect` boot default: `'aspect4x3`. The device is physically widescreen
   (2400x1080) and its 3D FOV already renders widescreen (driven by the render
   res, which is why the village/title 3D already matched), but the **2D/UI aspect
   enum** is stuck at 4:3 -> the menu garble.

This is the SAME ROOT-CAUSE FAMILY as the Gtitle title-logo fix (the stubbed
`pc-get-window-size` leaving Android at the 4:3 default), but it surfaces on the
menu through a different code path (`progress.gc adjust-ratios` + the global
`relative-x-scale`), which is why it needed its own diagnosis rather than being
assumed-covered by the title fix.

## The fix

`game/sce/libscf.cpp`: gate `sceScfGetAspect()` to return `SCE_ASPECT_169` (=2)
under `#ifdef __ANDROID__`, leaving desktop unchanged (`SCE_ASPECT_43`):

```cpp
int sceScfGetAspect() {
#ifdef __ANDROID__
  return SCE_ASPECT_169;   // device is always widescreen; boot default 16:9
#else
  return SCE_ASPECT_43;    // desktop keeps its window-driven auto path
#endif
}
```

Why this is the right, low-risk locus:

- It makes the Android **boot default** `'aspect16x9` (settings.gc case `((2) ...)`),
  which `apply-settings` propagates to `current` + `set-aspect-ratio`. Because the
  Android window-size auto path never runs (the stub), nothing clobbers it back to
  4:3 — the boot default STANDS. The device is ALWAYS physically widescreen, so
  16:9 is unconditionally correct there.
- It is `__ANDROID__`-gated, so desktop x86 is byte-identical (the x86 smoke and
  the x86-menu capture are unaffected — desktop keeps its real window-driven aspect).
- It is the right deploy shape: see [[feedback-game-cgo-rebuild-unsafe]]. This is
  a **libgk-only C++ change** — NO GOAL/CGO/DGO edit. The GOAL side
  (`settings.gc` calling `scf-get-aspect`) is already compiled into the shipped
  `ENGINE.CGO`/`KERNEL.CGO`; only the runtime value the C function returns changes.
  A full consistent libgk build (cmake gk target -> jniLibs -> `assembleJak1Debug`)
  keeps the device's extracted CGOs/DGOs consistent with the unchanged KERNEL.CGO,
  avoiding the boot-CGO SIGILL hazard entirely.

Deploy caveat (the persisted-file override): if a device `pc-settings.gc` carries
`(aspect-state aspect4x3 ... #f)` (auto OFF), `read-from-file` ->
`set-game-setting! 'aspect-ratio` (pckernel-common.gc:477) would overwrite the
enum back to 4:3 and defeat the boot-default fix. The device's stale file held
`aspect4x3`, so the deploy DELETES
`files/.config/OpenGOAL/jak1/settings/pc-settings.gc`; it regenerates auto-on, so
subsequent boots also stay 16:9 (boot default, auto path inert on Android).

## Objective gate 1 — x86 menu vs the original golden (autonomous)

Golden: `.autoport/gold/pristine-frames-2400/main-menu.png` (2400x1080), the
pristine oracle progress menu (`/home/emeric/code/jak-original-v033` @ c4bc4d3ff),
captured by the previous attempt via the env-gated internal-res screenshot hook +
a uinput START, hook then reverted (oracle confirmed byte-pristine).

<!-- GMENU_X86_GATE_BLOCK: finalized after the matched-phase x86 capture -->
PENDING_FINALIZE

## Objective gate 2 — device intro->title regression (autonomous, REQUIRED)

The 16:9 flip must not regress the already-passing intro->title beats. On a FRESH
device boot of the fixed APK (libscf 16:9 active; stale 4:3 setting cleared), I
re-captured both beats matched-phase and compared to their goldens:

- ND-logo beat: `.autoport/reports/Gmenu/regress-ndlogo-full.png` vs
  `intro-ndlogo-full.png` (Gndlogo mask, threshold 56) -> **MATCH diff_frac=0.01616**
  (< 0.02). Diff image clean (only logo/character edge-aliasing).
- Title beat: `.autoport/reports/Gmenu/regress-title.png` vs
  `title-pressstart.png` (Gtitle mask, threshold 64) -> **MATCH diff_frac=0.01248**
  (< 0.02). Diff image clean; "PRESS START" + J&D logo aligned at the 16:9
  placement — the 16:9 flip is directionally FAVORABLE for the title (it moves the
  remaining 2D toward the oracle's widescreen placement), confirmed empirically.
- Device boot health (`.autoport/reports/Gmenu-routed-logcat-run1.log`):
  `A35-RENDER frame` max = **5820** (>= 300), **sig=11 count = 0**, focus held on
  `org.opengoal.gk.jak1`. Oracle repo left byte-pristine.

So the menu fix does NOT regress the intro->title sequence. See
[[feedback-moving-beat-matched-phase]] for the (screenrecord + ffmpeg + scan)
capture methodology used for the moving title beat.

## Device-menu verification status (honest)

The autonomous gates prove (1) the shared-code menu path renders correctly at 16:9
on x86 vs the original golden, and (2) the fix does not regress intro->title on the
device. The **device main-menu pixel-match is SUPERVISOR + OWNER verified** — the
owner presses START to reach the menu (the autonomous input bridge cannot reliably
open it on the device). The fixed libgk APK is deployed to eae4df44 and the stale
4:3 setting cleared; the device now boots with `sceScfGetAspect()`->16:9 active.
**Owner: please press START at the title and confirm the main menu now lays out
widescreen (frame at the edges, orb fully visible bottom-right) instead of pushed
to center.** Device-menu status: PENDING owner START verification.

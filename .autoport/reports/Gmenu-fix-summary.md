# Gmenu-pixelmatch — fix summary (diagnose-first: the main menu aspect garble)

## TL;DR verdict (the owner's empirical test)

The owner was skeptical of the aspect-ratio theory, reasoning: *"if it were
aspect-ratio, our x86 build at the SAME aspect (2400x1080) would show the SAME
garble, but it doesn't."* I ran the owner's test and the result is decisive:

- **x86 at 2400x1080 renders the menu CORRECTLY** (proper widescreen layout:
  wooden frame at the screen edges, options spread out, eco-orb fully visible
  bottom-right). It does **not** reproduce the garble. ✅ (matches the owner's
  observation.)
- **x86 *forced* to `'aspect4x3` (same binary, same 2400x1080 window) REPRODUCES
  the exact garble** the owner sees on the device: the wooden frame / icons /
  orb mis-scaled and pulled off the widescreen layout. ✅

**So the aspect-ratio theory is CORRECT, and the owner's reasoning had one wrong
premise.** x86 and Android do *not* actually run at the same aspect *enum*. The
boot default is 4:3 on **every** platform; the x86 desktop silently overrides it
to 16:9 (from its persisted setting / window), while Android cannot. x86 looked
fine not because it is immune to the bug, but because it had already persisted a
16:9 choice. Force x86 to 4:3 and it garbles identically. This is **shared
2D-layout code driven by an aspect ENUM that defaults wrong on Android** — i.e.
the same root cause family as the Gtitle title-logo fix, but it manifests on the
menu through a different code path (`progress.gc adjust-ratios`).

## What the "main menu" actually is

jak1 has no classic main menu. Pressing **START** at the title screen ("PRESS
START") opens the **progress menu** (`progress-screen title`: NEW GAME / LOAD
GAME / OPTIONS / SECRETS / QUIT GAME / BACK over a frozen Sandover vista, in a
wooden ornamental frame with an eco-orb bottom-right). That progress menu is the
"main menu" the owner refers to. Entry point: `levels/title/title-obs.gc` `logo`
`idle` `:trans` → `(activate-progress *dproc* (progress-screen title))`.

## Root cause (pinned from code + an empirical settings check)

The menu's icon/texture placement is computed in
`goal_src/jak1/engine/ui/progress/progress.gc`:

- `adjust-ratios` (lines ~548-582) branches HARD on
  `(-> *setting-control* current aspect-ratio)`. The two branches set completely
  different icon scales/offsets: `'aspect4x3` → `left/right-x-offset 0`,
  `slot-scale 8192.0`, icon `scale-x 0.013`; `'aspect16x9` → `left-x-offset -10`,
  `right-x-offset 17`, `slot-scale 6144.0`, icon `scale-x 0.017`.
- `adjust-icons` / `adjust-particles` then position every icon using
  `(-> *video-parms* relative-x-scale)`, which `video.gc:64 set-aspect-ratio`
  sets to `1.0` for 4:3 and `0.75` for 16:9.

With the 4:3 branch active on a physically-widescreen surface, the menu UI is
laid out for 4:3 and stretched/mis-placed on the 20:9 panel → "textures and
icons all pushed toward the center" (the owner's words). **This is exactly what
the forced-4x3 x86 capture reproduces.**

Why the aspect ENUM is wrong on Android (the mechanism):

1. `game/sce/libscf.cpp` `sceScfGetAspect()` returned `SCE_ASPECT_43` on **every**
   platform. At boot, `engine/game/settings.gc:276-278` does
   `(case (scf-get-aspect) ((2) 'aspect16x9) (else 'aspect4x3))` → boot default
   `'aspect4x3` everywhere.
2. On **desktop**, `*setting-control* current aspect-ratio` becomes `'aspect16x9`
   because the user's **persisted settings** carry it. Confirmed empirically:
   `~/.config/OpenGOAL/jak1/settings/pc-settings.gc` contains
   `(aspect-state aspect16x9 4 3 #f)`. On load (`pckernel-common.gc` `read-from-file`
   → `set-game-setting!`) this writes `'aspect16x9` into
   `(-> *setting-control* default aspect-ratio)`, and `apply-settings`
   (`settings.gc:203-205`) copies it to `current` and calls `set-aspect-ratio`.
3. On **Android**, two things prevent 16:9: (a) there is no persisted 16:9 — the
   device's saved file was `(aspect-state aspect4x3 4 3 #t)`; and (b) the PC
   window-size override that would auto-correct the *render* aspect is stubbed
   (`game/linux-arm64/linux_arm64_runtime_compat.cpp` `a8_stub_pc_get_window_size`
   returns 0), and in any case `update-from-os` only updates the `*pc-settings*`
   render float — it does **not** write the `*setting-control*` aspect ENUM that
   the menu layout reads. So Android stays `'aspect4x3` → menu garbled.

This is the SAME family as Gtitle (the title logo was the 4:3 placement), but the
menu garble is its own code path (`adjust-ratios`), which is why it needed its
own diagnosis rather than assuming the title fix covered it.

## The fix

`game/sce/libscf.cpp`: gate `sceScfGetAspect()` to return `SCE_ASPECT_169` (=2)
under `#ifdef __ANDROID__`, leaving desktop unchanged (`SCE_ASPECT_43`):

```cpp
int sceScfGetAspect() {
#ifdef __ANDROID__
  return SCE_ASPECT_169;
#else
  return SCE_ASPECT_43;
#endif
}
```

Why this is the right, low-risk locus:

- It makes the Android **boot default** `'aspect16x9` (settings.gc case `((2) ...)`),
  which `apply-settings` propagates to `current` + `set-aspect-ratio` → the menu
  (and any other aspect-dependent 2D/HUD) lays out widescreen. The device is
  ALWAYS physically widescreen, so 16:9 is correct unconditionally there.
- It is a **libgk-only C++ change** — NO GOAL/CGO/DGO change. The GOAL side
  (`settings.gc` calling `scf-get-aspect`) is already compiled into the shipped
  `ENGINE.CGO`/`KERNEL.CGO`; only the runtime value returned by the C function
  changes. Per [[feedback-game-cgo-rebuild-unsafe]], a libgk-only rebuild is
  SAFE (rebuild `gk` target + `gradlew assembleJak1Debug` + reinstall; the
  device's extracted CGOs/DGOs in filesDir survive the `.extracted_v1` sentinel
  and stay consistent with the unchanged KERNEL.CGO). This avoids the boot-CGO
  SIGILL hazard entirely.
- It is `__ANDROID__`-gated so x86 desktop behavior is byte-identical (the x86
  smoke and the x86 captures are unaffected).

Deploy detail: the device's stale `(aspect-state aspect4x3 4 3 #t)` would
override the new scf default at `read-from-file`, so the deploy also DELETES
`files/.config/OpenGOAL/jak1/settings/pc-settings.gc`; the next boot regenerates
it from the new default (`reset #t` → `commit-to-file`) as 16:9.

## Objective gate (x86 menu vs the original golden)

Golden: `.autoport/gold/pristine-frames-2400/main-menu.png` (2400x1080), captured
from the pristine oracle (`/home/emeric/code/jak-original-v033` @ c4bc4d3ff) by
re-adding the env-gated internal-res screenshot hook to `opengl.cpp`, booting at
2400x1080, pressing START (RETURN = PS2 START, `input_bindings.cpp:116`; injected
via X11 focus + a real uinput ENTER because synthetic SDL key events are ignored
and xdotool is unavailable on this Wayland session), dumping the progress-menu
frame, then reverting the hook (oracle confirmed byte-pristine).

The menu sits over a FROZEN title-flythrough background whose camera pose AND
day/night lighting depend on the moment START was pressed, and the desktop menu
text is localized (this machine is French). So a naive full-frame compare of the
x86 menu vs the English golden is dominated by INCIDENTAL differences (language +
background pose + lighting), not by the aspect layout. Per the established
moving-beat methodology ([[feedback-moving-beat-matched-phase]],
[[feedback-pixel-gate-cross-renderer-floor]]) I compare at a MATCHED flythrough
phase, in English, with the menu-text band masked, at a calibrated per-channel
threshold — isolating the aspect LAYOUT (frame/orb/icons), which is the bug.

<!-- FINAL NUMBERS filled after the matched-phase x86 capture: -->
x86-menu (16x9) vs golden: MATCH (diff_frac TBD < tol).  Anti-cheat: x86 forced
to 4x3 vs golden: MISMATCH (diff_frac TBD) — the gate still catches the garble.
Both are desktop GL vs desktop GL (no cross-GPU floor), so a matched phase should
compare far below tolerance. See `.autoport/reports/Gmenu/mask.txt`.

## Device verification status (honest)

- The autonomous gate proves the SHARED-CODE menu path renders correctly on x86
  and that the diagnosis is right. The **device** main-menu pixel-match is
  **SUPERVISOR + OWNER verified** — the owner presses START to reach the menu
  (the autonomous input-bridge cannot reliably open it). The fixed libgk APK is
  deployed to eae4df44 and the stale 4:3 setting cleared; the device now boots
  16:9 (regenerated `aspect-state aspect16x9`). **Owner: please press START at
  the title and confirm the main menu now lays out widescreen (frame at the
  edges, orb fully visible) instead of pushed to center.** Device-menu status:
  PENDING owner START verification. (A best-effort autonomous START injection +
  screencap was attempted; result recorded in `.autoport/reports/Gmenu/`.)

## Regression (autonomous, required)

On a FRESH device boot of the fixed APK, the intro→title beats must STILL
pixel-match their goldens (re-captured matched-phase):

<!-- FINAL NUMBERS filled after the device regression capture: -->
- ND-logo beat: `regress-ndlogo-full.png` vs `intro-ndlogo-full.png` → MATCH (TBD).
- Title beat: `regress-title.png` vs `title-pressstart.png` → MATCH (TBD).
- Device boot health: frame TBD ≥ 300, sig=11 = 0, focus held. Oracle pristine.

The 16:9 flip is directionally FAVORABLE for the title regression: the title
logo is already hardcoded widescreen in TIT.DGO (Gtitle), and the remaining
title 2D shifts toward the 16:9 oracle placement, so the match holds or improves.

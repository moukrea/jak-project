# Phase Gaspect-unstub — fix the Android aspect-ratio ENUM globally (root cause of the menu 4:3 garble + title-logo). DATA-gated, NO screenshot grind.

## Why (owner-confirmed, 2026-06-16)
The owner re-checked the device: **the main menu is STILL garbled** — the wooden frame + UI elements are squeezed toward the center (4:3 layout) on the widescreen panel while the 3D backdrop bleeds through the sides. A prior attempt only edited `title-obs.gc` (the per-screen title-logo patch), which did NOT fix the menu. The real root cause: the Android build leaves the aspect-ratio **enum** at `'aspect4x3` because the source that derives it (`scf-get-aspect` / `sceScfGetAspect`, stubbed on Android; the settings.gc boot default) never resolves widescreen. Aspect-dependent UI (`engine/ui/progress/progress.gc::adjust-ratios`, the title logo) then takes the 4:3 branch. Fix it at the SOURCE so the enum is `'aspect16x9` (the device IS 2400x1080 widescreen) — one fix corrects the menu, the title logo, and all aspect UI.

## HARD ANTI-GRIND RULE (this is mandatory)
Do **NOT** screenrecord, record `.mp4`s, extract frame pools, or do animated screenshot phase-matching. That approach **filled the disk to 100% (66 GB)** and wasted tokens, and the owner has forbidden it. Verification here is **DATA** (the on-device aspect enum value, read from logcat) + **single static screencaps** for the owner's eye. If you create any large video/frame intermediates, the validator fails.

## Mandate
1. **Find + fix the GLOBAL aspect source.** Locate where the aspect-ratio enum is derived/defaulted: `scf-get-aspect`/`sceScfGetAspect` (PS2 BIOS, stubbed on PC/Android in C++ kmachine/kscheme), `*setting-control*`, `set-aspect-ratio`, settings.gc boot default, the PC window-size/`pc-settings` override. Make the **Android** build resolve/report `'aspect16x9`. This MUST change the aspect SOURCE (a settings/scf/kmachine file), not just `title-obs.gc`.
2. **Add a boot log marker** so the gate can verify deterministically: print the resolved enum once at boot, e.g. `fprintf(stderr, "GASPECT-DIAG aspect=%s\n", ...)` → emits `aspect=16x9` (or a `aspect-ratio ... aspect16x9` log line). The validator greps the device logcat for this.
3. **Retire the per-screen title-logo patch** in `title-obs.gc` (the global fix covers it); the logo's 16:9 placement now follows from the enum. Keep it only if removing it would regress the logo.
4. **Guard the 3D FOV** — it already renders widescreen; the enum change must NOT double-correct/warp it.
5. **Full consistent rebuild** (engine/boot-CGO change → a standalone boot-CGO push SIGILLs the device; rebuild all CGOs/DGOs) + redeploy the APK.
6. **One static menu screencap for the owner's eye:** boot, reach the menu (the input may need a real START — if injectable, use it; else capture what you can), single `adb exec-out screencap` → `.autoport/reports/Gaspect/menu-<t>.png`. NO recording/pooling.

## Rules / locks
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Leave the oracle repo + `.autoport/gold/` read-only. The `#else`/non-Android path of any gated change stays byte-identical (x86 untouched). NO video/frame-pool grind (see above).

## Validator (`phase-Gaspect-unstub.sh`, data-gated)
PASS requires: a global aspect-SOURCE change (more than title-obs.gc); the device logcat confirms the aspect enum resolves **widescreen** (16x9) and NOT 4x3 (the boot marker); no sig=11, boot sustained (frame≥300, tris>0); x86 still `link finish: logo`; no large `.mp4` intermediates + disk has headroom; a fix-summary; a single static `Gaspect/menu-*.png`. The menu/title VISUAL is OWNER-verified by eye (not gated by screenshots).

## Max settings
`max_turns: 1200`, `max_retries: 3`.

## Strategic note
The earlier attempt failed because it (a) only patched title-obs.gc, not the global source, and (b) burned the disk on animated screenshot regression matching. Fix the SOURCE (so the enum is 16:9 globally), prove it with the on-device enum DATA, and let the owner eye-confirm the menu. Cheap, deterministic, no grind.

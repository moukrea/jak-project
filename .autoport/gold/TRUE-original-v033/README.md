# TRUE PRISTINE reference build — jak1 @ upstream v0.3.3

This is an UNMODIFIED upstream `open-goal/jak-project` build at tag **v0.3.3**,
built in a fully separate clean clone — NOT inside the Android fork tree.
Use these frames as the visual ground truth for comparison.

## Provenance
- Clean clone: `/home/emeric/code/jak-original-v033`
- Tag: `v0.3.3` (commit `c4bc4d3ff`, detached HEAD)
- gk reports: `Compiled Version: v0.3.3`
- Toolchain (unmodified upstream): `cmake --preset=Release-linux-clang`
  (clang 21 + lld + Ninja), then `cmake --build build/Release/bin -j 8`.
  All deps vendored in `third-party/` + system Fedora libs (per upstream
  `docs/setup/system/linux.md`). NO source/renderer/compiler patches.
- Built: gk, goalc, decompiler, extractor (all link clean, 0 build errors).
- ISO data: read-copied from the fork's
  `/home/emeric/code/jak-project/iso_data/jak1/` (same PS2 disc).
- Asset extract: `decompiler .../jak1_config.jsonc ./iso_data ./decompiler_out
  --version ntsc_v1 --config-override '{"decompile_code":false,
  "levels_extract":true,"allowed_objects":[]}'`  (25 FR3 levels extracted).
- Game build: `goalc --user-auto --game jak1 --cmd "(mi)"`  -> 1317 targets,
  321 files in `out/jak1/iso/` (KERNEL.CGO, GAME.CGO, all CGO/DGO/TXT/STR).
- Note: the clone dir has no "jak-project" in its path and the decompiler
  binary cannot take a --proj-path override, so a `data` symlink to the repo
  root was placed next to each binary (the standard OpenGOAL data-dir
  convention). This is layout-only; no source was touched.

## Render
- Runtime: `gk -v --game jak1 --portable -- -fakeiso -debug` on `DISPLAY=:0`
  (Xwayland), `SDL_VIDEODRIVER=x11`. GPU: Mesa Intel UHD (CometLake), OpenGL
  4.6 core. Renders cleanly — full textured 3D Sandover Village, foliage,
  water, sky; "v0.3.3" watermark top-left.

## English + 2400x1080 — exactly how it was set
1. Language = English: edited the engine-generated PC settings file
   `build/Release/bin/game/OpenGOAL/jak1/settings/pc-settings.gc`:
     `(game-language 0)` `(text-language 0)` `(subtitle-language 0)`
     `(territory 0)`   ; 0 = english / SCEA(NTSC-US); default was 1 = french
   The main-menu frame confirms English ("NEW GAME / LOAD GAME / OPTIONS ...").
2. Resolution = 2400x1080: the physical monitor caps at 1920 wide, so the
   engine rejects a 2400-wide *window* ("2400x1080 is not a supported
   resolution"). The frames are instead rendered at a true internal
   2400x1080 via the engine's own internal-res screenshot path:
     - settings file set to `(window-size 2400 1080)` `(game-size 2400 1080)`
       `(aspect-state aspect16x9 2400 1080 #f)`  (20:9 widescreen).
     - at runtime, over the REPL (`(lt)`), a `screen-shot-settings` struct of
       {width 2400, height 1080, msaa 1} was registered via
       `(pc-register-screen-shot-settings ...)`, then `(pc-screen-shot)`.
   Every captured PNG is exactly 2400x1080 (the phone's target aspect),
   rendered by gk's own GL framebuffer (compositor-independent).

   Capture had to use gk's built-in screenshot because this host is
   GNOME-on-Wayland: the GNOME Shell Screenshot DBus is blocked
   ("Screenshot is not allowed") and X11 root grab returns black on the
   rootless Xwayland. gk's internal screenshot bypasses both.

## Frames (all 2400x1080, internal-res, clean)
- `01-attract-flythrough.png`        — in-engine title attract: Jak at
                                        Sandover Village (the v0.3.3 "title").
- `03-title-wait-english-subtitle.png` — title-wait state, English intro
                                        subtitle ("KEIRA: WE NEED POWER CELLS
                                        TO FUEL THE HEAT SHIELD...").
- `05-main-menu.png`                 — main title menu in ENGLISH (NEW GAME /
                                        LOAD GAME / OPTIONS / SECRETS /
                                        QUIT GAME / BACK).

Note: OpenGOAL's default jak1 flow has no separate Sony/SCE or Naughty-Dog
*movie* logo screens (those PS2 BIOS/FMV beats aren't part of the engine's
attract; skip-movies defaults on). The "title" is the in-engine attract above.
The intro renders clean — textured 3D scene over sky, no corruption.

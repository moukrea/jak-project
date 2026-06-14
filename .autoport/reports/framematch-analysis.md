# Frame-matched rendering divergence: MODIFIED fork (x86) vs TRUE original (v0.3.3)

Title attract (Sandover Village flythrough), no input, both builds configured identically:
English (`game-language 0`, `text-language 0`, `subtitle-language 0`, `territory 0`),
`aspect16x9 1920 1080`, launched `--game jak1 --portable -- -fakeiso -boot -debug`.
Screenshots are the in-engine `(pc-screen-shot)` internal-res capture (default jak1
`ScreenShotSettings {1920,1080,8,"screenshot"}`), so both are true 1920x1080 PNGs.

- ORIGINAL: `/home/emeric/code/jak-original-v033/build/Release/bin/game/gk`
- OUR FORK: `/home/emeric/code/jak-project/build-x86/game/gk`

## How frames were synced

The attract camera path + day/night cycle are deterministic functions of the GOAL
display frame counter `(-> *display* base-frame-counter)`. I drove each build's own
`goalc` over the listener (nREPL :8181 -> game DECI2 :8112), loaded the type DB with
`(asm-file "decompiler/config/jak1/all-types.gc" :no-code :no-throw)` so the typed
field read works WITHOUT relinking the game (no `(mi)`, no CGO writes), then for each
shot read `base-frame-counter` and fired `(pc-screen-shot)`, renaming the resulting
`OpenGOAL/jak1/screenshots/screenshot.png` to a frame-tagged file.

IMPORTANT sync caveat (documented honestly): `base-frame-counter` counts from kernel
boot, not from attract start, and the two builds' boot durations differ, so their
ABSOLUTE counter values do not coincide. Pairs below are therefore matched by attract
PHASE (camera pose; for the static window also blue-sky daytime). Filenames use the
ORIGINAL frame number as the shared anchor; the fork's actual frame is listed per pair.
The first four pairs sit in the long static daytime-village pose where the camera is
essentially fixed, so pose-matching is exact and any pixel delta is pure rendering.

## Matched pairs (paths under `.autoport/reports/framematch/`)

| anchor | original file (frame) | our-PC file (fork frame) | montage |
|--------|----------------------|--------------------------|---------|
| f501665 | orig-f501665.png (501665) | ourpc-f501665.png (322680) | compare-f501665.png |
| f508165 | orig-f508165.png (508165) | ourpc-f508165.png (334975) | compare-f508165.png |
| f516860 | orig-f516860.png (516860) | ourpc-f516860.png (350295) | compare-f516860.png |
| f521185 | orig-f521185.png (521185) | ourpc-f521185.png (368700) | compare-f521185.png |
| f546775 | orig-f546775.png (546775, dusk) | ourpc-f546775.png (421580, daytime) | compare-f546775.png |

(`diff-f501665.png` is an amplified absolute-difference of pair 1; it is noisy because
the static pose still has sub-pixel camera bob + animated ambient creatures, so the
near-black metric below is the reliable quantification.)

## Per-frame quantification (near-black pixel fraction)

"near-black" = fraction of pixels whose max(R,G,B) <= ~9% (i.e. effectively black).
`full` = whole 1920x1080 frame; `band` = the village-structure band (crop 1920x440+0+110)
that excludes the top debug-text line and the grass foreground.

| pair | orig full | orig band | our-PC full | our-PC band | band ratio (PC/orig) |
|------|-----------|-----------|-------------|-------------|----------------------|
| f501665 | 0.215% | 0.185% | 5.898% | 13.05% | ~70x |
| f508165 | 0.268% | 0.286% | 5.094% | 11.09% | ~39x |
| f516860 | 0.242% | 0.211% | 4.840% | 10.51% | ~50x |
| f521185 | 0.229% | 0.202% | 4.534% | 9.85%  | ~49x |
| f546775 | 0.401% | 0.432% | 4.671% | 10.01% | ~23x |

Across the entire captured sweep the fork held 4.2%-6.1% full-frame near-black on EVERY
frame, while the original stayed 0.21%-1.24% (its rise only at dusk, from natural
darkening). In the village-structure band the fork is ~10-13% black vs the original's
~0.2-0.4% — a 25-70x increase that is entirely attributable to the corrupted structures.

## Per-frame original-vs-ourPC divergence (described)

Every matched frame shows the SAME corruption signature:

- The Sandover Village man-made structures in the scene center -- the large
  thatched-roof hut, the smaller huts, the wooden dock/platform planks and the
  bird-house -- render as SOLID BLACK silhouettes on the fork. Their geometry is
  correct: outlines, shapes and screen positions match the original exactly, and they
  correctly occlude what is behind them. Only the surface is destroyed: no texture, no
  diffuse color, no lighting -- the fill is flat black.
- EVERYTHING ELSE matches the original: ground/terrain tfrag, grass, flowers, palm
  trees and foliage, the water, the sky gradient, the distant cliffs/rock walls, the
  waterfalls, Jak's character model (textured + lit), and the floating precursor ring
  are all rendered correctly with proper textures and lighting on both builds.
- Differences that are NOT bugs (sampling artifacts, called out for honesty): the
  animated ambient creature (blue bird/dragonfly) sits at a slightly different position
  per exact frame; and pair f546775's sky differs (original dusk vs fork daytime)
  because the day/night cycle and camera path are at different phases between the two
  runs. These do not affect the structural-corruption conclusion.

## Verdict

- HOW BROKEN: Our x86 PC build is broken in a specific, consistent, geometry-selective
  way -- NOT a general/global rendering failure. ~95% of the scene (terrain, foliage,
  water, sky, character, props) is pixel-faithful to the pristine original. The breakage
  is confined to a class of world structures that come out fully black, inflating the
  village-band near-black pixel fraction by 25-70x versus the original.
- WHICH CATEGORIES ARE CORRUPTED: the affected objects are the village's built
  structures (huts/buildings/platforms) -- i.e. instanced level model geometry
  (TIE/tfrag-class drawables), NOT the ground tfrag, NOT actors/skeletal models (Jak is
  fine), NOT textures globally (all other textured surfaces are correct), NOT lighting
  globally (the rest of the scene is lit correctly), NOT the sky/ocean. The corruption
  is "shape correct, surface black": vertex/transform/clip/raster is intact, but the
  per-fragment output for these draws collapses to black.
- BEST-GUESS LAYER: a "correct silhouette, black fill" failure on one draw class points
  at the per-vertex/per-fragment color OR texture-coordinate/material data feeding those
  specific buckets, rather than at vertex positions. Because positions, occlusion and
  every OTHER textured bucket are correct, the renderer C++ texture/material binding for
  the general path is working; the likely culprit is goalc CODEGEN producing wrong data
  for the GOAL routine that builds the DMA/draw data for those structure buckets
  (e.g. a miscompiled color/uv/material computation, or a bad pointer/value feeding the
  bucket), which then makes the renderer draw correctly-shaped but black-shaded geometry.
  A renderer-C++ regression specific to one bucket type is the secondary hypothesis. The
  fix investigation should start at the GOAL code that emits the affected structure
  bucket (TIE/instanced geometry) and the codegen for its color/material path.

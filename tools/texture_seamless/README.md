# Texture seamlessness

Unpacks every texture from the game ISO keeping the tpage hierarchy, then
answers, per texture: **is it meant to repeat** — horizontally, vertically,
both, or neither — **how many times**, **what object is it painted on**, and
**what does it depict**.

```sh
tools/texture_seamless/extract_textures.sh   jak1   # PNGs      -> extracted_textures/jak1/<tpage>/<name>.png
tools/texture_seamless/extract_draw_modes.sh jak1   # engine    -> extracted_textures/jak1-draw-modes/

python3 tools/texture_seamless/analyze.py extracted_textures/jak1 \
    -o extracted_textures/jak1-seamless.csv          # image estimate

python3 tools/texture_seamless/engine_truth.py \
    extracted_textures/jak1-draw-modes extracted_textures/jak1-seamless.csv \
    -o extracted_textures/jak1-tiling.csv            # engine truth, merged

python3 tools/texture_seamless/describe.py extracted_textures/jak1 \
    --tiling extracted_textures/jak1-tiling.csv \
    --draw-modes extracted_textures/jak1-draw-modes \
    -o extracted_textures/jak1-textures.csv --vision # + what it depicts
```

`calibrate.py` re-fits and re-checks the image thresholds.

## Where the answer comes from

**The engine knows.** The GS sets `clamp_s` / `clamp_t` per draw, and `clamp = 0`
*is* the game declaring that it wraps that texture on that axis. That covers
3517 of the 4002 textures — everything drawn through the level pipeline. The
remaining 485 (HUD, fonts, sprite banks) never reach it and fall back to the
image estimate; the `source` column says which you are looking at.

The REPEAT bit alone is not enough: a draw can be in REPEAT mode with UVs that
never leave `[0, 1]`, in which case no wrap boundary is ever sampled. So the
dump also carries the **UV range of each draw**, and the verdict asks whether
that range actually crosses an integer boundary in its interior. The difference
is not small — 2113 textures have the REPEAT bit set on both axes, but only 927
ever put both seams on screen:

| verdict | REPEAT bit set | seam actually drawn | image estimate |
| --- | --- | --- | --- |
| both | 2113 (60.1 %) | **927 (26.4 %)** | 1118 (31.8 %) |
| horizontal | 522 (14.8 %) | **651 (18.5 %)** | 819 (23.3 %) |
| vertical | 196 (5.6 %) | **361 (10.3 %)** | 480 (13.6 %) |
| none | 686 (19.5 %) | **1578 (44.9 %)** | 1100 (31.3 %) |

A draw running exactly `0..1` deliberately does not count — it shows the
texture once. Without that epsilon every character eye in the game comes back
tiling.

`max_tiles_h/v` gives the largest UV span any single draw asks for (up to 15×15
for `pal-environment-front`), and `draws_tiled_h/v` how many draws out of
`n_draws` actually cross. That separates `vil-wallplaster` (6 of 6 draws cross,
up to 12×6) from `bab-eye` (1 of 3, span 1.00) — a genuine tiling wall from a
marginal UV offset on an eye.

### What it cost in the decompiler

Four files, all additive and off by default:

* `config.h` / `config.cpp` — a `dump_draw_modes` flag.
* `extract_level.cpp` — one function walking the finished `tfrag3::Level`,
  emitting a row per draw (tfrag, tie, tie-wind, shrub, merc, hfrag) with the
  bound texture, the wrap bits, the UV range, and the owning object's name.
  Shrub UVs are divided by 4096 here because `shrub.vert:137` does the same —
  raw, they read as spans of 4097.
* `extract_tie.cpp` — a `TIE_PROTO_NAMES` env var. jak1 normally carries
  neither `proto_names` nor `tie_proto_idx` (the name "exists here and nowhere
  downstream", as the file's own `TIE_CENSUS` comment puts it), which left every
  tie-only texture with no idea what it is painted on. Setting it records both
  *without* enabling `has_per_proto_visibility_toggle`, so the renderer path is
  untouched; owner coverage goes from 73.8 % to **91.0 %**.

`extract_draw_modes.sh` runs all of this against a **shadow project directory** —
a tree of symlinks to the repo with its own `out/`, found by dropping a `data`
directory next to a *copy* of the binary (`file_util::try_get_data_dir`; a
symlink would not do, because `/proc/self/exe` resolves it back to the real build
tree). The real `out/<game>/fr3` is never opened, so this is safe to run while a
`gk` is playing.

## The image estimate, and how far off it is

Where the engine has no answer the image estimate stands, so it is still worth
having — but measured against the engine on the 3517 textures where both exist,
it agrees on the full class **48.7 %** of the time (65 % per axis). That is the
honest size of the gap between "this image could tile" and "the game tiles it".

"Does this image show a seam when tiled" and "is this texture meant to repeat"
are not the same question, and the difference is not academic: 674 of 4002
textures answer yes to the first and no to the second. An eye sprite sitting on
a flat surround has no discontinuity at its wrap — because nothing reaches the
wrap. So the image verdict needs both halves:

1. **the wrap must not show a step** — the seam test below;
2. **content must actually reach the wrap** — the border test below.

## How the image verdict is reached

A seam is visible when the wrap boundary introduces a discontinuity **unlike
the ones already present everywhere else in the image**. So the test is never
"does the left column equal the right column" — a tiling texture must
*continue*, not repeat.

Per axis, with lines being columns (horizontal) or rows (vertical):

| symbol | meaning |
| --- | --- |
| `e_k` | mean abs step between adjacent interior lines `k`, `k+1` |
| `e_seam` | mean abs step across the wrap, between the last line and the first |
| `ratio` | `e_seam / median(e_k)` — how many times rougher the seam is than a typical step |
| `rank` | fraction of interior steps at least as rough as the seam |

```
seamless  <=>  e_seam <= 0.008   or   ratio <= 1.3   or   rank >= 0.10
```

Both statistics are needed, because each alone has a failure the other covers:

* **ratio alone** rejects a legitimate 8-pixel checkerboard. Most interior
  steps are 0 (inside a tile), so the median is 0 and a perfectly normal tile
  edge landing on the wrap scores an infinite ratio. Its rank is 0.14, which
  is what says the wrap is just another tile edge.
* **rank alone** rejects a nearly flat image, where the seam is the largest
  step in the image (rank 0) while being only 1.05× a typical one.

The rank reference **ignores the 20 % of boundaries nearest each border**.
Those are the seam's own neighbourhood: a texture with a bright frame or a ramp
running into its edge produces both the mismatched wrap *and* the steep steps
beside it, so counting them lets the artefact acquit itself. Measured on jak1's
eight sky textures (a blob inside a bright frame), the untrimmed rank called 4
of 8 seamless at rank 0.26–0.32; trimming drops all eight to 0.00 while the
checkerboard keeps 0.14 and a mortar grid 0.16, because those repeat across the
whole image instead of hugging its border.

Channels are premultiplied RGB plus alpha, so RGB garbage under transparent
pixels cannot fabricate a seam. PS2 alpha is 0..128 and is normalised as such.

### The border test

Per line (column for horizontal, row for vertical) we measure how much that
line varies *along itself*, and compare the two border lines against a typical
one:

```
border_activity = mean(activity of first line, activity of last line) / median(activity)
```

A texture meant to repeat has structure running through its border, so this
sits near 1.0. A sprite matted into a flat or transparent surround has dead
border lines, so it sits near 0. The verdict requires `border_activity >= 0.35`
on top of a clean seam.

**This statistic does not separate cleanly, and the report says so.** Its
distribution over jak1 is bimodal — a spike of 485 verdicts below 0.05 and a
mode peaking at 1.0 — but roughly 14 % land in the valley between, where
`vil-hut-roof-tile-01` (0.27) is indistinguishable from `bab-eye` (0.28). Any
verdict decided inside `[0.05, 0.55]` is flagged `border-marginal-{h,v}` and
downgraded to `confidence = low` rather than presented as clean. This is the
band where the clamp bits would settle it and image statistics cannot.

Box-downsampling before measuring (scales 2, 4, 8) was tried, on the theory
that pixel noise can hide a low-frequency mismatch across the wrap. The
measurement refutes it: on a periodic image tilted by a non-periodic ramp of 16
levels, scale 1 catches 36/40 where scale 8 catches 29/40, and adding coarse
scales to the verdict only cost true positives. `scales` stays configurable so
that measurement can be reproduced; the default is scale 1 alone.

## Where the thresholds come from

There are no human labels for 4002 game textures, so `calibrate.py` manufactures
ground truth and fits against it:

* **Positive, provably seamless** — random-phase spectral synthesis of a real
  texture: keep `|FFT|`, replace the phase with that of a random real image.
  The inverse FFT of a finite spectrum is *exactly* periodic, so it tiles
  perfectly while keeping the source's real mix of low-frequency structure and
  pixel noise. 8-bit quantisation afterwards is pointwise and preserves
  periodicity exactly.
* **Negative, provably seamed** — the same synthesis at width `W+c`, cropped to
  `W`. The wrap now joins two lines that were `c` apart in the periodic image,
  so the mismatch has exactly the magnitude that texture's own autocorrelation
  gives at lag `c`. Sweeping `c` gives a difficulty ladder, and the *other*
  axis of those same images stays a positive.
* Plus the realistic hard negative: half of texture A glued to half of B.

At the shipped thresholds, over 788 labelled axis decisions:

| | |
| --- | --- |
| exactly-periodic positives kept | 463/487 (TPR 0.951) |
| provably-seamed negatives caught | 271/301 (TNR 0.900) |
| unrelated halves glued together | 60/60 |
| recall at crop lag c=1 / c=8 / c=32 | 0.70 / 0.97 / 0.93 |

The shipped values are the argmax of the sweep. `calibrate.py` also runs a
15-case regression suite that must pass at any threshold shipped — checkerboard
and mortar grid (hard-edged and exactly tiling, the reason the rank test
exists), the eight sky textures (the reason the rank test trims a border
margin), a random-phase positive, and that same positive matted into 2 px and
6 px flat and transparent surrounds (the reason the border test exists; the
seam test alone scores them rank 1.00 and calls them seamless). It exits
non-zero if one breaks.

## Checking the output

* `analyze.py --contact-sheet sheet.png` renders a random sample per verdict,
  each cell tiled 2×2, one row per class — seams show up immediately.
* `analyze.py --verify-invariance N` re-classifies N textures called seamless
  after a random roll. Rolling only moves *which* line the wrap falls on, and
  every line of a tiling texture is an equally valid wrap point, so a
  disagreement is the detector contradicting itself on the same image. It sits
  near 13 %, consistent with the measured TPR of 0.951 on both draws. The
  converse is not a defect and is not tested: rolling a *seamed* texture moves
  its discontinuity into the interior and genuinely leaves a clean wrap.

## What each texture depicts

`describe.py` answers "what is this a picture of" from two sources.

**The code**, free and exact: the asset name, the tpage (level + category —
tfrag is level background, pris is characters and animated props, shrub is
foliage, alpha is transparent effects), the merc model / tie prototype / shrub
prototype it is painted on, the levels it appears in, whether it is opaque, an
alpha cutout or blended, and its tiling. That already yields lines like

```
yeti-peltbellyfur; 64x64; characters and animated props; level 'snow';
    painted on yeti-lod0; drawn as merc; tiles horizontally only
vil-hut-wood-01; 128x128; level background geometry; level 'village1';
    painted on vil1-roofsupport.mb, thick.mb, vil1-hut-door.mb; drawn as tie
```

**Vision**, for what the name cannot say — material, colour, motif. Textures go
out in labelled contact sheets of 16 rather than one request per texture,
because the per-request overhead dwarfs a 128×128 image, and the sheet is drawn
on a grey checkerboard with PS2 alpha (0..128) stretched to 0..255, so
transparency reads as transparency instead of as black. The code context for
each cell rides along in the prompt, with instructions to trust the image where
they disagree. Each sheet's answer is cached as JSON next to it, so a rerun
resumes instead of repeating.

## Report columns

`jak1-textures.csv` (the merged end product): `path, tpage, name, width, height,
verdict, source, max_tiles_h, max_tiles_v, draw_kinds, owners, levels,
description, code_context`.

`jak1-tiling.csv` adds the raw engine and image columns side by side:
`repeats_{h,v}, draws_tiled_{h,v}, n_draws, engine_repeat_{h,v},
engine_tiled_{h,v}, image_class, image_seamless_{h,v}, image_confidence,
image_flags`.

`jak1-seamless.csv` is the image analysis alone: `class, seamless_h, seamless_v,
confidence, flags, {h,v}_step, {h,v}_typical_step, {h,v}_ratio, {h,v}_rank,
{h,v}_reason`. `confidence` is `low` below 8 pixels on an axis (7 interior
boundaries is not a distribution) and `medium` below 16. `flags` carries
`constant`, `fully-transparent` and `transparent-border-{h,v}` — a texture whose
border is entirely transparent tiles trivially, which is true but rarely what
you meant.

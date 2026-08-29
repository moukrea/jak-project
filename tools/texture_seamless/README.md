# Texture seamlessness

Unpacks every texture from the game ISO keeping the tpage hierarchy, then
decides per texture whether it tiles without a visible seam **horizontally**,
**vertically**, **both** or **neither**.

```sh
tools/texture_seamless/extract_textures.sh jak1        # -> extracted_textures/jak1/<tpage>/<name>.png
python3 tools/texture_seamless/analyze.py extracted_textures/jak1 \
    -o extracted_textures/jak1-seamless.csv --json extracted_textures/jak1-seamless.json
python3 tools/texture_seamless/calibrate.py extracted_textures/jak1   # re-fit / re-check thresholds
```

The dump layout is `<tpage>/<texture>.png` — the same layout
`custom_assets/<game>/texture_replacements/` expects, so the `path` column of
the report drops straight into a replacement folder.

## How the verdict is reached

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
regression suite (checkerboard, mortar grid, the eight sky textures) that must
pass at any threshold shipped; it exits non-zero if one breaks.

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

## Report columns

`path, tpage, name, width, height, class, seamless_h, seamless_v, confidence,
flags, {h,v}_step, {h,v}_typical_step, {h,v}_ratio, {h,v}_rank, {h,v}_reason`

`confidence` is `low` below 8 pixels on an axis (7 interior boundaries is not a
distribution) and `medium` below 16. `flags` carries `constant`,
`fully-transparent` and `transparent-border-{h,v}` — a texture whose border is
entirely transparent tiles trivially, which is true but rarely what you meant.

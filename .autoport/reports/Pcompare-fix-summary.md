# Phase Pcompare — objective pixel-compare gate (golden capture + diff tool)

**Ships NO game fix.** This phase builds the *measuring stick* every subsequent
intro/title phase gates on: an automated, objective pixel-match of an Android
device frame against the pristine upstream desktop ("oracle") build, beat by
beat. It delivers tooling (`.autoport/lib/`) + reference data
(`.autoport/gold/pristine-frames/`) + self-test evidence (`.autoport/reports/Pcompare/`).

Motivation (owner, 2026-06-14): the supervisor's *visual* judgment proved
unreliable — the intro was twice declared "fixed" off a couple of correct
frames while the actual animated Naughty-Dog-logo beat was still broken. So the
number-one validation rule becomes an automated gate, not eyeballing.

---

## 1. Golden capture method (oracle build)

**Oracle:** `/home/emeric/code/jak-original-v033` — clean upstream open-goal/jak-project
@ tag v0.3.3, HEAD `c4bc4d3ff`. Pre-built `build/Release/bin/game/gk`.

**Temporary hook (added, then REVERTED).** A small env-gated auto-screenshot
block was inserted into the oracle's `game/graphics/pipelines/opengl.cpp`, in
`GLDisplay::render()` immediately before the `render_game_frame(...)` call. It
reused the build's existing screenshot system (`g_want_screenshot` +
`g_screen_shot_settings` + `OpenGLRenderer::finish_screenshot()` →
`file_util::write_rgba_png`). Each target frame it set the requested
width/height/msaa + a deterministic filename (`autoport_f<NNNNNN>`) and raised
`g_want_screenshot`. The hook is **env-gated** (does nothing unless the env
vars are set) and was **reverted** with `git -C <oracle> checkout -- .` — the
oracle is back to a clean tree at `c4bc4d3ff` (verified by the validator).

Hook env vars:
- `AUTOPORT_SHOT_EVERY=N` — dump every N frames (enables the hook)
- `AUTOPORT_SHOT_START` / `AUTOPORT_SHOT_STOP` — frame-index window
- `AUTOPORT_SHOT_W` / `AUTOPORT_SHOT_H` / `AUTOPORT_SHOT_MSAA` — capture resolution

**Frame anchor = `g_gfx_data->frame_idx`** — a `u64` monotonic from boot,
incremented once per displayed frame at the end of `render()`. This is the
deterministic event anchor (NOT wall-clock). Because the engine is vsync-locked
to graphics-frame completion, screenshot overhead does not desync the
frame↔game-state mapping on the oracle.

**Run (real GPU on Xwayland :0):**
```
cd /home/emeric/code/jak-original-v033
ninja -C build/Release/bin gk          # incremental: recompiles opengl.cpp + relinks
XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 DISPLAY=:0 SDL_VIDEODRIVER=x11 \
AUTOPORT_SHOT_EVERY=10 AUTOPORT_SHOT_START=0 AUTOPORT_SHOT_STOP=4000 \
AUTOPORT_SHOT_W=1280 AUTOPORT_SHOT_H=720 AUTOPORT_SHOT_MSAA=1 \
timeout 220 ./build/Release/bin/game/gk --game jak1 --portable -fakeiso -iso-data out/jak1/iso -- -boot
```
Ran on `Mesa Intel(R) UHD Graphics` (OpenGL 4.6) — no software-Mesa fallback
needed. PNGs landed in `build/Release/bin/game/OpenGOAL/jak1/screenshots/`
(`get_user_screenshots_dir(jak1)`). 394 frames captured at stride 10
(f70→f4000); capture begins at f70 once the GL read path is ready.

### Selected golden beats (the deterministic frame anchors)

| golden file (in `.autoport/gold/pristine-frames/`) | frame_idx | beat |
|---|---|---|
| `intro-ndlogo-enter-f000400.png`  | 400  | Naughty Dog logo mid-animation: Daxter + "NAUGHTY DOG" box sliding in (on black) |
| `intro-ndlogo-full-f000630.png`   | 630  | Naughty Dog logo full: paw logo + Jak & Daxter (on black) — the beat prior phases mis-declared fixed |
| `intro-logo-reveal-f001110.png`   | 1110 | JAK & DAXTER logo light-burst reveal (transition out of black) |
| `title-pressstart-f001590.png`    | 1590 | Title screen: "JAK AND DAXTER / PRESS START" over Sandover village |

These start with the **on-black** intro beats (load-independent, cleanest to
match) and add the title screen. All are 1280×720, all > 20 KB (non-trivial).

> Note on device anchoring: the oracle anchor is `frame_idx`, but the phone's
> slow loader desyncs both wall-clock and frame counts. On-device, later phases
> anchor by **event** (a logged state transition / a fixed wait after a known
> marker) and then call the device-capture helper to snapshot + compare. The
> on-black beats are the most robust because they are load-independent.

---

## 2. Compare tool — `.autoport/lib/frame_compare.py` (PIL, no numpy)

```
python3 .autoport/lib/frame_compare.py GOLDEN CANDIDATE \
        [--tolerance F] [--threshold N] [--diff OUT.png] [--no-diff] [--quiet]
```

- **Normalize:** resize the candidate to the golden's resolution (LANCZOS), so
  a device screencap at a different resolution is normalized, not penalized.
  Both images are flattened to RGB first (goldens carry alpha — see caveat).
- **Metric (primary):** `diff_frac` = fraction of pixels whose **per-channel
  max delta** exceeds `--threshold` (default **24**/255). `MATCH` iff
  `diff_frac <= --tolerance` (default **0.02** = 2 %), else `MISMATCH`.
- **Metric (secondary, reported):** RMSE over all channels.
- **Diff image:** ALWAYS written (best-effort, red where pixels differ) for the
  supervisor to eyeball. Writing the diff can **never** flip the verdict — it is
  wrapped and falls back to a temp path if the candidate dir is unwritable.
- **Exit code:** `0` = MATCH, `1` = MISMATCH (also `1` on a load error,
  `2` on a usage/PIL error). The verdict depends only on the metric.

**Why tolerant, not exact:** desktop GL goldens vs the phone's Adreno GLES will
never be byte-identical (sub-pixel rasterization, different resolution). The
threshold+tolerance are tuned to flag anything a human would see (missing
geometry, logo-over-village, wrong color/lighting) while ignoring sub-pixel
noise. Defaults are deliberately set so the bare two-arg form already
distinguishes identical (MATCH) from clearly-different (MISMATCH).

---

## 3. Self-test (evidence: `.autoport/reports/Pcompare/selftest.txt`)

Verified with the tool itself (diff images in `.autoport/reports/Pcompare/diffs/`):
- **identical** (golden vs itself) → MATCH, `diff_frac=0.00000`, exit 0.
- **golden vs black** (all 4 goldens, black synthesized at golden dims) →
  MISMATCH, exit 1. Even the sparsest on-black logo beat scores 0.042 > 0.02,
  so the gate is sensitive regardless of which golden sorts first.
- **two different goldens** → MISMATCH, exit 1. Notably, the two frames of the
  *same* animated ND logo (enter vs full) score `diff_frac=0.085` → MISMATCH:
  the gate catches exactly the animated-logo difference that eyeballing missed.

The phase validator independently re-runs the identical→exit-0 and
golden-vs-black→nonzero checks on a captured golden, so the gate is proven, not
just asserted.

---

## 4. Device-capture helper — `.autoport/lib/capture_device_beat.sh`

```
capture_device_beat.sh OUT.png [GOLDEN.png] [-- <extra frame_compare args>]
```
Hard-pinned to `ANDROID_SERIAL=eae4df44` (the Redmi is shared with a parallel
x86 emulator — it refuses any other serial), uses
`/home/emeric/Android/platform-tools/adb`, **verifies `mCurrentFocus`/`mFocusedApp`
is `org.opengoal.gk.jak1`** before capturing (so a stray frame of the other
project's app can't poison a result), screencaps via `adb exec-out screencap -p`
(byte-exact), and — if a golden is given — runs `frame_compare.py` and
propagates its MATCH/MISMATCH exit code. The per-beat trigger (driving gk to a
given beat) lives in each downstream phase's runner; this script is the
capture+compare primitive.

---

## 5. How later phases use this gate

For each chronological intro/title beat: drive the device to the beat (event
anchor), `capture_device_beat.sh <out> .autoport/gold/pristine-frames/<beat>.png`,
and require MATCH. A previously-matched beat that later returns MISMATCH is a
regression and fails the phase. The diff image is always available for review.

---

## Files

- `.autoport/lib/frame_compare.py` — the diff gate
- `.autoport/lib/capture_device_beat.sh` — device snapshot + gate helper
- `.autoport/gold/pristine-frames/*.png` — 4 golden beats (frame anchors above)
- `.autoport/reports/Pcompare/selftest.txt` — self-test results
- `.autoport/reports/Pcompare/diffs/*.png` — self-test diff images
- Oracle hook: reverted; `/home/emeric/code/jak-original-v033` clean at `c4bc4d3ff`

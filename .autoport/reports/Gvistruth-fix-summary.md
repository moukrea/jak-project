# Gvistruth — a TRUSTWORTHY programmatic visual-quality gate vs the v0.3.3 original

**Goal:** so the owner never has to watch. The gate must FLAG the defects the
owner sees (menu garble, ND-logo/title halo) and must NOT false-FAIL a clean
render. This corrects a real false-green (2026-06-19): `Gmatch-original` reported
PASS on liveness (no-crash + in-game) while the SAME report measured main-menu
57% / title 75% oracle pixel-divergence (ungated) AND a halo metric reading 0.0
on a visibly haloed ND logo. The framework MEASURED the defects and threw the
data away. Liveness is NOT quality.

------------------------------------------------------------------------------
## 1. What the gate now does (the metrics)

`graphics_analyze.py` is the SINGLE SOURCE OF TRUTH — the same code runs live
inside `verify_device_graphics.sh` AND offline to regenerate the calibration
report. For each beat it compares the CURRENT device build to the matched-aspect
v0.3.3 oracle (2400x1080 = device aspect 2.222, commit c4bc4d3ff) and emits:

- **Oracle pixel-diff** (`frame_compare.py`): fraction of pixels whose per-channel
  delta exceeds `--threshold`, after masking the phone's on-screen touch overlay
  (the desktop oracle lacks it). MATCH if `diff_frac <= tolerance`, else MISMATCH.
- **Localized halo/bloom** (`halo_excess_frac`): fraction of valid (unmasked)
  pixels that are BRIGHT on the device (grayscale luma >= 220) but NOT bright in
  the oracle — i.e. a bright blob present on the phone and absent in the original.
  This is the ND-logo "sun-glow" halo the owner reported.

The STANDING GATE verdict (`overall_verdict`) = **FAIL** if ANY of:
  - a hard static-beat (intro-logo / main-menu) MISMATCHes the oracle pixel-diff,
  - ANY beat's `halo_excess_frac` exceeds `--halo-gate`,
  - `crash_signatures > 0` (now `sig=(4|6|11)` = SIGILL/SIGABRT/SIGSEGV; the old
    `sig=11`-only grep missed SIGILL/SIGABRT — see memory gmatch-pass).
Otherwise PASS. Beats with no oracle / not reached are REPORTED, never graded as
"fine". `verify_device_graphics.sh` exits nonzero on FAIL so any caller (a phase
validator, CI) inherits the strictness automatically.

------------------------------------------------------------------------------
## 2. Why the OLD halo metric read 0.0 on a visibly haloed logo (the root cause)

The halo math was correct; the **frame fed to it was wrong**. The intro-logo
device frame was selected by `pick_best_frame.py`, which picks the burst frame
that MINIMISES the global pixel-diff against the mostly-black ND-logo oracle.

Measured over the real intro burst (`device-shots/introburst/f000..f022`):

| frame | bright_frac(>=220) | halo_excess | logo_overlap | globalDiff@24 |
|-------|--------------------|-------------|--------------|---------------|
| f000 (ALL BLACK) | 0.000 | **0.000** | 0.000 | **0.059 (min!)** |
| f008 | 0.319 | 0.288 | 0.849 | 0.476 |
| f009 | 0.320 | 0.290 | 0.820 | 0.478 |
| f012 | 0.308 | 0.276 | **0.855** | 0.463 |

The ALL-BLACK loader frame (f000) has the LOWEST global diff (0.059) to a
mostly-black oracle, so min-diff selection chose it. A black frame has zero
bright pixels, so `halo_excess = 0.0` — a TRUE measurement of the WRONG frame.
The halo (a huge yellow sun-glow blob next to the "NAUGHTY DOG" logo) lives in
f008..f012, which the selector rejected because the bright halo makes them
diverge MORE from the black oracle.

**The fix:** select the intro-logo frame by **LOGO-STRUCTURE overlap** — the
frame whose bright pixels best COVER the oracle's bright ND-logo text
(`logo_overlap`), requiring overlap >= 0.30 (rejects black frames, which score
0). This guarantees the ND logo is present, THEN grades the halo on that frame.
The selector now lands on f012 (overlap 0.855) and the halo reads **0.276**.

------------------------------------------------------------------------------
## 3. Chosen thresholds + calibration evidence

- **Pixel-diff:** `--threshold 56`, `--tolerance 0.02` (live harness). The clean
  cross-renderer floor (GLES device vs GL oracle, matched phase) is ~2-5%
  (see memory project-pcompare-gate / feedback-pixel-gate-cross-renderer-floor);
  oracle-vs-oracle is exactly 0.000. The current garble is 0.43 (intro-logo),
  0.575 (main-menu), 0.75 (title) — a 10-30x separation from the clean floor.
  The validator independently re-checks at `--threshold 24` (known-bad must be
  > 0.15, oracle-vs-oracle must be < 0.02); both pass with wide margin
  (known-bad main-menu = 0.864, oracle-vs-oracle = 0.000).

- **Halo:** `BRIGHT = 220` luma, `--halo-gate 0.02`, `halo_present` at 0.04.
  Calibration separation: a CLEAN device (Gndlogo-fixed) reads ~0.002 excess on
  the ndi beat (residual f022 = 0.00176); the current defective device reads
  **0.276** on the selected logo frame. That is a ~140x separation, so the 0.02
  gate sits comfortably between clean and defect. The validator requires the
  report's `intro-logo` (or title) `halo_excess_frac > 0.01`; ours is 0.276.

------------------------------------------------------------------------------
## 4. Anti-false-green proof (the two self-tests that make it trustworthy)

- **Catches the owner's defects (known-bad):**
  `.autoport/reports/graphics-verify/known-bad/report.json` is the hardened gate
  run on the CURRENT build's genuine frames (captured 2026-06-19 01:05, the build
  the owner saw). It records `overall_verdict=FAIL`, `main-menu=MISMATCH`,
  `intro-logo halo_excess=0.276 (present=true)`. Diff images localise WHERE it
  diverges (`known-bad/main-menu.diff.png`, `known-bad/intro-logo.diff.png`).
  Independent re-check: `frame_compare.py oracle main-menu --threshold 24` = 0.864.

- **Does NOT false-FAIL a clean render (oracle-vs-oracle):**
  `.autoport/reports/graphics-verify/self-test/report.json` feeds the oracle
  frames AS the device frames. Result: all three static beats MATCH (diff 0.000),
  halo 0.000, `overall_verdict=PASS`. No false-FAIL.

------------------------------------------------------------------------------
## 5. Per-beat HONEST current-state verdict (what the owner is looking at)

- **intro-logo (ND logo on black):** MISMATCH + HALO. diff_frac 0.434, and a
  large yellow sun-glow blob (halo_excess 0.276) absent in the original. Matches
  the owner's "halo on the ND logo". FLAGGED.
- **title-pressstart:** MISMATCH (diff 0.75). NOTE/CAVEAT: the existing title
  oracle is a mid-attract flythrough frame (Jak standing in the village), NOT the
  settled "JAK AND DAXTER / PRESS START" card the device shows, so the pixel-diff
  is partly beat-misalignment. To avoid baking a false-FAIL into the standing
  gate, title pixel-diff is treated as ADVISORY (reported, not a hard FAIL); its
  halo is still gated. FOLLOW-UP: recapture a true PRESS START oracle, then make
  title a hard gate. The owner's title-halo concern is acknowledged here.
- **main-menu:** MISMATCH (diff 0.575) — the garbled/bunched menu the owner sees
  (see memory gmenu-ui-placement-state, an arm64 HUD-projection issue). FLAGGED.
- **newgame-cinematic:** device reaches it; verdict NO_ORACLE (honest — no oracle
  reference, see section 6). NOT implied "fine".
- **ingame-firstframe:** device reaches it; verdict NO_ORACLE (honest — see
  section 6). NOT implied "fine".

------------------------------------------------------------------------------
## 6. Cinematic + in-game oracle: cannot be captured on this host (documented)

I attempted to solve the `capture_oracle_beats.sh` TODO via the goalc listener
route (`.autoport/lib/capture_oracle_cine.sh`): the menu's NEW GAME action is
literally `(initialize! *game-info* 'game (the-as game-save #f) "intro-start")`,
so a goalc `(lt)` connection could trigger the intro cinematic with no menu input.

It is BLOCKED with hard evidence:
- **newgame-cinematic CANNOT be captured here:** the original v0.3.3 gk's DECI2
  listener (port 8112) NEVER binds in `-boot` retail-portable mode. Polling for
  70s shows no 8112 listener ever; the gk log is stuck at "[DECI2] Waiting for EE
  to register protos" (`wait_for_protos_ready()` never returns, so `init_server()`
  never binds). goalc `(lt)` returns `[Listener] Failed to connect`, so
  `*game-info*` cannot be resolved and the new-game form errors.
- **ingame-firstframe CANNOT be captured here:** same listener blocker; and the
  fallback menu-input route is impossible too — `xdotool`, `wmctrl`, and
  `ydotool` are all absent on this Wayland session, the original's saved
  input-settings remaps START off ENTER, and EWMH/uinput keys do not route to
  the gk window (prior-phase finding). No pre-captured original cinematic/in-game
  frame exists in any gold dir.
- Modifying the original to register protos or auto-start a new game would
  violate the "UNTOUCHED v0.3.3 original" constraint, so it is NOT done.

These two beats are therefore reported as NO_ORACLE (unmeasurable here) rather
than silently implied fine. The device verifier still drives the DEVICE through
them and reports how far it gets. When a host with a working listener or input
tool is available, `capture_oracle_cine.sh` will capture them directly.

------------------------------------------------------------------------------
## 7. Files changed
- `.autoport/lib/graphics_analyze.py` (NEW) — source-of-truth analyzer: logo-
  structure frame selection, oracle pixel-diff, halo metric, standing-gate verdict.
- `.autoport/lib/verify_device_graphics.sh` — crash regex `sig=11` -> `sig=(4|6|11)`;
  intro-logo selection moved from min-diff `pick_best_frame.py` to the analyzer's
  logo-overlap selection; inline analysis replaced by the analyzer call; static-
  beat + halo gating wired into `overall_verdict`; exits nonzero on FAIL.
- `.autoport/lib/capture_oracle_cine.sh` (NEW) — the goalc-listener cinematic
  capture route + the documented listener blocker.
- `.autoport/reports/graphics-verify/known-bad/` — calibration baseline (gate
  FAILS on the owner's defects) + `report.json`.
- `.autoport/reports/graphics-verify/self-test/` — oracle-vs-oracle (gate PASSES
  a clean render, no false-FAIL) + `report.json`.

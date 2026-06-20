# Grender-audit — ranked render-divergence map (device vs x86, deterministic, x86-first)

**Phase:** Grender-audit (DIAGNOSTIC only — no code fix). **Date:** 2026-06-20.
**Device:** Redmi Note 9 Pro `eae4df44`, arm64, `org.opengoal.gk.jak1`. **x86 ref:** `build-x86/game/gk`, same source HEAD.
**Method:** temporary, env/property-gated C++ dumps (`game/graphics/grender_audit.h`) reading the `*display*` game-clock
counters by symbol+offset and per-bucket triangle counts from the profiler, identical on both backends. Captured at the
**title attract** beat (Sandover vista + village flythrough + sun). Instrumentation removed after capture; the golden
`jak-original-v033` was never touched. NO screenshots, NO video. Raw dumps listed at the bottom.

> **Headline correction (the data overturns the phase premise).** The owner's "the game runs at ~HALF SPEED" is **NOT a
> broken game-logic clock**. The deterministic dump proves the device game-clock (`base-frame-counter`) advances at
> **real-time** — the engine's `time-ratio` catch-up works perfectly (it rises to 3.0–4.0 when fps drops, keeping
> `base==real==gamec`). The genuine divergence is **render throughput**: the Adreno 618 cannot sustain 60 fps on heavy
> content (village flythrough = 536k tris / 646 draw-calls per frame → ~20 fps; the new-game cutscene → ~16 fps), while
> x86 holds a flat 60 fps. The "**fluid but 2× time**" the owner sees is the **cutscene**, whose timeline is paced by the
> per-vsync IOP/overlord vblank (not by wall-clock), so it runs in slow-motion-but-fluid whenever the render rate drops.

---

## D1 — "Half speed" → render-throughput limit + vsync-paced cutscene clock  (SEVERITY: HIGH; owner's #1 complaint)

### Measured game-clock rate, device vs x86 (steady title-attract beat)

| metric | x86 (`build-x86`) | device (arm64) | note |
|---|---|---|---|
| game-clock `base-frame-counter` rate | **300.5 ticks/sec** | **~300 ticks/sec light / 339–355 under load** | both ≈ real-time (5 ticks × 60 fps target) |
| `base == real == gamec`? | yes (every sample) | **yes (every sample)** | the logic clock is internally consistent on arm64 |
| `time-ratio` (tr) | **1.000** (flat) | **1.0 → 3.0** (rises under load) | catch-up compensation WORKS |
| `time-adjust-ratio` (tar) | 1.000 | 1.0 → 3.0 | physics dt scales with tr |
| engine `frames-per-second` | **60.00** (flat) | **60 → 20** (drops under load) | the real divergence |
| display swap rate | **59.9 swaps/sec** | **~20–43 swaps/sec under load** | Adreno can't keep up |
| heavy frame cost (A35-RENDER) | n/a (60 fps) | **534k–536k tris, 646 draws → ~20 fps** | render-bound |
| new-game cutscene game-frame rate (existing `device-killdiag-full.log`) | 60 fps | **~16–17 fps** (frame 1140→1380 = 240 / 13.9 s) | cutscene is the heaviest beat |

### Mechanism (where the rate is set)
- The game-logic clock advances in `goal_src/jak1/engine/draw/drawable.gc:969` `display-frame-start`:
  `base-frame-counter += (int time-ratio) × time-factor(5)` per unpaused frame, where
  `time-ratio = timer-count(EE)/ *ticks-per-frame*(9765) + 1`. The EE timer is **byte-identical** on x86 and arm64
  (`clock_gettime(CLOCK_MONOTONIC)`, `ns*3/10`; `game/kernel/common/kmachine.cpp:475` ≡ `android/gk_android_main.cpp:421`).
  So the catch-up is correct on arm64 — **the timer is NOT the bug** (a candidate root, falsified by the dump: tr does
  rise to 3.0 and `base` tracks `real`).
- The **display swap is decoupled** from the game-chain on Android (`android/android_renderer.cpp` swaps every vsync;
  `A35-RENDER frame=N` = game/chain frames). When the Adreno can't render a chain in 16.6 ms, the EE thread blocks in
  `android/android_gfx.cpp:562 vsync()` for the next swap → fewer game-frames/sec.
- **The cutscene/spool clock is the slow-motion culprit.** `vsync()` fires the IOP/overlord VBlank handler exactly once
  per call via `fire_iop_vblank` (`android/android_gfx.cpp:569,618`); that handler advances the spooled-audio / fake-VAG
  str-pos that paces every cutscene. Because it is **per-vsync (= per game-frame), not wall-clock**, at the cutscene's
  ~16 game-fps it ticks ~16 Hz instead of 60 Hz → the cutscene timeline runs at **~0.27× real-time** (≈3.7× slow-motion),
  and stays *fluid* because the camera/joints interpolate. x86 holds 60 fps so the cutscene plays at 1×. (Secondary: below
  15 fps the `time-ratio` cap of 4.0 — `display.gc set-time-ratios` — lets even the logic clock slip slightly.)
- **This is the likely root of the deferred `Gcine-cut` "device GLIDES where x86 CUTs"**: a hard cut smeared over a
  0.27×-rate timeline reads as a glide. Flagged for the supervisor to confirm by dumping the str-pos/IOP-vblank rate
  during the cinematic (this audit measured the title beat; the cutscene fps comes from the existing killdiag log).

### Verdict
The base game clock is correct on arm64 (real-time, premise **falsified**). The owner's symptoms are: (a) low fps on
heavy scenes (render-bound: 646 draws / 536k tris on an Adreno 618), and (b) a cutscene/spool clock that is coupled to the
render cadence instead of wall-clock, producing fluid slow-motion in cinematics. Two distinct fixes (see fix order).

---

## D2 — Per-bucket census: which buckets are empty on device vs x86  (SEVERITY: MEDIUM)

Per-bucket triangle census at title-attract frame 900 (apples-to-apples; both backends free-run the same attract):

| bucket id / name | x86 tris | device tris | device state | cause |
|---|---|---|---|---|
| 49 `l0-pris-merc` | 1078 | **1078** | drawn | (merc OK — see D3) |
| 55 `common-pris-merc` | 6339 | **6339** | drawn | (merc OK) |
| 58 `l0-water-merc` | 742 | 742 | drawn | ok |
| 3 `sky` | 2 | 2 | drawn | ok |
| 66 `sprite` (particles) | 0 | 0 (frame900) / **36006** (frame2400) | drawn | 2D sprites OK; see below |
| **47 `shadow`** | **824** | **0** | **`ported=0` (hasdata=1)** | **Shadow2/ShadowRenderer TU EXCLUDED from Android CMake + 15 `shadow-cpu` mips2c builders noop'd; bucket wired as `SkipRenderer` (android_opengl_renderer.cpp:323)** |
| 64 `depth-cue` | (drawn) | skipped | `SkipRenderer` (:324) | `DepthCue.cpp` excluded from Android build |
| 11/18/46/.. `generic-*` | 0 @ title | 0 @ title | empty when used | `generic-merc`/`generic-effect`/`generic-tie` mips2c builders noop'd on arm64 (not in `kSet`) |

- **Measured missing bucket:** `shadow` (id 47) renders **824 tris on x86, 0 on device** → character/object shadows are
  absent on the device. Cause: the shadow renderer TU is not in the Android curated subset and the CPU shadow builders are
  noop'd in `game/mips2c/mips2c_table_jak1_arm64.cpp`.
- **2D sprites render** on device (sprite bucket = 36006 tris at frame 2400), so the SPRITE *renderer* TU is present.
- **Missing 3D world-particles / stars / sun-corona** are NOT a bucket-level zero — they are the subset built by
  `sp-process-block-3d`, which is **deliberately noop'd on arm64** (`mips2c_table_jak1_arm64.cpp:452-457`: "the 3D
  world-particle processor is deliberately NOT enabled" — it SIGSEGVs at frame ~190). 2D sparticles
  (`sp-launch-particles-var`, `sp-process-block-2d`, `particle-adgif`) ARE enabled. So: 2D HUD/sprites present; 3D ambient
  particles, sparks, stars, and the sun corona absent. See D4.

---

## D3 — "Jak invisible in the cinematic" vs "villains crash it": DIFFERENT roots  (SEVERITY: MED-HIGH)

**Verdict: they are NOT the same bug, and "Jak invisible" is NOT a merc-render-subset gap.**

- **Merc pipeline is PROVEN correct on arm64.** The device per-bucket census matches x86 **byte-for-byte** at the title
  beat: `l0-pris-merc`=1078, `common-pris-merc`=6339, `l0-water-merc`=742 — identical tri counts, no crash. All merc draws
  funnel through one entry point, `Merc2::do_draws()` (`game/graphics/opengl_renderer/foreground/Merc2.cpp:1360`), called
  twice per bucket (normal + envmap). It renders skinned characters correctly on the device.
- **The villain crash** is the **envmap/blend-shape sub-path**: the arm64 envmap merc draw (villains spawned with
  `blend-shape`) writes a corrupted *low* base pointer over the GOAL kernel `process::deactivate` / return-from-thread-dead
  code (KERNEL.CGO). It is **already mitigated** by the content-canary repair in `android/android_gfx.cpp:401-510`
  (Gcine-crash3 + Gmatch guards) plus the committed `*use-fp-blerc*` skip in
  `goal_src/jak1/engine/gfx/merc/merc-blend-shape.gc` (working tree is git-clean — the fix is in HEAD).
- **"Jak invisible"** cannot be a noop'd-builder consequence: `blerc-execute`/`setup-blerc-chains-for-one-fragment` ARE on
  the arm64 allowlist, and C++ FP-blerc does the real vertex blend. Since merc renders correctly at the title, Jak's
  invisibility is **cinematic-specific** — most plausibly a Jak spawn / cutscene art-joint / scene-player issue
  (cf. [[post-f1d-restart-state]] "Jak NOT spawned"), distinct from the villain stomp. Recommend a dedicated phase that
  REACHES the new-game cinematic on device and dumps Jak's merc-bucket draw count + spawn state (this audit measured the
  title beat, which has no Jak/villains, so the cinematic merc draw was not directly censused — the honest residual).

---

## D4 — Sun renders as a "weird halo" not a real disc  (SEVERITY: MEDIUM — same root as D2)

- The sun is drawn two ways in the original: (a) the disc/color baked into the **sky quad** via `render-sky-quad`/
  `render-sky-tri` — both **ON** the arm64 allowlist (`mips2c_table_jak1_arm64.cpp:402`), so the sky/sun-disc renders; and
  (b) the **corona/glow**, which is a **3D world-space sparticle group** `group-sun`
  (`goal_src/jak1/engine/gfx/mood/weather-part.gc:482`, defpart 1950/1951/1952, textures `middot`/`starflash2`/`sun-glow`)
  built by **`sp-process-block-3d`** — the builder that is **noop'd on arm64** (D2).
- So on the device the textured corona sprites are never built; only the additive sky-quad glow survives = the **"weird
  halo."** Same single root as the missing 3D particles/stars.
- **Ghalo / Ghalo-sun did NOT render the disc.** Ghalo (`300fe5ad2`) suppressed a village/sun-glow *leak* onto the ND-logo;
  Ghalo-sun (`8463d2b39`) FALSIFIED a "re-arm bug" and made **no** sun-state change. Neither re-enabled
  `sp-process-block-3d`. The missing corona is an open arm64 sparticle-3D gap, not a sun-state-reset bug.

---

## RANKED FIX ORDER (for supervisor triage into single-defect phases)

1. **D1-cutscene-clock decoupling (HIGH, targeted, low-risk).** Make the IOP/overlord vblank that paces spooled cutscenes
   fire on a **wall-clock 60 Hz** schedule instead of once-per-vsync (`android/android_gfx.cpp:569,618`), so cinematics
   play at real-time even when the render rate drops. Directly fixes the "fluid 2× time" cinematic and is the prime
   suspect for the deferred `Gcine-cut` glide-vs-cut. Confirm first by dumping str-pos rate during the cinematic.
2. **D1-render-throughput (HIGH, broad).** Reduce the Adreno 618 per-frame cost (646 draw-calls / 536k tris at the village
   flythrough → 20 fps): draw-call batching / state-change reduction / culling on the arm64 path. Lifting fps toward 60
   shrinks every downstream symptom (choppy gameplay AND, with #1, cutscene speed).
3. **D2/D4 — enable `sp-process-block-3d` on arm64 (MEDIUM).** One builder un-noop covers BOTH the missing 3D particles/
   stars AND the sun corona. Blocked on the frame-~190 SIGSEGV that caused it to be disabled — needs that crash fixed first.
4. **D3 — Jak-invisible cinematic localization (MED-HIGH).** Separate phase; merc pipeline is proven OK, so target Jak's
   cutscene spawn / art-joint / scene-player path (reach the cinematic on device, census Jak's merc draw). Villain stomp is
   already canary-mitigated.
5. **D2 — port the shadow renderer (MEDIUM).** `Shadow2`/`ShadowRenderer` TU + the 15 `shadow-cpu` mips2c builders, to
   restore character/object shadows (device shadow bucket = 0 vs x86 824).

---

## Raw dump artifacts (this directory)
- `x86-clock-census.log` — x86 baseline: 91 `GRA-CLOCK` samples (300.5 ticks/sec, tr=1.0, 60 fps) + 4×70 `GRA-CENSUS` frames.
- `device-clock-census.log` — device: 91 `GRA-CLOCK` (base==real, tr 1.0→3.0, fps 60→20) + 280 `GRA-CENSUS` + `A35-RENDER` + `sustained swap`.
- `device-foreground.txt` — end-of-run focus = `org.opengoal.gk.jak1` (frames valid), pid alive, 0 crash signatures.
- Cross-referenced (pre-existing): `../Gcine-cut/device-killdiag-full.log` — cutscene game-frame rate ~16–17 fps vs 60 swap.

## Caveats (honest residuals)
- Device clock/census captured at **title attract** (stable). The cutscene fps (~16) is from the existing killdiag log; the
  cutscene's spool-clock rate and Jak's cinematic merc draw were **not** directly censused (the cinematic is the unstable
  beat — deferred `Gcine-cut`). D1's cutscene mechanism is measured-fps + code-pacing, recommend runtime confirmation.
- Per-bucket SPRITE tris undercount (Sprite3 routes some draws through profiler children); merc/tfrag/tie/shadow counts are
  exact. This does not affect the shadow (D2) or merc (D3) conclusions.

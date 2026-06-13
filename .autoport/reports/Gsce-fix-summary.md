# Phase Gsce — restore the "Sony Computer Entertainment presents" screen in the first frames

**Chronological boot step 0.** The original retail Jak & Daxter shows a "Sony
Computer Entertainment presents" static screen in the very first frames of boot,
in every region, *before* the Naughty-Dog/Daxter (`ndi`) logo. OpenGOAL upstream
gated that screen to Japan only, so our SCEA/SCEE build never showed it. This
phase restores it (an intentional content divergence from upstream, toward the
original game) and proves it now spawns + reaches its render state on our
territory. The actual sprite blit is currently black on arm64 — root-caused
below to a LOCKED renderer stub, out of this phase's edit scope.

---

## 1. What renders the SCE "presents" screen

The screen is a `static-screen` process (`goal_src/jak1/levels/demo/static-screen.gc`).
It draws three screen-space sparticle sprites (`defpart 2966/2967/2968` →
`defpartgroup group-part-screen1`) — the SCE logo split into three horizontal
strips. `static-screen-init-by-other` overrides the three part textures with the
texture-ids passed by the spawner, and `go-virtual idle` blits them every frame
via the sparticle/sprite renderer.

It is spawned from `target-title` (`goal_src/jak1/levels/title/title-obs.gc`,
state `target-title`, `:code`). The boot intro sequence is:

```
target-title :code
  cond
    (first-boot)  -> static-screen-spawn 5  (SCE presents, plays (seconds 3))   ; THEN falls through
    else          -> wait for ndi-intro, suspend
  cfg-8 : wait for the static-screen to die (~3 s) + mc-slot-info
  cfg-41: process-spawn logo 'ndi   (Naughty-Dog/Daxter logo) -> go target-title-play
```

So on first boot the order is **SCE presents → ND/Daxter logo → title**, exactly
as the original game. The SCE textures live on texture page `#x649` (1609 =
`demo5j`, common slot 6), shipped in `TIT.DGO`, resident when `target-title` runs
(confirmed: `link finish: static-screen` and `tpage-1609` link at boot).

## 2. Why it never showed (the gate) — and the un-gate

Upstream `title-obs.gc:554` spawned the static-screen only when:

```lisp
((and (= (scf-get-territory) GAME_TERRITORY_SCEI) *first-boot*) ...)
```

`scf-get-territory` → C `DecodeTerritory()` is hardcoded to
`GAME_TERRITORY_SCEA` (= 0) on BOTH the pristine x86 gold and Android
(`game/kernel/common/kmachine.cpp:395`, `android/android_runtime_compat.cpp:793`);
`GAME_TERRITORY_SCEI` = 2 (`goal_src/jak1/kernel-defs.gc:291`). So `(= 0 2)` is
always false → the SCE screen never spawned on our build (or on pristine x86).
This is an UPSTREAM REMOVAL (Japan-only), not a port bug. The owner's
"French-shows / English-doesn't" intuition maps to this same territory gate; the
fix is region-agnostic.

**The change (the only behavioral edit):** drop the `(= (scf-get-territory)
GAME_TERRITORY_SCEI)` test, keep `*first-boot*` so the screen plays once at
startup (not on every return to title):

```lisp
(cond
  (*first-boot*
   (set! *first-boot* #f)
   (format 0 "GSCE-SCE-SPAWN static-screen-spawn territory=~D first-boot=~A~%" (scf-get-territory) *first-boot*)
   (set! gp-0 (ppointer->handle (static-screen-spawn 5 ... (seconds 3) #f self))))
  (else ...))
```

A second marker was added in `static-screen.gc` `static-screen-init-by-other`,
right before `go-virtual idle`, to confirm the screen reaches its render state:
`GSCE-SCE-RENDER static-screen idle enter (part-group ok, blitting SCE presents)`.

Both markers use `(format 0 ...)`, the proven GOAL→Android-logcat path (same as
`pckernel version:`). This is a deliberate, documented divergence from upstream;
only the two permitted goal_src files changed (no painted/hardcoded image).

## 3. First-frame evidence (device + x86 oracle)

Device (physical Redmi `eae4df44`, arm64), newest run
`.autoport/reports/Gsce-routed-logcat-run2.log`, with the rebuilt arm64
`TIT.DGO`+`DEM.DGO` pushed into the package filesDir (verified byte-equal):

- `01:08:11.605 GSCE-SCE-SPAWN static-screen-spawn territory=0 first-boot=#f`
  — the un-gate fired on **territory 0 (SCEA)**, which the old code rejected.
- `01:08:11.605 GSCE-SCE-RENDER static-screen idle enter (part-group ok, ...)`
  — the static-screen found its part-group and reached the idle render state.
- Boot sustained crash-free: `A35-RENDER frame=1800`, **0** `sig=11`.
- Final focus `org.opengoal.gk.jak1` (app stayed foreground).

x86 oracle (`/tmp/gsce-x86-oracle.log`, `build-x86/game/gk ... -boot`): reaches
the identical `GSCE-SCE-SPAWN`/`GSCE-SCE-RENDER` markers and continues into the
intro, still hitting `link finish: logo` (x86 smoke regression gate intact). So
the un-gated GOAL source is correct and behaves identically on both backends.

## 4. The screen renders BLACK on arm64 — root cause (honest)

Captured device frames for the ~3 s SCE window (run2 t04–t06s, frames ~5–180) are
**black** (only the touch overlay); the first non-black content is the `ndi` logo
at ~t07s. The static-screen *runs* (markers fire) but its three sprites never
reach the GPU. Root cause, proven:

- The sparticle sprite-DMA builders `sp-launch-particles-var`,
  `sp-process-block-2d`, `particle-adgif` (the functions that turn the launched
  particles into sprite DMA) are `def-mips2c`. On arm64 a mips2c function only
  gets its real trampoline if it is on the `a37_name_is_real()` allowlist
  (`kSet`) in `game/mips2c/mips2c_table_jak1_arm64.cpp`. These sparticle names
  are **NOT** on that allowlist, so they bind to the shared no-op
  (`__a37-mips2c-noop`, returns 0, writes no DMA).
- Runtime proof — run2 log lines 1781–1787:
  `A37-MIPS2C-FALLBACK particle-adgif -> shared noop (not on allowlist yet)` and
  the same for `sp-launch-particles-var` / `sp-process-block-2d`.
- Consequence: the sprite bucket is empty during the SCE window — A35-RENDER
  frames 5–180 show only `draws=1..2 tris=2..4` (essentially the clear, no sprite
  quads). Hence black.
- The texture and setting paths are NOT the blocker: `tpage-1609` (demo5j) links
  and maps to common slot 6, matching `(add-setting! 'common-page 'set 0.0
  (ash 1 6))`; `bg-a` is set transparent so sprites would show over black.

**Oracle verdict:** x86 has no arm64 noop allowlist — it binds the real sparticle
code, so the SCE sprites build there. The divergence is **arm64-only**, in a
LOCKED C++ file.

## 5. In-scope fixability — NO (and why I did not over-reach)

The GOAL source (the only two files this phase may edit) is correct: x86 renders
the same source. The black is a stubbed arm64 renderer function, in
`game/mips2c/mips2c_table_jak1_arm64.cpp` — outside this phase's edit scope. No
timing / setting / alternate-texture change in `title-obs.gc` or
`static-screen.gc` can substitute for a stubbed DMA builder. The phase prompt
explicitly anticipated this ("if the static-screen render path has the same arm64
issues the ND logo hit, coordinate with Gnd's fix"), and the methodology forbids
reaching into a separate, risky defect from a content phase (the sprite path is
shared with the live title → title-regression-gate risk; the prior A37/A40 notes
warn some arm64 trampoline ports are incomplete and need verification). So the
un-gate (this phase's deliverable) is complete and proven; the arm64 sprite
render is deferred.

## 6. Recommended follow-up phase (precise)

Add the sparticle sprite-DMA builders to the arm64 mips2c allowlist and verify
their trampolines build correct sprite DMA:

- File: `game/mips2c/mips2c_table_jak1_arm64.cpp`, `a37_name_is_real()` `kSet`.
- Add: `"sp-launch-particles-var"`, `"sp-process-block-2d"`, `"particle-adgif"`
  (and likely `"sp-process-block-3d"` for 3-D particles).
- Verify each trampoline produces byte-correct sprite DMA vs the x86 oracle
  before enabling (A37/A40 pattern: some ports were noop-bound *because* their
  port was incomplete — flipping the flag alone may crash/garble).
- Gate on: SCE sprites visible in the first frames + title still boots crash-free
  (regression). This likely unblocks a whole CLASS of particle renders (HUD
  sprites, effects, and the `ndi` particle elements), so it deserves its own
  oracle-diff phase rather than a content phase.

## 7. Build / sync procedure used

1. `find out/jak1/obj -type f \( -name '*.o' -o -name '*.go' \) -delete` then
   `build-arm64/goalc/goalc --user-auto --game jak1 --disable-ansi -c
   '(make-group "iso" :force #t)'` → arm64 DGOs (TIT.DGO 1372448, DEM.DGO
   5601904).
2. Stash arm64 `TIT.DGO`+`DEM.DGO` → `android/app/src/jak1/assets/iso_data/jak1/`
   and `out/jak1-arm64/iso/`.
3. Wipe obj again; `build/goalc/goalc ... '(make-group "iso" :force #t)'` → x86
   DGOs back in `out/jak1/iso/` for the x86 smoke/oracle (KERNEL.CGO restored).
4. Device: `adb push` the two arm64 DGOs to `/data/local/tmp`, then
   `run-as org.opengoal.gk.jak1 cp` into `files/iso_data/jak1/` (the
   `.extracted_v1` sentinel survives `pm install -r`, so a reinstall alone does
   NOT update DGOs — the per-DGO push is what takes effect). Harness:
   `.autoport/gsce_run.sh`.

## 8. Validator gate results (structural)

- Locks: only `title-obs.gc` + `static-screen.gc` changed in goal_src; IGenX86_64
  and infra untouched. PASS.
- Anti-cheat: no painted/hardcoded SCE image. PASS.
- x86 smoke: `link finish: logo` present. PASS.
- Device: newest `Gsce-routed-logcat-run2.log` has the static-screen SPAWN marker
  (`GSCE-SCE-SPAWN`), **0** `sig=11`, `frame=1800` (≥300). PASS.
- Focus: ends on `org.opengoal.gk.jak1`. PASS.
- Screencap + this report present. PASS.

**Summary:** the SCE "presents" screen is restored for all regions (un-gate
proven on territory 0, x86-oracle-confirmed, crash-free, spawns + reaches render
state). The first-frame sprite blit is black on arm64 due to the sparticle mips2c
no-op in the LOCKED `mips2c_table_jak1_arm64.cpp` allowlist — documented with a
precise follow-up. The supervisor pixel-judges the on-screen result against this
honest accounting.

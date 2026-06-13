# Phase Gintro — pre-title intro (SCE + Naughty Dog/Daxter logo) render

Chronological step 1 of the boot: make the pre-title intro RENDER before the
Jak&Daxter title flythrough. This report documents what was fixed, what the
3-tier/oracle render diff revealed, and the ONE remaining blocker that still
keeps the ND/Daxter logo off-screen — with an honest verdict, not a green-wash.

## TL;DR (honest verdict)

Two real, necessary fixes landed (renderer-pacing hold + corrupt-frame
re-present), and the boot now reaches the ndi window with the renderer up,
crash-free, at real-time pacing. **But the ND/Daxter logo still does NOT
visibly render.** The 3-tier oracle diff proved the cause is NOT a GLES
render-path / camera / texture gap (the phase's original hypothesis) — it is an
**arm64 runtime memory STOMP** (the long-standing F1a/A37 "joint-decompress"
blocker) that corrupts the per-frame DMA bucket chain on exactly the frames that
draw the ndi logo geometry. That stomp is a deeper goalc-arm64 defect and needs
its own phase; the render-path infrastructure here is the prerequisite for it.

## Finding 0 — the "SCE presents" static screen is a no-op on BOTH builds

`target-title` (title-obs.gc:553-563) only spawns the SCE `static-screen` when
`(= (scf-get-territory) GAME_TERRITORY_SCEI)` AND `*first-boot*`. But
`DecodeTerritory()` returns `GAME_TERRITORY_SCEA` on BOTH the pristine x86 gold
(game/kernel/common/kmachine.cpp:396) and Android
(android/android_runtime_compat.cpp:793). So `static-screen` only ever LINKS,
never spawns — verified in both `.autoport/gold/pristine-boot-raw.log` and our
Android boot (only `link finish: static-screen`, never a spawn). The SCE screen
is therefore not a render gap to close; the first rendered beat on both builds
is the ND/Daxter `ndi-intro`. (No territory was changed — that would diverge
from the gold standard.)

## Finding 1 — renderer brought up AFTER the intro already ran (FIXED)

A boot-timeline diff (our Android logcat vs the renderer-ready marker) showed
the GL renderer takes ~2 s to bring up (glad + 43 shaders + GAME.fr3) on the
SDL thread, while the GOAL dispatcher thread **free-ran the entire intro**
during that window. Every DMA chain for those frames was dropped
(`A35-RENDER send_chain before renderer init`: chains received == dropped ==
607), and the first A35-RENDER frame landed at `logo-intro` — past the ndi
logo. Desktop never sees this because GL init precedes the GOAL kernel.

**Fix (android/android_gfx.cpp::vsync):** pre-renderer-ready, HOLD the GOAL
dispatcher at its first vsync (ticking the IOP vblank at 60 Hz so the
overlord/fake-VAG clock stays real-time) until the renderer is up, then fall
through to the normal swap-chain block. The dispatcher now waits for the
renderer instead of racing past the intro. Verified: `send_chain before
renderer` count dropped to 0; the intro states (`ndi-intro`) now run with the
renderer consuming frames.

## Finding 2 — post-ready free-run fast-forwarded the ndi spool (FIXED)

With the renderer up, the ndi segment still showed flat/black frames. The
dispatcher was free-running at ~285 Hz during ndi (575 vsyncs in 2 s, should be
~120). Mechanism: the upstream/desktop pacing waits on
`frame_idx_of_input_data` (the swap index of the last CONSUMED chain). That
invariant assumes the renderer consumes a chain every frame. On Android the
chain-copy guard SKIPS a frame whose live chain is malformed — when it does,
`frame_idx_of_input_data` freezes while swaps keep advancing, so
`frame_idx > init_frame` is permanently true and vsync stops blocking. The
free-run over-fired the IOP vblank ~4.75×, fast-forwarding the spooled ndi
animation, and flooded send_chain so most ndi chains were dropped.

**Fix (android/android_gfx.cpp::send_chain):** on a corrupt frame, instead of
dropping it, RE-PRESENT the last good copied chain (`ever_copied` +
`has_data_to_render`). This keeps the consume cadence 1:1, so the oracle pacing
stays real-time, and the renderer redraws the previous frame instead of
black-flashing. Verified (run 4): vsync locked to 60/s, `dropped=0` for the
whole ndi window, ndi dwells ~17 s at real-time (matching the pristine
ndi-intro duration) instead of flashing past in ~3 s. The rush is gone.

## The 3-tier / oracle render diff — what actually corrupts the ndi frames

Using the harness intent of `.autoport/gold/compare-3tier.sh` (Original x86 →
our x86 → our Android), I diffed the ndi-intro per-frame render DMA chain.

- **Chain walk (Android, GINTRO-CHAINWALK):** the normal frame chain is
  `CALL→*default-regs-buffer*` (GS reset), `CNT`, `RET`, then a `NEXT` (kind=2,
  qwc=0) that links the chain header to the first bucket's data
  (e.g. `addr=0xce7cc0`, a valid high heap pointer). Bucket buckets are
  NEXT(qwc=0) tags whose addr is patched to the bucket DATA (dma-bucket.gc).
- **Android intermittently corrupts that bucket NEXT addr to a LOW value
  `0x1a50`** (sometimes `0x2070`). The Android-only chain-copy guard
  (`FixedChunkDmaCopier`, dma_copy.cpp:110-111, `ASSERT(addr >
  EE_MAIN_MEM_LOW_PROTECT=0x80000)`; mirrored by the send_chain precopy walk)
  rejects any frame with such a tag → the frame never reaches the GPU.
- **x86 oracle (decisive):** desktop uses zero-copy (`run_dma_copy = false`),
  so it follows the chain in place. Instrumenting the desktop `gl_send_chain`
  and running the same ndi-intro produced **ZERO low-address tags** over a full
  ndi run; every bucket NEXT was a high heap pointer (`0xcca510`, `0x507bb0`,
  …), structure otherwise identical (CALL/CNT/RET/NEXT). So `0x1a50` is NOT a
  legitimate camera/texture/bucket structure the Android renderer mishandles —
  it is **arm64 runtime corruption**. (`0x1a50 == 0x501a50 & 0xffff`, the low
  bits of the *default-regs-buffer* RET tag — a stomp signature, and the
  bucket-NEXT store in dma-bucket.gc is a clean 32-bit store with no truncation,
  so this is foreign data written over the tag, not a codegen mask bug.)

## ROOT CAUSE (the remaining blocker) — arm64 blend-shape/joint OOB stomp

Why ndi-only and intermittent: the `ndi` state (title-obs.gc:387-391) spawns
Jak (`*jchar-sg*`) and Daxter (`*sidekick-sg*`) as `logo-slave` with
`blend-shape #t` — full merc skeletons that the `startup`/`logo-intro` path
never instantiates. Those skeletons drive the arm64 joint-decompress /
blend-shape compute, whose A37-CSP canary band `[0x1900000, 0x1918000)` is
PROVABLY stomped (`A37-CSP CANARY-STOMP before-call#…`) at the exact frame the
bucket NEXT flips to `0x1a50`. The same out-of-bounds write class scribbles
low-EE memory including the per-frame DMA calc-buffer bucket tags
(`0x514e00`/`0x517530`). This is the long-standing arm64 "joint decompress"
blocker named in F1a (blocker B) and F1d-restart (spool-joint).

Crucially, the corruption hits the **logo-geometry** frames (the ones with the
merc/foreground draw), not the blackout/setup frames — so the only chains that
pass the guard are the empty/blackout ones. That is why even with perfect
pacing + re-present, the screen holds a blackout frame for the whole ndi
window: the logo frames are corrupt → skipped → re-presented as the last good
(blackout) frame. The logo geometry never reaches a clean chain.

Note: `(blerc-execute)` (the PS2 mips2c blend path) is gated off on the PC port
(`(unless *use-fp-blerc*)`, main.gc:377) — blend vertices are computed in the
C++ renderer (Merc2.cpp `blerc_avx`, into a C++ buffer, not EE memory). So the
stomp is NOT the C++ blend path; it is the GOAL/mips2c skeleton joint compute
that writes EE memory with an arm64-corrupt destination. Fixing it is a
goalc-arm64 / mips2c forensics task (oracle-diff the blend-shape skeleton joint
setup disasm) — out of reach of the GLES render path this phase was scoped to,
and warranting its own single-defect phase.

## Title-regression gate

Held. Across runs the title still boots crash-free and flies: `GK-DIAG sig=11`
= 0, A35-RENDER `frame_max` = 2100 (≥300), focus ends on
`org.opengoal.gk.jak1`. The `logo-intro`/`logo-intro-2` flythrough renders
normally (it has no blend-shape skeletons, so no stomp). G1's stable title is
intact.

## Frame evidence (run 4, no input — natural attract)

- Early/boot: dark-blue clear (renderer bring-up, dispatcher held).
- ndi window (t04s–t20s, frames 5→900, spool=`ndi-intro`, ~17 s real-time):
  flat ~59 KB frames — the ND/Daxter logo is NOT visible (logo-geometry frames
  corrupted + re-presented as blackout).
- Title flythrough (t24s+, spool=`logo-intro`/`logo-intro-2`, frames 1140→2040):
  ~1.3 MB frames — full textured 3D renders correctly.
  Captures: `.autoport/reports/Gintro-device-run4-*.png`,
  `.autoport/reports/Gintro-focus-run4.txt`,
  `.autoport/reports/Gintro-routed-logcat-run4.log`.

## What changed (files)

- `android/android_gfx.cpp` — vsync pre-ready hold; send_chain re-present of the
  last good chain on a corrupt frame; precopy diagnostic (kind/spr/addr/dst +
  chain walk) that named the corruption.
- `.autoport/gintro_run.sh` — device run/capture harness (dense early/mid
  time-series, each frame labeled with the live spool name).

## Recommendation

Open a dedicated phase for the arm64 blend-shape/joint OOB (the F1a/A37
blocker): oracle-diff the blend-shape skeleton joint-decompress on arm64 vs x86,
find the OOB index/destination, and stop the stomp. Once the logo-geometry
frames are no longer corrupted, the infrastructure landed here (renderer-up
hold + real-time pacing + re-present) will let the ND/Daxter logo render in
chronological order before the flythrough with no further changes.

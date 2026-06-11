# Phase A42 — tfrag-init: VILLAGE FLYTHROUGH RENDERS. Textured Sandover
# terrain on-device (run-7 captures: wooden hut interiors, plaster walls,
# sky openings, time-of-day night→dusk→day, attract level-name text over
# real geometry). THREE root causes fixed — none of them was A41's named
# suspect — including arm64 emitter bug class #11. 150 s @60 fps, zero
# faults, zero hangs, 26/26 focus checks, x86 byte-identical, qemu 675.

## A41's framing, falsified first

A41 closed with "tfrag buckets emit no tfrag-init, so TFragment never
sets up the loaded title level." Per the fiction-check discipline, that
claim was audited before being built on. The A41 run-4/5 logcats
contain `A36-TFRAG-CAM lvl=village1` ×3 (the probe inside
TFragment::handle_initialization) — **tfrag-init packets DID reach the
renderer**, with a sane camera, in a ~1-frame window at 11:50:51.755,
before village1.fr3 finished loading (51.7→52.2). The level was being
displayed and torn down so fast the renderer never had data while
displayed. The real question was: why does the title course not HOLD?

## Root cause 1 — the IOP never received a vblank: every spooled
## cutscene aborted at the 4-second str-pos timeout

The title sequence is spool-driven: logo/ndi play STREAMED animations
(`ja-play-spooled-anim`, loader.gc:632) whose frame advance is slaved to
`current-str-pos` — the VAG stream position the overlord DMAs to the EE
in `SoundIopInfo` from `VBlank_Handler` (srpc.cpp:446) — and village1 is
brought in/held by those spools' command lists (title-obs.gc). On
Android, `*sound-iop-info* strpos` stayed at its boot value **-1
forever**, so every spool hit `(and (<= sv-72 0) (time-elapsed? sv-40
(seconds 4)))` → abort → `restore-load-state-and-cleanup` executed the
whole command list at once (the display-self/turning-off dance in the
logs) and reverted the wants. The course collapsed in ~14-16 s (A41
run5: ndi-intro/logo-intro/logo-loop each linked exactly 2 of their
4/3/15/17 parts; x86 oracle: 5/3/15/18 over ~130 s).

Mechanism: `android/android_runtime_compat.cpp`'s
`Gfx::register_vsync_callback` was a **discard shim** (same disease
class as A41's `__pc-set-levels` noop). Desktop runtime.cpp:279 wires
`IOP_Kernel::signal_vblank` through it and gfx.cpp:119 fires it on every
`Gfx::vsync()`. On Android nobody stored, nobody fired: VBlank_Handler
never ran (it is also what advances jak1's **fake VAG clock**, the
engine's own no-audio pacing fallback).

Fix (desktop-parity, all Android-side): real register/clear in the Gfx
shims forwarding to `android_gfx::set_vsync_callback`; invoke in
`android_gfx::vsync()` (gfx.cpp:119-124 parity), clamped to 60 Hz while
`!renderer_ready` (pre-ready syncv free-runs at ~270 Hz — no swap chain
to block on); registration in `make_iop_thread`
(android_runtime_full.cpp, runtime.cpp:279 parity), cleared at IOP exit.
Plus: with 989snd still the phase-27 stub, `GetPlayPos()` can never
report SPU positions, so the PLAY_VAG_STREAM clock choice in
game/overlord/jak1/iso.cpp takes the **fake clock** on Android
(`#ifdef __ANDROID__`; desktop path byte-identical) — the same path
retail uses for silent STRs. Proof: `A42-STRCLK` telemetry, 300
vblanks/5.0 s, strpos +17/vblank, all spool parts streaming at ~4 s
cadence (run-7: ndi 5, logo-intro 3, logo-intro-2 15, logo-loop 22 —
desktop-identical).

## Root cause 2 — zero-copy chain hand-off: in-flight mutation hung the
## GL thread once the cutscene actually played

With pacing live, runs 2/3 hung ~60-100 s in: GL thread spinning in a
renderer drain loop (A37-HANG fp-walk → `dispatch_buckets_jak1+0x2e8` =
the virtual render call; run-2 OOM-killed at 3.77 GB rss — EyeRenderer's
unbounded `m_debug += "dma: …"` drain, run-2 registers full of "dma: 80"
ASCII), with 40 A37-BUCKET-MALFORMED skips showing bucket tags walking
to offset 0x0 mid-frame. The Android `send_chain` stored a RAW pointer
into GOAL memory; the newly-exercised cutscene code mutated the chain
under the reader. Fix: upstream's own `run_dma_copy` mode, always-on for
Android — `FixedChunkDmaCopier` copy taken on the game thread inside
send_chain (builder idle ⇒ tag stream stable), bounded pre-probe before
the copy (`A42-CHAIN-PRECOPY`, skips the frame instead of hanging the
unbounded copier walk), GL-side A37 probe now validates an immutable
copy. EyeRenderer's drain also got `ended()`-bounded + 64 KB debug cap +
one-shot reseat (upstream-grade hardening; never triggered post-copy).
Result: zero hangs/malformed/OOM in runs 4-7 (150 s each).

## Root cause 3 — arm64 emitter bug class #11: PSHUFLW/PSHUFHW were
## dup-stand-ins, so every `.ppach` was garbage → time-of-day alpha = 0
## → the alpha test discarded the entire village

Run 4: village displayed and STAYED, `TFRAG setup: 7.4ms` (first ever on
Android), logo-loop looping — terrain still black. A42 probes:
`A42-TFTREE lvl=village1 nodes=224 vis=178 draws=80 tris=61452` every
frame (occlusion vis real, popcount 6104; fog −0.06 — A41's "fog=-0.0"
was a %.1f print artifact), `A42-TFGL err=0x0`, 78/80 draws executed,
pixel still 000000ff. The TOD colors told it: `tod0=14003500` — **G=0,
A=0 — exactly the two weight lanes extracted from `word >> 16`** of the
GOAL-packed `(-> mood itimes)`. `update-mood-itimes` (mood.gc:30) packs
the 8 palettes' per-channel weights with `.ppach`; goalc lowers PPACH to
VPSHUFLW/VPSHUFHW(0x88) + VPSRLDQ(4) + PCPYLD (Asm.cpp:754); and
`goalc/emitter/IGenARM64.cpp` implemented both shuffles as
`dup_4s_elem` — duplicating ONE 32-bit word, nothing like the x86
halfword shuffle. interp_time_of_day then emitted alpha=0 vertex colors
and the tfrag alpha test (aref 0x26 ≥) discarded every fragment: 61k
tris submitted, zero pixels, while EE-projected content (direct text,
sky) drew fine.

Fix at the emitter: exact PSHUFLW/PSHUFHW via the free V0 scratch — ORR
copy + 4× `INS Vd.H[t], V0.H[s]` (multi-word InstructionARM64;
encodings NDK-assembler-verified; dst==src safe; other 64-bit half
preserved). On-paper composition check: the fixed sequence reproduces
PS2 PPACH bit-exactly. Blast radius: VPSHUFLW/HW are emitted ONLY by
compile_asm_ppach (imm 0x88 always) — all 38 `.ppach` sites (mood,
matrix, vector, collide, drawable, generic-tie, ocean) now correct.
All 28 CGO/DGOs regenerated (arm64), stashed to out/jak1-arm64/iso,
pushed to BOTH device data paths; x86 set rebuilt and **hash-identical
to the A2 baseline** (KERNEL/ENGINE/GAME sha256 match).

## Device evidence (Redmi Note 9 Pro eae4df44, org.opengoal.gk.jak1)

- Run 7 (fixed build + regenerated DGOs): 150 s, frame=9000+ @60 fps,
  ZERO sig= lines, ZERO hangs, ZERO malformed buckets, ZERO OOM.
- A42-device-run7-{10,15,20,28,32,45,60,75,90,105,120,135,150}s.png (13
  ticks), mCurrentFocus bracketed before+after every tick: **26/26 =
  org.opengoal.gk.jak1/MainActivity** (A42-focus-run7.txt). Interlopers
  (xiaoji egggameplus, ghplus.patcher, sshxmobile ×2) disabled per run,
  re-enabled by trap (verified re-enabled after every run).
- WHAT THE FRAMES SHOW: from ~75 s the attract settles in the village —
  **textured Sandover geometry** (curved hut planking, rope-bound beams,
  plaster walls, sky through the wall openings), time-of-day animating
  night (75 s, with "SENTINEL BEACH" attract text in the real font over
  the terrain) → dusk purple (135 s) → full daylight (105/150 s).
  px@L probe: village-region FBO pixel went 000000ff (runs 4-6) →
  live shaded colors tracking TOD (run 7).
- A42-TFTREE steady state: village1, 178/224 vis nodes, 80 draws,
  61,452 tris/frame from the NORMAL tfrag tree; tod alpha 0x80.

## Oracles

- x86 smoke: `link finish: logo` PASS (gk rebuilt — EyeRenderer/
  TFragment/iso/srpc are shared TUs; desktop branches byte-identical,
  Android additions __ANDROID__-gated or env-gated).
- x86 CGOs: byte-identical to A2 baseline after regen (sha256).
- qemu: 675 'link finish:' lines, exit 0, with the regenerated arm64
  CGOs (the fixed ppach code is in its boot path).

## Honest residuals (named, with evidence)

- `A42-CHAIN-PRECOPY`: 8 frames/run still arrive malformed at send time
  and are skipped (contained by the copy; previously these were the
  corruption that hung the GL thread). Mechanism unidentified — next
  candidate set: the same in-flight writer during course transitions.
- The Jak & Daxter floating logo and foreground actors of the title are
  MERC/generic/sprite buckets — SkipRenderer on Android (unported); the
  title shows terrain+sky+text without them. Camera holds the title's
  settled hut-side shot between 105-150 s; full desktop-pose parity
  unverified (logo mesh absent makes a 1:1 visual diff moot).
- A35-RENDER total-tris counter pins at 63612 across compositions where
  per-tree probes show 61452 tfrag tris — counter is suspect (probe +
  pixels are the evidence of record), worth a look next phase.
- EyeRenderer's get_draws content handling on Android untested beyond
  "no longer able to hang" (eyes are merc-adjacent, unported visually).

## Diagnostics added (all cheap, most one-shot or 5 s-rate)

- A42-VBLANK one-shot; A42-STRCLK (PlayVag clock choice + 5 s vblank/
  strpos heartbeat, __ANDROID__).
- A42-CHAIN-PRECOPY (malformed-at-send, first 8 logged).
- A42-VIS / A42-TFTREE / A42-TFGL probes in TFragment (__ANDROID__).
- A36-TFRAG-CAM now env-gated (`A42_CAM_DUMP`) on desktop for oracle
  diffs.

# Phase A41 — texture path LIVE: readable real-font text ("FIRE CANYON",
# "SANDOVER VILLAGE") over the textured, time-of-day-animated logo/title
# scene. THREE texture-path mechanisms found and fixed (none of them the
# one A40 predicted first), plus level-fr3 streaming unblocked. 60 fps,
# zero faults, zero pool misses (was 469/run), 18/18 focus checks, both
# oracles green (x86 logo, qemu 675).

## The gate as named by A40

A40 left "animated untextured text quads over black 3D" — tris=63,612
drawn but every textured draw flat. A41's brief ranked three suspects:
the noop'd `adgif-shader<-texture-with-update!` mips2c binding, the
TexturePool GLES upload formats, and DirectRenderer's miss behavior.
All three turned out to be real, plus a fourth nobody named. In fix
order:

## Fix 1 — adgif-shader<-texture-with-update! bound to the shared noop

Ground truth from the A40 run-1 logcat (the binding state is printed at
boot): `A37-MIPS2C-FALLBACK adgif-shader<-texture-with-update! ->
shared noop (not on allowlist yet)`. This function packs tex0/tex1/
miptbp — including tbp0, the PC pool's lookup key — from a texture
object into an adgif-shader; every `adgif-shader-login*` call funnels
through it (texture.gc:2007/2019/2041/2055). With the noop, shaders
went out with tex0=0: the run-1 `Failed to find texture at 0 ...
sky-direct` line is that disease's fingerprint. Fix: added to the kSet
real-bindings allowlist in game/mips2c/mips2c_table_jak1_arm64.cpp
(pure ExecutionContext math, no DMA-cursor return — NOT a blerc-shaped
risk; callers discard the return value). Verified live:
`A37-MIPS2C-REAL adgif-shader<-texture-with-update! -> arm64
trampoline` in every A41 run.

NOTE: the FONT path never touches this function — font tex0s are
written by GOAL-side font-set-tex0 (texture.gc:1659-1690) — which is
why fixing it alone could never have textured the visible text. The
font's mechanism was:

## Fix 2 — boot-time texture uploads/relocates silently dropped (race)

android_gfx::texture_upload_now/texture_relocate early-returned on
`!g_renderer_ready`. On Android the GOAL boot races GL bring-up:
InitMachine — which runs the CGO links incl. every tpage login that
calls `__pc-texture-upload-now`, and the engine boot through
setup-font-texture!'s four `__pc-texture-relocate` calls — completes
BEFORE android_renderer_run can flip renderer-ready ON THE SAME SDL
THREAD. A40 run-1 timeline: first send_chain dropped at 10.127s, ready
at 10.782s. Every one-shot texture call was lost; the font texture
never entered the pool; DirectRenderer missed at slot 14720 (=0xe6000/
64, the relocated 24-pt font) 469 times/run and drew the placeholder —
A40's "untextured text quads" WERE the checkerboard placeholder.
Desktop never sees any of this because GL init precedes the kernel.

Two wrong fixes were tried and falsified on-device before the right
one:
1. Blocking wait for renderer-ready (run-1): DEADLOCK — the link-time
   calls run on the SDL thread, upstream of the bring-up they wait
   for. Boot parked in InitMachine; zero A35-RENDER lines.
2. FIFO queue replaying the saved tpage POINTER (run-2): the font page
   is KICKED by setup-font-texture! right after its relocate, so at
   flush time handle_upload_now read reused heap, slot 0x2786 (the
   font's source) never linked, and TexturePool::relocate ASSERT'd
   'src' — SIGABRT at 3.2s.
Final fix: queue pre-ready calls FIFO, but SNAPSHOT the upload's page
walk at call time (android_gfx::snapshot_upload — read-side mirror of
handle_upload_now, pure GOAL-memory reads while the page is alive)
into (PcTextureId, name, dest) entries; apply at flush via the new
additive TexturePool::handle_upload_precomputed (same inner-loop slot
rules, pool-locked, GL-free; unused on desktop). Relocates queue by
value. Flush runs at renderer-ready, after load_common — so the mt4hh
relocate's gpu_textures.at(0) sees real textures, desktop-ordered.
Run-5 proof: `A41-TEX flushing 13 queued pre-ready texture calls`,
uploads #1-8 (212/62/3/3/4/12/24/0 slot links), all four font planes
relocated (dst=0x3800 fmt=36+44, dst=0x3980 fmt=36+44), zero ASSERT,
zero misses at 14720 forever after.

## Fix 3 — GLES rejects GL_UNSIGNED_INT_8_8_8_8_REV: loader textures black

Run-3 was the falsification run for "fix 1+2 are enough": zero pool
misses, 60 fps — and a pitch-black frame. Mechanism: with lookups now
SUCCEEDING, draws bound the LOADER-created textures, and the loader's
glTexImage2D calls still used GL_UNSIGNED_INT_8_8_8_8_REV — illegal
under GLES; the call fails, the texture never gets storage, and GLES
samples incomplete textures as BLACK. (A40's visible quads had bound
the placeholder, which was created via TexturePool::upload_to_gpu —
one of only two sites that already had the REV→BYTE Android branch.)
Fixed the remaining live sites, same little-endian byte-identical
substitution, desktop enums untouched:
- loader/LoaderStages.cpp add_texture — EVERY fr3 texture (font, hud,
  level) goes through this one.
- SkyBlendCPU.cpp ×3, SkyBlendGPU.cpp ×1 — the latter also kills the
  "SkyTextureHandler setup failed." error printed by every boot since
  A35 (REV broke the sky FBO attachment storage): zero in run-4/5.
Already-correct sites confirmed: TexturePool::upload_to_gpu (A35),
FramebufferTexturePair (A36, covers EyeRenderer), TFragment's
time-of-day LUT (A36). Not touched: TextureAnimator/ProgressRenderer/
Hfrag/Shrub/Tie3 (not compiled or not driven on the jak1 Android path).

## Fix 4 — __pc-set-levels was a permanent noop: no level fr3 ever streamed

The a17 binding comment claimed InitMachine_PCPort rebinds it "later in
boot" — fiction on Android: InitMachineScheme is the runtime_compat
stub, so the rebind never ran. level-update calls __pc-set-levels every
frame (level.gc:1370); with the noop the Loader never received
want-levels and never streamed a level fr3 (zero loader-thread loads in
every log through run-4). Bound the real jak1::pc_set_levels (already
compiled into android_kernel). Run-5 proof: two `------------> Load
from file` loader-thread loads (~3s in; intro + title fr3s).

## Device evidence (Redmi Note 9 Pro eae4df44, org.opengoal.gk.jak1)

- A41-routed-logcat-run4/run5.log: frame=3540 (59s+ @60fps sustained),
  tris=63612, draws=104, buckets_drawn=18, ZERO sig= lines, ZERO
  asserts, ZERO "Failed to find texture at 14720" (469 in A40); run-5's
  single miss is `at 0 ... sky-direct` ONCE at first frame — the
  original game's draw-before-login frame-1 artifact (documented in
  TexturePool.h), gone from frame 2 on.
- Captures A41-device-run4-*.png + A41-device-run5-*.png (9 ticks
  each, 5-60s), mCurrentFocus bracketed before+after every tick:
  36/36 checks = org.opengoal.gk.jak1/MainActivity
  (A41-focus-run4.txt, A41-focus-run5.txt). Interlopers (xiaoji,
  ghplus, sshxmobile ×2) disabled for each run, re-enabled by trap.
- WHAT THE FRAMES SHOW: readable REAL-FONT text — "FIRE CANYON"
  (run4-10s), "SANDOVER VILLAGE" (run5-45s) — glyphs alpha-blended
  with shading from the actual relocated game font over the logo/title
  sequence's textured planet+sky, whose time-of-day palette animates
  across the run (blue at 5s → sunset pinks at 32s → night blue at
  60s). First readable words and first textured scene of the port.

## Honest residual (named, with evidence) — the next phase's gate

The village tfrag flythrough is not yet on screen. The boot reaches
logo-intro → logo-loop (435 link finishes) and sits in the logo/
attract sequence; the tfrag buckets carry no tfrag-init packets, so
TFragment::render never sees a level_name and never runs
setup_for_level — zero "TFRAG setup:" lines even with title.fr3 now
LOADED by fix 4. The left half of the captures stays black where the
village would be. tris is pinned at exactly 63,612 every frame of both
runs — the drawn set (sky dome + blend + direct text quads) without
background geometry. Next phase: drive the GOAL boot/attract past
logo-loop into the title's village scene (or confirm what gates
tfrag-init emission — likely level status 'active + background engine
draw path), then the flythrough textures are already in place.

## Build/infra notes

- gradle buildNativeLibs declares outputs but no inputs — it goes
  UP-TO-DATE and never recompiles C++; drive `cmake --build
  build-android --target gk` first (or delete the apk) when iterating.
- A stale in-place packaging artifact once produced a 131MB apk (76MB
  of zip data + 55MB slack); rm the apk before repackaging.
- INSTALL_FAILED_INSUFFICIENT_STORAGE at 715MB free: pm trim-caches
  4G + temporarily lowering sys_storage_threshold_* (restored — were
  null) unblocked; thresholds restored same run.
- x86: gk REBUILT with the shared-TU changes (TexturePool/+SkyBlend/
  LoaderStages are desktop code): `link finish: logo` smoke PASSES
  post-rebuild. Desktop texture enums byte-identical (REV kept under
  #ifndef __ANDROID__ / desktop branch).
- qemu: 675 'link finish:' lines, exit 0, rebuilt with all changes
  (mips2c table + shared TUs).
- No goal_src changes, no DGO regen needed (all fixes host-side C++);
  out/jak1-arm64 + APK assets untouched from A40's regen.

## Diagnostics added (always-on, boot-time-only volume)

- A41-TEX queue/flush/upload/relocate logs (android_gfx.cpp): every
  pre-ready call queued+counted, flush size, per-upload slot-link
  count (first 8 + every 100th), every relocate with dst/src/fmt.
- DirectRenderer's existing per-miss WARN remains the miss detector
  (it found both the 14720 pattern and the frame-1 sky-direct one).

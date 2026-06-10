# Phase A35 — attempt 1 progress: renderer port LIVE on-device (43/43 shaders compile on Adreno 618, GAME.fr3 textures load, DMA hand-off wired); arm64 bug class #7 fixed (A33's all-GPR cc truncated every 128-bit arg/return); the stale-level-DGO discovery; TWO crash frontiers retired in 7 device runs

## Headline

1. **The Android game-content renderer exists and initializes on-device.**
   `android/android_opengl_renderer.cpp` is the jak1 bucket-dispatch
   skeleton (default-regs parse, 70 buckets, vif-interrupt per bucket,
   FBO render + pcrtc window blit — mirroring OpenGLRenderer.cpp), and it
   instantiates the REAL desktop renderer subset compiled verbatim for
   Android: DirectRenderer (DEBUG/DEBUG_NO_ZBUF/SUBTITLE),
   TextureUploadHandler on all eleven jak1 *_TEX buckets, EyeRenderer,
   TexturePool, and the fr3 Loader. Device log (run 2+):
   `A35-RENDER all 43 shaders compiled under GLES 3.20`,
   `A35-RENDER common level (GAME.fr3) loaded`, on
   `GL_RENDERER=Adreno (TM) 618`. The `NO GAME CONTENT RENDERER WIRED`
   log is GONE — replaced by per-frame
   `A35-RENDER frame=N chain_bytes=M buckets_drawn=K skipped=J` stats and
   one-time `A35-RENDER skip bucket=<name> id=<n> (not ported)` lines.
   GOAL already SENDS chains (`A35-RENDER send_chain` fires during boot).

2. **arm64 codegen bug class #7, root-caused and fixed at the
   mechanism**: A33's calling convention flattened EVERY argument and
   return to a GPR slot — silently truncating 128-bit value types to 64
   bits. First load-bearing victim: `res-lump get-tag-data (this, tag
   res-tag)` — the uint128 res-tag arg arrived in X6; `FMOV D23, X6`
   zeroes bits 64..127; ZIP2 (pcpyud) yields 0; `(-> tag data-offset)`
   reads 0; get-tag-data returns data-base+0; get-property-struct derefs
   `[data-base]` = 0 — the 0 that `entity-by-name` handed to `name=`,
   whose `(-> arg0 type)` is the EE−4 that has gated the boot since A34
   run 13. Fix: goalc/emitter/CallingConvention.cpp +
   compilation/{Function,Type}.cpp — arm64 now mirrors the x86
   convention exactly (128-bit args/returns in XMM-id registers →
   V16..V31 at encode). Verified in the regenerated binary: get-tag-data
   reads the tag from V17 (= the x86 oracle's XMM1).

3. **The stale-level-DGO discovery**: the APK's 25 level DGOs (VI1.DGO =
   village1, the title screen's level!) were OLD arm64 builds predating
   A34's six fixes and the A35 cc fix. The boot only ever exercised
   KERNEL/ENGINE/GAME/TIT (which were synced); the moment run 5
   survived entity-by-name, VI1.DGO linked 55 stale objects and died in
   an A18 method-zero trap (`type='reflector-end'` — its method table
   truncated by old-codegen `new-type` flags). ALL 28 CGO/DGOs are now
   regenerated with the current backend on every sync
   (A35-baseline-arm64-cgo-hashes.txt) — the first time the level code
   on-device carries the full A34+A35 fix set.

## The forensics (7 device runs, each named its blocker in one cycle)

* Runs 1-2: crash identical to A34 run 13 (fault=EE−4 pc=0x7f004c5234).
  New A35-DIAG in the SIGSEGV handler: (a) the A16 adrp walk now NAMES
  every symbol slot it resolves; (b) ~30 suspect symbols get
  `name goal value` dumped at crash. Result: pc = `name=`+0x30 (value
  0x4c5204), crash lr = `entity-by-name`+0x1a4 (value 0x1f1b574),
  frame 1 = `process-by-ename`+0x38, frames 2-3 = camera-tracker
  `command-get-process` (the logo cutscene script looks up a process by
  name).
* Runs 3-4: window dumps over the entity res-lump + its tag array + data
  area. The level data is INTACT: 6 res-tags, tag-pair (1,1) in x2 (the
  binary search WORKED), tag[1]='name' data-offset 0x80 by-reference,
  `[data-base+0x80]` = 0x38054d4 → string **"villagea-water-2"**. Only
  the extraction of data-offset from the uint128 read 0 → disassembly
  diff vs the x86 oracle nailed the calling convention (xmm1 vs X6).
* Run 5 (cc fix + regen KERNEL/ENGINE/GAME/TIT): **the name= crash is
  DEAD** — boot proceeds: text loads, `Load soundbank village1`,
  `Adding level village1`, VI1.DGO opens... and trips the A18
  method-zero trap (stale VI1).
* Run 6: extended the A18 trap to name the type + method slot from the
  dispatch site → `type='reflector-end'` in one cycle → stale-DGO
  diagnosis.
* Run 7 (ALL 28 DGOs regenerated + synced): **both previous frontiers
  retired**. village-obs and 54 more VI1 objects link with CURRENT
  codegen; entity birth + the process tree run; the crash moves 33 ms
  past logo-intro to a process-tree walk.

## NEXT BLOCKER (named): process-tree/dead-pool-heap rec corruption

Run 7: SIGSEGV fault=0x7f1000001a pc=0x7f001900fc lr=0x7f0018d1c8.
Offline mapping against the deterministic kernel layout (6/6
dead-pool-heap method anchors vote gkernel main-seg base 0x189304):
the crashing code is a gkernel process-tree walker (fn65+0xE8) reading
`(-> ptr 0 self)` — `LDR W9,[X16]` (ppointer deref) then
`LDR W9,[X16,#24]` — where the ppointer deref returned **0x10000002**
(a process-mask-shaped value, NOT a pointer; > the 128 MB EE). Caller
frame = gkernel fn37 (the get-process/change-parent area, dead-pool-heap
m15 anchor), frame 2 = ENGINE (the display-loop process pump). I.e. a
dead-pool-heap rec's `process` field (or a child/brother ppointer slot)
holds a mask-like value when the tree is walked — the compact/churn/
get-process bookkeeping is the suspect area, and it runs every frame
once entities exist. Same forensics loop applies (the lr-window byte
matcher + the A35 sym-value dump are already in place; the gkernel base
computation above makes every future kernel address instantly nameable).

## Files changed (this attempt)

* NEW android/android_gfx.{h,cpp} — GfxRendererModule + chain hand-off
  (desktop mutex/cv pacing; syncv/sync-path now block for real).
* NEW android/android_opengl_renderer.{h,cpp} — jak1 bucket dispatch.
* android/android_renderer.cpp — glad via SDL_GL_GetProcAddress, render
  loop consumes chains, dark-blue clear only when no chain arrived.
* android/android_runtime_compat.cpp — GetCurrentRenderer() returns the
  real module; sceGsSyncV/SyncPath forward to the real pacing.
* android/gk_android_main.cpp — real impls for __send-gfx-dma-chain,
  __pc-texture-upload-now/-relocate, __read-ee-timer (was returning 0!),
  display size/mode/refresh, os/timestamp/rand, game-res/letterbox/
  vsync/frame-rate + the A35-DIAG crash dumps.
* game/graphics/opengl_renderer/Shader.cpp — Android path compiles from
  the phase-D2 GLES 3.20 blob; per-shader failure naming.
* game/graphics/texture/TexturePool.cpp — 8_8_8_8_REV → UNSIGNED_BYTE
  under __ANDROID__ (byte-identical little-endian).
* game/kernel/common/klink.cpp — A18 trap now names type + method id.
* goalc/emitter/CallingConvention.cpp, compilation/{Function,Type}.cpp —
  bug class #7 fix (shared x86 shape restored).
* android/CMakeLists.txt — renderer subset TUs + glad + imgui core +
  zstd + loader/Tfrag3Data/texture TUs.
* android/app: LoaderActivity fr3 extraction (own sentinel); assets:
  GAME/intro/title/village1.fr3 + all 28 regenerated CGO/DGOs.

## Gates

* x86 desktop smoke: PASS — `link finish: logo` (452 links), and the
  three x86 CGOs are byte-identical to the A2 baseline after both
  regens (the cc fix restores the exact x86 code paths).
* qemu: 675 link-finishes, exit 0, with the regenerated CGOs (floor
  675, no regression). Zero emitter asserts across all targets.
* nm physical gates: DirectRenderer = 62 symbols,
  DmaFollower/send_chain = 21 in build-android libgk.so (53.3 MB).
* gk_log_pipe + all A11-A34 diag infra intact (the routed logcat carried
  every dump above).
* Device evidence: A35-device-run{1..7}-{2,4,6,10,20,40}s.png +
  A35-routed-logcat-run{1..7}.log. The screencaps show the activity's
  touch overlay over the renderer's dark-blue "no chain" clear — the
  kernel still dies (33 ms after logo-intro now) before steady-state
  chain flow, so no real-content frame claim is made for this attempt;
  the named bucket-content blockers are the process-tree corruption
  above, then (renderer-side) the unported 3D buckets (sky/tfrag/tie/
  merc — logged by name when skipped).

## Hygiene

* Device eae4df44 only; egggameplus/egggame disabled per run, re-enabled
  by the EXIT trap; install via plain `adb install -r -g`; iso sentinel
  wiped only on CGO-changing runs (full 1.4 GB re-extraction, 8.7 s on
  this eMMC); fr3 sentinel independent so fr3 updates never force iso
  re-copies.
* Commits: e87604d27 (renderer port + wiring), b5f068530 (bug class #7
  cc fix + diag), + this report/klink-naming commit. The stale-DGO
  asset sync is content (gitignored) — hashes recorded in
  A35-baseline-arm64-cgo-hashes.txt.

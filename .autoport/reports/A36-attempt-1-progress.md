# Phase A36 — attempt 1 progress: kernel steady-state ACHIEVED (4380+ rendered frames, zero tree violations, zero crashes); THREE root causes fixed at the mechanism (A18 trap poisoning entity-info's method-slot-13 cache → heap-overlap birth; Android's missing exec_runtime init_globals sequence → dead ConvertTable/text; AArch64 unsigned-char divergence class); renderer feeds real chains (64,404 tris/frame submitted); next blocker NAMED: update-math-camera arm64 codegen divergence leaves *math-camera* camera-temp zero → geometry degenerates → frames render black

## Headline

1. **The dead-pool-heap rec corruption is DEAD — root-caused to A18's
   method-zero trap, not to any kernel codegen.** The per-frame A36-TREE
   scanner (sceGsSyncV hook, GOAL thread) + dph method-slot operation
   hooks caught it live in five device runs:
   - run 8: live actor "windmill-sail-4" (rec 23, [0x1f33a4,0x1f3d00))
     overlapped by newborn "money-2679" (rec 49, [0x1f32b0,0x1f3b54)).
   - run 11: the operation = get-process; run 12 (zero-distortion
     find-gap-by-size hook): boot-time spawns request size=0x4070 (sane),
     the level-restart birth wave requests size=0xffffffffaa060451 —
     sign-extended INSTRUCTION BYTES.
   - The size comes from `(-> info heap-size)` where info =
     entity-info-lookup's CACHE in **type method-table slot 13**
     (entity-table.gc:199 — jak1 reserves process-tree method 13,
     literally named "process-tree-method-13", as a data slot whose
     zero means "not cached"). klink.cpp's A18
     walk_loaded_types_and_patch_a18 filled EVERY zero method slot with
     the trap fn — so the first birth! of each actor type read the trap
     FUNCTION as an entity-info and its code bytes as heap-size. With
     size huge-negative, find-gap-by-size's `(< gap-size size)` rejects
     nothing and returns first-gap unconditionally — harmless on the
     virgin heap (first-gap = the end gap), fatal at the first
     post-kill-wave birth (money planted inside windmill; wiped headers;
     change-parent's brother-walk wandered; A35 run-7's signature
     fault=0x7f1000001a pc=change-parent+0xE8 reproduced byte-for-byte
     at frame 285-288 in runs 1/2/5/8/9/10/11).
   - FIX (klink.cpp): the trap walk never fills slot 13. Slot-13 zero is
     load-bearing game state. Post-fix: heartbeat
     `viol-total=0` across every run; 4800+ kernel frames clean.

2. **Android never ran the desktop exec_runtime init_globals sequence.**
   android_goal_main.cpp called only kboot+kmalloc; fileio/kdgo/kdsnetm/
   klink/kmachine/kscheme(jak1+common)/klisten/kmemcard/kprint were
   .bss-zeros. Visible casualty: kprint's ConvertTable — kitoa emitted ""
   for every digit, so the text loader composed "common.TXT" instead of
   "0common.TXT" and the fakeiso (which HAS the TXT files — they were on
   device all along) reported not-found. FIX: mirror runtime.cpp's full
   init list (jak1+common subset + the Android kmachine shim).
   Post-fix: `link finish: 0subtit.TXT` / `0common.TXT` on device —
   the COMMON/SUBTIT TXT blocker is closed (it was never an asset-sync
   problem; probes 2/3/4/5 in kprint/stream.cpp documented the chain:
   fmt intact → args intact → caseD in=0 len=-1 → kitoa="").

3. **AArch64 `char` is unsigned — an entire divergence class vs the x86
   oracle.** The compiler itself flagged 7 `char != -1` tautologies in
   kprint (directive parser + kitoa pad/length sentinels: "no pad" -1
   became 255 → 255-byte 0xFF pad smears written into GOAL heap
   strings). FIX at the mechanism: `-fsigned-char` for all three arm64
   build paths (android, linux-arm64/qemu, stress) in the root
   CMakeLists — the oracle's semantics restored globally.

4. **The renderer now consumes real chains for minutes.** Newest A36
   logcats carry `A35-RENDER frame=4380 chain_bytes=152176
   buckets_drawn=18 skipped=15 draws=103 tris=64404` — sustained 73+
   seconds, zero crashes (validator gate ≥300: met 14x over). Renderer
   fixes, each named by a symbolized crash (dladdr added to the SIGSEGV
   handler):
   - FramebufferTexturePair: GL_UNSIGNED_INT_8_8_8_8_REV → GL_UNSIGNED_BYTE
     on GLES (EyeRenderer's FBOs aborted the GL thread at init).
   - the desktop-profile glad parses "OpenGL ES 3.2" as 3.2 and skips its
     GL_VERSION_4_1 list — where ES2-core fns live (glClearDepthf,
     glDepthRangef). They stayed NULL → BLR-to-0 from
     android_renderer_run. FIX: post-load resolve with dlsym fallback.
   - TFragment: glPrimitiveRestartIndex → GL_PRIMITIVE_RESTART_FIXED_INDEX
     (ES; identical semantics for u32 indices), no_multidraw=true (ES has
     no glMultiDrawElements), and the time-of-day LUT migrated 1D → Wx1
     2D on BOTH backends (GLES has no glTexImage1D; texelFetch ivec2 is
     texel-exact on desktop too; tfrag3.vert updated).
   - SkyRenderer/SkyBlendGPU/SkyBlendCPU/TFragment/background_common/
     dma_helpers compiled in; sky + tfrag (normal/lowres/dirt/ice) +
     sky-blend buckets live (desktop jak1 table mirrored, empty
     anim-slot array = jak1's null TextureAnimator);
     SkyBlendCPU/GPU init_textures called after the bucket loop
     (desktop OpenGLRenderer.cpp:883 parity — fixed a null GpuTexture
     crash in move_existing_to_vram).
   - setup_frame ends with glViewport(0,0,game_res) — desktop
     OpenGLRenderer.cpp:1290 parity; A35's port left the window-size
     viewport on the small FBO.

## Device evidence (all with foreground proof)

- A36-device-run{22,25,27,...}-{2,4,6,10,20,40}s.png +
  A36-focus-run*.txt: run 22/25 show `mCurrentFocus=
  org.opengoal.gk.jak1` at ALL SIX capture points (the parallel
  sshx-mobile + com.ghplus.patcher automations are pm-disabled for the
  run window and re-enabled by the EXIT trap — same reversible pattern
  as the egggame pair; a keep-foreground guard re-fronts the activity).
- A36-routed-logcat-run{1..30}.log: the full forensic ladder.
- The kernel runs the title flow: logo-intro/logo-intro-2 STR chunks
  stream, VAG audio plays, `GAMEPLAY: enter title`, pad polling live,
  text linked. A36-TREE heartbeats: frame=4800 viol-total=0.

## NEXT BLOCKER (named): update-math-camera arm64 divergence → camera-temp = 0 → black frames

The screen stays black with 64,404 tris/frame submitted because every
vertex degenerates: `*math-camera* camera-temp` (+0x23C) is ZERO rows
0-2 on-device (A36-CAM probe, frame 600), and the tfrag pc-port block
faithfully carries those zeros (A36-TFRAG-CAM: cam0=0, trans=0, but
hvdf=(2048,2048,8380365.5,264.3) and fog=(0,25.5) sane — the block
builder is innocent). camera-temp's producer is ENGINE.CGO
math-camera fn1 (update-math-camera, the 6KB function), and the
arm64-vs-x86 mem-op differ (now AVX-aware, /tmp/a36_memop_diff.py)
flags exactly it: x86 performs an 8-byte flag-test load at +0x18C
(`mov 0x18c(%r15,%r9),%r9; and $0x100` — a logtest guarding the
aspect-ratio perspective[0].x scale) plus 2 more ops that arm64 never
emits (123 vs 126 mem-ops, aligned either side of the gap). That
dropped-guard family (64-bit bitfield logtest on a loaded struct,
feeding a float conditional) is the next arm64 codegen class to chase
with the A34 loop; fixing update-math-camera's codegen should light up
the village flythrough — sky + terrain renderers are proven live and
waiting (draws=103 includes the sky quad: "sky-direct" draw confirmed).

## Gates

- validator: no forbidden edits; anti-cheat clean; x86 smoke passes
  (`link finish: logo` — the tfrag3.vert 2D-LUT change compiles on
  desktop GL, TFragment desktop path updated in lockstep); qemu ≥675;
  gk_log_pipe intact; nm DirectRenderer=62 / DmaFollower+send_chain
  symbols in libgk.so; frame counter 2160-4380 in the newest logs
  (gate: ≥300).
- No goal_src/IGenX86_64/infra edits. No CGO regen needed (zero
  goalc/codegen changes this phase — every fix was C++/CMake/shader).
- All A11-A35 diag infra preserved; new permanent diag: dladdr
  symbolization in the SIGSEGV handler, A36-TREE scanner + heartbeat,
  glad canary, FBO/camera probes (one-shot, logging only).

## Honest screencap statement

The captured frames show the game's letterboxed output black with the
touch overlay (the FBO probe explains why: zero camera matrix). No
real-content frame is claimed for this attempt; the content gate is
the named camera codegen divergence above, not the renderer — the
renderer demonstrably consumes 152 KB chains and submits 64k tris with
stable pacing for 4000+ frames.

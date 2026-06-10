# Phase A35 — attempt 1 progress: the renderer port is LIVE (43/43 shaders compile on the Adreno 618, GAME.fr3 textures load, DMA hand-off wired end-to-end) + arm64 codegen bug class #7 root-caused & fixed (128-bit args/returns truncated to 64 bits by the A33 all-GPR calling convention — the post-logo-intro name=(0,…) crash)

## Headline

Two mandate fronts, both moved:

1. **The Android game-content renderer exists and initializes on-device.**
   `android/android_opengl_renderer.cpp` is the jak1 bucket-dispatch
   skeleton (default-regs parse, 70 buckets, vif-interrupt per bucket,
   FBO render + pcrtc window blit — mirroring OpenGLRenderer.cpp), and it
   instantiates the REAL desktop renderer subset compiled verbatim for
   Android: DirectRenderer (DEBUG/DEBUG_NO_ZBUF/SUBTITLE), a
   TextureUploadHandler on all eleven jak1 *_TEX buckets, EyeRenderer,
   TexturePool, and the fr3 Loader. Device log, run 2:
   `A35-RENDER all 43 shaders compiled under GLES 3.20` and
   `A35-RENDER common level (GAME.fr3) loaded` on
   `GL_RENDERER=Adreno (TM) 618`. The `NO GAME CONTENT RENDERER WIRED`
   log is gone — replaced by per-frame
   `A35-RENDER frame=N chain_bytes=M buckets_drawn=K skipped=J` stats and
   one-time `A35-RENDER skip bucket=<name> id=<n> (not ported)` lines.

2. **The kernel-loop blocker (EE−4 6 ms after logo-intro) is fully
   root-caused — arm64 codegen bug class #7 — and fixed at the
   mechanism.** The A33 arm64 calling convention flattened EVERY
   argument and return to a GPR slot, silently truncating 128-bit value
   types to 64 bits. The first load-bearing victim: `res-lump`
   `get-tag-data (this, tag res-tag)` — the uint128 res-tag arg arrives
   in X6, `FMOV D23, X6` zeroes bits 64..127, ZIP2 (pcpyud) then yields
   0, so `(-> tag data-offset)` reads 0, get-tag-data returns
   data-base+0, and get-property-struct derefs `[data-base]` = 0 — the 0
   that `entity-by-name` handed to `name=`, whose `(-> arg0 type)` is
   the EE−4. Fix: goalc/emitter/CallingConvention.cpp +
   compilation/{Function,Type}.cpp — the arm64 backend now mirrors the
   x86 convention exactly (128-bit args/returns in XMM-id registers,
   V16..V31 at encode). Safe now because A33's is_128bit_simd classing +
   bank-aware movers already exist; the all-GPR flattening was the
   over-correction that outlived its cause.

## The renderer port (mandate items 2+3)

* **Architecture**: `Gfx::GetCurrentRenderer()` on Android returns a real
  `GfxRendererModule` (android/android_gfx.cpp) — so `PutDisplayEnv`'s
  pmode-alp, jak1 `pc_set_levels`, `send_gfx_dma_chain` and the texture
  hooks flow through the SAME call shapes as desktop gRendererOpenGL.
  The game thread hands chains via the desktop mutex/cv handshake
  (send_chain → has_data_to_render; sync-path waits consumed; syncv
  waits frame_idx — `sceGsSyncV/SyncPath` now block for real, ending the
  free-running display loop).
* **GL loading**: glad resolved through SDL_GL_GetProcAddress (EGL/dlsym).
  GLES 3.2 provides the audited surface; the only desktop-only call in
  the ported set (glPolygonMode) was already __ANDROID__-guarded in
  phase 21. GL_UNSIGNED_INT_8_8_8_8_REV → GL_UNSIGNED_BYTE under
  __ANDROID__ (byte-identical on little-endian).
* **Shaders**: the phase-D2 GLES 3.20 blob (preprocess.py) is now consumed
  by Shader.cpp's Android path — all 43 shaders compile on the Adreno
  618 driver, first try.
* **Textures**: TexturePool::handle_upload_now links tpage slots to
  loader textures; without the Loader EVERYTHING is a checkerboard
  placeholder, so GAME.fr3 + intro.fr3 + title.fr3 (2.5 MB) ship in the
  APK (`assets/fr3/`, extracted by LoaderActivity to
  `<files>/out/jak1/fr3/` under an independent sentinel — the 1.4 GB
  iso_data extraction is untouched).
* **GOAL-visible bindings made real** (gk_android_main.cpp):
  `__send-gfx-dma-chain`, `__pc-texture-upload-now`,
  `__pc-texture-relocate`, `__read-ee-timer` (was returning 0 — every
  EE-clock read!), pc-get-active-display-size / window-size /
  refresh-rate / display-mode, pc-get-os ('linux), pc-get-unix-timestamp,
  pc-rand, pc-set-game-resolution / letterbox / vsync / frame-rate.
* **Physical validator gates**: nm -C libgk.so → DirectRenderer = 62
  symbols, DmaFollower/send_chain = 21. libgk.so 53.3 MB.

## The crash forensics (mandate item 1) — one A34-style loop, 4 device runs

* Run 1-2: crash IDENTICAL to A34 run 13 (fault=EE−4 pc=0x7f004c5234)
  — deterministic, renderer changes didn't move it. The A34-DIAG
  fp-walk gave 5 frames; 24-word windows byte-matched (full-window,
  unique hit) into GAME.CGO obj#265 `entity`.
* New A35-DIAG (this phase, in the SIGSEGV handler): (a) the A16 adrp
  walk now NAMES every symbol slot it resolves; (b) a fixed list of ~30
  suspect symbols gets `name goal value` dumped at crash. That turned
  run 2 into the full chain: pc = `name=` + 0x30 (value 0x4c5204 ✓);
  crash lr = `entity-by-name` + 0x1a4 (value 0x1f1b574 ✓); frame 1 =
  `process-by-ename` + 0x38; frames 2-3 = camera-tracker territory
  (`command-get-process` — the logo cutscene script asking for a process
  by name).
* Run 3-4: raw window dumps over x3 (the entity res-lump) + x1 (its tag
  array) + the lump data area. The entity is INTACT: 6 res-tags;
  tag-pair (1,1) in x2 = the lookup WORKED; tag[1] = 'name, key-frame
  −1e9, data-offset 0x80, by-reference; `[data-base+0x80]` =
  0x38054d4 → a real string **"villagea-water-2"**. The data and the
  binary search are perfect — only the data-offset EXTRACTION from the
  uint128 tag reads 0.
* Disassembly diff (x86 oracle vs arm64, res obj fn3 `get-tag-data`):
  x86 receives the tag in **XMM1** (`vpunpckhqdq %xmm1…`); arm64
  receives it in **X6** (`FMOV D23, X6` → high 64 bits = 0 →
  ZIP2 .2D → 0 → LSL16/LSR48 → data-offset 0). get-property-struct
  itself disassembles CORRECT on arm64 — the truncation is purely the
  call-boundary convention.

## The fix (bug class #7 of the arm64 backend)

* goalc/emitter/CallingConvention.cpp: removed the A33
  `#ifdef GOALC_BACKEND_ARM64` all-GPR branches in BOTH
  get_function_calling_convention and get_arg_registers — 128-bit value
  args bind to XMM-id arg registers, 128-bit returns to the XMM return
  register, identical to x86 (the varargs/format path stays all-GPR on
  both, unchanged).
* goalc/compiler/compilation/Function.cpp + Type.cpp: removed the
  matching A33 return-path branches (to_xmm128 + INT_128 return classes
  restored) and the bitfield-inspect arg constraint branch.
* Why this is safe NOW: A33 introduced the flattening because the
  then-inverted is_128bit_simd classing let XMM-id constraints leak into
  GPR-op encodes (X16/X17/X20-22 clobbers). A33 itself fixed that
  inversion AND added the bank-aware mover
  (emit_arm64_reg_to_reg_mov: fp→fp = full 128-bit MOV Vd.16B) and the
  128-bit spill machinery (store128/load128_xmm128_reg_offset on the
  arm64 side). The shared compiler code (call-site staging via
  is_128bit_simd, INT_128 param classes at Function.cpp:196/Type.cpp:578,
  inline-call return classes) was ALREADY written for the x86 shape —
  the arm64 special case was the only divergence.
* x86 byte-identity: build/goalc (x86) output verified hash-identical to
  the A2 baseline after the regen (the removed ifdefs restore the exact
  x86 code path; the desktop x86 gk binary also rebuilt + smoke-passes
  `link finish: logo`).

## Gates at time of writing

* x86 desktop smoke: PASS (452 link-finishes, `link finish: logo`).
* qemu (pre-CGO-regen): 675 link-finishes, exit 0 — re-run after the
  regen below.
* nm gates: DirectRenderer=62, dma=21 — PASS.
* Device evidence: A35-device-run{1..4}-{2,4,6,10,20,40}s.png +
  A35-routed-logcat-run{1..4}.log. Runs 1-4 still show the pre-fix
  crash (the fix's CGO regen is the step in flight); screencaps show
  the touch overlay + dark-blue clear (kernel dies before chains flow).

## Next (in flight)

* Regenerate arm64 KERNEL/ENGINE/GAME.CGO + TIT.DGO with the fixed cc
  (B1-pipeline mirror), restore + hash-verify x86, re-run qemu (floor
  675), sync APK assets, full-extraction device run, multi-frame
  screencaps. If the kernel survives entity-by-name, the logo flow's
  chains hit the now-live renderer — first real-content frame attempt.

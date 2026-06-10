# Phase A35 — Android renderer bring-up: DMA chains → GLES 3.2 → FIRST REAL CONTENT FRAME

## Where we are (read these first)

- `.autoport/reports/A34-attempt-2-progress.md` — A34 fixed SIX arm64 codegen/runtime bug classes (init_crc missing on custom boot paths; push-RA trampoline contract + .load-sym-to-SP ×2; silent offset truncation — 620 sites; float conditionals comparing the WRONG REGISTER BANK — 605 sites; LDR-literal static loads that cannot span the heap — 304 sites; PS2 128-bit SIMD ops with wrong arrangements). On-device boot: **427 link-finishes** (through `title-vis` INTO `logo-intro`), display loop starts, renderer thread alive.
- Two things now stand between us and the title screen:
  1. **Kernel loop not yet stable**: SIGSEGV 6 ms after `link finish: logo-intro` — `fault=0x7efffffffc` (EE−4 again) `pc=0x7f004c5234 lr=0x7f01f1b708`. Same −4 family A34 kept killing. The A34-DIAG arsenal (full reg dump, fp-chain walk, *camera* window, disasm windows) is live in `android/gk_android_main.cpp` — use it.
  2. **There is no game-content renderer on Android.** `android/android_renderer.cpp` (185 lines) is an honest GLES 3.2 clear/swap stub that logs `NO GAME CONTENT RENDERER WIRED`. The desktop renderer (`game/graphics/opengl_renderer/**`) is not even compiled into libgk.so, and `__send-gfx-dma-chain` is bound to a drain stub in `android/gk_android_main.cpp` (~line 519). Even a perfect GOAL boot draws dark blue.

## Mandate (in order)

1. **Stabilize the kernel display loop.** Root-cause the post-logo-intro EE−4 with the existing diag arsenal. Candidates: (a) yet another arm64 codegen class (A34 found six — use the same instruction-level forensics + x86-oracle object diffing), (b) a pc-port hook stub returning 0/#f where GOAL expects real data — audit `game/kernel/common/kmachine.cpp`'s `make_func_symbol_func` surface (e.g. screen-size / display-mode / vsync hooks) against what Android actually binds in `gk_android_main.cpp`; a 0 return feeding display math yields exactly these −1-index/−4 faults. Fix honestly — no null-guards that skip display init. Keep fixing until the loop RUNS (sustained frames, kernel alive past 30 s).
2. **Wire the DMA chain hand-off.** Desktop path is `kmachine.cpp:486`: `send_gfx_dma_chain` → `Gfx::GetCurrentRenderer()->send_chain(g_ee_main_mem, chain)`. On Android, replace the drain stub: copy the chain (or hand the offset) to the renderer thread each frame. `DmaFollower` / `dma_chain_read.h` is portable C++ — compile it for Android.
3. **Port the minimum renderer subset to GLES 3.2** for first visible content:
   - `OpenGLRenderer` skeleton (bucket dispatch over the DMA chain) — compile for Android, stripped to the buckets you port.
   - `DirectRenderer` (~1.5 kLOC) — draws the GIF-packet immediate primitives: legal/text/loading screens and 2D content. This is the first-content workhorse.
   - `TexturePool` + the texture upload path (`__pc-texture-upload-now` currently stubbed on Android — make it feed the pool like linux/desktop does).
   - Shaders: desktop GLSL (`#version 410/430`) → `#version 320 es` + precision qualifiers. Known deltas to handle honestly: no `glClipControl` in core GLES (use `GL_EXT_clip_control` if the Adreno driver exposes it, else compensate in the projection/shader), no logic ops, no 1D textures.
   - **Unported buckets: skip with a ONE-TIME named log each** (`A35-RENDER skip bucket=tfrag3 (not ported)`) — never silently, never faking output. Replace the `NO GAME CONTENT RENDERER WIRED` log with real consumption + per-frame chain stats (`A35-RENDER frame=N chain_bytes=M buckets_drawn=K skipped=J`).
4. **Capture frames.** Multi-frame screencaps at 2/4/6/10/20/40 s → `.autoport/reports/A35-device-*.png`. First frame with REAL game content (legal text, loading visuals, ND logo, title screen) = the project goal. If content needs a bucket you haven't ported, name the exact bucket + what it draws in the report.

## Device rules (shared device — unchanged + new lessons)

`export ANDROID_SERIAL=eae4df44` ONLY (never emulator-5554). `source .autoport/lib/android-env.sh`. Package `org.opengoal.gk.jak1` / LoaderActivity. Disable `com.xiaoji.egggameplus` + `com.xiaoji.egggame` reversibly; **re-enable both when done**. Keep APK CGOs synced from `out/jak1-arm64/iso/`. Install dialog is pre-approved (user set Remember) — plain `adb install -r -g` works, ~35 s. If the device spontaneously reboots: it is probably a Google Play Mainline staged train (`adb shell getprop sys.boot.reason` → `reboot,rollback_staged_install`) — wait for re-enumeration, check `sys.boot_completed`, note it in the report; the user may need to unlock the screen once (storage locked until first unlock).

## Scope

**UNLOCKED**: `android/**`, `game/**` (incl. `graphics/opengl_renderer/**` ports), `goalc/**` except the oracle, `common/**`.

**LOCKED**: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts.

## Anti-cheat (hard rules)

1. x86 desktop still boots to `link finish: logo`; qemu ≥ 675 (no regression).
2. **A render claim is ONLY a screencap with real game content** — the supervisor independently re-captures and reads every frame. Painted test patterns, solid colors, or hardcoded textures are cheats. Chain-consumption counters must correlate with the GOAL kernel actually running.
3. No weak/abort-additions/dodge/stubs; no skipping display init; no silencing the honest renderer logs — replace them with real paths.
4. Preserve ALL prior fixes/infra (gk_log_pipe, A32 bindings, A33 calling-convention + bank asserts, all six A34 fixes, the A34-DIAG arsenal).

## Deliverables (lean)

- **A35-fix-summary.md** (≥80 lines) with a real-content screencap, OR **A35-attempt-N-progress.md / next-blocker.md** (≥80 lines): kernel-loop status (stable? crash evolution), what got wired/ported (chain hand-off, buckets), per-frame chain stats from the routed logcat, screencaps, the exact next blocker (named bucket / named crash).
- Screencaps → `.autoport/reports/A35-device-*.png`; CGO baseline file if CGOs changed.

## Validator (`phase-A35-android-renderer-dma-to-gles.sh`)

Lean + physical: no forbidden edits/cheats; x86 boots; qemu ≥ 675; gk_log_pipe preserved; **nm finds DirectRenderer + DmaFollower symbols compiled into libgk.so**; ≥1 A35-device-*.png; report ≥ 80 lines. Render judged by the supervisor's eyes.

## Max settings

`max_turns: 2500`, `max_retries: 3`. Budget ~$250.

## Strategic note

A34 ended the codegen war — six bug classes, each verified by the boot line moving. What remains is plumbing and a focused C++ port: the kernel builds DMA chains every frame already; nothing reads them. DirectRenderer + textures gets legal/loading/2D content on glass — likely the first real pixels of the whole project. The 3D scene buckets (tfrag/tie/merc for the title) are the phase after, unless momentum carries you there. Go.

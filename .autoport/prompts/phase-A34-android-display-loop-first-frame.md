# Phase A34 — Android: fix the post-title-vis sentinel deref → start the display loop → FIRST RENDERED FRAME

## Where we are (read these first)

- `.autoport/reports/A33-fix-summary.md` — A33 fixed the shared calling-convention/classing inversion: **qemu now links AND executes everything, exit 0, 675 link-finishes incl. `link finish: logo`, TIT.DGO staged.** The fast-loop work is done; qemu's harness ends at execute-complete and never runs the display loop.
- `.autoport/reports/A33-routed-logcat-attempt1.log` — the device boot: **369 link-finishes**, through `ndi` / `ndi-cam` / `ndi-volumes` / **`title-vis`** (the title-screen data!), app stable in **landscape** with the touch overlay rendered (screencap `A33-device-4-1500ms.png`). Then, 2 ms after `link finish: title-vis`:

```
GK-DIAG sig=11 fault=0x7efffffffe pc=0x7f01ce0b98 lr=0x7f01ce0bd8
x0=0x14fd24 x1=0x14fd2c x2=0x14fd24 x3=0x0 x9=0x14fd1a x8=0x4
```

**fault = device EE_base (0x7f00000000) − 2** → a GOAL pointer of `-2` (0xfffffffe) was host-converted and dereferenced. `x3=0`, small kernel-global-area values in x0/x1/x2/x9 (~0x14fd2x, near kglobalheap base). This fires in display/title-screen startup code that qemu never executes (its harness exits after link/execute). A `-2`/uninitialized-sentinel field — likely a display/video-mode/profile global that Android's init path never populated (another linux-vs-android runtime divergence, same family as A32's missing pc-helper bindings).

## Mandate

1. **Root-cause the −2 deref.** Disassemble around pc=0x7f01ce0b98 (GOAL offset ~0x1ce0b98) in the on-device CGOs; identify the GOAL function (it runs right after title-vis links — display/title init). Find which global/field holds −2 or is read uninitialized. Compare what initializes it on x86 desktop (kmachine/kdgo/display init in `game/kernel/**`) vs what the Android runtime does (`android/gk_android_main.cpp`, `android/android_runtime_compat.cpp`) — A32 proved these diverge (bindings never back-ported). The linux-arm64 runtime (`game/linux-arm64/linux_arm64_main.cpp`) is the richer reference: it has A11-A29 bindings/init the Android side may still lack. Audit the FULL delta between linux_arm64_main's GOAL-visible init surface and Android's — fix the gap class, not just this one symbol.
2. **Fix it (no guards/stubs that skip display init).** Then keep fixing any subsequent crash until **the display loop runs and the renderer draws the first frame** (Naughty Dog logo / title screen).
3. **Capture the frame.** Multi-frame screencaps during boot (the 1.5 s overlay capture worked; the kernel boots its 369 DGOs in ~3-4 s on-device, so capture at ~2 s, 4 s, 6 s, 10 s, 20 s, 40 s) → `.autoport/reports/A34-device-*.png`. The moment a frame shows REAL game content (ND logo, title screen), that's the project goal. If the display loop runs but draws black/garbage, name exactly which renderer stage (DMA chain transfer? GS unpack? texture upload? GLES draw?) produces nothing — evidence from the routed logcat + the android_renderer markers.

## Device rules (shared device — unchanged)

`export ANDROID_SERIAL=eae4df44` ONLY (never emulator-5554). `source .autoport/lib/android-env.sh`. Package `org.opengoal.gk.jak1` / `org.opengoal.gk.LoaderActivity`. Disable `com.xiaoji.egggameplus` + `com.xiaoji.egggame` reversibly for clean boots; **re-enable both when done**. Keep APK assets CGOs synced from `out/jak1-arm64/iso/` (A30's stale-CGO trap). d4_run.sh or manual; warm cache = fast installs. Routed logcat via gk_log_pipe is your eyes.

## Scope

**UNLOCKED**: everything except hard locks — `android/**`, `game/**` (kernel, linux-arm64 reference, graphics/renderer), `goalc/**` except the oracle, `common/**`.

**LOCKED**: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts.

## Anti-cheat (only hard rules)

1. x86 desktop still boots to `link finish: logo`.
2. qemu ≥ 675 (no regression).
3. No fake output of any kind — **a "rendered frame" claim is ONLY a screencap with real game content** (the supervisor independently re-captures to verify; black/dark-blue/overlay-only ≠ render). No weak/abort-additions/dodge/stubs; no skipping display-init to avoid the crash.
4. No edits to goal_src/, IGenX86_64.*, .autoport infra.
5. Preserve all prior fixes/infra (gk_log_pipe, A32 bindings, A33 calling-convention fix + bank asserts, tracers).

## Deliverables (lean)

- **A34-fix-summary.md** (≥80 lines) ONLY with a real-content screencap: root cause, fix, on-device count, which frame shows what.
- OR **A34-attempt-N-progress.md / next-blocker.md** (≥80 lines): named root cause of the −2 deref, fix landed, where the boot now stops, screencaps + routed-logcat tail, the exact next blocker (e.g., the named renderer stage if display runs but draws nothing).
- Screencaps → `.autoport/reports/A34-device-*.png`; baseline file if CGOs changed.

## Validator (`phase-A34-android-display-loop-first-frame.sh`)

Lean: no forbidden edits/cheats; x86 boots; qemu ≥ 675; gk_log_pipe preserved; ≥1 A34-device-*.png; report ≥ 80 lines. The render claim is judged by the supervisor's own eyes.

## Max settings

`max_turns: 2500`, `max_retries: 3`. Budget ~$250.

## Strategic note

Everything is loaded: engine, game, ND-logo assets, title-vis. The app is stable, landscape, overlay up. One sentinel deref stands between the kernel and its display loop. Fix the init gap (audit the whole linux-vs-android init delta while you're in there — A32 and this bug are the same disease), let the display loop spin, and bring back the first frame. That frame is the entire project's goal.

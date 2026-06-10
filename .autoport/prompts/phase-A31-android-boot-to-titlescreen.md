# Phase A31 — Android: push the on-device boot from 291 through init to the display loop + render the title screen

## Status / why

A30 got the GOAL kernel RUNNING on the real device (Redmi Note 9 Pro) for the first time — from "0% CPU, never started" to **291 on-device link-finishes** — by routing native stdout/stderr to logcat (`gk_log_pipe` in `android/gk_android_main.cpp`), fixing the real "won't start" cause (the egggameplus launcher + MIUI AdbInstallActivity dialog hijacking the activity transition, NOT a surface block), fixing an Android `MAP_FIXED_NOREPLACE` SIGILL, and refreshing the stale APK CGOs to the A29 build. The SDL/Adreno GL surface now comes up (dark-blue clear loop runs).

**But the device boot SIGSEGVs at the `progress-part` CGO top-level (on-device link #291)** — mid-init, BEFORE the game's display/dispatch loop. qemu reaches 660 link-finishes; the 291→660 gap is Android-specific crashes that qemu (headless, different memory map) doesn't hit. The title screen (`logo`) only *draws* once the display loop runs after init — so we must clear the remaining on-device init crashes to get there.

A31 continues the wide-sprint Android bring-up. Read `.autoport/reports/A30-attempt-1-progress.md` and `.autoport/reports/A30-routed-logcat-tail.txt` first — they have the exact crash point + what's already fixed.

## Mandate

1. **Fix the post-291 `progress-part` SIGSEGV on-device.** The routed logcat shows exactly where it dies. Likely an Android-specific memory-layout / renderer-DMA / stubbed-pc-helper issue (qemu doesn't hit it). Diagnose via the routed logcat (and add targeted logging if needed).
2. **Keep fixing** each subsequent on-device crash (same wide-sprint style) to push the on-device link-finish count from 291 toward 660 and into the **display/dispatch loop**.
3. **Render the title screen.** Once the kernel enters the display loop, the renderer (GOAL DMA → PS2 GS → GLES) should draw. Capture a screencap. If it draws the title screen → goal reached. If the renderer is incomplete (black/dark-blue clear but no game content even though the kernel is in the dispatch loop), name exactly what the renderer is missing (which GS/DMA path) so A32 can scope it.

The on-device link-finish count (from routed logcat) is the progress metric now — NOT qemu (qemu is already at 660 and won't change from Android-only fixes).

## Device specifics (READ — shared device)

- **ONLY** `export ANDROID_SERIAL=eae4df44` (the Redmi). NEVER touch `emulator-5554` (a parallel project's x86 emulator). The device also hosts other game-port projects (Mario64 Coop, GameHub) — only operate on `org.opengoal.gk.jak1`.
- adb: `source .autoport/lib/android-env.sh`. Package `org.opengoal.gk.jak1`, launch activity `org.opengoal.gk.LoaderActivity`.
- The `com.xiaoji.egggameplus` + `com.xiaoji.egggame` launcher steals foreground. Disable reversibly (`pm disable-user --user 0 <pkg>`) before a clean boot test, **re-enable both (`pm enable`) when done** — they're shared-device apps, always restore them.
- Build+install+capture: `.autoport/lib/d4_run.sh` (warm cache → fast). Routed logcat lands in `.autoport/reports/D4-boot.log`.
- **CGO freshness (important)**: A30 found the APK shipped STALE CGOs. Before each device test, ensure the APK assets have the CURRENT arm64 CGOs: the asset dir is `android/app/src/jak1/assets/iso_data/jak1/`; sync from `out/jak1-arm64/iso/` if they differ (A30 did this manually). If you change codegen/CGOs, re-sync before building the APK. Consider wiring the sync into the repo build so it can't go stale again (a CMake/gradle rule or a documented step — but NOT in .autoport/lib, which is locked).

## Scope (same wide unlocks as A30)

**UNLOCKED**: everything except the hard locks. Especially `android/**`, `game/linux-arm64/**`, `game/kernel/**`, `game/system/**`, the renderer code, all of goalc except IGenX86_64.

**LOCKED**: `goalc/emitter/IGenX86_64.{cpp,h}` (x86 oracle), `goal_src/**` (GOAL source), `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts.

## Anti-cheat (only hard rules)

1. x86 desktop still boots to `link finish: logo`.
2. qemu link-finish ≥ 660 (no regression).
3. No fake link-finish / fake renderer output; no weak/abort-additions/dodge/`*_stubs.cpp`.
4. No edits to goal_src/, IGenX86_64.*, .autoport infra.
5. **A black/dark-blue screen is NOT a rendered title screen.** Only claim a render if the screencap shows actual game content; the supervisor will independently screencap to verify. Honest progress/next-blocker exits are fine and expected.
6. Preserve A30's gk_log_pipe routing + the MAP_FIXED fix (don't regress them).

## Deliverables (lean)

- **A31-fix-summary.md** (≥80 lines) only if the screencap shows the title screen (or real game content): what you fixed, the on-device link-finish count reached, the screencap path.
- OR **A31-attempt-N-progress.md** / **next-blocker.md** (≥80 lines): on-device link-finish count reached (paste routed logcat tail), the current crash/blocker with evidence, the screencap.
- Save device screencaps to `.autoport/reports/A31-device-*.png`.

Evidence (routed logcat + screencap) over prose.

## Validator (`phase-A31-android-boot-to-titlescreen.sh`)

1. No goal_src / IGenX86_64 / infra edits; no weak/abort-adds/dodge/stubs/fake-link.
2. x86 desktop smoke reaches `link finish: logo`.
3. qemu link-finish ≥ 660 (no regression).
4. A30's gk_log_pipe routing still present in android/gk_android_main.cpp.
5. ≥1 `A31-device-*.png` screencap captured (>1 KB) + a report ≥ 80 lines.
6. Supervisor independently screencaps to judge any render claim.

## Max settings

`max_turns: 2500`, `max_retries: 3`. Budget ~$250 (device iteration is slower).

## Strategic note

This is the home stretch. The kernel runs on-device and the surface is up; what remains is clearing the Android-specific init crashes (291→display loop) and confirming the renderer draws. If the renderer turns out to need real GS/DMA work once the kernel reaches the dispatch loop, name precisely what's missing. The routed logcat + screencap are ground truth — the supervisor judges the image.

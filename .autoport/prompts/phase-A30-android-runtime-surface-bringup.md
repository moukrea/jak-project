# Phase A30 — Android runtime bring-up: get the GOAL kernel to actually RUN + render on the real device

## Why this phase (the pivot)

The codegen is essentially done. Two wide sprints (A28, A29) took qemu from the 8-phase 216 ceiling to **660 link-finishes** — past the title screen (`logo`) into Geyser Rock level loading. **But the kernel does not run on the real device.** A30 pivots from qemu-codegen to Android-runtime integration. Same lean wide-sprint methodology.

## The device finding (your starting point)

On the real device (Redmi Note 9 Pro, arm64), with the foreground-stealing launcher disabled, the app:
- Loads libgk.so, mmaps the 128 MB EE memory, completes `MainActivity onCreate`, sets up the touch overlay.
- Then sits at **0.0% CPU, State=S (sleeping), 20 threads, black PORTRAIT screen** (landscape expected), **no GOAL kernel boot, no renderer markers, no crash/tombstone.**

**Interpretation**: `gk_main`/the GOAL kernel boot never starts on Android. The SDL main thread (which runs SDL_main → gk's main → the GOAL kernel loop) is almost certainly blocked in startup — waiting on GL-surface/EGL-context creation that never completes, OR a lifecycle/threading gap. The kernel is idle *before* it even begins interpreting bytecode (0% CPU rules out "booting invisibly").

Also: **native stdout/stderr is NOT routed to logcat on Android**, so the GOAL kernel's `link finish:` / printf output is invisible on-device. You are debugging blind until you fix this.

## Mandate (in order)

1. **Route native gk stdout+stderr to logcat FIRST.** Without this you can't see the on-device boot. dup2(pipe) → a reader thread calling `__android_log_write`, or equivalent, in the Android gk entry (`android/gk_android_main.cpp` / wherever main starts). Then a device launch will show the same `link finish:` lines qemu shows — that alone tells you how far the kernel gets on-device.
2. **Diagnose why `gk_main` doesn't run** (the 0% CPU). Look at `android/gk_android_main.cpp`, the SDLActivity/SDL_main path, the InitMachine/display-init sequence, and where startup waits for the SDL window / GL surface / EGL context. Compare to how linux-arm64 starts gk. The hypothesis: a surface-format / EGL-config / GLES-context-creation issue on the Adreno GPU, or gk_main blocking on a window that the Android lifecycle never delivers.
3. **Get the kernel booting on-device toward `logo` + the display loop.** Once logs are routed you'll see exactly where it stops. Fix forward (same wide-unlock latitude). The kernel will run the SAME boot qemu does (it should reach ~logo, maybe crash later at the Geyser-Rock level-load like qemu's 660 SIGSEGV — that's fine, the title screen renders before that).
4. **Render the title screen + screencap it.** When the display loop runs, the renderer (GOAL DMA → GS-emulation → GLES) draws. Capture a screencap and assess: title screen? black? garbage? If the renderer is stubbed/incomplete, name exactly what's missing.

Iterate fix → build → install-on-device → capture. This is device-centric, so the inner loop is APK build + install (warm cache: iso_data is already extracted, so installs are fast and no 1.4 GB re-extract).

## Device specifics (READ — shared device)

- **Target ONLY the real device**: `export ANDROID_SERIAL=eae4df44` (Redmi). There is ALSO an `emulator-5554` (x86) for a parallel project — NEVER touch it.
- adb is at `~/Android/platform-tools`; `source .autoport/lib/android-env.sh` or add to PATH.
- The `com.xiaoji.egggameplus` / `com.xiaoji.egggame` GameHub launcher steals foreground (backgrounds our app → SDL pauses the thread). For a clean test: `adb -s eae4df44 shell pm disable-user --user 0 com.xiaoji.egggameplus` (and egggame) before launching, and **re-enable both with `pm enable` when done** (they're shared-device apps — always restore them).
- Build+install+launch helper: `.autoport/lib/d4_run.sh` (builds libgk.so + APK, installs, launches, captures logcat to `.autoport/reports/D4-boot.log`). It already wipes the `.extracted_v1` sentinel so fresh CGOs reach the device. Or do the steps manually. After your log-routing fix, D4-boot.log will show the GOAL kernel output.
- App: package `org.opengoal.gk.jak1`, launch activity `org.opengoal.gk.LoaderActivity` (→ MainActivity).
- Manifest already locks MainActivity to landscape + handles orientation via configChanges, so orientation isn't the blocker — foreground + surface/threading is.

## Scope (same wide unlocks)

**UNLOCKED**: everything EXCEPT the three hard locks. Especially: `android/**` (the activity, SDL glue, `gk_android_main.cpp`, the Android renderer), `game/linux-arm64/**` (shared SDL/surface/runtime bits), `game/kernel/**`, `game/system/**`, all of goalc except IGenX86_64.

**LOCKED**: `goalc/emitter/IGenX86_64.{cpp,h}` (x86 oracle), `goal_src/**` (GOAL source), `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts.

## Anti-cheat (the only hard rules)

1. **x86 desktop still boots to `link finish: logo`.**
2. **qemu link-finish count ≥ 660** (no regression — Android changes shouldn't touch codegen/qemu).
3. No fake "link finish" / fake renderer output; no `__attribute__((weak))`, no `abort()` additions, no dodge patterns (`gk_recover_to_renderer`, forced-recovery), no `*_stubs.cpp`.
4. No edits to goal_src/, IGenX86_64.*, or .autoport infra.
5. **A black screen is not a pass.** "Renders the title screen" means the screencap shows actual game content. If you can't get there, that's an honest progress/next-blocker exit — don't claim a render you can't show. Don't fake a renderer marker.

## Deliverables (lean)

- **A30-fix-summary.md** (≥80 lines) if the kernel boots on-device AND you have a screencap showing the title screen (or meaningful rendered content): what you fixed (log routing, surface/threading), how far the on-device boot gets (paste the routed logcat `link finish:` tail), the screencap path + what it shows.
- OR **A30-attempt-N-next-blocker.md** / **A30-attempt-N-progress.md** (≥80 lines): logs now routed, on-device boot reaches link-finish N (paste it), the specific blocker (surface init / renderer gap / crash) with evidence + screencap.
- Save the device screencap(s) to `.autoport/reports/A30-device-*.png`.

Keep reports tight. Evidence (routed logcat + screencap) over prose.

## Validator (`phase-A30-android-runtime-surface-bringup.sh`)

1. No goal_src / IGenX86_64 / infra edits; no weak/abort-adds/dodge/stubs/fake-link.
2. x86 desktop smoke reaches `link finish: logo`.
3. qemu link-finish count ≥ 660 (no regression).
4. Native-log-routing code present in the Android entry (grep for the dup2/`__android_log` stdout routing).
5. One A30 report ≥ 80 lines + at least one `A30-device-*.png` screencap present.
6. (Supervisor does the independent device screencap to confirm any rendering claim.)

## Max settings

`max_turns: 2500`, `max_retries: 3`. Budget ~$200.

## Strategic note

This is the last bounded chunk before "title screen on device": make the kernel run + the surface come up + the renderer draw. The renderer (GOAL DMA → PS2 GS → GLES) is the genuine unknown — once the kernel runs on-device, the screencap tells us if it's solid or stubbed. Route the logs, unblock gk_main, and push to a visible title screen. If the renderer turns out to need real work, name exactly what's missing so the next phase can scope it.

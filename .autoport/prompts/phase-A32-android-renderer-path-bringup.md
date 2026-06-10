# Phase A32 — Android renderer-path bring-up: fix the null-object dispatch at tpage-463 (device now exercises the real renderer qemu skips)

## The key reframe

qemu reaches 660 link-finishes; the device reaches 316 and crashes — same arm64 CGOs, so the difference is the RUNTIME ENVIRONMENT. The device crash is at **`tpage-463`** (#316): a `type-method-zero` dispatch on a NULL/freed object (`obj-goal=0x0`, method slot loads `0xdeadbeef` = freed-heap poison → BLR to EE_BASE → SIGILL). **`tpage-463` = texture-page data = RENDERER.** The device has a real Adreno GL renderer + GS-emulation path that qemu (headless) skips or stubs. So the remaining device-only crashes are almost certainly **renderer / GS-emulation / texture-page bugs that qemu never exercises** — this is the "renderer is the real unknown" surface, now reached.

A31 was diagnostics-only (the +25 was ASLR drift, no real fix — honest but low-yield). A32 must LAND A FIX and push the on-device boot past 316 toward the display loop + a rendered title screen. Wide-sprint methodology: fix, don't just instrument.

Read first: `.autoport/reports/A31-attempt-2-progress.md` (the crash characterization), `.autoport/reports/A31-routed-logcat-attempt2.log` (the GK-DIAG A18 type-method-zero dump at the crash).

## Mandate

1. **Identify the null/freed object at tpage-463.** The A18 `a18_method_zero_trap` infrastructure (from the linux-arm64 side) catches exactly this NULL-self method-dispatch pattern and can name the missing method/type. Ensure that trap (or equivalent diagnostic) is ACTIVE on the Android build so the crash names WHICH object/method/type is null — then trace back to why it's null/freed on Android but not qemu.
2. **Root-cause, don't whack-a-mole.** `0xdeadbeef` = a freed object reused, or an object never allocated. Likely systemic: (a) the Android EE heap layout/size differs from qemu (compare g_ee_main_mem size + the kheap/kglobalheap/kdebugheap config in gk_android_main vs linux_arm64_main — a smaller/mismapped heap → failed alloc → null object); (b) a renderer/texture-page init path that runs on real GL (device) but is skipped headless (qemu) and has a latent bug; (c) an init-order difference (Android threads/IOP/display start differently). Align the device runtime config with qemu's where they diverge.
3. **Fix it + keep going.** Push the on-device link-finish count past 316 through the remaining renderer/init crashes toward the display loop. Each device-only crash you clear is progress.
4. **Render the title screen + screencap** when the display loop runs. If the renderer (GOAL DMA → GS → GLES) draws incomplete/garbage, name exactly which GS/DMA/texture path is missing.

On-device link-finish count (routed logcat) is the metric. **You MUST advance past 316 with a real fix** — an instrumentation-only phase that drifts is not acceptable this time; if you cannot fix, the honest exit names the exact root cause + the file/function for A33.

## Device specifics (READ — shared device)

- ONLY `export ANDROID_SERIAL=eae4df44` (Redmi). NEVER `emulator-5554`. Other game-port projects share the device — only touch `org.opengoal.gk.jak1`.
- `source .autoport/lib/android-env.sh`. Package `org.opengoal.gk.jak1`, activity `org.opengoal.gk.LoaderActivity`.
- Disable `com.xiaoji.egggameplus` + `com.xiaoji.egggame` reversibly (`pm disable-user --user 0`) for a clean foreground boot; **re-enable both (`pm enable`) when done**.
- `.autoport/lib/d4_run.sh` builds+installs+captures (warm cache → fast). Routed logcat → `.autoport/reports/D4-boot.log` (A30's gk_log_pipe makes GOAL output visible).
- CGO freshness: keep `android/app/src/jak1/assets/iso_data/jak1/*.CGO` synced from `out/jak1-arm64/iso/` before each APK build (A30 found stale CGOs once). If you change codegen, re-sync.

## Scope

**UNLOCKED**: everything except hard locks. Especially the renderer (wherever GS-emulation / texture-page / DMA→GLES lives — likely `game/graphics/**`, `game/kernel/**`, `android/**`), `game/linux-arm64/**`, all of goalc except IGenX86_64.

**LOCKED**: `goalc/emitter/IGenX86_64.{cpp,h}` (x86 oracle), `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts.

## Anti-cheat (only hard rules)

1. x86 desktop still boots to `link finish: logo`.
2. qemu link-finish ≥ 660 (no regression).
3. No fake link-finish/renderer output; no weak/abort-additions/dodge/`*_stubs.cpp`.
4. No edits to goal_src/, IGenX86_64.*, .autoport infra.
5. Preserve A30's gk_log_pipe routing + the MAP_FIXED fix + A31 diagnostics.
6. **Black/dark-blue ≠ rendered title screen.** Only claim a render with a screencap showing real game content; the supervisor verifies independently. NULL-object dispatch must be fixed by making the object valid (correct alloc/init), NOT by null-guarding the dispatch to skip it (that just hides the bug and the renderer still won't draw).

## Deliverables (lean)

- **A32-fix-summary.md** (≥80 lines) if the screencap shows the title screen / real content: the root cause, the fix, the on-device link-finish count reached, screencap path.
- OR **A32-attempt-N-progress.md** / **next-blocker.md** (≥80 lines): the NAMED root cause of the tpage-463 null object (which object/type/method, why null on Android), the fix attempted, on-device count reached (paste routed logcat tail), screencap, the next blocker.
- Save device screencaps to `.autoport/reports/A32-device-*.png`.

## Validator (`phase-A32-android-renderer-path-bringup.sh`)

Same lean gates as A31 (no forbidden edits/cheats, x86 boots, qemu≥660, gk_log_pipe preserved, ≥1 A32-device-*.png + report ≥80 lines). Supervisor judges the screencap + the on-device advance.

## Max settings

`max_turns: 2500`, `max_retries: 3`. Budget ~$250.

## Strategic note

The device exercising the real renderer is the moment of truth for the "is the renderer stubbed" question. If tpage-463's null object traces to a renderer-init path that was stubbed/incomplete (D-bucket), that's the named gap. Root-cause it. The title screen is on the far side of the renderer coming up — get the texture-page/GS path working and the display loop should draw it.

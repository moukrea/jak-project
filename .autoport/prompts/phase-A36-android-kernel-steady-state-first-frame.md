# Phase A36 — kernel steady-state + FIRST REAL CONTENT FRAME (the renderer is ready and waiting)

## Where we are (read these first)

- `.autoport/reports/A35-attempt-1-progress.md` — A35 shipped the WHOLE renderer: `android/android_opengl_renderer.{h,cpp}` (jak1 bucket dispatch, 70 buckets, FBO + pcrtc blit) instantiating the verbatim desktop subset — DirectRenderer (DEBUG/DEBUG_NO_ZBUF/SUBTITLE), TextureUploadHandler on all eleven jak1 *_TEX buckets, EyeRenderer, TexturePool, fr3 Loader. On-device: `all 43 shaders compiled under GLES 3.20`, `GAME.fr3 loaded`, per-frame `A35-RENDER frame=N chain_bytes=M buckets_drawn=K skipped=J` stats, one-time skip logs per unported bucket. GOAL sends chains; `__read-ee-timer` now real (was 0); sceGsSyncV/SyncPath block for real.
- A35 also fixed arm64 bug class #7 (A33's cc truncated every 128-bit arg/return — the uint128 res-tag chain that fed `name=` its null) and found STALE PRE-A34 LEVEL DGOs in the APK (all 28 regenerated + synced — keep them fresh: see the stale-asset memory, regen+sync ALL 28 after ANY codegen change).
- Boot now: 427 link-finishes + village1 actors birthing (yakow!), zero crashes through +33 ms, then:

## THE blocker (named, instrumented)

Run-7: `SIGSEGV fault=0x7f1000001a pc=0x7f001900fc lr=0x7f0018d1c8`. Offline mapping (6/6 dead-pool-heap method anchors vote gkernel main-seg base 0x189304): crash = gkernel process-tree walker (fn65+0xE8) reading `(-> ptr 0 self)` where the ppointer deref returned **0x10000002 — a process-mask-shaped value, not a pointer**. Caller = dead-pool-heap **method 15 `return-process`**: a process dying ~33 ms in; the tree-unlink walk hits a rec/ppointer slot holding a mask-like value. Suspect area: get-process/return-process/compact rec bookkeeping — runs EVERY FRAME once entities exist. Candidates: another arm64 codegen class (store width? 128-bit again? pointer arithmetic on the rec array?) or an earlier mis-write into the rec. The A35 sym-value dump + lr-window byte matcher + the gkernel base mapping make every kernel address instantly nameable — same forensics loop as A34/A35 (saved in the a34-crash-forensics-loop memory).

## Mandate (in order)

1. **Kill the dead-pool-heap rec corruption.** Root-cause with the existing arsenal; fix at the mechanism (no guards). Then keep fixing until the kernel runs ≥30 s with entities alive — watch the `A35-RENDER frame=N` counter climb into the hundreds.
2. **Fix the missing text assets**: `[FAKEISO] failed to find COMMON TXT / SUBTIT TXT` — the text/subtitle files never made it into the APK fakeiso layout (check `out/jak1/iso/` vs APK assets; the desktop build generates TXT files via the text generation step). On-screen text (loading/legal/menus) needs them.
3. **First real content frame.** With the kernel sustained, read the per-frame stats: `buckets_drawn` vs `skipped`. If visible content is gated by an unported bucket, port it (the A35 skeleton makes each additional bucket small — e.g. ProgressRenderer for loading bars, SkyRenderer/TFRAG for the title scene). The ND logo / title screen camera flythrough draws the village1 scene — getting THAT needs tfrag3; the earlier 2D/text content (legal text, loading visuals) should flow through DirectRenderer + textures already. Aim for whatever real content comes FIRST in the boot sequence.
4. **Capture + verify frames**: screencaps at 2/4/6/10/20/40 s → `.autoport/reports/A36-device-*.png`, AND record `adb shell dumpsys window | grep mCurrentFocus` at capture time into the report — the device is shared with another automated project (sshx terminal) that steals foreground; a frame only counts with `org.opengoal.gk.jak1` focused (see the screencap-foreground memory).

## Device rules (unchanged)

`export ANDROID_SERIAL=eae4df44` ONLY. `source .autoport/lib/android-env.sh`. Disable/re-enable `com.xiaoji.egggameplus` + `com.xiaoji.egggame` reversibly. APK CGOs synced from `out/jak1-arm64/iso/` (ALL 28). Install pre-approved (`adb install -r -g`, ~35 s). Spontaneous reboot → `getprop sys.boot.reason` (Google Mainline trains), wait, note it; user may need one unlock.

## Scope

**UNLOCKED**: `android/**`, `game/**`, `goalc/**` except the oracle, `common/**`.

**LOCKED**: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts.

## Anti-cheat (hard rules)

1. x86 desktop still boots to `link finish: logo`; qemu ≥ 675.
2. **Render claim = screencap with real game content + foreground proof** — supervisor re-captures independently. Solid colors / test patterns / hardcoded images are cheats; chain stats must correlate with a live kernel.
3. No weak/abort/dodge/stubs; no skipping process-kill paths to avoid the crash (the unlink walk must actually work — entities die constantly in real gameplay).
4. Preserve ALL prior fixes/infra (gk_log_pipe, A32-A35 fixes, renderer + stats, diag arsenal).

## Deliverables (lean)

- **A36-fix-summary.md** (≥80 lines) with real-content frame + foreground proof, OR **A36-attempt-N-progress.md / next-blocker.md** (≥80 lines): rec-corruption root cause + fix, kernel lifetime achieved, frame stats over time, buckets drawn/skipped, screencaps + focus records, exact next blocker (named bucket if content-gated).
- Screencaps → `.autoport/reports/A36-device-*.png`; CGO baseline if CGOs changed.

## Validator (`phase-A36-android-kernel-steady-state-first-frame.sh`)

A35's gates (no forbidden edits/cheats; x86 boots; qemu ≥ 675; gk_log_pipe; nm DirectRenderer/DmaFollower; report ≥ 80; ≥1 screencap) PLUS sustained-loop evidence: newest A36 routed logcat must contain an `A35-RENDER frame=N` line with N ≥ 300. Render judged by supervisor vision.

## Max settings

`max_turns: 2500`, `max_retries: 3`. Budget ~$250.

## Strategic note

A35 left the table set: renderer compiled, shaders proven, chains flowing, stats honest. One rec-corruption bug stands between the kernel and steady state — and steady state means the renderer finally gets fed real frames. The first content frame is the project's goal; it has never been closer than this. Go.

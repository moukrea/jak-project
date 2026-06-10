# Phase A37 — fix update-math-camera → the 64K submitted triangles become THE VISIBLE TITLE SCENE

## Where we are (read these first)

- `.autoport/reports/A36-attempt-1-progress.md` — A36 achieved **kernel steady-state on-device**: 4380+ rendered frames, zero crashes, zero tree violations. The renderer consumes real chains every frame at 60 fps: `frame=2940 chain_bytes=152176 buckets_drawn=18 skipped=15 draws=103 tris=64404`. Three root causes fixed at the mechanism (the A18-trap method-slot-13 poisoning that caused the dead-pool heap overlap; Android's missing exec_runtime init_globals sequence — ConvertTable/text now alive; the AArch64 unsigned-char divergence class via -fsigned-char).
- **The screen is still black with 64,404 triangles submitted per frame** because every vertex degenerates:

## THE blocker (named, evidenced)

`*math-camera*`'s `camera-temp` matrix (offset +0x23C) is **ZERO** — `update-math-camera` (GOAL, heavy 128-bit matrix/float code) diverges on arm64 and never writes the perspective-projection product. Zero matrix × every vertex = degenerate clip positions = black frames. The A36 report's blocker section has the dump evidence (read its tail in full).

This is the LAST named blocker between the current state and the project's goal frame. The function is matrix math — prime suspects are the residual arm64 SIMD/128-bit classes (A34 fixed wrong-arrangement stand-ins for ZIP/EXT/INS-blend; A35 fixed the cc 128-bit truncation; this may be the next sibling: a matrix multiply emit, a `.lvf/.svf` offset form, a vector op arrangement, or another cc path). The forensics loop is established and cheap: extract update-math-camera from the arm64 and x86 objects (cgo_inspect.py --extract-function), objdump both, diff the math against the x86 oracle instruction by instruction; or instrument with the A36-style hooks (dump *math-camera* fields each frame until the divergent write is found).

## Mandate (in order)

1. **Root-cause and fix the update-math-camera divergence** at the mechanism (likely an IGenARM64 emit or cc class — fix the CLASS, regen ALL 28 DGOs + sync APK assets, per the stale-asset memory).
2. **Boot, sustain, photograph.** Captures MUST extend late: screencap at 5/10/15/20/30/45/60 s (the heavy scene starts ~10-15 s in). Record `mCurrentFocus` before AND after each tick (boot-cycle races; parallel apps sshxmobile/ghplus/xiaoji steal focus — keep the reversible disable/re-enable dance, ALWAYS re-enable).
3. **The goal frame**: the village1 title scene (or ND logo / any real game visual). If geometry appears but textures are wrong/missing, capture anyway and name the texture-path blocker precisely (TexturePool upload state, tpage decode, fr3 vs tpage source). If the camera fix reveals a NEXT degenerate stage (e.g., sky-only, z-fighting void), name it with evidence.
4. **Report**: A37-fix-summary.md (≥80 lines) with the frame + focus proof if real content lands; else A37-attempt-N-progress.md with the named next blocker.

## Device rules (unchanged)

`export ANDROID_SERIAL=eae4df44` ONLY. `source .autoport/lib/android-env.sh`. Reversible disables (xiaoji ×2, sshxmobile, ghplus) with guaranteed re-enable. APK CGOs synced from `out/jak1-arm64/iso/` after ANY codegen change (all 28). Install pre-approved. Spontaneous reboot → `sys.boot.reason` (Mainline trains), note + continue. User may need one unlock after reboot.

## Scope

**UNLOCKED**: `android/**`, `game/**`, `goalc/**` except the oracle, `common/**`.

**LOCKED**: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts.

## Anti-cheat (hard rules)

1. x86 desktop still boots to `link finish: logo`; qemu ≥ 675.
2. **A render claim is ONLY a screencap with real game content + focus proof** — the supervisor re-captures independently and reads every frame. No hardcoded matrices that bypass update-math-camera (the camera must COMPUTE correctly — hardcoding a "working" matrix is a cheat and dies at the first camera move); no test patterns; no painting.
3. No weak/abort/dodge/stubs. Preserve ALL prior fixes/infra (gk_log_pipe, A32-A36 fixes, renderer + stats, diag arsenal, steady-state).
4. Frame-stats gate stays: newest A37 routed logcat must show `A35-RENDER frame=N` with N ≥ 300 AND tris > 0.

## Deliverables (lean)

- **A37-fix-summary.md** (≥80 lines, with the goal frame + focus proof) OR **A37-attempt-N-progress.md / next-blocker.md** (≥80 lines).
- Screencaps → `.autoport/reports/A37-device-*.png` (+ focus files). CGO baseline if CGOs changed.

## Validator (`phase-A37-android-camera-matrix-first-visible-frame.sh`)

A36's gates (no forbidden edits/cheats; x86 boots; qemu ≥ 675; gk_log_pipe; nm renderer symbols; report ≥ 80; ≥1 screencap; frame ≥ 300 in newest A37 logcat). The render itself is judged by the supervisor's eyes on the frames.

## Max settings

`max_turns: 2500`, `max_retries: 3`. Budget ~$250.

## Strategic note

Everything is alive: kernel steady at 60 fps, 64K triangles per frame in flight, textures loaded, text systems initialized. One zero matrix stands between the GPU and the village. Fix the camera, photograph the title scene, and the project's north-star frame is on glass. Go.

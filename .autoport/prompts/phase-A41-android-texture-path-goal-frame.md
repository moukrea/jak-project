# Phase A41 — texture the quads: glyphs become readable, the scene becomes visible → THE GOAL FRAME

## Where we are (read these first)

- `.autoport/reports/A40-fix-summary.md` + commit 1b9816ea0 — A40 found **arm64 bug class #10**: callee-saved xmm8-15 (v24-v31) were preserved by NOBODY (prologues banked only GPRs). One clobbered s24 froze print-game-text's origin.y and a padding loop swept 12 MB per call — the real mechanism behind A39's "cursor walk" (honestly falsified: the 493×64B arithmetic was numerology). Fix: GOAL prologues/epilogues now bank used saved-xmms; +8 MB global-heap headroom; all 28 DGOs regenerated; x86 byte-identical; qemu 675 exit 0.
- **Device now (supervisor-verified independently): frame=3720 @ 60 fps, 62 s alive, ZERO faults, tris=63,612, draws=104, 18/18 focus checks in-app — and the screen shows ANIMATED UNTEXTURED TEXT QUADS over black 3D.** The kernel computes text layout, the renderer draws real geometry — only textures are missing. The supervisor's frame: `.autoport/reports/SUPERVISOR-a40-verify-10s.png`.
- Iteration niceties from A40: slim APK (`-PslimIso=true`, 77 MB) + run-as data seeding (storage-pressure recipes in the A39/A40 reports); diagnostics property-gated (a40.dproc, a40.sweepdump, A40-SPWIN, a39.*, A38 tripwire).

## THE gate: why do the quads render untextured?

Strong leads, in order:

1. **`adgif-shader<-texture-with-update!` is a def-mips2c function** (the function that resolves texture IDs and writes the adgif shader/texture registers into draw packets). Check its binding state in `game/mips2c/mips2c_table_jak1_arm64.cpp` — A37's graded enablement left ocean/ripple/load-boundary guarded; if the adgif pair is noop'd or missing from the real-bindings allowlist, every draw packet goes out with no texture bound. (History: A32 first met this symbol when the empty `gLinkedFunctionTable` crashed tpage links.) If it's the cause: bind real, verify with the A37 falsification rigor.
2. **TexturePool/upload path**: A35 ported TextureUploadHandler on all eleven jak1 *_TEX buckets and `__pc-texture-upload-now` feeds the pool. Verify uploads actually succeed on GLES (formats! desktop GL constants like GL_RGBA8/GL_UNSIGNED_INT_8_8_8_8_REV vs GLES acceptance — A36 already fixed one REV→BYTE case in the FBO; texture uploads may have siblings). Add a one-time per-tpage log: uploaded? size? GL error?
3. **DirectRenderer texture lookup/bind**: when a draw references a texture id the pool lacks, what does the ported DirectRenderer do — bind nothing (flat quads!) or assert? A one-time "tex-id MISS" log names every miss.

Falsify in this order with evidence; fix at the mechanism (no hardcoded textures, no forced white — readable REAL glyphs or the actual scene textures only).

## Then: THE GOAL FRAME

4. With textures bound: the text becomes READABLE (legal/loading text = real content) and the title sequence's scene (village flythrough after the logo) gets its tfrag textures. Boot, run ≥ 60 s, captures at 5/10/15/20/24/28/32/45/60 s + focus brackets (`A41-focus-runN.txt`), reversible disables (xiaoji ×2, sshxmobile, ghplus) with guaranteed RE-ENABLE.
5. **A41-fix-summary.md** (≥80 lines) with the goal frame + focus proof — or honest progress/next-blocker (≥80) naming the residual stage with evidence.

## Rules (unchanged)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts. Anti-cheat: x86 boots to logo; qemu ≥ 675; render claim = real-content screencap + focus proof (supervisor re-captures); no fake textures/painting; preserve ALL prior fixes (esp. the xmm-banking prologues — regression there re-breaks everything). `export ANDROID_SERIAL=eae4df44` only; keyguard check before runs.

## Validator (`phase-A41-android-texture-path-goal-frame.sh`)

A40's gates with A41 names (report ≥ 80, ≥1 A41-device-*.png, frame ≥ 300 AND tris > 0 in newest A41 logcat, nm renderer syms, gk_log_pipe, x86 smoke, qemu ≥ 675, no forbidden edits). Render judged by supervisor vision.

## Max settings

`max_turns: 1500`, `max_retries: 3`.

## Strategic note

The kernel runs for a minute straight at 60 fps drawing real geometry. Ten arm64 bug classes are dead. What remains is making the pixels carry their textures — most likely one more noop'd mips2c binding, the same disease cured twice already. Texture the quads, read the words, film the village. This is the last gate. Go.

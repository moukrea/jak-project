# Phase A40 — stop the 64 B/frame hint-text cursor walk → boot survives past frame 522 → THE GOAL FRAME

## Where we are (read these first)

- `.autoport/reports/A39-fix-summary.md` + commit 1d281432d — A39 verified the A38 blerc fix live AND named the residual ~9 s SIGILL at instruction level: **an UNRESET display-frame DMA cursor that `print-game-text` walks at 64 B/frame.** Per frame, the (empty) hint-line append writes NEXT-tags at +0xf80/f90/fa0 and writes the cursor back at **+0xfbc** (via `dma-bucket-insert-tag+0x40`); the cursor never resets, so the appends march. Collateral en route (all observed live): buf1 header zeroed in passing (pre=0xcfe150→post=0x0), **l0 level heap poisoned (the tris ≤ 82 pin)**, the engine band entered at exactly 0x1904000, `draw-string`'s code (disk-verified valid) smashed at band+0x7b40 = **exactly 493 frames × 64 B**, then print-game-text's own draw-string call (lr=+0xed8) executes the smashed tags → sig=4 at frame ~522, every boot, process `level-hint`.
- Diagnostics already committed (default-off): `a39.symdump` (draw-string body snapshot + symbol scan), `a39.linkscan` (per-link draw-string sampler), at-crash writer-table dump, BASECELL anomaly filter. A38's tripwire is also still available (property-gated).
- Camera oracle-exact (A37); heap/recs clean (A36/A38); renderer consuming chains at 60 fps. **This cursor walk is the last named bug between boot and the title sequence.**

## THE fix (mechanism, not band-aid)

Find why the cursor at display-frame+0xfbc never resets on Android while x86 resets it (or never appends emptily):

1. **Oracle comparison first**: on desktop x86, does the same hint-line append happen per frame? If yes — find WHO resets +0xfbc there (display-frame-start? a per-bucket reset? a debug-draw init?) and why that reset is missing/diverging on arm64 (dropped store class? mips2c-adjacent helper? init ordering?). If no — find what makes Android's `level-hint` process emit an EMPTY hint line every frame (a stubbed/noop'd input feeding `print-game-text` an empty-but-drawn string? text-id lookup failing → empty string but still appending buckets?). The A39 linkscan + symdump make both paths cheap to instrument.
2. Fix at the mechanism. NO null-guards that skip hint drawing entirely (hints are real gameplay UI), no band-aid resets sprinkled in C++ unless that IS the desktop-mirrored mechanism.
3. x86 + qemu gates must stay green (the fix likely touches shared kernel/GOAL-adjacent C++ or goalc emit — regen ALL 28 DGOs + sync APK if CGOs change).

## Then: THE GOAL FRAME

4. Boot past frame 522 → the title sequence finally runs (logo → village flythrough). Expect TRIS to JUMP once l0's heap stops being poisoned (the ≤82 pin dies with the walk).
5. Captures at 5/10/15/20/24/28/32/45/60 s → `.autoport/reports/A40-device-*.png` + `mCurrentFocus` before AND after each tick (`A40-focus-runN.txt`). Reversible disables (xiaoji ×2, sshxmobile, ghplus), RE-ENABLE after. MIUI install recovery recipe is in the A39 report + the updated memory (dialog returns after uninstall — pm path + tap race; remember-choice may be unticked).
6. **A40-fix-summary.md** (≥80 lines) with the goal frame + focus proof — or honest progress/next-blocker (≥80) naming what still gates content (e.g., texture stage) with evidence.

## Rules (unchanged)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts. Anti-cheat: x86 boots to logo; qemu ≥ 675; render claim = real-content screencap + focus proof (supervisor re-captures independently); no fake frames; preserve ALL prior fixes/diag. `export ANDROID_SERIAL=eae4df44` only. Device may need user unlock after idle (keyguard check before runs; wait, don't burn attempts).

## Validator (`phase-A40-android-hint-cursor-reset-goal-frame.sh`)

A39's gates with A40 names (report ≥ 80, ≥1 A40-device-*.png, frame ≥ 300 AND tris > 0 in newest A40 logcat, nm renderer syms, gk_log_pipe, x86 smoke, qemu ≥ 675, no forbidden edits). Render judged by supervisor vision.

## Max settings

`max_turns: 1500`, `max_retries: 3`.

## Strategic note

493 frames × 64 bytes — the bug even did the math for you. Stop the walk, watch the triangle counter explode, and bring back the village. Everything else already works. Go.

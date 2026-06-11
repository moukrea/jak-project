# Phase A38 — catch the float-sprayer with the designed tripwire → village tfrag survives → THE GOAL FRAME

## Where we are (read these first)

- `.autoport/reports/A37-attempt-1-progress.md` + commit c380eb105 — A37 killed the camera blocker for good: the real cause was the ENTIRE jak1 def-mips2c surface bound to a shared no-op on Android (the camera follows the title camera-anim actor's joint bone transform; the bone producers `calc-animation-from-spr` + `cspace<-parented-transformq-joint!` are mips2c). The fix: a real arm64 mips2c table (`game/mips2c/mips2c_table_jak1_arm64.cpp`, GOAL-heap trampolines from an early arena) + `_mips2c_call_arm64` rewritten (x16/x12 contract, GOAL x86-id arg regs into ctx, callee-saves across AAPCS bodies). **On-device proof: camera-rot/trans/camera-temp BIT-IDENTICAL to the x86 oracle.** Plus: arm64 bug class #9 (`LDP Xt,Xt` is CONSTRAINED UNPREDICTABLE — SIGILL on device, silent on qemu), the android_gfx condvar UB (one cv two mutexes → lost wakeups → the sync_path hang), mid-link heap arena, bucket-stream guard + chain validator (malformed chains named+skipped, GL thread untrappable).
- Graded mips2c enablement: all REAL except `ocean/ripple/load-boundary` (corrupt when real, chain-poison when noop'd — the guard absorbs them for now; fixing them properly is in-scope here if they block the frame, else next phase).
- Boot now: steady frames (`frame=329 tris=82` in the newest log), camera oracle-exact, focus-proofed captures at 5/10/15/20/24/26/28/30/45/60 s.

## THE blocker (named, tripwire designed)

**A float-spray writes garbage floats over the engine-object band `[0x1904000, 0x1915000)` once the deep draw paths engage.** Effects: kills `l0-tfrag` (the village geometry) EVERY frame before it draws, and a font-code SIGILL at the level-hint draw. A37's report sketches the tripwire: **mprotect the band read-only (or canary-grid + per-frame rearm), take the SIGSEGV at the spraying STORE, dump pc/lr/fp-walk → the sprayer is named instantly.** The A37 forensics arsenal (frame-stall watchdog, SIGUSR2 ucontext dump, fp-walk on GOAL+GL threads, PCWIN/LRWIN, A37-WHOSYM reverse-scan) is live — use it.

Mechanics note: mprotect needs page alignment — the band is page-alignable (0x1904000 is 4K-aligned); the GOAL heap mapping must tolerate temporary RO (rearm by catching the fault, logging, restoring RW, single-stepping past or emulating the store, re-protecting). A canary grid (pattern words every N bytes, scanned per frame with first-corruption bisection over frame time) is the fallback if mprotect proves too hot.

## Mandate (in order)

1. **Implement the tripwire, catch the sprayer, name it** (pc/lr/GOAL fn via WHOSYM). Likely classes: one of the guarded mips2c fns (ocean/ripple write through bad pointers when their inputs are right-shaped?), a remaining arm64 emit class (float store with wrong base?), or a renderer-side write-back. Falsify honestly — A37 proved hypotheses die under instruction-level evidence.
2. **Fix it at the mechanism.** If the sprayer is ocean/ripple/load-boundary mips2c: fix their real implementations (translation bugs), don't widen the guard. If codegen: fix the class, regen ALL 28 DGOs + sync APK.
3. **The goal frame.** With tfrag surviving: captures across the 20-30 s window (the title sequence timing claude mapped) + 45/60 s. `mCurrentFocus` before AND after each tick. The frame: village1 flythrough terrain/sky/water — or the ND logo / legal text en route. If geometry appears wrong-but-present (texture/color issues), capture it anyway — wrong-colored village = REAL CONTENT = goal met; name the residual.
4. **Report** A38-fix-summary.md (≥80 lines, frame + focus proof) or A38-attempt-N-progress.md with the named next blocker.

## Device rules (unchanged)

`export ANDROID_SERIAL=eae4df44` ONLY. `source .autoport/lib/android-env.sh`. Reversible disables (xiaoji ×2, sshxmobile, ghplus) with guaranteed re-enable; parallel automation also trips MIUI camera/accessibility popups — bracket focus per tick and discard polluted frames. APK CGOs synced after codegen changes (all 28). Spontaneous reboot → `sys.boot.reason` (Mainline). User may need one unlock.

## Scope

**UNLOCKED**: `android/**`, `game/**`, `goalc/**` except the oracle, `common/**`.

**LOCKED**: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts.

## Anti-cheat (hard rules)

1. x86 desktop still boots to `link finish: logo`; qemu ≥ 675.
2. **Render claim = screencap with real game content + focus proof**; supervisor re-captures independently. No painting, no test patterns, no hardcoded scene data. The tripwire must be REMOVABLE (a diagnostic, not a load-bearing guard): the fix must hold with the tripwire disarmed — state explicitly in the report that the final boot ran tripwire-off (or justify why it stays as cheap hygiene).
3. No weak/abort/dodge/stubs; don't widen the ocean/ripple guard to "fix" the spray. Preserve ALL prior fixes/infra.
4. Frame gates stay: newest A38 routed logcat shows `A35-RENDER frame=N` N ≥ 300 AND tris > 0.

## Deliverables (lean)

- **A38-fix-summary.md** (≥80 lines, goal frame + focus proof) OR **A38-attempt-N-progress.md / next-blocker.md** (≥80 lines): sprayer identity + evidence, fix, tripwire-off verification, frame stats, captures.
- Screencaps → `.autoport/reports/A38-device-*.png` + focus files. CGO baseline if CGOs changed.

## Validator (`phase-A38-android-float-spray-tripwire-goal-frame.sh`)

A37's gates (no forbidden edits/cheats; x86 boots; qemu ≥ 675; gk_log_pipe; nm renderer syms; report ≥ 80; ≥1 screencap; frame ≥ 300 + tris > 0 in newest A38 logcat). Render judged by supervisor vision.

## Max settings

`max_turns: 2500`, `max_retries: 3`. Budget ~$250.

## Strategic note

The camera waits with oracle-exact values; the geometry flows; one memory-corrupting writer stands between the village and the glass. The tripwire design is already on paper — build it, catch the sprayer in one boot, fix it, and bring back the frame. Everything else is done. Go.

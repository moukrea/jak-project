# Phase F1d — make input reach the GOAL cpad: press START → Geyser Rock loads → Jak spawns and moves

## Where we are (read these first)

- **F1c VERIFIED DONE (camera)**: the title screen flies. Bug class #13 = arm64 integer modulo returned the QUOTIENT not the remainder (missing `MSUB`); the joint decompressor selects its per-frame control nibble via a `mod`, so a broken modulo froze the camera-look joint. Fix in `goalc/compiler/IR.cpp` + `goalc/emitter/IGenARM64.cpp` (commit ca47ddc32). Supervisor independently confirmed (own boot: `SUPERVISOR-f1c-title-aerial.png` / `-huts.png` — two distinct flying locales, horizon level, logo + PRESS START).
- **F1c's honest residual = THIS phase**: input injection does NOT reach the game. From F1c's fix-summary "Honest residuals" + commit 633ecf601 ("START→cpad gap localized"): the injected touch (`adb input tap`) IS delivered to the app (MIUIInput shows ACTION_DOWN/UP on the MainActivity input channel), AND `adb input keyevent 108` (BUTTON_START) is delivered — but **neither reaches `(cpad-pressed? 0 start)`** in GOAL. The title stays on PRESS START; no Jak spawns. The gap is the **headless-injection → SDL virtual-gamepad → GOAL `cpad`** path (or the title's cpad-index read). Touch-overlay coordinates were already corrected (1080×2400 physical vs 2298×1036 overlay `mAppBounds`, +102,0 cutout offset) — the coords hit the START zone; the gap is deeper than coordinates.

## Mandate (in order)

1. **Trace the real input path** in `android/**`: how does the on-screen `TouchOverlayView` (D-pad / face buttons / START) turn a touch into a GOAL controller-pad button? Find the bridge — does it (a) synthesize SDL_CONTROLLERBUTTON events, (b) write cpad state directly via JNI, or (c) feed `pad-buttons` some other way? Then find why injected `input tap`/`keyevent` doesn't traverse it. Likely: the overlay handles only real `onTouchEvent` (not window-injected events), or the GOAL cpad reads a controller index the virtual pad isn't on, or SDL isn't actually in the loop.
2. **Make autonomous input register as a real cpad press.** Acceptable mechanisms (pick the cleanest that makes the GAME genuinely respond): (a) fix `TouchOverlayView` to also accept injected/dispatched motion events; (b) a debug **cpad-injection hook** in the Android runtime that sets the SAME real button/stick state the overlay would (a legitimate test boundary — the GOAL game logic must genuinely react; this is NOT cheating because it injects a real INPUT, not a faked RESULT); (c) SDL event-queue injection. **Document which path and why.** Add a one-time log when a button reaches `(cpad-pressed? 0 start)` so the press is provable in the timeline.
3. **Drive the flow with evidence at each step:**
   - START → the title ADVANCES (a frame VISUALLY distinct from the title — the start/hero menu, a loading screen, or the level — NOT logo+PRESS START). Logcat: `set-master-mode 'play` / the title state machine leaving attract.
   - Geyser Rock / `training` level becomes ACTIVE and **`target` (Jak) SPAWNS** — logcat: target process birth / `(start 'play ...)` / a target-position print. (The boot-time `medres-training` *data* link does NOT count — that happens at boot regardless. Require the level to be the ACTIVE played level + Jak alive.)
   - Inject MOVEMENT (left-stick / D-pad) → **Jak's position changes** — target-position telemetry in the SAME logcat timeline as the injected stick events, AND device frames showing Jak in the level at different positions.
4. **Captures**: title → (START) → menu/load → level + Jak → (move) → Jak moved. Screencaps at each transition (named by what they ACTUALLY show, verified) + `mCurrentFocus` brackets. Reversible disables (xiaoji ×2, sshxmobile, ghplus), RE-ENABLE after.
5. **F1d-fix-summary.md** (≥ 80 lines): the input-path root cause + fix mechanism, the START→play→spawn→move evidence timeline, frames. No aspirational frame labels — label frames by verified content.

## Cross-check available

The owner is watching the device live and CAN press START physically. If autonomous injection is blocked, a manually-pressed START that advances the title is a valid diagnostic (proves the game logic + render path work and isolates the gap to injection) — note it, but the orchestrator's deliverable is autonomous injection driving the flow.

## Rules / Anti-cheat (hard)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts. x86 boots to `link finish: logo`; qemu ≥ 675; preserve ALL prior fixes (esp. the F1c modulo/MSUB — regression re-freezes the camera). **No fake input evidence**: injecting a real button/stick STATE at the input boundary is fine ONLY if the GOAL game logic genuinely responds; faking the RESULT (a hardcoded "Jak moved" log, a painted level frame, a synthetic target-position) is a cheat. The supervisor re-captures independently and reads frames. `export ANDROID_SERIAL=eae4df44` only; keyguard check; slim APK + run-as seeding.

## Validator (`phase-F1d-android-input-cpad-start-geyser.sh`) — STRICT

PASS requires a real **`F1d-fix-summary.md`** (≥ 80 lines; progress/next-blocker do NOT pass) PLUS the newest `F1d-routed-logcat-*.log` containing a **play-mode / target-spawn marker** — one of: `set-master-mode`...`play`, `(start 'play`, `target`-process birth, or a `target` position/state print — proving the game left the title attract loop (a boot-time `medres-training` data link does NOT satisfy this). Plus: no forbidden edits; x86 smoke; qemu ≥ 675; gk_log_pipe; nm renderer syms (DirectRenderer + MercRenderer ≥ 5); ≥ 1 `F1d-device-*.png`; frame ≥ 300 + tris > 0. Whether a frame shows a LOADED LEVEL with Jak (vs the title) is judged by the supervisor's own eyes.

## Max settings

`max_turns: 2000`, `max_retries: 3`.

## Strategic note

The title flies, the renderer draws, the level data links at boot — the only thing between here and *playing* is making a button press cross the headless-injection → cpad boundary. Crack that, press START, watch Jak drop into Geyser Rock, and move him. Thirteen bug classes down; this one isn't codegen, it's the input bridge. Go.

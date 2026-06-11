# Phase F1a — straighten the camera, port merc: the title screen finally looks like the title screen

## Where we are (read these first)

- `.autoport/reports/A42-fix-summary.md` + commit 495fa856d — the village RENDERS on-device: textured Sandover (hut planking/plaster/sky openings), time-of-day cycling, 150 s @ 60 fps, zero faults/hangs, 26/26 focus checks. Three mechanisms fixed: the Android vsync DISCARD SHIM (IOP never saw vblank → every spooled cutscene aborted at the 4 s str-pos timeout → the title course collapsed ~14 s; now desktop-parity store+fire, spool parts stream at desktop cadence), zero-copy send_chain races (now run_dma_copy mode + bounded EyeRenderer drain), and **arm64 bug class #11** (VPSHUFLW/HW were dup-element stand-ins → every `.ppach` garbage → TOD weights packed alpha=0 → tfrag alpha test discarded the village; exact PSHUF semantics, 38 sites, 28 DGOs regenerated).
- **USER-REPORTED + supervisor-verified residuals** (frames: `SUPERVISOR-village-hut-day/-dusk.png`, `A42-device-run7-*.png`):
  1. **The camera is parked INSIDE a hut, tilted ~+85°** (constant across all runs — horizon vertical, half the screen black where the rotated view lands). The cutscene now streams, but the title-course camera does not fly its path.
  2. **No JAK AND DAXTER logo, no actors**: merc/generic/sprite buckets are still SkipRenderer entries (the logo is a merc model; so is Jak himself — gameplay prerequisite).
  3. Scrolling level names over the scene = the attract/hint text running while the title state machine sits in its broken pose.

## Mandate (in order)

1. **Root-cause the camera pose** (the +85° tilt + parked position are likely ONE transform bug). With the A37-CAM oracle-compare arsenal still in place, dump the title-course camera fields on BOTH backends at matched frames: if camera-rot/trans match the oracle but the SCREEN is tilted, the bug is downstream (projection build/pcrtc blit/viewport — check w/h or axis transposes in the Android-side `setup_frame`/blit, and any remaining SIMD stand-in ops in math-camera's matrix build — bug-class #11 had 38 `.ppach` sites; audit the OTHER pack/shuffle/merge ops (`.pextlw/.pextuw/.pcpyld/.pcpyud/.mfir/.qmfc2` families) for stand-ins the same way). If camera fields DIVERGE from the oracle, walk the title-course state chain (`*camera*` process, cutscene str → camera keyframes) for the first divergent field. Fix at the mechanism — no hardcoded camera poses.
2. **Port the merc bucket family** (MercRenderer + Generic/EyeRenderer hookups it needs; sprite if cheap): the A35 skeleton makes each bucket mechanical — compile the desktop TUs, GLES-ize shaders (#version 320 es; A36/A41 catalogued the format/clip deltas), wire bucket ids, one-time skip logs only for what remains. Min bar: **the floating JAK AND DAXTER logo renders on the title screen; village actors appear during the flythrough.**
3. **The correct title screen**: logo over a FLYING camera (course progressing through locales), horizon HORIZONTAL, PRESS START text. Run ≥ 150 s, captures at 10/20/30/45/60/90/120/150 s + focus brackets (`F1a-focus-runN.txt`), reversible disables (xiaoji ×2, sshxmobile, ghplus) with guaranteed RE-ENABLE.
4. **F1a-fix-summary.md** (≥ 80 lines) with the correct-title frames + focus proof — or honest progress/next-blocker (≥ 80) with evidence. Note explicitly: horizon orientation, logo presence, camera motion (frames at different ticks must show DIFFERENT locales if the course flies).

## Rules (unchanged)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts. Anti-cheat: x86 boots to logo; qemu ≥ 675; render claims = screencap + focus proof (supervisor re-captures); no hardcoded transforms/poses; preserve ALL prior fixes (xmm banking, mips2c table, texture queue+flush, vsync parity, chain copy-mode, PSHUF semantics). `export ANDROID_SERIAL=eae4df44` only; keyguard check; slim APK + run-as seeding.

## Validator (`phase-F1a-android-camera-merc-title-correct.sh`)

A42's gates with F1a names (report ≥ 80, ≥1 F1a-device-*.png, frame ≥ 300 AND tris > 0 in newest F1a logcat, nm renderer syms — plus MercRenderer symbols ≥ 5, gk_log_pipe, x86 smoke, qemu ≥ 675, no forbidden edits). Title correctness judged by supervisor vision.

## Max settings

`max_turns: 1500`, `max_retries: 3`.

## Strategic note

The village is alive and lit; the camera just isn't flying it and the cast hasn't shown up. Straighten the pose, bring in merc, and the title screen becomes the real thing — and with merc, Jak himself is one phase from controllable (F1b: START → Geyser Rock). The user is watching the device live and confirmed every visual finding so far. Go.

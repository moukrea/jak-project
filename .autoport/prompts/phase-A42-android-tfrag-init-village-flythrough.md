# Phase A42 — tfrag-init: the loaded title level's geometry sets up → the village flythrough completes the title screen

## Where we are (read these first)

- `.autoport/reports/A41-fix-summary.md` + commit 392a9138c — the texture path is LIVE on-device: readable real-font text (FIRE CANYON / SANDOVER VILLAGE) over the textured, time-of-day-animated logo/title scene; 60 fps, 62 s, zero faults, 36/36 focus checks. Four mechanisms fixed: adgif mips2c bound real; boot-time `__pc-texture-upload-now/relocate` queued via call-time page-walk snapshots + `TexturePool::handle_upload_precomputed` at renderer-ready; GLES REV→BYTE on LoaderStages/SkyBlend live sites; `__pc-set-levels` bound real (first level-fr3 streams: intro+title).
- **Residual (named)**: the boot sits in the logo-loop — **tfrag buckets emit no `tfrag-init`, so TFragment never sets up the (now-loaded) title level**; the village flythrough's geometry never draws. Its textures are already in the pool.

## Mandate

1. **Root-cause why tfrag buckets emit no tfrag-init on Android.** On desktop, the level's drawable trees emit per-bucket init packets (tfrag-init) once the level is set up; the ported TFragment renderer consumes them. Candidates: (a) the GOAL side never runs the level's birth/setup (logo-loop = title state machine waiting on something — a progress/state flag, a stream completion signal from `pc_set_levels`' new path, an spr/dma sync?); (b) the init packets ARE in the chain but the bucket-dispatch drops/mis-routes them (bucket id mapping for l0/l1 tfrag on the Android skeleton); (c) TFragment::init path diverges on GLES (A41 fixed SkyBlend siblings — check TFragment's own setup for REV-format/storage issues that abort init silently). Instrument with the existing per-bucket stats + one-time logs; falsify in order with evidence.
2. **Fix at the mechanism.** No forced inits, no skipping the state machine — the level must set up the way the desktop oracle does. x86 + qemu gates stay green; regen ALL 28 DGOs + sync if CGOs change.
3. **The complete title screen**: logo scene → village flythrough with REAL tfrag terrain (textures already loaded). Run ≥ 90 s (the flythrough cycles locales), captures at 10/15/20/28/32/45/60/75/90 s + focus brackets, reversible disables (xiaoji ×2, sshxmobile, ghplus) with guaranteed RE-ENABLE.
4. **A42-fix-summary.md** (≥80 lines) with flythrough frames + focus proof — or honest progress/next-blocker (≥80) naming the residual with evidence.

## Rules (unchanged)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts. Anti-cheat: x86 boots to logo; qemu ≥ 675; render claim = real-content screencap + focus proof (supervisor re-captures); preserve ALL prior fixes (xmm prologue banking, mips2c real table, texture queue+flush, REV→BYTE sites). `export ANDROID_SERIAL=eae4df44` only; keyguard check; slim APK + run-as seeding for iteration.

## Validator (`phase-A42-android-tfrag-init-village-flythrough.sh`)

A41's gates with A42 names (report ≥ 80, ≥1 A42-device-*.png, frame ≥ 300 AND tris > 0 in newest A42 logcat, nm renderer syms, gk_log_pipe, x86 smoke, qemu ≥ 675, no forbidden edits). Render judged by supervisor vision.

## Max settings

`max_turns: 1500`, `max_retries: 3`.

## Strategic note

The textures are loaded, the level streams, the camera flies — only the terrain's init packet path is silent. Light up tfrag and the title screen is complete; after that, F1 presses START. Go.

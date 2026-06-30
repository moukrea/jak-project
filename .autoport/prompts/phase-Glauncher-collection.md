# Phase Glauncher-collection — multi-game launcher (Jak 1/2/3/X), games gated by built-in assets

## Why (owner 2026-06-29/30)
The final APK should be a "Collection" LAUNCHER, not jak1-only. OpenGOAL can compile Jak 1/2/3/X — the
APK should boot to a launcher that lets you pick the game, with the AVAILABLE games defined by which
asset sets were provided at build time (only jak1 provided now → jak1 is the sole option; provide
jak1+jak2 → both appear; etc.). Usable by gamepad OR touch. Ideally the launcher is built in GOAL with
the graphics pipe wired (e.g. Jak 1 selected → show the in-game Jak & Daxter idle render as preview).

## Mandate (investigate-first; this is a SUBSYSTEM, scope it honestly)
1. INVESTIGATE: how the runtime currently selects game (--game jak1 / the per-game runtime), how the
   self-contained APK bundles + unpacks assets ([[project_final_apk_launcher_collection]] /
   [[project_apk_distributable_packaging]] — the compressed bundle + first-run unpack), and whether
   multiple games can coexist in one APK (asset dirs, CGOs, libgk per-game vs shared).
2. BUILD-TIME GAME GATING: the launcher's game list = which per-game asset bundles are present in the
   APK at build time. Define the manifest/detection (provide jak1 only → 1 option).
3. LAUNCHER UI: a boot-time menu (gamepad + touch) to pick the game, then launch that game's runtime.
   Prefer a GOAL-built launcher with the graphics pipe wired (idle preview of the selected game) if
   feasible; if that's too large for one phase, a minimal functional launcher (list + select + launch)
   is acceptable as step 1 — say so honestly and propose the GOAL/preview version as a follow-up.
4. Only jak1 assets exist now, so jak1 must remain fully playable through the launcher (all current
   fixes intact). Do NOT break the jak1 path.

## Honest scope warning
This is the biggest item. If a full GOAL launcher + multi-game coexistence can't land cleanly in one
phase, deliver the SMALLEST honest increment (e.g. a working launcher that lists jak1 and launches it,
with the gating mechanism in place for future games) and report exactly what remains. No false-green:
the owner play-tests.

## Verify (device, actual screen)
The APK boots to the launcher; jak1 is listed and selectable by gamepad AND touch; selecting it
launches jak1 (all fixes intact, boots + renders). The game-gating is asset-driven (documented: adding
a jak2 bundle would add a jak2 entry). Full CONSISTENT build, deploy_verify PASS, screencaps.

## Report (`.autoport/reports/Glauncher-collection/report.txt`) with `RESULT: MULTI-GAME LAUNCHER` (or `RESULT: LAUNCHER STEP-1` for a documented minimal increment)
the launcher UI (screencap), gamepad+touch selection, asset-driven game gating mechanism, jak1 launches
+ plays, what remains for full Jak 2/3/X + GOAL-preview, x86/build status.

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; keep jak1 fixes intact; .autoport/gold READ-ONLY.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.

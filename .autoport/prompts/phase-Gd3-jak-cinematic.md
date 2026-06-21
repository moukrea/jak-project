# Phase Gd3-jak-cinematic — make Jak VISIBLE in the new-game cinematic (deterministic, x86-first)

## The defect (owner + Grender-audit D3)
On the device, **Jak is invisible in the new-game cinematic** — wherever Jak should appear, nothing is drawn. The audit proved the **merc (skinned-character) pipeline is byte-for-byte correct on arm64** (title-beat merc tri-counts identical to x86, no crash; `Merc2::do_draws` renders skinned characters fine). So Jak's invisibility is **NOT a merc-render-subset gap** — it's **cinematic-specific**: most plausibly a Jak **spawn / cutscene art-joint / scene-player** issue (cf. [[post-f1d-restart-state]] "Jak NOT spawned"). The villain envmap stomp is a DIFFERENT, already-canary-mitigated bug — do not conflate. The cutscene now plays at real-time (Gd1-cutscene-clock fixed), so the cinematic is reachable/censusable.

## Mandate — diagnose deterministically, x86-FIRST, then fix
1. **Reach the new-game cinematic on device** (cpad_inject NEW GAME, as the Gcine-audit/Gd1 tooling does) and **census Jak's merc draw**: is Jak's merc bucket PRESENT but drawing **0 tris** (skipped/culled), or is the bucket ABSENT, or is Jak's process/art **never spawned** (no `jak`/`target` process, no art-joint)? Dump the relevant state (process list / scene-player actor spawn / Jak's merc fragment count) on DEVICE.
2. **x86-FIRST compare:** run the SAME cinematic on `build-x86/game/gk` and dump the same state. Jak IS visible on x86 → diff the dumps to pin exactly what's missing on arm64 (spawn not firing? art-joint/joint-anim not loaded? scene-player actor entry skipped? a draw gated off?). If our-x86 already fails to show Jak, it's an our-code bug to fix on the host first; if only the device fails, it's the arm64 delta.
3. **Fix the real cause** (spawn / scene-player / art-joint path), Android-runtime or goal_src as the diagnosis requires.
4. Temporary dumps removed after; `jak-original-v033` golden stays git-clean.

## Verify (deterministic, NOT screenshots)
- After the fix, the device cinematic shows **Jak's merc bucket drawing > 0 tris** (matching x86 within tolerance) at the beat(s) where Jak appears — dumped numerically. Plus: cinematic still plays crash-free, reaches gameplay.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Golden READ-ONLY/pristine. `deploy_verify.sh eae4df44` PASS. After any failing run, `bash .autoport/restore_knowngood_device.sh`. Device may need the owner to keep the phone unlocked for captures. NO screenshot/video grind.

## Validator (`phase-Gd3-jak-cinematic.sh`) PASS requires
1. `.autoport/reports/Gd3-jak/jak-census.txt`: device vs x86 Jak-in-cinematic state — BEFORE (device Jak merc tris = 0 / not spawned) and AFTER (device Jak merc tris > 0, matching x86), with `RESULT: JAK VISIBLE IN CINEMATIC`.
2. A real code change (`goal_src/**` or `android/**` or `game/**`); fix-summary ≥60 lines naming the spawn/scene-player/art-joint mechanism + the fix; temp dumps removed; golden git-clean.
3. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; cinematic crash-free (no sig 4/6/11), reaches gameplay.

## Max settings
`max_turns: 1500`, `max_retries: 3`.

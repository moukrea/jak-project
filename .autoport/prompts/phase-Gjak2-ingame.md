## WORK ECONOMY
MANAGER: plan/decide/verify yourself. Delegate to autoport-researcher/implementer/tester. Parallelize.

# Phase Gjak2-ingame — make jak2 PLAYABLE: systemic collision + the "Two years later" crash

## Owner blockers (2026-07-08 live playtest, repro recipes in hand)
 1. **COLLISION IS SYSTEMICALLY ABSENT** — the character falls through the floor EVERYWHERE (owner
    jumped every reachable direction incl. straight at respawn -> endless fall/reload loop). The
    collide system returns NO hits at all on arm64. Check in order:
    (a) does jak2 level COLLISION DATA even load on Android (fr3 extraction built WITH collision?
        jak1 needed extract_collision in the decompiler config for its path — check the jak2 fr3
        pipeline + what the runtime loads);
    (b) jak2 mips2c collide functions (collide_cache.cpp etc.) on arm64 — state-dump one collide
        query our-x86 vs device at the same position (returns hits vs nothing);
    (c) noop'd collide builders in the arm64 allowlist (the shadow-cpu family was noop'd the same
        way — audit ALL remaining noop'd jak2 mips2c entries while at it).
 2. **Intro cinematic crashes at the "TWO YEARS LATER" card** — the WHOLE portal sequence + capture
    plays; the crash is the SCENE TRANSITION beat (intro->prison level/spool handoff). Forensics at
    that beat (fp-walk/lr-window), fix the transition path.
 3. Residual (if time): the intro-skip path should land in-game standing on solid ground.

## Verify (device eae4df44) — owner-grade
In-game via intro-skip: Jak STANDS on the floor, walks/jumps without falling through (60s+ moving
gameplay video, mCurrentFocus=jak2, crash-free). Intro cinematic plays THROUGH "Two years later"
into the prison scene without crash. x86 jak2 oracle parity for any touched path. Full consistent
build; deploy_verify PASS.

## Report (.autoport/reports/Gjak2-ingame/report.txt) `RESULT: JAK2 INGAME <verdict>`
collision root cause (data-load vs mips2c vs noop) + fix, transition-crash forensics + fix, video
evidence, honest residuals.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY; full consistent
builds; grep -a routed logcat; state-dumps over screenshots.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.

## TRANSFERRED VISUAL RESIDUALS (owner verdict on Gjak2-visuals, 2026-07-08 ~04:30)
Owner: intro cinematic = "nickel" (visuals mandate met) BUT these remain and belong here:
 * **jak1 ORANGE translucent overlay STILL behind jak2 menus** — never actually fixed (no commit
   touched it; the title progress menu is dark, the owner's orange context is elsewhere — find WHERE
   it draws (pause/in-game menu state?) and gate the jak1-keyed overlay for real this time.
 * **Rift gate still renders as a HUGE luminous ball** + other particle issues — the glow/bloom
   family for the portal is still wrong (lamps were fixed; the rift-gate GLOW bucket isn't).
 * **Electric particles when Daxter plugs in the JAK II logo** are broken (small, note it).
 * Intro-skip spawn = the Fortress — likely story-CORRECT (post-intro = Baron's prison); the bug is
   the missing collision, not the spawn point. Verify against x86 rather than "fixing" the spawn.

## WORK ECONOMY (manager/worker delegation)
MANAGER: plan, decide, VERIFY subagent claims yourself. Delegate to autoport-researcher (state/event
code scans, x86-oracle diffs), autoport-implementer (edits to spec), autoport-tester (device runs,
navs, captures). Parallelize.

# Phase Gjak1-intermittent-events — INTERMITTENT event/trigger failures game-wide (jak1)

## Owner bug report (2026-07-07, refined 2026-07-09 — HIS eye is the gate)
Original (2026-07-07): in Snowy Mountain fort, ground enemies were IMMOBILE as if waiting on an
event that never fired.
CORRECTION (2026-07-09, verbatim French): "Bah étrangement j'y suis retourné et tout fonctionnait,
je pense que des fois les évents se déclanchent pas que ils doivent, ça m'est arrivé à d'autres
endroits, mini-cinématiques contextuelles qui se déclanchent pas des fois, plateformes supposées
bouger qui ne bougent pas des fois, énemis immobiles des fois, etc. Faut quand même traîter le point,
mais du coup c'est pas juste le truc de Snowy Mountain et Snowy Mountain n'est pas un example
constant."

=> This is an INTERMITTENT, GAME-WIDE bug, NOT a Snowy-Mountain-specific one. Snowy Mountain worked
on a later retry, so it is NOT a reliable repro. Symptoms (each happens SOMETIMES, not always):
  - contextual mini-cutscenes that don't trigger,
  - platforms that should move but don't,
  - enemies that stay immobile,
  - (and similar "waiting on an event that never fired" actor states).
Original PS2/x86: these fire deterministically every time.

## Diagnosis leads — INTERMITTENT + device-only + random-location is a huge tell
1. **PRIME SUSPECT: bug class #14 stale-icache (Gjak1-icache-flush).** Intermittent, device-only,
   random-object/random-trigger failures are the EXACT fingerprint of a stale instruction stream
   (klink.cpp:623 no-op flush). If Gjak1-icache-flush has landed, RETEST for these event failures
   FIRST — the icache fix may already resolve them. If it hasn't landed, land it (or coordinate) and
   measure before/after. This connection is the most likely single root cause; prove or disprove it
   before chasing per-event bugs.
2. Other classes if #14 does NOT fully explain it:
   * enter-state / SUSPEND-vs-RETURN handling (G1/G2 history: compile-time pop-RA could not
     distinguish RETURN from SUSPEND — a stuck process waiting on a state transition freezes actors).
   * event dispatch (send-event/process-event through mips2c or FFI trampolines) intermittently
     dropping/mis-delivering.
   * spool/cutscene streaming (spool-joint blockers F1d, loader af-spike Gcine-cut).
3. **x86-first oracle** (mandatory): whatever repro you find, drive the same beat our-x86 vs
   original-x86 — both identical (our-x86 == original). If our-x86 is fine and only arm64 fails
   intermittently, it's a translation-layer bug; localize with state dumps (actor states, task/event
   flags, spool status) + counters over many trials, NOT single screenshots.

## Repro strategy for an INTERMITTENT bug
Don't rely on one location. Script repeated trials of several event triggers (level-entry cinematics,
a known moving platform, an enemy-encounter trigger) across N runs on device; log a
fired/not-fired counter per trigger to catch the intermittent miss. A/B against HEAD with/without the
icache fix. Name the mechanism, don't just observe the symptom.

## Mandate
Reproduce (statistically) -> localize the common intermittent mechanism -> fix in the TRANSLATION
LAYER ONLY (arm64 codegen / mips2c / kernel glue / pc layer) — engine goal_src UNTOUCHED, our-x86 ==
original-x86. If bug class #14 is the cause, the fix is the icache flush; else name+fix the real one.

## Verify (device eae4df44)
The previously-intermittent triggers now fire reliably across N repeated trials (report the
before/after fired-rate); x86 link finish: logo; full consistent build; deploy_verify PASS +
deploy_verify_assets PASS (arm64 CGOs). No regression on surrounding gameplay.

## Report (`.autoport/reports/Gjak1-intermittent-events/report.txt`) `RESULT: INTERMITTENT EVENTS <verdict>`
the named common root cause (mechanism + arm64 divergence + bug class), the fix (file:line), device
before/after fired-rate evidence across trials, x86 oracle parity, relation to bug class #14.

## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; .autoport/gold READ-ONLY; full
consistent builds; state dumps + counters over screenshots for intermittent divergence work.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.

## DEVICE HYGIENE (owner 2026-07-10, MANDATORY)
ALWAYS force-stop the game (`adb -s eae4df44 shell am force-stop org.opengoal.gk.jak1`) the
moment a device test window ends. A left-running app overheats the Redmi for hours -> can
reboot it -> PIN lockout -> pipeline stranded until the owner is physically there. Never leave
the app foregrounded after a capture/verify.

## OWNER REDIRECT (2026-07-13 16:10, verbatim — MANDATORY, current method is VOID)
"Bon tu trouves ou tu te touches en chargeant des niveaux de façon random ? Il y a pas de cinématique
sur le chargement de niveau, donc si tu trouves pas dans le code les trucs qui trigger des cinématiques
contextuelles et trouve un moyen de les reproduire in game pour voir si elles se déclenchent bien...
Bah tu travailles dans le vide et ça sert à rien !"

=> STOP the warp-to-level-start A/B loops (33+ runs, 0 information: nothing contextual fires at level
load, so "fired 6/6" proves nothing about the bug). REQUIRED method instead:
1. CODE-FIRST census (autoport-researcher): enumerate in goal_src/jak1 the actual trigger mechanisms
   for contextual mini-cutscenes / platform activations / enemy wake-ups — e.g. (process-entity-status!
   / task-control closures, nav-enemy notice/aware gates, trigger volumes (bsphere/plane checks),
   `hint` / `scene-player` spawns, (send-event ... 'trigger), camera-tracker, training-obs-style
   proximity states. Produce a concrete list: actor type, level, trigger condition, code location.
2. Pick 3-5 REPRODUCIBLE in-game triggers from that list (reachable in <60s of scripted cpad nav from
   a warp point — e.g. beach pelican/sculptor beats, jungle lurker ambush, misty bone-bridge zoomer
   beat, snowfort gate) and drive Jak INTO the trigger condition (cpad_inject nav + level.warp.pos),
   NOT just boot the level. Verify state transitions via per-actor state dumps (the analysis harness
   already samples actor states) on BOTH arms if an A/B is still warranted.
3. The failure is INTERMITTENT: a trigger firing once proves nothing. If no miss reproduces after
   genuine in-trigger attempts, instrument the dispatcher paths (send-event/state-enter logging behind
   a debug prop) so the OWNER's next real-world miss is capturable, and report honestly.

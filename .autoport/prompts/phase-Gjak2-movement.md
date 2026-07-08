## WORK ECONOMY: MANAGER plans/verifies; delegate researcher/implementer/tester. Parallelize.

# Phase Gjak2-movement — jak2: inputs arrive, animations play, but Jak DOESN'T MOVE (owner-blocking)

## Owner report — VERBATIM, do not reinterpret (2026-07-08, Redmi, shipped build)
"L'overlay gamepad est présent, le jeu prend bien les inputs vu qu'on voit les animations de
déplacement se jouer, c'est juste que le perso reste collé au sol et drift (toujours dans la même
direction)." => INPUT IS FINE. The walk/movement ANIMATIONS TRIGGER on stick input. The character's
POSITION never changes (glued), plus a slight CONSTANT DRIFT in one fixed direction.

## Diagnosis leads (movement/physics integration, NOT input)
 1. The collision RESPONSE path: standing works (ground found) but every move may be CANCELLED by
    bad response data — the newly-enabled jak2 collide mips2c returns hits, but if the resolution
    data (normals/overlap/backoff) is garbage on arm64, the mover rejects all displacement (glued)
    and a garbage normal component yields the constant one-direction drift. State-dump one
    move-resolution (query in + result out) our-x86 vs device at the same spot.
 2. target/movement integration: velocity -> transform update (target-*, move-legs class code) —
    verify the computed velocity is nonzero on stick input and where it dies before the transform.
 3. The 14 default-off'd collide names (method-17 collide-cache, sphere-hash, spatial-hash): if the
    MOVER depends on one of them, its absence may zero all displacement — A/B with
    debug.opengoal.jak2.enable_names (mind the known nav-mesh symbol stomp when enabling).
 4. Suspect known arm64 classes in the jak2 movement mips2c (bones/collide siblings): 128-bit cc,
    IDIV-R8, gpr_addr upper-32 — run the bug-class playbook on the move-resolution functions.

## Verify (device eae4df44): Jak WALKS/JUMPS/translates via the overlay; NO idle drift; 2-3 min free
movement video, mCurrentFocus=jak2, crash-free; x86 movement unaffected (our-x86 == original-x86).
## Report .autoport/reports/Gjak2-movement/report.txt `RESULT: JAK2 MOVEMENT <verdict>` — root cause
named (which stage of the move pipeline died + why arm64), fix (file:line + class), video evidence.
## Locks: ANDROID_SERIAL=eae4df44; engine goal_src untouched; gold READ-ONLY; full consistent builds.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.

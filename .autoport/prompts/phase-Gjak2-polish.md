## WORK ECONOMY: MANAGER plans/verifies; delegate researcher/implementer/tester. Parallelize.

# Phase Gjak2-polish — owner playtest round-2 fixes (2026-07-08 verbatim)

## The five items (device eae4df44, owner-verifiable each)
 1. **CROUCH-LOCK (owner retested — NOT just the L1/R1 button)**: after a few actions (even just
    two jumps) Jak ends up crouched and LOCKED in that stance whatever the input; jump works but he
    re-crouches on landing. Owner's lead: "ça me fait penser au bug de collisions dans Jak 1 qui
    accroupissait Jak très souvent". STRONG HYPOTHESIS (sibling of the Gjak2-movement root cause):
    the CEILING/stand-up collide probe (the query deciding whether Jak can stand) consumes a stack
    collide-tri-result that a still-noop'd/garbage-filling collide fn never writes -> the game
    permanently believes there's a ceiling -> forced duck. Audit the crouch/stand path's collide
    consumers exactly like the movement fix did (which fn fills its result? is it noop'd/garbage on
    arm64? state-dump the probe result our-x86 vs device mid-crouch-lock). ALSO still verify the
    overlay L1/R1-as-one-button mapping vs jak2's real bindings (secondary).
 2. **Cinematics ignore the aspect-ratio setting**: cutscenes render forced 16:9 while gameplay
    follows the configured aspect (fit-to-screen). Cutscenes must FOLLOW the setting too.
 3. **Graphics menu parity with jak1**: same OPTION ORDER as jak1's graphics page, and the
    "Options PS2"/"Advanced Settings" row named exactly as jak1 names it (match jak1's final label).
 4. **FPS counter option missing**: port jak1's FPS-counter toggle to jak2's menu.
 5. **Rift-gate glow: too bright ONLY before the metalheads emerge** (after that beat it's OK) —
    tune the pre-beat glow inputs (state-dump the glow size/interp vs x86 at that exact beat; the
    Ghalo/sun methodology).
## Verify: device screencaps/video per item (crouch-free play with the overlay incl. the L1/R1 button,
cutscene at 4:3 AND fit-to-screen, menu order+labels side-by-side vs jak1, FPS counter live, portal
beat A/B vs x86). mCurrentFocus=jak2; x86 unaffected; full consistent build; deploy_verify PASS.
## Report .autoport/reports/Gjak2-polish/report.txt `RESULT: JAK2 POLISH <n>/5`
## Locks: ANDROID_SERIAL=eae4df44; engine goal_src untouched (pc/ + glue only); gold READ-ONLY.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.

## OWNER ROUND-3 REJECT (2026-07-09) — false-green + REGRESSIONS + "stop reinventing the wheel"
Owner quote (verbatim, French):
"Le glow est toujours là (sur Rift Gate) et les cinematiques n'occupent toujours pas tout
l'aspect ratio. J'ai l'impression que t'es retombé dans le soucis de vitesse du jeux variable
qu'on avait mis longtemps à régler sur Jak 1 (bizarre, le build précédent n'avait pas ce
problème) et il y a des soucis de collisions (idem qu'on avait mis longtemps à régler sur
Jak 1) j'ai l'impression qu'au lieu d'avoir tiré des leçons de Jak 1 on réinvente la roue
pour le 2, c'est bizarre et surtout wasteful."

STRATEGIC MANDATE (owner): do NOT re-solve jak1's already-solved problems for jak2 — PORT
the jak1 fixes. See the full analysis in .autoport/reports/Gjak2-polish/jak1-to-jak2-gap-analysis.md.

Truth of this round (the prior "5/5 device-verified" was a FALSE GREEN — 2 items don't hold,
2 regressions introduced). Do these, honestly, and DO NOT claim a subjective/visual item is
"device-verified" — the OWNER's eye is the gate; report what you CHANGED and let him judge:

1. VARIABLE GAME-SPEED (owner: regressed, prev build was fine). Analysis: the frame-pacing
   ENGINE is SHARED C++ + jak2 already compiles the jak1 pckernel copies (jak1-proven clock),
   so global speed should be stable. The real gap is the Gcamera-interp fix that exists ONLY
   in jak1: `cam-render-interp!` (goal_src/jak1/engine/camera/cam-update.gc:226, globals
   :220-224, call :369) — jak2 computes the interp alpha and DISCARDS it (no jak2 caller of
   pc-camera-interp-alpha; the C++ binding IS already there for jak2). Result = camera
   judder at sub-refresh fps that reads as "variable speed". PORT cam-render-interp! into
   goal_src/jak2/engine/camera/cam-update.gc. Also A/B-confirm the collision change below
   isn't what he's feeling as "variable speed".

2. COLLISION (owner: regressed). Root cause: THIS phase's crouch fix ADDED method-17
   collide-cache + nav-engine (17/18/20/21) to the arm64 allowlist (mips2c_table_jak1_arm64
   .cpp:1087-1093), turning ON a previously-OFF arm64 nav-mesh + sphere-probe path that runs
   every frame and hits the arm64 collision-MATH divergence class jak2 was never validated
   against. DO NOT just re-noop it (that reinstates crouch-lock). Instead: verify the jak1
   arm64 collision-math translation fixes (Gcollision-systemic/nanroot: NaN-compare, fmin/
   fmax, vftoi) actually COVER jak2's now-active nav-engine + sphere-probe methods; extend
   them if jak2 diverges. This is the "port jak1's lesson" path.

3. RIFT-GATE GLOW still too bright (owner: NOT fixed). The GlowRenderer depth-FBO tweak did
   not do it. Re-diagnose the actual glow-size/intensity driver for the rift-gate beat; jak1
   had glow/halo work (Gsun-halo, Ghalo) — check whether a jak1 glow lesson applies.

4. CINEMATICS still don't fill the aspect ratio (owner: NOT fixed). The real-movie? letterbox
   split at math-camera.gc:78 did not achieve full-screen cutscenes. Re-diagnose: what
   actually forces the cutscene to 16:9 vs following aspect-ratio-auto? — port the jak1
   cutscene-aspect handling if jak1 solved this (Gcine-camfov did cutscene 4:3/aspect work).

Efficiency: batch all four into ONE consistent arm64 jak2 build, prove the OBJECTIVE ones
(camera-interp present + called, collision-math covers the active methods, build boots +
deploy_verify jak2 + deploy_verify_assets jak2), and hand the SUBJECTIVE ones (glow look,
cutscene fill, speed feel, collision feel) to the owner — do NOT self-certify them.

## OWNER CONCRETE COLLISION REPRO + PARK DECISION (2026-07-10)
Owner quote (verbatim, French):
"Je peux pas casser les caisses, la première plateforme qui bouge du jeu je peux pas y sauter
dessus, la collision fait comme si j'étais en chute dessus, et je fini par tomber à côté. ça
arrive très vite dans le progrès du premier niveau. J'avoue j'ai pas testé plus du coup. Pour
moi tu peux parker Jak 2 pour l'instant et continuer avec Jak 1."

VERDICT: the collision regression is REAL and game-breaking (confirmed repro):
  - Cannot break CRATES (caisses).
  - Cannot land on the FIRST MOVING PLATFORM — collision treats Jak as falling THROUGH/onto it,
    he slides off to the side and falls. Happens very early in level 1.
This CONFIRMS the crouch-fix root cause: enabling the nav-engine + collide-cache method-17 mips2c
path (mips2c_table_jak1_arm64.cpp:1087-1093) turned on an arm64 collision path whose MATH is wrong
on arm64 — my earlier "audit says jak1 math already covers it" was FALSE (owner repro disproves it).

REVISIT PLAN (when jak2 resumes): do NOT ship the method-17/nav-engine enablement as-is. Either
(a) actually fix the arm64 collision-math for those specific methods (fmin/fmax/NaN-compare/vftoi
divergence — verify on the crate-break + moving-platform-land beats, NOT by audit), or (b) find a
crouch fix that doesn't require enabling the broken collide path. The crouch-lock and the collision
are COUPLED — solve them together, verify BOTH on device (jump-onto-moving-platform + break-crate +
crouch-release-stands-up). The camera-interp port + glow depth-stencil fix + cutscene-aspect refine
from round-3 are independent and can be kept.

STATUS: PARKED by owner 2026-07-10 — Jak 2 paused, focus returns to Jak 1.

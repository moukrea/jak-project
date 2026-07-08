## WORK ECONOMY
MANAGER: plan/decide/verify yourself (LOOK at frames). Delegate to autoport-researcher /
autoport-implementer / autoport-tester. Parallelize.

# Phase Gjak2-visuals — from "it renders" to "it looks RIGHT" (jak2 title flythrough)

## Where we are (Gjak2-render done — first frames)
jak2 renders Haven City on device (TFragment/Tie3/Merc2 families, ~23k tris, 60fps, crash-free,
title-attract flythrough with camera motion). Owner verdict (live, 2026-07-07): "c'est pas bon,
avec beaucoup d'erreurs et d'éléments manquants, mais c'est déjà quelque chose" — geometry is DARK,
many elements MISSING, visual errors everywhere. This phase closes that gap for the TITLE/ATTRACT
beat (gameplay quality comes later).

## Mandate — same arc as jak1 A41-A42 + G-phases, with the playbook
1. **TOD/lighting palettes**: the world renders dark — port the time-of-day palette upload path for
   jak2 (jak1's tfrag TOD blend pattern; state-dump our-x86 vs original-x86 FIRST for any divergence
   — never screenshot-diff timing-dependent beats).
2. **Missing bucket families**: port the remaining visible families for the title beat — sky/ocean,
   sprite/particles (sparticle 2D/3D via the jak2 mips2c builders), shadow, eye, direct/HUD, etaux —
   one family at a time (kSet allowlist + CMakeLists TUs + bucket registration + GLES gates, the
   [[project_gwater_state]] 3-part pattern). Honest per-family verdict (ported / deferred + why).
3. **Visual errors**: fix what the owner sees (wrong/garbage textures, misplaced geometry, aspect) —
   x86-first oracle comparisons; known jak1 bug classes first (upper-32 gpr_addr #f-guards, IDIV R8,
   128-bit cc, swizzle...).
4. Keep the 60fps crash-free soak intact (no stability regressions; kill-switches per family).

## Verify (device eae4df44) — owner's eye is the bar
Title/attract flythrough side-by-side comparable to the x86 oracle: sky present, world lit (TOD),
no missing major element in view, no garbage textures. Screencaps at matched beats + a 60s
screenrecord. mCurrentFocus=jak2, crash-free >= 5 min. x86 jak2 oracle intact; full consistent
build; deploy_verify PASS.

## Report (`.autoport/reports/Gjak2-visuals/report.txt`) `RESULT: JAK2 VISUALS <verdict>`
per-family table (ported/deferred), TOD/lighting fix, per-error fix + bug class, matched-beat
screencaps vs oracle, fps, honest residuals list.

## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY; full consistent
builds; grep -a routed logcat; state-dumps over screenshot-diffs for divergence work.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.

## OWNER LIVE OBSERVATION (2026-07-08) — the "milky veil" is VERTEX EXPLOSION, not lighting!
The owner watched the device live: "C'est pas un éclairage laiteux — il y a de la VERTEX EXPLOSION,
des shaders/effets visuels qui pètent dans tous les sens, des FREEZES, des glitches !"
REDIRECT the investigation:
 * The white wash in screenshots = GIANT EXPLODED POLYGONS covering the screen (corrupt/NaN vertex
   positions stretching to infinity), NOT overexposure/TOD. Stop treating it as palette/exposure.
 * Suspects = the KNOWN jak1 arm64 vertex/matrix corruption classes, in priority order:
   1. NaN bone matrices (jak1 Gcine-pose class: matrix-inv-scale 1/0 on degenerate data; cspace);
   2. merc/emerc vertex SWIZZLE (bug class #12) — jak2's emerc/merc2 formats differ from jak1's;
   3. bone-matrix upload path (Merc2 anim-slot / bounds — the guards added may hide OOB garbage);
   4. LDP Xt,Xt / 128-bit cc / IDIV-R8 codegen classes in jak2-only mips2c builders (bones.cpp!);
   5. DMA chain misparse feeding wrong vertex strides to Tie3/TFragment.
 * FREEZES + exploding effects = likely the same garbage data (effects = sprite/particle builders).
 * Method: per-family isolation (kill-switch each family to find which one(s) explode), then
   state-dump the vertex/matrix inputs our-x86 vs original-x86 vs device (NaN scan, stride check).
   A static screenshot CANNOT diagnose this — use short screenrecords (motion shows the explosion).

## OWNER IN-GAME PLAYTEST (2026-07-08, live device — repro recipe: SKIP the intro cutscene to reach gameplay)
Four precise symptoms, mapped to targets (fix in this order):
 1. **ANIMATED-JOINT/BONE MATRIX CORRUPTION (root of the explosions)** — title glitches START exactly
    when the camera reaches the Jak II LOGO: the joint holding the logo spins/wanders, THEN vertex
    explosion + weird effects. In-game: 3D models fly around / wander on their own. Common factor =
    ANIMATED models (merc + joint anim). Suspects: jak2 mips2c bones.cpp (arm64), joint/anim
    decompression, bone-matrix upload (Merc2). State-dump bone matrices our-x86 vs device (NaN/garbage
    scan) at the logo beat. This is the #1 fix.
 2. **COLLISION BROKEN** — the character falls THROUGH THE FLOOR -> scene reloads over and over
    (death loop). Suspect: jak2 mips2c collide_cache.cpp (arm64) returning garbage (same
    freshly-wired mips2c family as bones). Verify collide queries vs x86.
 3. **JAK1 ORANGE TINT LEAKING into the jak2 main menu** — the menu background tint is jak1's orange
    ("un truc repris de jak1 qui n'a rien à faire là"): find the jak1-default in OUR Android/pc glue
    (menu tint backdrop from the jak1 Gmenu fixes, clear color, or a jak1-keyed constant applied
    game-agnostically) and gate it to jak1 / use jak2's real value.
 4. (minor) ~2s freeze + weird effect just before the Sony panel at boot — likely fr3/texture upload
    stall; investigate after 1-3.
The owner CAN reach gameplay via intro-skip — use that recipe for in-game verification (models
behave, character stands on the floor, no reload loop).

## OWNER MENU TEST (2026-07-08 ~02:40) — explosion GONE in menus ✓, but:
 * The JAK1 ORANGE OVERLAY is STILL THERE behind the jak2 options menu (symptom 3 NOT fixed — the
   supervisor's "menu clean" screenshot reading was wrong; the owner sees it live). Find the
   jak1-keyed tint/overlay in our glue and gate it to jak1.
 * "Display Mode" shows garbage default "UNKNOWN ID 999187" — the display-mode enumeration is
   unwired on Android/jak2; at minimum make it not display a garbage ID (proper backport = the
   queued Gjak2-pcmenus backlog phase; don't scope-creep the full system here).

## OWNER OBSERVATION (2026-07-08 ~03:00) — intro cinematic: portal emits a MASSIVE luminous blob
Particles in the intro cinematic are broken: the rift PORTAL emits a huge glowing blob. The owner
notes it resembles jak1's early SUN rendering problem — that analogy is a strong lead: jak1's sun/
halo class (Ghalo/Ghalo-sun forensics) was the GLOW/sprite family where glow SIZE = camera-driven
interp (sun-fade/current-interp); a corrupted interp/size input or an unported glow/sprite-distort
renderer produces exactly a massive blob. Check: the jak2 glow bucket / sprite-distort renderer
(is it ported or falling back to something wrong?), the glow size/interp inputs vs x86 state-dump
at the same cinematic beat, and the sparticle launch flags for the portal effect. Fix or cleanly
skip-with-kill-switch the glow family (honest deferral OK) rather than shipping the blob.

## OWNER PLAYTEST UPDATE (2026-07-08 ~03:15) — two hard repros
 1. **Intro cinematic CRASHES at the exact beat where the METALHEADS start crossing the portal** —
    that beat combines a merc spawn burst (metalhead models) + the portal particle storm; forensics
    the crash there (fp-walk/lr-window) and map to bones/merc-spawn vs particle suspects.
 2. **COLLISION IS TOTALLY ABSENT, not localized**: owner jumped in every reachable direction incl.
    straight at the respawn point — falls through the floor EVERYWHERE, endless respawn loop. This is
    a SYSTEMIC collide failure on arm64: the collide system returns no hits at all. Check in order:
    (a) jak2 mips2c collide_cache.cpp / collide functions on arm64 — do queries return real results?
        A/B one collide query state-dump our-x86 vs device at the same position;
    (b) does the level COLLISION DATA even load on Android (collide mesh/fr3 extraction path — we
        build the jak2 fr3 without collision? jak1 needed extract_collision for its path);
    (c) the collide trampoline/allowlist entries (a noop'd collide builder = zero hits = fall-through).
    Fixing collision unblocks ALL in-game verification — HIGH priority (equal to bones).

## OWNER CORRECTION (2026-07-08 ~03:55) — cinematic crash beat FALSIFIED and re-pinned
The intro cinematic goes MUCH further than previously noted: the ENTIRE portal sequence plays
(metalheads crossing included), Jak gets captured (rifle-butt hit -> black screen), then the
"TWO YEARS LATER" text card appears — and THAT is where it crashes. So the crash is NOT the
metalhead/particle beat: it is the SCENE TRANSITION beat. Suspects, in order:
 1. the intro->prison SCENE/LEVEL TRANSITION (next level/segment load kicked off behind the card —
    level DGO/spool handoff on arm64);
 2. the spool chain segment handoff (end of intro spool -> next);
 3. the text-card rendering path itself (subtitle/card draw — less likely).
Forensics the crash AT the "Two years later" card (fp-walk/lr-window + which subsystem). The
metalhead/portal beat earlier framing is WITHDRAWN (it plays fine apart from the glow blob).

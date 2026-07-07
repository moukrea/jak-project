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

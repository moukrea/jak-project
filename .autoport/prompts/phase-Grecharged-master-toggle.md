# Phase Grecharged-master-toggle — global RECHARGED ON/OFF (OFF = pure vanilla)

ultrathink. Small, surgical phase: settings plumbing + menu. No new rendering features.

## OWNER DIRECTIVE (2026-07-21)
"Un toggle ON/OFF GLOBAL de toute la partie Rechargée : OFF ⇒ rend EXACTEMENT comme le jeu original — sans
custom assets, sans l'herbe dynamique, sans le realtime lighting, sans les probes et compagnie, TOUT vanilla.
(Utile aussi pour les captures de probes.)"

## WHAT TO BUILD
1. A **RECHARGED master on/off** (top row of the Recharged Settings menu; consider also surfacing it near the
   Graphics root for discoverability — pick the cleanest, document it). Persisted like the other settings.
2. **OFF forces the STOCK state of EVERY recharged feature at runtime** WITHOUT destroying the user's
   individual toggles (they must come back exactly as configured when master goes back ON). Master OFF ⇒
   effective-off for: custom assets/texture replacements, PBR materials, enhanced/HD models, recharged HUD,
   recharged grass (all grass settings), foliage wind, AO (all modes), realtime lighting (sun/green-sun/
   shadows), directional/probe ambient + reflections resource, and any future recharged feature — implement
   as a SINGLE effective-flag helper (e.g. `recharged_active() = master && feature_flag`) consumed at every
   feature gate, NOT per-feature copies that can drift.
3. **OFF == byte-identical vanilla render**: with master OFF the frame must be identical to a stock build
   (the per-feature OFF==stock gates already exist — the master must compose them all). Prove with a device
   A/B (master OFF vs the accepted stock baseline) — pixel-identical (or the established thr) on a fixed beat.
4. **Menu coherence**: with master OFF, the individual recharged rows grey out (option-disabled-func), no
   unknown-ID; UPDATE `.autoport/menu-tree.md` (standing rule).
5. Expose the master to the C++ side + a debug prop (`debug.opengoal.recharged`) so headless tooling (e.g.
   probe captures) can force vanilla without touching the user's saved settings.

## GATES
- Source: single effective-flag helper consumed by all feature gates (grep-provable), not scattered copies.
- Device: master OFF ⇒ stock-identical frame (measured A/B vs stock baseline); master back ON ⇒ user's
  individual settings restored exactly (no reset).
- Menu: master row present, rows greyed when OFF, menu-tree.md updated, no unknown-ID.
- Report RESULT: PASS + device evidence + jak1 focus. owner_verify: the owner flips it on his Honor.

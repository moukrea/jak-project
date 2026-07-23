# Phase Grecharged-texture-hotreload — live texture toggle (no game restart)

Small phase. OWNER (2026-07-23): toggling Recharged Textures / custom assets ON<->OFF currently requires a
full game restart to take effect. Make it apply LIVE: flipping either toggle (or the master) re-resolves the
texture replacements (rescan indexes + re-upload affected GPU textures / invalidate the replacement pool)
without restarting. Keep precedence semantics exactly (user > bundled > stock, alpha-last-wins among user
dupes). Careful with in-flight loader state and the texture pool's src_data contract (see LoaderStages.cpp
notes). Mechanical bar + "READY FOR OWNER VISUAL CHECK" (toggle flips visibly in-game live); no capture
batteries. menu-tree.md untouched unless menu changes.

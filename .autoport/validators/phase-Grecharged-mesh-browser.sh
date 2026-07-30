#!/usr/bin/env bash
set -uo pipefail
R=".autoport/reports/Grecharged-mesh-browser/report.txt"
fail(){ echo "[Gmbrowse FAIL] $*" >&2; exit 1; }
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"

# 1. embedded per-level mesh index, derived => must ship in the APK (owner structural rule)
grep -qiE 'index' "$R" || fail "no embedded per-level mesh index"
grep -qiE 'centroid|bbox|bounding box' "$R" || fail "index lacks centroid/bounding box (needed for auto-framing)"
grep -qiE 'apk' "$R" || fail "index not shown to ship inside the APK (derived data rule)"
# 2/3. navigation + filters + worst-first + auto-framing
# 4. toggles, including the offline grade shown on screen (the cross-check loop)
grep -qiE 'grade|note' "$R" || fail "the offline test's grade is not displayed on screen (the confirm/refute loop)"
# 5. touch AND gamepad, no adb
grep -qiE 'touch|tactile' "$R" || fail "touch control not evidenced (the owner has no adb)"
# OWNER 2026-07-29: "impossible a parcourir via le tactile". The word "touch" in a report proves
# nothing — demand the gesture -> state-change chain, injected and observed on the device.
grep -qiE 'input (swipe|tap)|injected (gesture|touch)|geste inject' "$R" || fail "TOUCH: no injected gesture evidence (input swipe/tap) driving the browser"
grep -qiE 'state change|changement d.etat|selected mesh changed|etat du navigateur' "$R" || fail "TOUCH: gestures not shown to CHANGE the browser state (a screenshot proves nothing)"
grep -qiE 'gamepad|manette|pad' "$R" || fail "gamepad control not evidenced"
grep -qiE 'without adb|sans adb|no setprop' "$R" || fail "not proven reachable without adb/setprop"
# 6. debug-only, no regression, menu doc
grep -qiE 'no regression|aucune regression|unchanged when (off|closed)' "$R" || fail "no proof the normal path is unchanged when the browser is closed"
grep -qiE 'menu-tree' "$R" || fail "menu-tree.md not updated (standing owner rule)"
grep -qiE 'boot|smoke|no crash' "$R" || fail "no smoke run evidencing the build boots"
grep -qiE 'capture (sweep|campaign)|angle sweep|pixel (statistics|fraction)' "$R" && fail "in-game visual measurement campaign detected — banned by the owner"
grep -qiE 'rotate the mesh|faire tourner le mesh|mesh rotation' "$R" || fail "no independent MESH rotation (distinct from camera orbit)"
grep -qiE 'name.*(on ?screen|affich)|nom.*ecran|identifier displayed' "$R" || fail "the mesh/material/level identifier is not displayed on screen for the owner to quote back"
grep -qiE 'files/|export' "$R" || fail "no way to export the selected mesh identifier (the owner has no adb)"
grep -qiE 'time of day|heure|tod' "$R" || fail "no in-browser time-of-day control (PBR behaves differently in shade and at night)"
# PHYSICAL artifact checks — the text gate passed while gk was never linked and no smoke run happened.
# Log-string greps are trivially defeated; require the actual binaries.
[ -f out/jak1/obj/mesh-browser-pc.o ] || fail "GOAL object out/jak1/obj/mesh-browser-pc.o missing — the browser screen was not compiled"
GKB=""
for c in build-mbrowse/game/gk build-mbrowse/gk build/game/gk; do [ -f "$c" ] && GKB="$c" && break; done
[ -n "$GKB" ] || fail "no gk binary produced — the report's 'gk built in build-mbrowse' claim is unverifiable"
# mesh-browser-pc.gc is GOAL: it compiles into the CGO via goalc, NOT into the gk C++ binary.
# Requiring gk to be newer than a .gc file forces a pointless relink and stalled the phase 3x
# (same fingerprint). The correct freshness pair is:
#   - the GOAL object newer than its source (goalc ran), and
#   - gk newer than the C++ bridge this phase edits (kmachine.cpp), when that file changed.
[ out/jak1/obj/mesh-browser-pc.o -nt goal_src/jak1/pc/mesh-browser-pc.gc ] \
  || fail "mesh-browser-pc.o is OLDER than mesh-browser-pc.gc — goalc did not recompile the screen"
if [ game/kernel/jak1/kmachine.cpp -nt "$GKB" ]; then
  fail "gk binary is OLDER than kmachine.cpp — the C++ bridge changed but was not relinked"
fi
grep -qiE 'independent mesh rotation|rotate the mesh' "$R" || fail "mesh rotation: if the mesh cannot be spun, the report must say so explicitly as a GAP, not substitute light rotation silently"
# owner delivery condition: all levels indexed, and the browser ships WITH the mesh corrections
IDX=$(ls custom_assets/jak1/mesh_index/mesh_index_*.txt 2>/dev/null | wc -l)
# 25, not 26: jak1 ships 26 fr3 files but GAME.fr3 is the shared container and has ZERO geometry
# (tess_sign: "faces=0 gverts=0 (tfrag trees 0, tie trees 0)"), so there is nothing in it to browse.
# The 26 figure was the supervisor's assumption; the measurement corrected it.
[ "$IDX" -ge 25 ] || fail "index covers only $IDX level(s); every jak1 level WITH GEOMETRY must be indexed (25)"
grep -qiE 'all[- ](levels|25 levels)|tous les niveaux|25 levels' "$R" || fail "report does not evidence an all-levels index"
# OWNER 2026-07-29: free cam around the mesh centroid, NOT a player warp.
grep -qiE 'free ?cam|camera libre|detached camera' "$R" || fail "CAM: no free camera — selecting a mesh must move the CAMERA, not teleport Jak"
grep -qiE 'centroid' "$R" || fail "CAM: the orbit origin must be the mesh centroid (already in the index)"
grep -qiE 'does not (move|teleport|warp) (the )?player|ne (deplace|teleporte) pas' "$R" || fail "CAM: must state the player is NOT moved"
grep -qiE 'bounding box|bbox|boite englobante' "$R" || fail "CAM: initial distance must come from the bounding box so any mesh size frames correctly"
grep -qiE '360|full orbit|tour complet|elevation' "$R" || fail "CAM: full azimuth + elevation (incl. looking up at an overhang's underside) not evidenced"
grep -ciE 'centroid' "$R" | awk '$1>=5{ok=1} END{exit !ok}' || fail "CAM: fewer than 5 meshes checked for camera-vs-centroid accuracy (owner: 'warp toujours au meme endroit')"
# ---- V2 FREECAM (owner 2026-07-30): reticle-first redesign; the list is no longer the primary UI ----
grep -qiE 'freecam|free-cam|free cam' "$R" || fail "V2: no freecam mode"
grep -qiE '(l3|r3)[^.]{0,50}(freecam|toggle|entre)|freecam[^.]{0,50}(l3|r3)' "$R" || fail "V2: L3/R3 freecam entry not evidenced"
grep -qiE 'overlay[^.]{0,40}(button|bouton)' "$R" || fail "V2: no overlay UI button to enter freecam (owner has no gamepad attached)"
grep -qiE '(start|select)[^.]{0,60}(freecam|cam)|freecam[^.]{0,60}(start|select)' "$R" || fail "V2: freecam button not placed next to Start/Select in the overlay (owner placement)"
grep -qiE 'reticle|viseur|crosshair' "$R" || fail "V2: no first-person reticle"
grep -qiE '(left stick|stick gauche)[^.]{0,60}(fly|vol|vertical|air|all directions|toutes)' "$R" || fail "V2: left-stick free flight incl. vertical not evidenced"
grep -qiE '(r1|r2)[^.]{0,50}(target|cible|pick)' "$R" || fail "V2: R1/R2 targeting not evidenced"
grep -qiE '(name|nom)[^.]{0,50}(screen|ecran|plain text|en clair)' "$R" || fail "V2: targeted mesh name not shown in plain text on screen"
grep -qiE '(l1|l2)[^.]{0,50}(hide|show|cacher|montrer|visib)' "$R" || fail "V2: L1/L2 show/hide toggle not evidenced"
grep -qiE 'square[^.]{0,60}(checker|damier)' "$R" || fail "V2: Square checker-tessellation toggle not evidenced"
grep -qiE 'circle[^.]{0,60}(gizmo|normal)' "$R" || fail "V2: Circle normal-orientation gizmos not evidenced"
grep -qiE 'triangle[^.]{0,50}(defocus|deselect|deselec)' "$R" || fail "V2: Triangle defocus not evidenced"
# the two DEAD toggles must prove BOTH directions via runtime state, injected input
grep -qiE 'cpad_inject|input (tap|swipe)' "$R" || fail "V2: no injected-input evidence"
grep -qiE '(hide|cacher)[^.]{0,80}(on *-> *off *-> *on|aller.*retour|both directions|draw (count|counter))' "$R" || fail "V2: hide toggle not proven BOTH ways via a runtime counter (it is currently dead)"
grep -qiE '(checker|damier)[^.]{0,80}(on *-> *off *-> *on|aller.*retour|both directions|flag)' "$R" || fail "V2: checker toggle not proven BOTH ways via runtime state (it is currently dead)"
grep -qiE 'pick[^.]{0,60}(5|five|cinq)|5/5[^.]{0,30}(pick|target|cible)' "$R" || fail "V2: reticle pick accuracy not proven on >=5 distinct meshes"
# ---- V2.1: axes + renderer-level proof (owner: every target toggle is dead, axes inverted) ----
grep -qiE '(axis|axes)[^.]{0,60}(sign|convention|invers)' "$R" || fail "V2.1: axis convention fix not documented"
grep -qiE '4 axes|four axes|chacun des 4' "$R" || fail "V2.1: all 4 inverted axes not individually proven (input sign -> delta sign)"
grep -qiE 'renderer[^.]{0,60}(counter|compteur)|draw (count|counter)[^.]{0,40}(frame|per-frame)' "$R" || fail "V2.1: no renderer-side per-frame counters (variable flips proved nothing)"
grep -qiE '(hide|cach)[^.]{0,100}(0|zero)[^.]{0,60}(draw|soumis)' "$R" || fail "V2.1: hide not proven by the mesh draw count hitting ZERO"
grep -qiE '(checker|damier)[^.]{0,80}bind' "$R" || fail "V2.1: checker not proven by material BINDS on the targeted mesh"
grep -qiE 'gizmo[^.]{0,80}(primitive|draw|vertices|dessine)' "$R" || fail "V2.1: gizmos not proven by primitives actually drawn"
grep -qiE 'relief[^.]{0,80}(uniform|shader)' "$R" || fail "V2.1: relief not proven at the shader uniform actually pushed"
echo "[Gmbrowse PASS]"

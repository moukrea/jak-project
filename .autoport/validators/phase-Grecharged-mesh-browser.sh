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
grep -qiE 'filter|filtre' "$R" || fail "no filters (PBR-only / failing-only / material search)"
grep -qiE 'worst[- ]first|pire d.abord|sorted .*worst' "$R" || fail "mesh list not sorted worst-grade first"
grep -qiE 'auto[- ]?fram|cadrage' "$R" || fail "no automatic camera framing from the bounding box"
grep -qiE 'orbit' "$R" || fail "no free orbit around the selected mesh"
# 4. toggles, including the offline grade shown on screen (the cross-check loop)
grep -qiE 'checker|damier' "$R" || fail "no real-texture <-> checker toggle"
grep -qiE 'tessellation' "$R" || fail "no tessellation/parallax/off toggle"
grep -qiE 'relief' "$R" || fail "no relief slider"
grep -qiE 'grade|note' "$R" || fail "the offline test's grade is not displayed on screen (the confirm/refute loop)"
# 5. touch AND gamepad, no adb
grep -qiE 'touch|tactile' "$R" || fail "touch control not evidenced (the owner has no adb)"
# OWNER 2026-07-29: "impossible a parcourir via le tactile". The word "touch" in a report proves
# nothing — demand the gesture -> state-change chain, injected and observed on the device.
grep -qiE 'input (swipe|tap)|injected (gesture|touch)|geste inject' "$R" || fail "TOUCH: no injected gesture evidence (input swipe/tap) driving the browser"
grep -qiE '(swipe|glissement)[^.]{0,60}(scroll|defil|list)' "$R" || fail "TOUCH: list scrolling by swipe not demonstrated"
grep -qiE 'pinch|pincer' "$R" || fail "TOUCH: pinch-to-zoom in the 3D view not demonstrated"
grep -qiE 'state change|changement d.etat|selected mesh changed|etat du navigateur' "$R" || fail "TOUCH: gestures not shown to CHANGE the browser state (a screenshot proves nothing)"
grep -qiE '3613|thousands|milliers' "$R" || fail "TOUCH: scrolling a 3613-entry list not addressed (one-step-at-a-time is unusable by construction)"
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
[ "$GKB" -nt goal_src/jak1/pc/mesh-browser-pc.gc ] || fail "gk binary is OLDER than mesh-browser-pc.gc — it does not contain this work"
grep -qiE 'independent mesh rotation|rotate the mesh' "$R" || fail "mesh rotation: if the mesh cannot be spun, the report must say so explicitly as a GAP, not substitute light rotation silently"
# owner delivery condition: all levels indexed, and the browser ships WITH the mesh corrections
IDX=$(ls custom_assets/jak1/mesh_index/mesh_index_*.txt 2>/dev/null | wc -l)
# 25, not 26: jak1 ships 26 fr3 files but GAME.fr3 is the shared container and has ZERO geometry
# (tess_sign: "faces=0 gverts=0 (tfrag trees 0, tie trees 0)"), so there is nothing in it to browse.
# The 26 figure was the supervisor's assumption; the measurement corrected it.
[ "$IDX" -ge 25 ] || fail "index covers only $IDX level(s); every jak1 level WITH GEOMETRY must be indexed (25)"
grep -qiE 'all[- ](levels|25 levels)|tous les niveaux|25 levels' "$R" || fail "report does not evidence an all-levels index"
echo "[Gmbrowse PASS]"

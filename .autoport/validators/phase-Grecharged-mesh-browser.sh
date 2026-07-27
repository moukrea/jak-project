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
echo "[Gmbrowse PASS]"

#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Glp FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-lightprobes/report.txt
D=.autoport/reports/Grecharged-lightprobes/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"

# --- SOURCE-LEVEL (un-stubbable) ---
# A programmatic bake tool/harness must exist.
ls .autoport/*probe*bake* .autoport/*lightprobe* game/graphics/**/probe* tools/**/probe* 2>/dev/null | grep -qi . \
  || grep -rliE 'probe.?bake|bake.?probe|lightprobe|light_probe|irradiance.?(grid|volume|probe)' game/ .autoport/ common/ 2>/dev/null | grep -qi . \
  || fail "no programmatic probe-bake harness/code found"
# A village1 probe ASSET must have been produced (non-trivial size).
PROBE=$(find . -path ./.git -prune -o \( -iname '*village1*probe*' -o -iname '*probe*village1*' -o -iname '*lightprobe*village1*' -o -iname 'village1*.probes' \) -type f -print 2>/dev/null | head -1)
[ -n "$PROBE" ] || fail "no village1 probe asset file produced by the bake"
SZ=$(stat -c%s "$PROBE" 2>/dev/null || echo 0)
[ "$SZ" -gt 4096 ] || fail "village1 probe asset is trivially small ($SZ bytes) — likely a stub"
# A world shader must consume the probe (runtime integration), not just the analytic SH.
grep -rliE 'u_.*probe|probe.?sh|probe.?irr|probe.?cube|lightprobe' game/graphics/opengl_renderer/shaders/*.frag 2>/dev/null | grep -qi . \
  || fail "no world shader references the local probe (runtime ambient/IBL integration missing)"

# --- REPORT EVIDENCE ---
grep -qiE 'village1' "$R" || fail "no village1 (proving level) evidence"
grep -qiE 'programmatic|auto.?place|automated bake|no manual' "$R" || fail "no programmatic-bake evidence"
grep -qiE 'all (explorable )?heights?|per.?height|above each.*(walkable|collision|surface)|height layer|multi.?height' "$R" || fail "no all-explorable-heights grid evidence (owner)"
grep -qiE 'inside.?box|inside.?sphere|room center|interior probe|each room' "$R" || fail "no interior room-center probe evidence (inside-box)"
grep -qiE 'suns? included|full lit|includ.*sun|HDRI|not (zero|exclud).*sun|lit environment' "$R" || fail "no suns-INCLUDED full-lit-environment capture evidence (owner: excluding the suns falsifies it)"
grep -qiE 'double.?count|energy.?(consistent|conserv)|no.*(blow.?out|double).*sun|not.*re-?add.*sun|delta (only|the)' "$R" || fail "no no-double-count / energy-consistent composition evidence (the design crux)"
grep -qiE 'interior.*(A/B|local|correct|darker|different from.*(global|sky))|local ambient.*interior' "$R" || fail "no interior LOCAL-ambient A/B evidence (probe SH != global sky SH)"
grep -qiE 'reflection|IBL|prefilter|cubemap.*(metal|water|precursor|env)|metal.*reflect|water.*reflect' "$R" || fail "no reflection/IBL consumer evidence (metal/water/Precursor sampling the local cubemap)"
grep -qiE 'menu|recharged setting|toggle.*(probe|reflection)|no unknown.?id|selector' "$R" || fail "no coherent Recharged menu-entry evidence (no unknown-ID)"
grep -qiE 'off ?== ?stock|byte-identical|probes? off.*(stock|unchanged)' "$R" || fail "no OFF==stock byte-identical evidence"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus"
ls "$D"/*.mp4 >/dev/null 2>&1 || fail "no device video"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
grep -qiE 'full ?res|native res|render scal(e|ing) (off|disabled)|no (dynamic )?render.?scal|512|1024|cube.?face.*(res|resolution)' "$R" || fail "no full-resolution HDRI capture evidence (owner: full res, render scaling off, framerate irrelevant)"
echo "[Glp PASS]"

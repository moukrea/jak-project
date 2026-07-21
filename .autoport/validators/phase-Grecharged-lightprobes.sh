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
# OWNER 2026-07-21: probes must SHIP in the repo + APK (no manual side-load).
# (owner-approved location = a committed first-party dir e.g. custom_assets/<game>/probes,
#  NOT the git-ignored out/ build output; either a tracked out/ copy or ANY tracked .probes
#  satisfies "in the repo". NOTE: `git ls-files | grep -q` SIGPIPEs git under `set -o pipefail`
#  even on a match -> capture into a var and test emptiness instead of piping to grep -q.)
git ls-files --error-unmatch out/jak1/fr3/village1.probes >/dev/null 2>&1 \
  || [ -n "$(git ls-files -- '*.probes' 2>/dev/null)" ] \
  || fail "the .probes asset is not committed to the repo (owner: our probes must be IN the repo)"
grep -qiE 'bundle.*apk|embed.*apk|apk.*(bundle|asset|ship).*probe|probe.*(bundle|embed|ship).*apk|install-?only|no (manual )?side-?load|LoaderActivity.*probe|packaged.*probe' "$R" \
  || fail "no APK-bundled probes evidence (owner: probes embedded in the APK, clean install-only, no manual side-load)"
# OWNER PLAYTEST #1 (2026-07-21) — QUALITY gates (priority):
grep -qiE 'multiple interiors?|several interiors?|all (village1 )?interiors?|[3-9] interiors?|interiors? .*(each|all).*(probe|covered)|containment|occlusion.?aware.*select' "$R" || fail "no MULTI-interior coverage/selection evidence (owner: most interiors muted; cover ALL + select by containment, not just the one hut)"
grep -qiE 'contrast (preserv|kept|retain|unchanged)|detail (preserv|kept)|not (washed|muted|flatten)|albedo detail|preserve.*(contrast|detail)' "$R" || fail "no contrast/detail-preserved evidence (owner: probe mutes details/contrast)"
grep -qiE 'reflection.*(resource|expose|hand.?off|for pbr|to pbr|to water|not applied|no broad|removed from.*shader|cubemap.*(resource|input))|probe (system|grid) (does not|no longer) appl.*reflect|leave.*reflect.*(pbr|water)|reflect.*(deferred|handed).*(pbr|water)' "$R" || fail "reflections not deferred to PBR/water (owner: probe system must NOT apply reflections broadly = grey wash; bake+expose the cubemaps as a RESOURCE, let PBR/water apply them)"
grep -qiE 'per.?pixel.*(sh|probe|ambient|3d tex)|no (checker|damier|grid pattern)|seamless.*(probe|grid|interp)|checker.?board.*(fixed|removed|gone)|grid pattern.*(absent|none|no)|fft.*(no|absent).*period' "$R" || fail "no ground-checkerboard fix evidence (owner: visible probe checkerboard on the ground; per-pixel SH eval / seamless interp)"
# OWNER PLAYTEST #1b (2026-07-21):
grep -qiE 'AO.*(stable|no flicker|flicker.*(fixed|gone)|temporal(ly)? stable)|no (AO )?flicker|flicker.*movement.*(fixed|removed)|frame.?to.?frame.*AO.*(stable|low)' "$R" || fail "no AO-flicker-on-movement fix evidence (owner regression: AO flickers when moving; likely per-vertex->per-pixel root)"
grep -qiE 'green.?sun.*shadow.*(visible|preserv|kept|not (wash|vanish|invisible))|moon.*shadow.*(visible|preserv)|cast shadow.*(preserv|visible).*(probe|on)|shadow.*not.*(washed|invisible).*probe' "$R" || fail "no green-sun/moon shadow-still-visible-with-probes-ON evidence (owner regression: probe fill washes out the moon cast shadow)"
grep -qiE 'renam.*(probe|baked ambient|local ambient)|baked ambient|local ambient|no longer.*probe.*(label|menu)|menu.*(baked|local) ambient' "$R" || fail "no menu rename evidence (owner: 'probes' misleading since baked/precomputed; rename user-facing label)"
echo "[Glp PASS]"

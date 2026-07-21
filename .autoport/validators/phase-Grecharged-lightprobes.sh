#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Glp FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-lightprobes/report.txt
D=.autoport/reports/Grecharged-lightprobes/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
grep -qiE 'READY FOR OWNER VISUAL CHECK' "$R" || fail "no READY-FOR-OWNER marker (owner protocol)"
# FINAL ARCHITECTURE (owner plan): baked-modulation — multiplicative lit-brighten warm / shadow-darken cool.
grep -qiE 'baked.*(never removed|base|kept).*(modulat|influence)|modulat.*baked|multiplicative.*(brighten|lit)|lit.*(boost|brighten).*multiplicativ' "$R" || fail "no baked-modulation model evidence (owner final plan: baked = base, multiplicative influence)"
grep -qiE '(warm|sun).*(tint|hue|saturat).*(lit|brighten)|lit.*(warm|toward the sun)' "$R" || fail "no warm-tint-on-lit evidence"
grep -qiE '(cool|blue).*(tint|hue).*(shadow|dark)|shadow.*(cool|refroid)' "$R" || fail "no cool-tint-on-shadow evidence"
grep -qiE 'contrast (preserved|kept|intact|by construction)|multiplicat.*preserv.*contrast' "$R" || fail "no contrast-preserved evidence"
grep -qiE '(elevation|TOD).*(scale|weight).*(amplitude|boost|darken)|night.*(yellow|sun).*(zero|->0|fades)' "$R" || fail "no TOD/elevation amplitude scaling evidence (no ghost night shadows)"
grep -qiE 'green.?sun.*(tint|weaker|visible)|both suns' "$R" || fail "no green-sun modulation evidence"
grep -qiE 'green.?(sun|star).*(shadow map|cast shadow|projection)|shadow.*(from|her).*(green|star)' "$R" || fail "no green-star CAST-SHADOW projection evidence (owner: lighting + projection, symmetric with the sun, weaker but visible)"
grep -qiE 'no (temporal|EMA|tod).?smooth.*(baked)|baked.*(native|untouched).*(interp|timing|style)|prune.*(ema|crossfade)|removed.*(ema|tod.?smooth)' "$R" || fail "no NO-TOD-smoothing-on-baked evidence (owner: baked native keyframe rhythm = the style; EMA/crossfade era pruned)"
grep -qiE 'smoothstep|terminator.*(smooth|soft)|soft.*(boundary|terminator)' "$R" || fail "no smooth-terminator evidence"
# probes: world projection defaults OFF; resource kept for PBR/water; GPU upload skipped when unused.
grep -qE 'recharged_rt_probe_enable *= *false' game/graphics/gfx.h || fail "probe world-projection default is not OFF in gfx.h (owner: toggle kept as curiosity, default off)"
grep -qiE 'probe.*(resource|pbr|water).*(future|kept|reserved)|skip.*(gpu )?upload.*(probe|3d tex)|lazy.*(probe|upload)' "$R" || fail "no probes-as-resource + skip-GPU-upload-when-off evidence"
grep -qiE 'debug prop|tunable|rt\.(litboost|shadowmul|tint)' "$R" || fail "no tunable-amplitude debug props evidence"
grep -qiE 'off ?== ?stock|byte-identical' "$R" || fail "no OFF==stock evidence"
grep -qiE 'menu-tree' "$R" || fail "menu-tree.md not updated (standing rule)"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus (boots to gameplay)"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still (mechanical boot proof)"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
echo "[Glp PASS]"

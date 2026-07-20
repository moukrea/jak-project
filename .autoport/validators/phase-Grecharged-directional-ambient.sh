#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gda FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-directional-ambient/report.txt
D=.autoport/reports/Grecharged-directional-ambient/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
grep -qiE 'smooth.*(vertex )?normal|per-vertex normal|reconstruct.*normal|vertex normal' "$R" || fail "no smooth-vertex-normal reconstruction evidence (root-cause fix)"
grep -qiE 'relief|no longer flat|not (faceted|flat)|form.*(curved|shadow|model)|faceted.*fixed' "$R" || fail "no relief-restored evidence"
grep -qiE 'hemisphere|SH|IBL|tier|selector' "$R" || fail "no tiered ambient evidence"
grep -qiE 'off ?== ?stock|byte-identical' "$R" || fail "no OFF==stock"
grep -qiE 'better than.*baked|beats.*baked' "$R" || fail "no better-than-stock-baked evidence"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus"
ls "$D"/*.mp4 >/dev/null 2>&1 || fail "no device video"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
grep -qiE 'crease|hard edge|sharp edge|no.*(random|incoherent).*(patch|zone|lit)|coherent.*light' "$R" || fail "no crease-angle/hard-edge fix evidence (round-2 defect 1)"
grep -qiE 'selector.*(menu|Recharged|row|live)|Hemisphere / SH / IBL.*menu|3.*(model|ambient).*(menu|selectable)|menu.*(SH|IBL)' "$R" || fail "no in-menu ambient selector evidence (round-2 defect 2)"
grep -qiE 'stone|warp.?gate|multiple.*building|several.*(building|vantage)' "$R" || fail "no test-at-stone-building/multiple-vantages evidence (round-2)"
grep -qiE 'shadow.*(rock|terrain|form|sculpt)|rocks?.*(form|sculpt|not flat)|form in shadow' "$R" || fail "no shadowed-form (rocks not flat) evidence — round-2 CORE"
grep -qiE 'research|investigat|cost.*(Adreno|Snapdragon|618|8 Elite)|recommend' "$R" || fail "no real-research evidence — round-2"
grep -qiE 'ambient.*base|base.*ambient|additive.*sun|sun.*(add|on top)|compositing order|shadow.*(removes|only).*direct|varies by normal.*shadow' "$R" || fail "no ambient-base + additive-sun compositing evidence (owner root cause)"
grep -qiE 'default (colored )?render|vertical (surface|rock|wall)|rock face.*form|SH.*(vertical|form)|IBL.*(vertical|form)|NOT (the )?(dbg|viz)|real render' "$R" || fail "no default-render vertical-surface form evidence (supervisor correction — viz not acceptable)"
grep -qiE 'sun off.*(relief|form|sculpt)|ambient (only|alone).*(relief|form|sculpt)|sun-off.*(relief|form)|add light.*not.*shadow' "$R" || fail "no sun-OFF-shows-relief evidence (owner core gate)"
# SHIPPED-DEFAULT gate (supervisor 2026-07-20): the model the owner downloads out-of-box must be the one
# that sculpts vertical surfaces. hemisphere (model 0) is N.y-only => FLAT on vertical rocks/walls by
# construction. A prop-forced SH capture can false-pass the report greps while the shipped build stays flat.
# So the gfx.h default MUST be a directional model (SH=1 / IBL=2), not hemisphere.
DEFMODEL=$(grep -oE 'recharged_rt_ambient_model *= *[0-9]+' game/graphics/gfx.h | grep -oE '[0-9]+$' | head -1)
[ -n "$DEFMODEL" ] || fail "cannot read recharged_rt_ambient_model default from gfx.h"
[ "$DEFMODEL" != "0" ] || fail "shipped default ambient model is 0 (hemisphere = flat on vertical); must ship SH/IBL as default so the downloaded build sculpts (supervisor 2026-07-20)"
# owner playtest 2026-07-20 validated the exact combo SH(1) + strength 0.2 + contrast 1.0 — ship THAT default.
[ "$DEFMODEL" = "1" ] || fail "owner validated SH (model 1) as default; gfx.h default is $DEFMODEL (require 1=SH unless owner re-approves IBL)"
grep -qE 'recharged_rt_ambient_strength *= *0\.2' game/graphics/gfx.h || fail "shipped default ambient strength != 0.2 (owner-validated value)"
grep -qE 'recharged_rt_ambient_contrast *= *1\.0' game/graphics/gfx.h || fail "shipped default ambient contrast != 1.0 (owner-validated value)"
# sun must be coherent ON TOP of the strong ambient (owner: current WIP sun looks bizarre) — prove sun-ON too.
grep -qiE 'sun on.*(coheren|preserv|relief|lit side|adds? light|not.*(blow|flat))|sun-on.*(coheren|clean|relief)|both sun (on|off)' "$R" || fail "no sun-ON coherence evidence (owner: WIP sun bizarre; additive sun must not re-flatten the relief)"
# and the default-render capture must be documented as taken OUT-OF-BOX (no rt.ambientmodel setprop override)
grep -qiE 'out.?of.?box|no.*(setprop|prop).*override|shipped default|fresh install.*(capture|render)|default model.*(no|without) prop|as shipped' "$R" || fail "default-render capture not proven out-of-box (could be a prop-forced model that the download does not use)"
echo "[Gda PASS]"

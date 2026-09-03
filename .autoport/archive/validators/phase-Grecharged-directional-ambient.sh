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
# OWNER PLAYTEST #2 (2026-07-20): daylight nickel + "plus flat, excellent" (relief ACCEPTED). Two items:
# ITEM B — NIGHT abrupt steps: "deux changements brutaux de lumière la nuit + un au lever de soleil". The rt
# lighting must vary CONTINUOUSLY across the TOD cycle (no discrete jumps). Require a device TOD-sweep with a
# measured max-frame-to-frame step proving smoothness.
grep -qiE 'tod.?sweep|day.?night.*(sweep|cycle).*(smooth|delta|step)|no (brutal|abrupt|discrete).*(step|jump|transition)|frame.?to.?frame.*(delta|luminance).*(smooth|below|max.?step)|sunrise.*(smooth|no jump|continuous)|night.*(transition|step).*(smooth|fixed|no jump)' "$R" || fail "no NIGHT/TOD smoothness evidence (owner playtest #2: 2 brutal night light changes + 1 at sunrise — rt lighting must vary continuously across TOD, prove with a measured device sweep, no discrete step)"
# OWNER INSIGHT: the night KEY light must be the GREEN STAR / MOON (directional, weaker than sun, green),
# not an uncontrolled ambient tone. Require the moon/green-star directional light + smooth sun<->moon crossover.
grep -qiE 'green.?star|moon.?light|moon.?dir|u_rt_moon|sky-moon|moon key light|green.?sun|second (directional )?light' "$R" || fail "no green-star/moon directional night-light evidence (owner: night key light must come from the green star/moon, weaker than sun, not an uncontrolled source)"
grep -qiE 'cross(over|-?fade)|sun.{0,6}(<->|to|/).{0,6}moon|hand.?off|fade (the )?(sun|moon).*(in|out)|continuous.*(blend|handoff).*(sun|moon)|elevation.*(weight|blend)' "$R" || fail "no smooth sun<->moon crossover evidence (the fade that kills the brutal night/sunrise steps)"
# ITEM A — sun-lit vs shadow contrast too weak / mood-match to stock baked. Require contrast tuning + a
# device A/B vs the STOCK BAKED tone at the same vantage/TOD (mood preserved).
grep -qiE '(sun.?lit|lit side).*(contrast|separation).*(stronger|raised|increas|tuned)|contrast.*(sun.?lit|lit vs shadow|lit/shadow)|mood.?match|match.*(stock )?baked.*(tone|mood|colou?r)|baked.*(tone|colou?r).*match|tone.?match.*baked' "$R" || fail "no sun-lit contrast / stock-baked mood-match evidence (owner playtest #2 item A)"
# OWNER PLAYTEST #3 (2026-07-20): à-coups CONFIRMED fixed. Green star = Jak's 2ND SUN (not a night-only moon).
# Item 1 — green sun CASTS SHADOWS like the yellow sun.
grep -qiE 'green.?sun.*(shadow|cast)|moon.*(shadow|cast)|second.*(sun|light).*(shadow|cast)|green.?star.*(shadow|cast)|shadow.*(from|by).*(green|moon)|two shadow' "$R" || fail "no green-sun shadow-casting evidence (owner playtest #3 item 1: the green sun must cast shadows like the yellow sun)"
# Item 2 — green sun uses its REAL sky position (sky-sun index 1) and INFLUENCES the DAY when up, not synthesised night-only.
grep -qiE 'sky.?sun.*(index )?1|sun (index|idx) ?1|real (green.?sun|moon) (sky )?pos|green.?sun.*(day|daytime|whenever.*up|above.*horizon)|day.*green.?sun|not (synthes|night-only)|actual sky.*(green|moon).*(pos|dir)' "$R" || fail "no green-sun REAL-sky-position / day-influence evidence (owner playtest #3 item 2: drive from sky-sun index 1, contribute in daytime when up, not a synthesised night-only vector)"
# Item 4 — the GROUND (hfrag / heightmap terrain, or whichever bucket) must get the SH/IBL directional ambient (was flat).
grep -qiE 'hfrag|ground.*(SH|IBL|ambient|relief|rt path|directional)|floor.*(SH|IBL|ambient|relief)|terrain.*(SH|ambient|rt|relief)|heightmap.*(ambient|rt|lighting)|sol.*(SH|ambient|relief)' "$R" || fail "no ground/hfrag directional-ambient evidence (owner playtest #3 item 4: the ground renders flat — extend the rt SH ambient path to the ground shader/geometry)"
# OWNER PLAYTEST #4 (2026-07-20): the yellow-sun <-> green-sun REGIME handoff is brutal (a COLOUR shift the
# luminance-only smoothness metric missed). Require a SMOOTH per-channel crossfade at the handoff, measured
# PER-CHANNEL (R,G,B), not just luminance.
# Require the LITERAL per-channel measurement (attempt-7 report had 0 "per-channel" — luminance-only), AND a
# reference to the yellow<->green-sun handoff being a smooth crossfade. Both, so incidental RGB values / the
# old sun<->moon crossover mention can't false-pass.
grep -qiE 'per.?channel|per.?colou?r channel|R/G/B (max.?step|delta|step)' "$R" || fail "no PER-CHANNEL smoothness MEASUREMENT (owner playtest #4: luminance-only missed the yellow->green hue jump; measure R,G,B frame-to-frame step across the handoff)"
grep -qiE '(yellow|day).?sun.*(->|to|<->|hand.?off|cross).*green|green.?sun.*(->|<->|hand.?off|cross).*(yellow|day).?sun|colou?r crossfade.*(sun|handoff)|smooth.*(colou?r|hue).*(sun.?<->.?green|handoff)' "$R" || fail "no smooth yellow<->green-sun COLOUR crossfade evidence at the handoff (owner playtest #4)"
# OWNER PLAYTEST #5 (2026-07-20): the real bug is the shading ORIENTATION snapping (incl. the AMBIENT), not
# colour. Require (a) the dark-neutral-middle / per-sun elevation-fade orientation model, and (b) a STRUCTURAL
# per-pixel measurement (SSIM / per-pixel mean-abs frame-to-frame) — a MEAN/per-channel metric averages away
# an orientation flip, so it's insufficient.
grep -qiE 'orientation|re.?orient|dark (neutral )?middle|dark (neutral )?trough|elevation.?weight.*(fade|zero|below horizon)|per.?sun.*(fade|elevation)|ambient.*(not snap|no.*snap|smooth.*orient|near.?uniform.*middle)|directional.*(fade (out|in)|to zero)' "$R" || fail "no shading-ORIENTATION-smoothness / dark-neutral-middle model evidence (owner playtest #5: the ambient+key-light orientation snaps at the handoff; fix = per-sun elevation fade through a dark neutral middle, not a colour crossfade)"
grep -qiE 'per.?pixel|ssim|structural (delta|change|similarity)|spatial (delta|diff)|frame.?to.?frame.*(per.?pixel|ssim|structural)|mean.?abs.*(per.?pixel|consecutive frame)' "$R" || fail "no STRUCTURAL per-pixel smoothness MEASUREMENT (owner playtest #5: a mean/per-channel metric cancels an orientation flip; measure per-pixel/SSIM frame-to-frame across the sunset->dark->green-rise transition, no structural spike)"
echo "[Gda PASS]"

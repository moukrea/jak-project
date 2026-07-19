#!/usr/bin/env bash
# Grecharged-realtime-lighting: sun-only realtime lighting, obvious-model acceptance.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Grtl FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-realtime-lighting/report.txt
D=.autoport/reports/Grecharged-realtime-lighting/device
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no explicit RESULT: PASS (WIP does not gate)"
grep -qiE '^RESULT: WIP' "$R" && fail "report is WIP"
# obvious-model criteria must each be evidenced
grep -qiE 'sun.?side|lit.?side|N.?dot.?L|terminator' "$R" || fail "no sun-side-lit/dark-side evidence (criterion 1)"
grep -qiE 'cast shadow|casts? a shadow|shadow.*behind|contact' "$R" || fail "no cast-shadow evidence (criterion 2)"
grep -qiE 'h8.*h16|flip|opposite.*sun|sun.?consistent' "$R" || fail "no sun-consistency / h8-h16 flip evidence (criterion 3)"
grep -qiE 'orbit|camera.?independent|pinned' "$R" || fail "no camera-orbit stability evidence (criterion 4)"
grep -qiE 'baked.?off|no baked|baked.*disabled|pure.*sun' "$R" || fail "no baked-off evidence (criterion 5)"
grep -qiE 'no ambient|zero ambient|ambient.*(off|none|removed)|genuinely dark' "$R" || fail "no 'no-ambient' evidence"
grep -qiE 'realtime-lighting\?|realtime lighting.*(on|off|toggle)' "$R" || fail "no realtime-lighting toggle evidence"
grep -qiE 'off ?== ?stock|byte-identical|stock by construction' "$R" || fail "no OFF==stock claim"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "no device jak1 focus evidence"
ls "$D"/*.mp4 >/dev/null 2>&1 || fail "no device video (orbit clip)"
ls "$D"/*.png >/dev/null 2>&1 || fail "no device still"
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "gold not pristine"
grep -qiE 'relief|drape|terrain|conform|per-fragment world' "$R" || fail "no shadow-follows-relief evidence (round-2)"
grep -qiE 'fade|no pop|does not pop|smooth.*edge|distance fade' "$R" || fail "no no-pop/fade-at-range evidence (round-2)"
grep -qiE 'shadow quality|shadow.?map res|shadow distance|quality.*setting' "$R" || fail "no shadow quality/distance settings (round-2)"
grep -qiE 'all (casters|geometry|tie)|complete.*caster|every.*caster' "$R" || fail "no complete-geometry evidence (round-2)"
grep -qiE 'beyond.*range.*(lit|shad|N.?L)|distant.*(lit|shaded)|N.?L.*(everywhere|global|whole world|unconditional)' "$R" || fail "no global-N.L-beyond-shadow-range evidence (round-3 defect A)"
grep -qiE 'shrub' "$R" || fail "no shrub cast/receive evidence (round-3 defect B)"
grep -qiE 'menu row|Recharged Settings.*(row|toggle|slider)|in-game menu|4 (rows|settings)' "$R" || fail "no in-menu settings evidence (round-3 defect D)"
grep -qiE '150' "$R" || fail "no default-distance-150 evidence (round-4)"
grep -qiE 'baked.*fallback|fallback.*baked|crossfade.*baked|far.*baked' "$R" || fail "no far=baked fallback evidence (round-4)"
grep -qiE 'anti.?pixel|never.*pixel|adaptive PCF|distance-aware.*(blur|pcf|soft)|smooth.*distant' "$R" || fail "no shadow anti-pixelation evidence (round-4)"
grep -qiE 'very low|very high|5 (tier|quality|level)|512.*8192' "$R" || fail "no 5-tier quality evidence (round-4)"
grep -qiE 'shadow strength|residual|0\.2|not.*black|partial.*dark|opacity' "$R" || fail "no partial-shadow (not-black, ~0.2 residual) evidence (round-5)"
grep -qiE 'penumbra|wider.*kernel|distant.*smooth|blur.*(harder|wider|distance)|poisson|separable' "$R" || fail "no stronger-blur/smooth-distant evidence (round-5)"
echo "[Grtl PASS]"

#!/usr/bin/env bash
# Validator — Grecharged-hud-jak1: optional Recharged HUD for jak1, gated (OFF==stock).
# Checks: report evidence (menu placement + gate + heart/gauge technique + OFF==stock A/B),
# recharged assets baked into the build, a real device screencap, gold pristine.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Grecharged-hud FAIL] $*" >&2; exit 1; }
ok(){ echo "[Grecharged-hud ok] $*"; }

R=.autoport/reports/Grecharged-hud-jak1/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*RECHARGED[[:space:]]+HUD' "$R" || fail "report lacks RESULT: RECHARGED HUD <what-lands>"
grep -qiE 'RESULT:.*(IN-PROGRESS|in progress|underway|not final)' "$R" && fail "report RESULT is a living skeleton (IN-PROGRESS) — not a final result"
grep -qiE 'recharged settings|réglages rechargés' "$R" || fail "must add a 'Recharged Settings' submenu"
grep -qiE 'before.*advanced|advanced.*after|precede.*advanced|avant.*advanced' "$R" || fail "Recharged Settings must sit BEFORE Advanced settings"
grep -qiE 'recharged hud.*(on|off|toggle)|toggle.*recharged|hud rechargé' "$R" || fail "must have a Recharged HUD ON/OFF toggle"
grep -qiE 'persist' "$R" || fail "toggle must persist"
grep -qiE 'off.*(stock|default|identical|unchanged|original)|stock.*(off|identical)|no regression' "$R" || fail "must prove OFF path == stock HUD (no regression)"
grep -qiE 'jak_heart_100|heart.*100|health.*bucket|33.*blink|blink.*33' "$R" || fail "must implement the 4-state heart (incl 33% blink over jak_heart_0)"
grep -qiE 'gauge|mask|tip|end.*piece|rotate' "$R" || fail "must implement the eco gauge (mask + rotated tip technique)"
ok "report: menu placement + gate + OFF==stock + heart + gauge described"

# OWNER ROUND 2 (2026-07-09): gauge scale, fuel-cell regression, center eco particle, green sphere by heart
grep -qiE 'gauge.*(scale|resiz|larger|size|taille)|(scale|resiz).*gauge' "$R" || fail "round2: gauge must be scaled up to the stock gauge footprint"
grep -qiE '(fuel.?cell|power.?cell|pile).*(restor|visible|appears|fixed|back|réappar)' "$R" || fail "round2: fuel cell must appear again in the HUD (regression)"
grep -qiE '(cent(er|re)|hole|trou).*(eco|particle|particule)|(eco|particle).*(cent(er|re)|hole)' "$R" || fail "round2: 3D eco particle in the gauge center hole when active"
grep -qiE 'green.*(sphere|orb|particle|particule)|(sphere|orb|particule).*vert' "$R" || fail "round2: real green eco sphere pickup model between heart and counter"
ok "round2 items addressed in report"

# PHYSICAL: recharged assets baked into the build (not just referenced in source)
BAKED=0
# NOTE: `| grep -q` under pipefail SIGPIPE-fails (141) on big streams even when the
# pattern matches (documented validator bug class) — count with grep -c instead.
for so in build-android/lib/arm64-v8a/libgk.so; do
  [ -f "$so" ] && { n=$(strings -a "$so" 2>/dev/null | grep -icE 'recharged|jak_heart|jak_gauge' || true); [ "${n:-0}" -gt 0 ] && BAKED=1; }
done
n=$(find android build-android out -type f 2>/dev/null | grep -icE 'recharged|jak_heart|jak_gauge' || true); [ "${n:-0}" -gt 0 ] && BAKED=1
[ "$BAKED" -eq 1 ] || fail "recharged_assets not baked into the build (heart/gauge not found in build outputs)"
ok "recharged assets baked into the build"

# STRICT: a real device screencap artifact
FRAME=$(find .autoport/reports/Grecharged-hud-jak1 -type f \( -name '*.png' -o -name '*.jpg' \) -newermt '-1 day' 2>/dev/null | grep -v '/x86/' | grep -iE 'device|jak1focus' | head -1)
[ -n "$FRAME" ] || fail "no device screencap artifact"
SZ=$(stat -c %s "$FRAME" 2>/dev/null || echo 0); [ "$SZ" -ge 20000 ] 2>/dev/null || fail "screencap $FRAME too small ($SZ B)"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1|screencap|screenshot' "$R" || fail "report must tie screencaps to jak1 foreground"
ok "device screencap present ($FRAME, $SZ B)"

# OWNER ROUND 4 (2026-07-09): round-3 features proven broken on the ARM64 device
grep -qiE 'arm64.*(device|divergen)|device.*(arm64|verif)|on.?device' "$R" || fail "round4: must prove fixes on the ARM64 DEVICE (x86-verify insufficient)"
grep -qiE '(world|monde).*(space|particle|launch|émet)|launch.*(hud|world).?space|mis.?target' "$R" || fail "round4: must fix the HUD particle launcher firing in WORLD space (Jak emits green eco every ~4s)"
grep -qiE '(fuel.?cell|pile).*(body|model|corps|render|draw).*(device|arm64|fix)|cell body' "$R" || fail "round4: fuel-cell BODY must render on device (only glow shows)"
grep -qiE '(green|eco).*(particle|sprite|group).*(device|arm64|render|fix)' "$R" || fail "round4: green eco real particle group must render on device"
ok "round4 arm64-device items addressed in report"

# DEVICE ASSET FRESHNESS: the HUD lives in GOAL code (hud-classes-pc.gc -> GAME.CGO).
# deploy_verify.sh only covers libgk.so; this proves the device runs the fresh CGO set
# (2026-07-09: a gate false-passed while the Redmi ran an INTERMEDIATE round-3 GAME.CGO).
bash .autoport/lib/deploy_verify_assets.sh eae4df44 jak1 >/dev/null 2>&1 || fail "device runs STALE GOAL CGOs — re-push out/jak1/iso/ (deploy_verify_assets.sh)"
ok "device runs the fresh GOAL CGO/DGO set (deploy_verify_assets)"

# gold pristine
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "golden pristine"
# OWNER ROUND 3 (2026-07-09): particle-system fidelity + pickup behavior + fade blink
grep -qiE '(vacil|waver|flicker|shimmer).*(green|eco)|(green|eco).*(vacil|waver|flicker|shimmer)' "$R" || fail "round3: green eco must waver like in-game"
grep -qiE '(launch|group|sparticle|launcher).*(hud|icon|gauge|heart)|(hud|gauge).*(sparticle|particle group)' "$R" || fail "round3: must drive real in-game particle groups in HUD, not lookalike sprites"
grep -qiE '(cell|pile).*(render|visible|appears|draw)' "$R" || fail "round3: fuel cell body must render (not just halo)"
grep -qiE '(halo|glow|lueur).*(tint|teinte|color|colour)' "$R" || fail "round3: halo tint must match in-game"
grep -qiE '(pickup|collect|ramass).*(heart|coeur)|(heart|coeur).*(pickup|collect|pop)' "$R" || fail "round3: heart must pop on green-eco pickup like original HUD"
grep -qiE 'fade.*(in|out|blink)|crossfade|alpha.*(fade|lerp)' "$R" || fail "round3: low-health blink must be fade in/out, not hard on/off"
ok "round3 items addressed in report"
# OWNER LIVE REVIEW round2 addendum: HUD fuel cell must match in-game rendering
grep -qiE '(anim|spin).*(speed|rate|slow|clock)|vitesse.*anim' "$R" || fail "addendum: fuel-cell animation speed must match in-game"
grep -qiE 'glow|lueur|bloom' "$R" || fail "addendum: fuel-cell glow must match in-game"
grep -qiE 'tint|teinte|hue|color match' "$R" || fail "addendum: fuel-cell tint must match in-game"
ok "addendum: fuel-cell in-game-match (anim speed + glow + tint) addressed"
# OWNER ROUND 4 addendum #2: eco-type-correct center particle + item scaled into the hole
grep -qiE '(blue|red|yellow|per.?type|active eco).*(particle|emitter|center)|(center|gauge).*(active eco|per.?type)' "$R" || fail "round4-add2: gauge-center particle must follow the ACTIVE eco type (not always green)"
grep -qiE '(scal|size|fit).*(hole|center|trou)|(hole|center).*(scal|fit)|z.?order|draw order' "$R" || fail "round4-add2: center item must be scaled to fit INSIDE the hole (not full-gauge-size behind the gauge)"
ok "round4-add2 (eco-type particle + center scale/z-order) addressed"
echo "[Grecharged-hud PASS] Recharged HUD gated + menu + heart/gauge + assets baked + device frame. (owner play-test next)"

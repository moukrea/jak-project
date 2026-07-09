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
grep -qiE 'recharged settings|réglages rechargés' "$R" || fail "must add a 'Recharged Settings' submenu"
grep -qiE 'before.*advanced|advanced.*after|precede.*advanced|avant.*advanced' "$R" || fail "Recharged Settings must sit BEFORE Advanced settings"
grep -qiE 'recharged hud.*(on|off|toggle)|toggle.*recharged|hud rechargé' "$R" || fail "must have a Recharged HUD ON/OFF toggle"
grep -qiE 'persist' "$R" || fail "toggle must persist"
grep -qiE 'off.*(stock|default|identical|unchanged|original)|stock.*(off|identical)|no regression' "$R" || fail "must prove OFF path == stock HUD (no regression)"
grep -qiE 'jak_heart_100|heart.*100|health.*bucket|33.*blink|blink.*33' "$R" || fail "must implement the 4-state heart (incl 33% blink over jak_heart_0)"
grep -qiE 'gauge|mask|tip|end.*piece|rotate' "$R" || fail "must implement the eco gauge (mask + rotated tip technique)"
ok "report: menu placement + gate + OFF==stock + heart + gauge described"

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
FRAME=$(find .autoport/reports/Grecharged-hud-jak1 -type f \( -name '*.png' -o -name '*.jpg' \) -newermt '-1 day' 2>/dev/null | head -1)
[ -n "$FRAME" ] || fail "no device screencap artifact"
SZ=$(stat -c %s "$FRAME" 2>/dev/null || echo 0); [ "$SZ" -ge 20000 ] 2>/dev/null || fail "screencap $FRAME too small ($SZ B)"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1|screencap|screenshot' "$R" || fail "report must tie screencaps to jak1 foreground"
ok "device screencap present ($FRAME, $SZ B)"

# gold pristine
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "golden pristine"
echo "[Grecharged-hud PASS] Recharged HUD gated + menu + heart/gauge + assets baked + device frame. (owner play-test next)"

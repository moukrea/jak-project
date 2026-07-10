#!/usr/bin/env bash
# Validator — Grecharged-grass-poc: 3D grass PoC on the training level, gated (OFF==stock).
# Physical: gated renderer code + grass shader present in build, device screencap/video artifacts,
# report covers the 3 LOD tiers + breeze + trample + fps cost + OFF==stock.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Ggrass FAIL] $*" >&2; exit 1; }
ok(){ echo "[Ggrass ok] $*"; }

R=.autoport/reports/Grecharged-grass-poc/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*RECHARGED[[:space:]]+GRASS[[:space:]]+POC' "$R" || fail "report lacks RESULT: RECHARGED GRASS POC"
grep -qiE 'tra-grass|grass.*texture.*(detect|ground)|texture.*(id|match).*grass' "$R" || fail "placement must be driven by grass ground-texture detection (tra-grass)"
grep -qiE 'blade' "$R" || fail "must implement individual near blades"
grep -qiE 'size|scale' "$R" && grep -qiE 'orientation|rotation|yaw' "$R" && grep -qiE 'curv|bend|bent' "$R" || fail "blades need variable size + orientation + curvature"
grep -qiE 'flat.?color|no.?texture|couleur' "$R" || fail "PoC blades must be FLAT COLOR (no texture yet)"
grep -qiE 'breeze|wind|brise|sway' "$R" || fail "must implement breeze idle motion"
grep -qiE 'trample|flatten|écras|crush|bend.*(jak|player)|jak.*(walk|pos)' "$R" || fail "must implement the trample-under-Jak effect"
grep -qiE 'card' "$R" || fail "must implement mid-range grass cards (crossed quads)"
grep -qiE 'lod|distance|band|tier|far' "$R" || fail "must describe the 3-tier LOD (near blades / mid cards / far texture)"
grep -qiE 'training|geyser' "$R" || fail "PoC must be scoped to the training level"
grep -qiE 'fps|cost|perf' "$R" || fail "must report the fps cost on device"
grep -qiE 'off.*(stock|identical|unchanged)|stock.*off|no regression' "$R" || fail "must prove OFF == stock"
# OWNER OVERRIDE 2026-07-10: grass ships DEFAULT ON (toggle still exists; OFF == stock).
grep -qiE 'default[ -]?on|on by default|default.*#t|défaut.*(on|activ)|ships? (on|enabled)' "$R" || fail "owner override: grass must default ON (not OFF) — toggle still exists, OFF still == stock"
ok "report: placement + blades(size/orient/curve, flat-color) + breeze + trample + cards + LOD + training-only + fps + OFF==stock + DEFAULT ON"

# PHYSICAL: grass renderer/shader actually in the build
SO=build-android/lib/arm64-v8a/libgk.so
[ -f "$SO" ] || fail "no built Android libgk.so"
HITS=$(strings -a "$SO" 2>/dev/null | grep -ciE 'recharged.?grass|grass.?blade|grass_inst|g_grass')
[ "${HITS:-0}" -gt 0 ] || { HITS=$(grep -rli 'recharged.*grass\|grass.*blade\|grassPoc\|g_grass' game/graphics android 2>/dev/null | wc -l); [ "${HITS:-0}" -gt 0 ] || fail "no grass renderer code/strings found in build or source (stub)"; }
ok "grass renderer present ($HITS refs)"

# STRICT: device visual artifacts (screencap; video counts too)
FRAME=$(find .autoport/reports/Grecharged-grass-poc -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.mp4' \) -newermt '-2 days' 2>/dev/null | head -1)
[ -n "$FRAME" ] || fail "no device screencap/video artifact"
SZ=$(stat -c %s "$FRAME" 2>/dev/null || echo 0); [ "$SZ" -ge 20000 ] || fail "artifact $FRAME too small ($SZ B)"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "report must assert jak1 foreground at capture"
ok "device visual artifact present ($FRAME)"

# GRASS RENDERER IS C++ (libgk) — the DEVICE must actually run the libgk that contains it.
# 2026-07-10: a report claimed "working on device". The RELIABLE proof is deploy_verify
# (build==APK-bundled==device-installed-APK libgk) PLUS the APK-bundled libgk actually
# containing grass strings. NOTE: this device extracts the native lib from INSIDE the APK
# at load time (extractNativeLibs=false) — it is NOT a readable file on disk, so any
# `run-as strings /data/app/.../lib/arm64/libgk.so` check FALSE-FAILS (No such file).
# Read the libgk out of the installed APK instead (host adb has pm-path + pull rights).
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL — device APK libgk != fresh build; the grass renderer never reached the device (reinstall the APK)"
ADB=/home/emeric/Android/platform-tools/adb
DP=$("$ADB" -s eae4df44 shell pm path org.opengoal.gk.jak1 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
[ -n "$DP" ] || fail "jak1 not installed on device"
mkdir -p .autoport/tmp; DTMP=$(mktemp .autoport/tmp/gdv.XXXXXX.apk)
"$ADB" -s eae4df44 pull "$DP" "$DTMP" >/dev/null 2>&1 || fail "could not pull device APK"
DEVGRASS=$(unzip -p "$DTMP" lib/arm64-v8a/libgk.so 2>/dev/null | strings | grep -ciE 'recharged.?grass|grass.?blade|g_grass')
rm -f "$DTMP"
[ "${DEVGRASS:-0}" -gt 0 ] || fail "the installed device APK's libgk has NO grass renderer strings ($DEVGRASS) — the toggle has nothing to act on"
ok "device runs the grass libgk (APK-bundled: $DEVGRASS grass refs) + deploy_verify PASS"

git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "golden pristine"
echo "[Ggrass PASS] 3D grass PoC gated + 3-tier LOD + breeze/trample + device evidence. (owner play-test next)"

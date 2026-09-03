#!/usr/bin/env bash
# grass_p19_postunlock.sh — run the moment the owner unlocks the Redmi.
# 1. install the near-fade APK  2. restore DEFAULT grass settings (near 30 / card 95 / density 150, ON)
# 3. deploy_verify  4. stability run x2 at the DEFAULT config (the config that used to die 3/3).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
die(){ echo "[postunlock FAIL] $*" >&2; exit 1; }

echo "## 1. install"
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 | grep -q Success || die "install failed"
echo "  install OK"

echo "## 2. restore DEFAULT grass settings"
$ADB shell am force-stop $PKG; sleep 1
$ADB shell cat "$PCS" > /tmp/pcs19r.gc || die "cannot read pc-settings"
sed -i 's/^recharged-grass? = #[tf]/recharged-grass? = #t/;s/^recharged-grass-near-dist = [0-9.]*/recharged-grass-near-dist = 30.0000/;s/^recharged-grass-card-dist = [0-9.]*/recharged-grass-card-dist = 95.0000/;s/^recharged-grass-density = [0-9.]*/recharged-grass-density = 150.0000/' /tmp/pcs19r.gc
$ADB push /tmp/pcs19r.gc /data/local/tmp/p.gc >/dev/null && $ADB shell cp /data/local/tmp/p.gc "$PCS" && $ADB shell rm -f /data/local/tmp/p.gc
$ADB shell cat "$PCS" | grep -E 'recharged-grass' | tr -d '\r'

echo "## 3. deploy_verify"
bash .autoport/lib/deploy_verify.sh $S jak1 2>&1 | tail -2 | grep -q PASS || die "deploy_verify failed"
echo "  deploy_verify OK"

echo "## 4. stability x2 at DEFAULT config (was 3/3 dead before the near-fade fix)"
bash .autoport/grass_p19_stability.sh 2>&1 | tail -3 | grep -q 'p19stab PASS' || die "stability run 1 FAILED"
echo "  stability run 1 PASS"
bash .autoport/grass_p19_stability.sh 2>&1 | tail -3 | grep -q 'p19stab PASS' || die "stability run 2 FAILED"
echo "  stability run 2 PASS"
echo "[postunlock] ALL GREEN — proceed to grass_p19_capture.sh"

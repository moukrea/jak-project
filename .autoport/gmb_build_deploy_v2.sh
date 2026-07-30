#!/usr/bin/env bash
# gmb_build_deploy_v2.sh — Grecharged-mesh-browser V2 (freecam/reticle) consistent build + deploy.
# Modeled on gda_build_deploy_full.sh. One consistent pass:
#   * custom pack       (android/build_custom_pack.sh jak1 — mesh_index 25 levels + the owner
#                        "browser ships WITH the mesh corrections" freshness guard)
#   * 28 arm64 CGO/DGO + text + libgk.so + APK  (./build.sh android-arm64 --pbr — includes the
#                        v2 mesh-browser-pc.gc freecam GOAL and the v2 C++: kmachine bridge,
#                        MeshBrowserGizmos, Tie3/TFragment mb_* counters, TouchOverlayView CAM)
#   * install + deploy_verify + assets verify + boot to live render via LoaderActivity
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-mesh-browser; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gmb-build FAIL] $*" >&2; exit 1; }

say "0. adb server refresh (wedged daemon => false 'not installed')"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device

say "1. custom pack (mesh_index 25 levels + bake-freshness guard)"
bash android/build_custom_pack.sh jak1 || die "build_custom_pack failed (freshness guard?)"
NIDX=$(unzip -l android/app/src/jak1/assets-slim/bundle/jak1_custom.zip 2>/dev/null | grep -c 'mesh_index/mesh_index_.*\.txt')
[ "$NIDX" -ge 25 ] || die "custom pack carries only $NIDX mesh_index files (need 25)"
PACK_VER=$(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
echo "  custom pack version=$PACK_VER mesh_index files=$NIDX"

say "2. full android build: ./build.sh android-arm64 --pbr (CGOs + text + libgk + APK)"
./build.sh android-arm64 --pbr || die "build.sh android-arm64 --pbr failed"
[ -f "$APK" ] || die "APK not produced"
MB=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'mesh_browser_state')
GZ=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -ciE 'mb.gizmo|MeshBrowserGizmos')
echo "  libgk mesh_browser_state strings=$MB gizmo strings=$GZ"
[ "$MB" -gt 0 ] || die "libgk.so missing mesh_browser_state (v2 bridge not compiled in)"

say "3. install APK + deploy_verify (build==APK==device libgk)"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s $S shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then die "DEVICE_LOCKED — needs owner unlock"; fi
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
# deploy_verify moved AFTER step 4: its custom-pack stamp check compares against the freshly
# built pack version, but the stamp's SOLE writer is a LoaderActivity boot (step 4). Running it
# here fails by construction whenever the pack version moves (deploy_verify trap class #4).

say "4. boot via LoaderActivity: custom-pack stamp + CGO extraction + live render"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/gmb-v2-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|link finish|Fatal signal|signal [0-9]+ \(SIG|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
stamp_ok(){ [ "$($ADB -s $S shell run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r')" = "$PACK_VER" ]; }
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 900 ]; do
  if grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  CRASH during boot"; break; fi
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; break; }
  sleep 5
done
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_render=$ok focus=$FOCUS"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach render (crash or hang)"
if stamp_ok; then echo "  custom pack stamp matches $PACK_VER"; else
  echo "  waiting for custom pack re-extraction (version change)"
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 600 ]; do stamp_ok && break; sleep 10; done
  stamp_ok || die "custom pack stamp never reached $PACK_VER (LoaderActivity is the sole writer)"
fi
NDEV=$($ADB -s $S shell "run-as $PKG sh -c 'ls files/custom/jak1/mesh_index/ 2>/dev/null'" | grep -c mesh_index_)
echo "  device mesh_index files: $NDEV"
[ "$NDEV" -ge 25 ] || die "device holds only $NDEV mesh_index files"

say "5. deploy_verify (build==APK==device libgk + pack stamp) + deploy_verify_assets"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify (libgk) failed"
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -5 || die "deploy_verify_assets failed"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[gmb-build] DONE — v2 freecam build on device, boots to render, deploy_verify + assets PASS."

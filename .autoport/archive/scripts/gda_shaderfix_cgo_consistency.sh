#!/usr/bin/env bash
# gda_shaderfix_cgo_consistency.sh — the device reverted to a STALE x86 CGO pack (older stamp) while the
# APK now bundles the arm64 pack (ce2e511129fa7) + the fresh arm64 libgk (additive-sun shaders). goal_src
# is UNCHANGED so the arm64 CGOs are still valid — we just need them on the device consistent with libgk.
# Path: boot once => LoaderActivity re-extracts the arm64 bundled pack (stamp mismatch) => then push the
# local arm64 overlay (belt-and-suspenders, sha-verified) => deploy_verify (+assets) must go GREEN.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gda-cgofix FAIL] $*" >&2; exit 1; }
PACK_VER=$(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
echo "target bundled pack version = $PACK_VER (arm64)"

"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device

dev_ogf(){ $ADB -s $S shell "run-as $PKG cat files/cgo/jak1/GAME.CGO" 2>/dev/null | strings -a | grep -oE 'ogflags:[0-9a-f]+:[a-z0-9_-]+' | head -1; }
dev_stamp(){ $ADB -s $S shell "run-as $PKG cat files/.cgo_pack_stamp_jak1" 2>/dev/null | tr -d '\r'; }
extract_done(){ [ "$(dev_stamp)" = "$PACK_VER" ] && [ "$($ADB -s $S shell run-as $PKG ls files/cgo/jak1/ 2>/dev/null | grep -cE '\.(CGO|DGO)\r?$')" -ge 28 ]; }

say "1. boot once to force re-extraction of the arm64 bundled pack (stamp mismatch => re-extract)"
echo "  before: stamp=$(dev_stamp) GAME.CGO=$(dev_ogf)"
LOG="$OUT/gda-cgofix-extract.log"; : > "$LOG"
( $ADB -s $S logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gda_cgofix_lc.pid )
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 900 ]; do
  extract_done && break
  sleep 10
done
kill "$(cat /tmp/gda_cgofix_lc.pid 2>/dev/null)" 2>/dev/null || true
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
echo "  after : stamp=$(dev_stamp) GAME.CGO=$(dev_ogf)"
extract_done || die "arm64 pack never (re)extracted in 900s (stamp still $(dev_stamp) != $PACK_VER)"
case "$(dev_ogf)" in *android-arm64*) : ;; *) die "device GAME.CGO still not android-arm64 after extract: $(dev_ogf)";; esac

say "2. push local arm64 overlay (sha-verified) — reinforce consistency"
bash .autoport/Gconsolidate_deploy_cgos.sh 2>&1 | tail -4 || die "Gconsolidate push failed"

say "3. deploy_verify + deploy_verify_assets (must be GREEN now)"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -6 || die "deploy_verify still failing"
bash .autoport/lib/deploy_verify_assets.sh "$S" jak1 2>&1 | tail -6 || die "deploy_verify_assets failing"
echo "[gda-cgofix] DONE — device is arm64-consistent (libgk additive-sun + arm64 CGO pack). Ready to capture."

#!/usr/bin/env bash
# gpbrf3_disp.sh — REOPEN #3 DISPLACEMENT A/B evidence via the REAL user path:
# settings.ini pbr-displacement (menu-committed key) -> hud push -> gs -> TFragment tess
# routing / POM gate. One boot per mode (the tess program switch is a gs read at draw
# time, but we A/B the whole chain the owner uses).
#   mode M    (M = 0 Off | 1 Parallax | 2 Tessellation): set ini, boot wall vantage, capture disp_m$M
#   metrics   bdiff wall crops 0v1 (POM), 1v2 (tessellation), 0v2 + tess logcat health
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device; mkdir -p "$OUT"
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
BIS=.autoport/gpbrf3_bisect.sh
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gpbrf3-disp FAIL] $*" >&2; exit 1; }

case "${1:?stage (mode|metrics)}" in
mode)
  M=${2:?0|1|2}
  adb shell am force-stop $PKG; sleep 2
  adb shell cat "$PCS" > /tmp/g3d_pcs.ini 2>/dev/null || die "cannot read $PCS"
  tr -d '\r' < /tmp/g3d_pcs.ini > /tmp/g3d2.ini && mv /tmp/g3d2.ini /tmp/g3d_pcs.ini
  if grep -qaE '^pbr-displacement = ' /tmp/g3d_pcs.ini; then
    sed -i -E "s/^pbr-displacement = .*/pbr-displacement = $M/" /tmp/g3d_pcs.ini
  else
    sed -i "/^\[secrets\]/i pbr-displacement = $M" /tmp/g3d_pcs.ini
  fi
  adb push /tmp/g3d_pcs.ini /data/local/tmp/g3d_pcs.ini >/dev/null 2>&1 || die "push ini"
  adb shell cp /data/local/tmp/g3d_pcs.ini "$PCS" || die "cp ini"
  adb shell cat "$PCS" | tr -d '\r' | grep -qa "^pbr-displacement = $M" || die "ini did not land"
  bash "$BIS" boot
  sleep 2
  adb shell screenrecord --time-limit 3 --bit-rate 8000000 /sdcard/g3d_m$M.mp4 || die "rec m$M"
  adb pull /sdcard/g3d_m$M.mp4 /tmp/g3d_m$M.mp4 >/dev/null 2>&1 || die "pull m$M"
  adb shell rm -f /sdcard/g3d_m$M.mp4
  rm -rf /tmp/g3d_fr; mkdir -p /tmp/g3d_fr
  ffmpeg -y -loglevel error -i /tmp/g3d_m$M.mp4 -vf fps=2 /tmp/g3d_fr/f_%03d.png
  cp "$(ls /tmp/g3d_fr/f_*.png | tail -1)" "$OUT/disp_m$M.png"
  rm -rf /tmp/g3d_fr /tmp/g3d_m$M.mp4
  cp "$OUT/logcat-bisect.log" "$OUT/logcat-disp-m$M.log" 2>/dev/null || true
  bash "$BIS" cleanup
  echo "  mode $M -> $OUT/disp_m$M.png"
  ;;
metrics)
  {
    python3 .autoport/gpbrf_reopen_measure.py bdiff "$OUT/disp_m0.png" "$OUT/disp_m1.png"
    python3 .autoport/gpbrf_reopen_measure.py bdiff "$OUT/disp_m1.png" "$OUT/disp_m2.png"
    python3 .autoport/gpbrf_reopen_measure.py bdiff "$OUT/disp_m0.png" "$OUT/disp_m2.png"
    for M in 0 1 2; do
      L="$OUT/logcat-disp-m$M.log"
      [ -f "$L" ] || continue
      echo "mode $M logcat: link/compile errors: $(grep -acE 'shader.*[Ee]rror|link.*[Ff]ail' "$L") tess-unsupported: $(grep -acE 'tess' "$L")"
    done
  } | tee "$OUT/disp_metrics.txt"
  ;;
*) die "unknown stage $1";;
esac

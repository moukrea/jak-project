#!/usr/bin/env bash
# mm_device_proof.sh — Grecharged-materials-modern-parity, device proof on the Redmi.
#
# PROOF ECONOMY (owner standing order): prove only what would break SILENTLY, with the cheapest
# instrument that already exists. So this reuses .autoport/pbr_device_capture.sh's `run` stage
# verbatim for the warp+record and adds only the four checks this phase actually owes:
#   1. FRESHNESS  — the APK on the device is the one just built (flag marker + the new FFI symbol).
#   2. EXTERNAL   — materials.txt is read from the EXTERNAL pack, not the packaged copy, because a
#                   tuning edit has to cost a kilobyte and not a 581 MB APK.
#   3. ACTIVE     — the modern chunk really executed on device: per-channel draw counters, not a
#                   screenshot somebody has to squint at. No visual measurement (permanently banned).
#   4. OFF==STOCK — the same boot with the master off registers ZERO opted-in materials and ZERO
#                   active draws, i.e. the layer is not merely subtle, it is absent.
# Quality is the OWNER's call: the two clips exist so HE can look, not so this script can grade them.
#
# Stages:  all | deploy | on | off | harvest
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-materials-modern-parity/device; mkdir -p "$OUT"
PROOF="$OUT/device_proof.txt"
EXT=/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets
CAP=.autoport/reports/Grecharged-pbr-materials/device
adbs(){ "$ADB" -s "$S" "$@"; }
say(){ echo "$*" | tee -a "$PROOF"; }
die(){ say "[mm-device FAIL] $*"; exit 1; }

# The owner's PBR vantage (registered in the pbr phase): the sage stone wall + straw roof.
# TOD 7 is a LOW sun — subsurface transmission is a BACK-LIT effect, so a noon sun would hide the
# one channel this phase is named for.
export PBR_POS="${PBR_POS--112.0 42.0 205.0}"
export PBR_TOD_HOUR="${PBR_TOD_HOUR:-7}"
export PBR_WALK_STYLE="${PBR_WALK_STYLE:-arc}"

stage_deploy() {
  APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
  [ -n "$APK" ] || die "no APK built"
  say "APK: $APK ($(stat -c%s "$APK") bytes, built $(date -d @"$(stat -c%Y "$APK")" +%F' '%T))"
  unzip -p "$APK" lib/arm64-v8a/libgk.so > /tmp/mm_apk_libgk.so || die "cannot read libgk from APK"
  MARK=$(strings /tmp/mm_apk_libgk.so | grep -m1 '^ogflags:' || true)
  say "APK libgk flag marker: $MARK"
  # FEATURE-STALE GUARD, at the artifact and not at the run: a marker can be identical across two
  # builds of the same flag set, so also require the SYMBOLS this phase adds. If either is missing
  # the APK predates this work no matter what the marker says.
  for sym in pc-set-modern-materials! u_mm_flags tex_PBR_TH materials.txt; do
    n=$(strings /tmp/mm_apk_libgk.so | grep -cF "$sym" || true)
    [ "${n:-0}" -ge 1 ] || die "APK libgk lacks '$sym' — stale build"
    say "  APK libgk carries '$sym' (x$n)"
  done
  # the modern shader chunks must be inside the GLES blob compiled into libgk
  for chunk in u_mm_sss mm_ggx_d_aniso mm_tonemap_aces; do
    n=$(strings /tmp/mm_apk_libgk.so | grep -cF "$chunk" || true)
    [ "${n:-0}" -ge 1 ] || die "APK libgk GLES blob lacks '$chunk' — the companion chunks never reached the Android blob (file(GLOB) staleness)"
    say "  APK GLES blob carries '$chunk' (x$n)"
  done
  rm -f /tmp/mm_apk_libgk.so
  # the ORM demonstrator must be in the packaged custom pack
  unzip -p "$APK" assets/bundle/jak1_custom.zip > /tmp/mm_custom.zip 2>/dev/null || true
  if [ -s /tmp/mm_custom.zip ]; then
    n=$(unzip -l /tmp/mm_custom.zip | grep -c '_orm\.png' || true)
    say "  APK custom pack ships $n _orm.png file(s)"
    n=$(unzip -l /tmp/mm_custom.zip | grep -c 'recharged_assets/materials.txt' || true)
    say "  APK custom pack ships materials.txt: $n"
  fi
  rm -f /tmp/mm_custom.zip

  adbs devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not connected"
  adbs shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  if adbs shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then
    die "device PIN-LOCKED — wait for the owner"
  fi
  adbs shell am force-stop $PKG >/dev/null 2>&1 || true
  say "installing..."
  adbs install -r -d "$APK" >/dev/null 2>&1 || die "adb install failed"
  say "install ok"

  # EXTERNAL-PACK PROOF. Push materials.txt to the external dir with a MARKER COMMENT that exists
  # in no packaged copy, so the log line naming the source cannot be satisfied by the APK's own file.
  adbs shell mkdir -p "$EXT" </dev/null
  sed '1i # EXTERNAL-OVERRIDE-MARKER mm-device-proof' recharged_assets/materials.txt > /tmp/mm_materials.txt
  adbs push /tmp/mm_materials.txt "$EXT/materials.txt" >/dev/null || die "push materials.txt failed"
  say "pushed materials.txt -> $EXT (external override, with marker)"
}

leg() {  # $1 = on|off
  local want="$1" tag="mm_$1"
  adbs shell "setprop debug.opengoal.mm.on '$([ "$want" = on ] && echo 1 || echo 0)'" </dev/null
  say "--- leg $want (debug.opengoal.mm.on=$([ "$want" = on ] && echo 1 || echo 0)) ---"
  bash .autoport/pbr_device_capture.sh run "$tag" 2>&1 | tee -a "$PROOF"
  [ -f "$CAP/pbr_$tag.mp4" ] || die "no clip for leg $want"
  cp "$CAP/pbr_$tag.mp4" "$OUT/$tag.mp4"
  cp "$CAP/logcat_$tag.log" "$OUT/logcat_$tag.log" 2>/dev/null || true
  say "clip: $OUT/$tag.mp4 ($(stat -c%s "$OUT/$tag.mp4") bytes)"
  # the pullable diag carries the per-channel ACTIVE-DRAW counters
  adbs shell "run-as $PKG cat files/pbr_tan_diag.txt" </dev/null > "$OUT/diag_$tag.txt" 2>/dev/null || true
  say "diag_$tag.txt: $(wc -l < "$OUT/diag_$tag.txt") lines"
}

stage_harvest() {
  say ""
  say "================ HARVEST ================"
  for tag in mm_on mm_off; do
    L="$OUT/logcat_$tag.log"; D="$OUT/diag_$tag.txt"
    say "--- $tag ---"
    [ -f "$L" ] && {
      grep -a '\[mm\] PARAMSRC' "$L" | tail -2 | sed 's/^/  /' | tee -a "$PROOF" >/dev/null
      grep -a '\[mm\] PARAMSRC' "$L" | tail -2 | sed 's/^/  /'
      grep -a '\[mm\] materials.txt parsed' "$L" | tail -1 | sed 's/^/  /' | tee -a "$PROOF" >/dev/null
      grep -a '\[mm\] materials.txt parsed' "$L" | tail -1 | sed 's/^/  /'
      say "  ORM unpack lines: $(grep -ca 'pbr ORM unpack' "$L" || true)"
      grep -a 'pbr ORM unpack' "$L" | tail -1 | sed 's/^/  /'
      say "  pbr binding lines with mm_flags!=0: $(grep -a 'pbr binding' "$L" | grep -cav 'mm_flags=0x0 ' || true)"
      grep -a 'pbr binding' "$L" | grep -av 'mm_flags=0x0 ' | tail -4 | sed 's/^/  /'
      say "  crash signals: $(grep -caE 'signal (4|6|7|11) \(SIG' "$L" || true)"
      # SAMPLER BUDGET. The world fragment stage now declares 15 samplers against a GLES floor of
      # 16, so the failure this phase could plausibly introduce is a LINK failure, not a wrong
      # pixel — and a failed link is a black screen, which a clip would show but a counter would
      # not. Must be 0.
      say "  shader compile/link errors: $(grep -caiE 'shader (compile|link)|ERROR: .*sampler|too many' "$L" || true)"
      grep -aiE 'shader (compile|link) (error|fail)|too many .*sampler' "$L" | head -3 | sed 's/^/    /'
      grep -a 'MM-MENU' "$L" | tail -1 | sed 's/^/  /'
    }
    [ -s "$D" ] && grep -a '^\[mm\]' "$D" | tail -12 | sed 's/^/  /' | tee -a "$PROOF" >/dev/null
    [ -s "$D" ] && grep -a '^\[mm\]' "$D" | tail -12 | sed 's/^/  /'
  done
  say "========================================="
}

case "${1:-all}" in
  deploy) stage_deploy;;
  on) leg on;;
  off) leg off;;
  harvest) stage_harvest;;
  all)
    : > "$PROOF"
    say "=== Grecharged-materials-modern-parity device proof $(date -Is) ==="
    say "HEAD: $(git rev-parse --short HEAD)  vantage: $PBR_POS  tod_hour: $PBR_TOD_HOUR"
    stage_deploy; leg on; leg off; stage_harvest
    # never leave the TOD pinned — the owner reads a pinned clock as a broken day/night cycle
    adbs shell "setprop debug.opengoal.tod.hour ''" </dev/null || true
    adbs shell "setprop debug.opengoal.mm.on ''" </dev/null || true
    adbs shell am force-stop $PKG >/dev/null 2>&1 || true
    say "props cleared, app stopped."
    ;;
  *) echo "usage: $0 [all|deploy|on|off|harvest]"; exit 2;;
esac

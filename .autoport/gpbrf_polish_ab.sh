#!/usr/bin/env bash
# gpbrf_polish_ab.sh — PBR RENDERING POLISH round (2026-07-25).
#
# The owner validated the mesh consolidation ("call me impressed, c'est nickel") and recorded THREE
# PBR rendering defects from playtest #16. This harness measures each one on device, as an A/B in a
# SINGLE boot at HIS vantage with the FULL stack on and the TOD frozen at noon, by flipping only the
# one bisect bit that disables the corresponding fix:
#
#   defect 1  displacement in the WRONG DIRECTION on the same texture
#             -> the normal map was decoded in stable_frame(), a WORLD frame that is a function of the
#                surface normal alone, so its U axis rotates with the slope and inverts past 90 deg.
#                FIX: decode in the per-vertex UV frame the map was authored in.
#                A/B bit 32768 = restore the world frame.
#   defect 2  completely FLAT in shadow
#             -> in cast shadow sun_occ = moon_occ = 0 so fdetail collapsed to exactly 1.0 and the
#                only other normal-dependent term (famb_spec) is matte-gated to 0 on rough dielectrics:
#                a shadowed fragment had NO normal dependence at all.
#                FIX: indirect relief = E(Nm)/E(N) on the ambient share.
#                A/B bit 262144 = ambient relief off.
#   defect 3  relief reads FLAT — "un bump map glorifie"
#             -> (a) the height field never occluded a light (no self-shadow anywhere in the shader),
#                (b) the tess-eval displaced the vertices but emitted the UNDISPLACED normal, so real
#                    geometry was shaded as if still flat.
#                A/B bit 524288 = height self-shadow off; displacement 1 vs 2 = (b).
#
# Every adb logcat here is wrapped in `timeout` (supervisor harness rule: an un-timeouted logcat has
# zombied captures repeatedly).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/polish; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
HOUR="${HOUR:-12}"                                   # noon: baked stable AND PBR visible
WARP_POS="${WARP_POS:--112.0 42.0 205.0}"            # owner vantage (his pos_dump: -111.98 41.96 204.99)
CONT="${CONT:-village1-hut}"
# A/B masks — each disables exactly ONE of this round's fixes.
B_WORLDFRAME=32768      # defect 1: normal map back in the world frame
B_AMBOFF=262144         # defect 2: no indirect (ambient) relief
B_MSOFF=524288          # defect 3a: no height-field self-shadow
B_ALLOFF=819200         # 32768|262144|524288 = the pre-polish behaviour
adb(){ "$ADB" -s "$S" "$@"; }
say(){ echo; echo "######## $* ########"; }
die(){ echo "[polish-ab FAIL] $*" >&2; exit 1; }
fg_require(){ local f; f=$(timeout 30 "$ADB" -s "$S" shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
  echo "  focus: $f"; echo "$f" > "$OUT/focus.txt"
  case "$f" in *org.opengoal.gk.jak1*) : ;; *) die "jak1 not foreground: $f";; esac }

shoot(){ # $1 = label, $2 = bisect, $3 = displacement ('' = leave), $4 = pbr.kill, $5 = rt.light
    # A screen that has timed out makes screenrecord emit an empty (~4 KB) mp4 with no frames — that
    # is what killed the regression cells on the first run, after the long second boot.
    timeout 20 "$ADB" -s "$S" shell "svc power stayon usb" >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect $2"
    [ -n "$3" ] && timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement $3"
    timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.kill $4"
    timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.rt.light $5"
    sleep 4
    # The FIRST screenrecord after a fresh boot has twice come back as an empty ~4 KB mp4 (encoder
    # got zero frames). Retry with a longer settle rather than shipping a black frame as evidence.
    local try mp4sz L
    for try in 1 2 3; do
      timeout 20 "$ADB" -s "$S" shell rm -f /sdcard/polish_$1.mp4 >/dev/null 2>&1 || true
      timeout 60 "$ADB" -s "$S" shell screenrecord --time-limit 4 --bit-rate 12000000 /sdcard/polish_$1.mp4 >/dev/null 2>&1 || true
      sleep 1
      timeout 60 "$ADB" -s "$S" pull /sdcard/polish_$1.mp4 "$OUT/$1.mp4" >/dev/null 2>&1 || true
      timeout 20 "$ADB" -s "$S" shell rm -f /sdcard/polish_$1.mp4 >/dev/null 2>&1 || true
      mp4sz=$(stat -c%s "$OUT/$1.mp4" 2>/dev/null || echo 0)
      rm -rf /tmp/polish_fr; mkdir -p /tmp/polish_fr
      [ "$mp4sz" -gt 20000 ] && ffmpeg -y -loglevel error -i "$OUT/$1.mp4" -vf fps=1 /tmp/polish_fr/f_%03d.png
      L=$(ls /tmp/polish_fr/f_*.png 2>/dev/null | tail -1)
      if [ -n "$L" ]; then
        # reject an all-black frame too (mean luma < 2 = the surface was not producing)
        if python3 -c "import sys;from PIL import Image;import numpy as np;sys.exit(0 if np.asarray(Image.open('$L').convert('L'),dtype=float).mean()>2.0 else 1)"; then
          break
        fi
        echo "  ($1: black frame, retry $try)"; L=""
      else
        echo "  ($1: empty capture ${mp4sz}B, retry $try)"
      fi
      timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
      sleep 12
    done
    [ -n "$L" ] || die "no usable frames $1"
    cp "$L" "$OUT/$1.png"; rm -rf /tmp/polish_fr
    echo "  $1 (bisect=$2 disp=${3:-keep} kill=$4 rt=$5) -> $OUT/$1.png"
}

case "${1:?stage (build|boot|matrix|tess|reg|metrics|plate|cleanup|all)}" in

build|all)
  say "0. adb server refresh (a wedged daemon reports a false 'package not installed')"
  "$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
  timeout 60 "$ADB" -s $S wait-for-device || die "device not present"

  say "1. build android libgk (shaders are compiled INTO the .so via shaders_android_blob.h)"
  cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -8
  [ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
  # FRESHNESS: this round's markers must be present in the shipped binary, or the capture is stale.
  for M in pbr_micro_shadow rt_amb_eval world_frame_rot; do
    C=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c -- "$M")
    echo "  marker '$M' = $C"
    [ "$C" -gt 0 ] || die "libgk missing marker '$M' (stale build — the polish is not in the .so)"
  done

  say "2. assemble APK + sha match (a stale gradle cache is a known false-pass)"
  ( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -6 ) || die "gradle assemble failed"
  BSHA=$(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -c1-16)
  ASHA=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -c1-16)
  echo "  libgk sha build=$BSHA apk=$ASHA"; echo "libgk build=$BSHA apk=$ASHA" > "$OUT/sha.txt"
  [ "$BSHA" = "$ASHA" ] || die "APK libgk != build libgk"

  say "3. install + deploy_verify"
  timeout 30 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s "$S" shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
  timeout 30 "$ADB" -s "$S" shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  timeout 30 "$ADB" -s "$S" shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
  timeout 60 "$ADB" -s "$S" shell pm trim-caches 999G 2>/dev/null || true
  timeout 300 "$ADB" -s "$S" install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3 || die "apk install failed"
  bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -4 || die "deploy_verify failed"
  [ "${1:-}" = "all" ] || exit 0
  ;&

boot)
  say "4. seed the FULL PBR STACK in settings.ini (owner: no more blind captures)"
  timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" > /tmp/polish_settings.ini 2>/dev/null || die "cannot read device settings.ini"
  grep -qa 'pbr-materials?' /tmp/polish_settings.ini || die "settings.ini has no pbr-materials? key"
  sed -i \
    -e 's/^pbr-materials? = #[tf]/pbr-materials? = #t/' \
    -e 's/^realtime-lighting? = #[tf]/realtime-lighting? = #t/' \
    -e 's/^recharged-master? = #[tf]/recharged-master? = #t/' \
    -e 's/^pbr-texture-relief = [0-9.]*/pbr-texture-relief = 1.5000/' \
    -e 's/^pbr-isolate = [0-9]*/pbr-isolate = 0/' \
    -e 's/^pbr-displacement = [0-9]*/pbr-displacement = 1/' \
    /tmp/polish_settings.ini
  timeout 30 "$ADB" -s "$S" push /tmp/polish_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || die "settings push failed"
  BACK=$(timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" 2>/dev/null | grep -aoE "^(pbr-materials\? = #[tf]|realtime-lighting\? = #[tf]|pbr-isolate = [0-9]+|pbr-displacement = [0-9]+|pbr-texture-relief = [0-9.]+)" | tr '\n' ' ')
  echo "  seeded: $BACK"; echo "$BACK" > "$OUT/settings_seeded.txt"
  case "$BACK" in *"pbr-materials? = #t"*) : ;; *) die "seed readback: pbr-materials? not #t";; esac
  case "$BACK" in *"realtime-lighting? = #t"*) : ;; *) die "seed readback: realtime-lighting? not #t";; esac
  case "$BACK" in *"pbr-isolate = 0"*) : ;; *) die "seed readback: pbr-isolate not 0 (normal map would be bisected OFF)";; esac

  say "5. boot to the owner vantage ($WARP_POS), TOD frozen at $HOUR"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  pkill -f "$ADB -s $S logcat" 2>/dev/null || true; sleep 1
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG rm -f files/pbr_tan_diag.txt" >/dev/null 2>&1 || true
  timeout 30 "$ADB" -s "$S" logcat -c >/dev/null 2>&1 || true
  for P in "debug.opengoal.cpad_inject neutral" "debug.opengoal.renderscale.native 1" \
           "debug.opengoal.pbr.kill 0" "debug.opengoal.pbr.bisect 0" "debug.opengoal.mesh.weld 1" \
           "debug.opengoal.rt.light 1"; do timeout 20 "$ADB" -s "$S" shell "setprop $P"; done
  for P in "debug.opengoal.pbr.relief" "debug.opengoal.pbr.debug" "debug.opengoal.pbr.nstrength" \
           "debug.opengoal.tod.fast"; do timeout 20 "$ADB" -s "$S" shell "setprop $P ''"; done
  timeout 20 "$ADB" -s "$S" shell setprop debug.opengoal.level.warp "$CONT"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp.pos '$WARP_POS'"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.tod.hour '$HOUR'"
  LOG="$OUT/boot-logcat.log"; : > "$LOG"
  ( timeout 400 "$ADB" -s "$S" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|pbr binding|pbr normal DC|custom pbr|Fatal signal|GK-DIAG sig=|shader.*[Ee]rror|link.*[Ff]ail|pbr-tess|tangent' >> "$LOG" ) 2>/dev/null &
  timeout 60 "$ADB" -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 320 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$LOG" && die "crash during boot"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$LOG" || die "no LEVEL-WARP-SPAWN in 320s"
  echo "  spawned at vantage; settling 90s (camera must CONVERGE: at 25s the follow-cam was still moving and dominated every A/B delta)"; sleep 90
  fg_require
  say "5b. tessellation capability on THIS device (the A/B for defect 3b needs it)"
  grep -a 'pbr-tess' "$LOG" | tail -5 | tee "$OUT/tess_capability.txt"
  [ -s "$OUT/tess_capability.txt" ] || echo "  (no [pbr-tess] line yet)"
  [ "${1:-}" = "all" ] || exit 0
  ;&

matrix|all)
  say "6. LIVE A/B matrix — one bit per defect, same boot, same vantage, same TOD"
  #      label            bisect          disp  kill rt
  shoot  base             0               1     0    1   # all three polish fixes ON (the shipped default)
  shoot  d1_worldframe    $B_WORLDFRAME   1     0    1   # defect 1 A/B: old world normal-map frame
  shoot  d2_amboff        $B_AMBOFF       1     0    1   # defect 2 A/B: no indirect relief
  shoot  d3_msoff         $B_MSOFF        1     0    1   # defect 3a A/B: no height self-shadow
  shoot  prepolish        $B_ALLOFF       1     0    1   # all three OFF = the build the owner rejected
  shoot  base2            0               1     0    1   # DRIFT FLOOR: identical to base, captured last
  fg_require
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.displacement 1"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.kill 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.rt.light 1"
  say "6b. pull the on-device diag (the Honor obscures logcat, so this is the file channel)"
  timeout 30 "$ADB" -s "$S" shell "run-as $PKG cat files/pbr_tan_diag.txt" 2>/dev/null > "$OUT/pbr_tan_diag.txt" || true
  grep -aE 'world_frame_|tan_frame_pairs=|mesh_weld_enabled=|normal_smoothed_coincident' "$OUT/pbr_tan_diag.txt" 2>/dev/null | head -12 || echo "  (diag missing)"
  [ "${1:-}" = "all" ] || exit 0
  ;&

tess|all)
  # DEFECT 3b needs REAL tessellation, and the tess PROGRAM is selected from the SETTING, not the
  # prop: TFragment.cpp:609 gates on Gfx::g_global_settings.recharged_pbr_displacement == 2. Driving
  # only debug.opengoal.pbr.displacement would set the shader uniform to 2 (which makes the fragment
  # stage skip its POM) while still drawing through the NON-tess program — a cell with no
  # displacement at all. So this stage seeds the setting and takes its own boot. Inside that boot the
  # A/B is bisect bit 1048576, which makes the tess-eval emit the UNDISPLACED normal = exactly the
  # pre-polish behaviour, with the same displaced vertices.
  say "6c. SECOND boot with pbr-displacement = 2 (REAL tessellation) — defect 3b A/B"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  # pbr_killswitch() caches its prop at FIRST USE (background_common.cpp:509), i.e. during the boot
  # below — so it must be cleared BEFORE am start, not in shoot(). A stale 1 here would silently
  # boot with the whole PBR material path disabled and the cells would compare nothing.
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.kill 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  sed -i -e 's/^pbr-displacement = [0-9]*/pbr-displacement = 2/' /tmp/polish_settings.ini
  timeout 30 "$ADB" -s "$S" push /tmp/polish_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || die "settings push failed"
  timeout 30 "$ADB" -s "$S" shell "cat $SETTINGS_DEV" 2>/dev/null | grep -aoE '^pbr-displacement = [0-9]+' | tee "$OUT/tess_setting.txt"
  grep -q 'pbr-displacement = 2' "$OUT/tess_setting.txt" || die "displacement setting did not take"
  TLOG="$OUT/tess-boot-logcat.log"; : > "$TLOG"
  ( timeout 400 "$ADB" -s "$S" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|Fatal signal|GK-DIAG sig=|pbr-tess' >> "$TLOG" ) 2>/dev/null &
  timeout 60 "$ADB" -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 320 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$TLOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$TLOG" && die "crash during tessellation boot"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$TLOG" || die "no LEVEL-WARP-SPAWN in 320s (tess boot)"
  sleep 90
  fg_require
  grep -a 'pbr-tess' "$TLOG" | tail -4 | tee -a "$OUT/tess_capability.txt"
  shoot  d3_tess          0               2     0    1   # tessellation + height-derived normal (fixed)
  shoot  d3_tess_flatn    1048576         2     0    1   # tessellation + UNDISPLACED normal (pre-polish)
  shoot  d3_tess2         0               2     0    1   # DRIFT FLOOR for the tessellation pair
  [ "${1:-}" = "all" ] || exit 0
  ;&

reg|all)
  sed -i -e 's/^pbr-displacement = [0-9]*/pbr-displacement = 1/' /tmp/polish_settings.ini
  timeout 30 "$ADB" -s "$S" push /tmp/polish_settings.ini "$SETTINGS_DEV" >/dev/null 2>&1 || true
  # The two REGRESSION cells need pbr-materials OFF, and pbr_killswitch() is cached at first use
  # (background_common.cpp:509 `static int cached`) — so it cannot be flipped live like the bisect
  # word. They get their own boot with the prop already set. rt.light IS read per frame, so both
  # cells come out of this one boot.
  say "6c. SECOND boot with the PBR material path killed — the two regression cells"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.kill 1"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.rt.light 1"
  RLOG="$OUT/reg-boot-logcat.log"; : > "$RLOG"
  ( timeout 400 "$ADB" -s "$S" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|Fatal signal|GK-DIAG sig=' >> "$RLOG" ) 2>/dev/null &
  timeout 60 "$ADB" -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 320 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$RLOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$RLOG" && die "crash during regression boot"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$RLOG" || die "no LEVEL-WARP-SPAWN in 320s (regression boot)"
  sleep 90
  fg_require
  shoot  reg_rt_only      0               1     1    1   # rt ON + pbr OFF  = the accepted directional-ambient look
  shoot  reg_stock        0               1     1    0   # rt OFF + pbr OFF = stock
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.kill 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.rt.light 1"
  [ "${1:-}" = "all" ] || exit 0
  ;&

plate)
  # PLATE-REGRESSION GUARD. The previous round's owner-visible win was that relief no longer creates
  # hard brightness PLATES. Defect 1's fix moves the normal map back into the per-chunk UV frame, so
  # the plate metric has to be re-earned, not assumed: {UV frame, world frame} x {relief 0, relief
  # 2.5}, same boot, same vantage, scored by the SAME script and the SAME criterion the owner's
  # acceptance used (low-frequency |dL|/L must stay near the noise floor, high-frequency detail must
  # rise). Named legacy_*/fixed_* so gpbrf_plate_metrics.py reads them unchanged.
  POUT="$OUT/plate"; mkdir -p "$POUT"
  say "8. plate-regression guard: does the UV frame bring the hard brightness plates back?"
  timeout 30 "$ADB" -s "$S" shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.kill 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.rt.light 1"
  PLOG="$OUT/plate-boot-logcat.log"; : > "$PLOG"
  ( timeout 400 "$ADB" -s "$S" logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|Fatal signal|GK-DIAG sig=' >> "$PLOG" ) 2>/dev/null &
  timeout 60 "$ADB" -s "$S" shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 320 ]; do
    grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$PLOG" && break
    grep -aqE 'Fatal signal|GK-DIAG sig=' "$PLOG" && die "crash during plate boot"
    sleep 5
  done
  grep -aq "LEVEL-WARP-SPAWN name=$CONT" "$PLOG" || die "no LEVEL-WARP-SPAWN in 320s (plate boot)"
  sleep 90
  fg_require
  pshoot(){ # $1 label, $2 bisect, $3 relief
    timeout 20 "$ADB" -s "$S" shell "svc power stayon usb" >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect $2"
    timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.relief $3"
    sleep 4
    timeout 20 "$ADB" -s "$S" shell rm -f /sdcard/pl_$1.mp4 >/dev/null 2>&1 || true
    timeout 60 "$ADB" -s "$S" shell screenrecord --time-limit 4 --bit-rate 12000000 /sdcard/pl_$1.mp4 >/dev/null 2>&1 || die "screenrecord $1"
    sleep 1
    timeout 60 "$ADB" -s "$S" pull /sdcard/pl_$1.mp4 "$POUT/$1.mp4" >/dev/null 2>&1 || die "pull $1"
    timeout 20 "$ADB" -s "$S" shell rm -f /sdcard/pl_$1.mp4 >/dev/null 2>&1 || true
    rm -rf /tmp/pl_fr; mkdir -p /tmp/pl_fr
    ffmpeg -y -loglevel error -i "$POUT/$1.mp4" -vf fps=1 /tmp/pl_fr/f_%03d.png
    L=$(ls /tmp/pl_fr/f_*.png 2>/dev/null | tail -1); [ -n "$L" ] || die "no frames $1"
    cp "$L" "$POUT/$1.png"; rm -rf /tmp/pl_fr
    echo "  $1 (bisect=$2 relief=$3)"
  }
  pshoot fixed_r0   0     0
  pshoot fixed_r25  0     2.5
  pshoot legacy_r0  32768 0
  pshoot legacy_r25 32768 2.5
  fg_require
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.relief ''"
  echo "  (legacy_* = normal map in the WORLD frame, fixed_* = in the authored UV frame)"
  python3 .autoport/gpbrf_plate_metrics.py "$POUT" | tee "$POUT/plate_matrix.txt"
  ;;

metrics|all)
  say "7. METRICS — one number per defect, measured, not asserted"
  python3 .autoport/gpbrf_polish_metrics.py "$OUT" | tee "$OUT/polish_matrix.txt"
  ;;

cleanup)
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.bisect 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.relief ''"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.pbr.kill 0"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.rt.light 1"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp '\"\"'"
  timeout 20 "$ADB" -s "$S" shell "setprop debug.opengoal.level.warp.pos '\"\"'"
  echo "[polish-ab] cleaned"
  ;;
*) die "unknown stage ${1:-}";;
esac

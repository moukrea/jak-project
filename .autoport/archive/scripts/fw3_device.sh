#!/usr/bin/env bash
# Grecharged-foliage-wind3 — JAMBE APPAREIL (Redmi eae4df44).
# DIRECTIVES vd9e8b66782
#
# TROIS COURSES, MEME APK, MEME PACK — c'est l'ablation sur le meme binaire que les directives
# exigent, et c'est la seule facon d'avoir un avant/apres qui ne compare pas deux builds :
#   1. D1-ABLATION : option Recharged ETEINTE, `debug.opengoal.wind.native_rate=0`
#                    -> la brise native telle que l'owner l'a vue.
#   2. D1-CORRIGE  : option ETEINTE, `native_rate=1` (le defaut)
#                    -> la brise native a la cadence de ND.
#   3. D2+D3       : option ALLUMEE, defauts compiles
#                    -> couverture + amplitude.
#
# Ce que chaque course doit publier, et qui porte le verdict :
#   [foliage-wind] shear-audit ... fps= rate_ticks= raw_rms= satfrac= stock_rms= dstock_rms=
#   [foliage-wind] TIE census / TIE sway-cover  (couverture, D2)
#   [foliage-wind] NATIVE RATE actif ...        (cablage de D1)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-foliage-wind3/device; mkdir -p "$OUT"
BEACH_POS="-123.3 2.3 -54.6"
VILL_POS="-156.0 34.0 188.0"
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

set_toggle(){ # $1 = t|f
  $ADB shell cat "$PCS" > /tmp/fw3d_pcs.ini 2>/dev/null || true
  grep -q 'recharged-foliage-wind?' /tmp/fw3d_pcs.ini || { echo "FATAL: pas de cle de toggle"; exit 1; }
  sed -i "s/^recharged-foliage-wind? = #[tf]/recharged-foliage-wind? = #$1/" /tmp/fw3d_pcs.ini
  $ADB push /tmp/fw3d_pcs.ini "$PCS" >/dev/null 2>&1
  echo "  toggle: $($ADB shell cat "$PCS" | grep -E 'recharged-(foliage-wind|master)\?' | tr -d '\r' | paste -sd' ')"
}

leg(){ # $1=tag  $2=toggle(t|f)  $3=native_rate(0|1)  $4=continue  $5=pos
  local TAG="$1" TOG="$2" NAT="$3" CONT="$4" POS="$5"
  local LOG="$OUT/$TAG.log"
  echo "######## $TAG : toggle=$TOG native_rate=$NAT lieu=$CONT ########"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  set_toggle "$TOG"
  $ADB shell "setprop debug.opengoal.wind.native_rate $NAT" >/dev/null 2>&1
  # les boutons d'amplitude reviennent aux DEFAUTS COMPILES : une propriete oubliee laisserait la
  # brise a moitie allumee et la course ne mesurerait pas ce qui est livre.
  for k in tie_mult tie_amp frond shrub_amp tie_sway; do $ADB shell "setprop debug.opengoal.foliage.$k ''" >/dev/null 2>&1; done
  local ok=0
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/fw3d_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/fw3d_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    local t0=$(date +%s)
    while [ $(( $(date +%s)-t0 )) -lt 200 ]; do
      grep -qa "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && break
  done
  [ "$ok" = 1 ] || { echo "[fw3 FAIL] $TAG boot"; return 1; }
  # sejour : une fenetre d'audit = 300 images de vent ; a ~15 img/s c'est 20 s. On en veut >= 2.
  $ADB shell "setprop debug.opengoal.cpad_inject 'ly=0'" >/dev/null 2>&1; sleep 4
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  for i in 1 2 3 4 5 6 7 8 9; do
    sleep 10
    local n=$(grep -ac 'shear-audit' "$LOG" 2>/dev/null || echo 0)
    echo "  +$((i*10))s  fenetres=$n  $(focus)"
    [ "${n:-0}" -ge 3 ] && break
  done
  echo "  --- recolte $TAG ---"
  grep -ao "shear-audit.*" "$LOG" | sed 's/.*lev=/lev=/' | cut -c1-260
  grep -ao "TIE census.*\|TIE sway-cover.*\|NATIVE RATE actif.*\|TIE static sway ACTIVE.*\|TIE breeze ACTIVE.*" "$LOG" | cut -c1-260
  echo "  crashlines=$(grep -acE 'signal (4|6|11) \(SIG|Fatal signal' "$LOG")"
  $ADB shell am force-stop $PKG >/dev/null 2>&1
  kill "$(cat /tmp/fw3d_lc.pid 2>/dev/null)" 2>/dev/null || true
}

leg d1-ablation f 0 beach-start   "$BEACH_POS"
leg d1-corrige  f 1 beach-start   "$BEACH_POS"
leg d2d3-on     t 1 village1-hut  "$VILL_POS"

# ne laisser AUCUNE propriete injectee derriere : une `cpad_inject` oubliee tient un bouton
# enfonce pour la course suivante, et un `native_rate` oublie desarme le correctif pour l'owner.
$ADB shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.wind.native_rate ''" >/dev/null 2>&1
echo "fini — $OUT"

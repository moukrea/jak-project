#!/usr/bin/env bash
# ghdmodels2_run.sh — Grecharged-hd-models2 round-2 device evidence driver.
# Uses the function library in ghdmodels2_capture.sh. For each of {samos, keira}
# vantage x {off, on}: flip the persisted ENHANCED MODELS toggle in the EXTERNAL
# pc-settings (the menu item's storage), kill+relaunch (models load on reload),
# warp to the vantage, screenrecord, and harvest the objective loaded-model
# discriminators (HD-MODELS fr3-select / merc-load tris / merc-tex) from the
# SAME run's logcat. Jak+Daxter are in frame at both vantages (player character).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
source .autoport/ghdmodels2_capture.sh

# replace-or-insert (attempt-2 lesson: sed on an absent key silently no-ops)
set_models(){ # $1 = t|f
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  if $ADB shell grep -q "^recharged-enhanced-models? = " $EXT 2>/dev/null; then
    $ADB shell "sed -i 's/^recharged-enhanced-models? = #[tf]/recharged-enhanced-models? = #$1/' $EXT" >/dev/null 2>&1
  else
    $ADB shell "sed -i 's/^\[settings\]/[settings]\nrecharged-enhanced-models? = #$1/' $EXT" >/dev/null 2>&1
  fi
  local now; now=$($ADB shell grep -E 'recharged-enhanced-models\?' $EXT 2>/dev/null | tr -d '\r')
  echo "  models set #$1: ext=$now"
  case "$now" in *"#$1"*) ;; *) echo "  TOGGLE SET FAILED"; exit 9;; esac
}

harvest(){ local LOG="$1" TAG="$2"
  echo "  --- discriminators $TAG ---"
  grep -a "HD-MODELS fr3-select" "$LOG" | sed 's/^.*HD-MODELS/  HD-MODELS/' | sort -u
  grep -aE "HD-MODELS merc-load .*model=(eichar|sidekick|sage|assistant)-lod0" "$LOG" | sed 's/^.*HD-MODELS/  HD-MODELS/' | sort -u
  grep -aE "HD-MODELS merc-tex" "$LOG" | sed 's/^.*HD-MODELS/  HD-MODELS/' | sort -u
  grep -a "HD-MODELS toggle push" "$LOG" | sed 's/^.*HD-MODELS/  HD-MODELS/' | sort -u
  echo "  focus: $(focus)"
}

run_one(){ # $1 char-tag $2 t|f $3 pos $4 aim-fn
  local TAG="$1-$([ "$2" = t ] && echo on || echo off)"
  say "RUN $TAG"
  set_models "$2"
  local LOG="$OUT/${TAG}_boot.log"
  boot_warp village1-hut "$3" "$LOG" || { echo "  $TAG BOOT FAILED"; return 1; }
  rec "$TAG" 16 "$4"
  harvest "$LOG" "$TAG"
  kill "$(cat /tmp/hd_lc.pid 2>/dev/null)" 2>/dev/null || true
}

run_one samos f "-132.7 48 216.5" aim_sage
run_one samos t "-132.7 48 216.5" aim_sage
run_one keira f "-134.5 36 205.5" aim_hold
run_one keira t "-134.5 36 205.5" aim_hold
$ADB shell am force-stop $PKG >/dev/null 2>&1
echo "== DEVICE RUNS DONE =="

#!/usr/bin/env bash
# gpbrf11_menu_proof.sh — REOPEN#11 DECISIVE device proof of the PBR ISOLATE carousel:
#   (A) the 4 options render as REAL LABELS (no "Unknown ID 5924-5927") — screenshots,
#   (B) flipping the carousel ACTUALLY APPLIES: each confirm writes settings.ini pbr-isolate
#       AND pc_set_pbr_isolate writes the resolved u_pbr_bisect MASK to files/pbr_tan_diag.txt.
# Nav path mirrors the proven gpbrf2 relief-fix path: 17x down = SPECULAR INTENSITY (row 19),
# +3 down = PBR ISOLATE (row 22, just before Back). Carousell edit = X (enter), RIGHT (advance),
# X (confirm) — same machinery as Displacement. All flips happen WHILE SITTING IN THE MENU (no
# level load => TFrag3Data does not clobber the diag).
set -uo pipefail
cd /home/emeric/code/jak-project
ADB=~/Android/platform-tools/adb; SER=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device/menu-proof11
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
mkdir -p "$OUT"
adb(){ "$ADB" -s "$SER" "$@"; }
say(){ echo "$*" | tee -a "$OUT/proof-log.txt"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.8; inject ""; sleep "${2:-2.0}"; }
fg_ok(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; }
iso_disk(){ adb shell cat "$PCS" 2>/dev/null | tr -d '\r' | grep -aE '^pbr-isolate = ' | tr '\n' ' '; echo; }
diag(){ adb shell "run-as $PKG cat files/pbr_tan_diag.txt" 2>/dev/null | tr -d '\r'; }

: > "$OUT/proof-log.txt"
say "== REOPEN#11 PBR ISOLATE menu proof =="
adb shell am force-stop $PKG; sleep 2
say "settings.ini pbr-isolate BEFORE: '$(iso_disk)'  (empty = never committed = default 0 BOTH)"
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
sleep 80
held=0; for i in $(seq 1 40); do
  if fg_ok; then held=$((held+1)); [ $held -ge 4 ] && break; else held=0; adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1; sleep 8; fi
  sleep 6
done
say "  fg held=$held"

say "-- enter Recharged Settings (proven gpbrf2 path) --"
tapb "start" 3.0; tapb "down"; tapb "down"; tapb "x" 3.0; tapb "down"; tapb "x" 3.0
for i in $(seq 1 8); do tapb "down" 1.6; done
tapb "x" 2.5
for i in $(seq 1 17); do tapb "down" 1.6; done      # SPECULAR INTENSITY (row 19)
shot "01-specular-intensity-row"
for i in $(seq 1 3); do tapb "down" 1.6; done        # +3 -> PBR ISOLATE (row 22)
shot "02-pbr-isolate-row-BOTH"
say "PBR ISOLATE row reached (screenshot 02). settings.ini='$(iso_disk)'"
say "diag @BOTH:"; diag | tee -a "$OUT/proof-log.txt" >/dev/null; diag | sed 's/^/    /'

flip(){ # $1 = expected label, $2 = expected mask, $3 = shot tag
  tapb "x" 1.5; tapb "right" 1.5; tapb "x" 2.2   # enter edit, advance one, confirm
  sleep 1.5
  shot "$3"
  local D; D=$(iso_disk); local G; G=$(diag)
  say "-- after flip -> expect $1 (mask $2):  settings.ini='$D'"
  echo "$G" | sed 's/^/    diag: /' | tee -a "$OUT/proof-log.txt" >/dev/null
  say "    diag mask line: $(echo "$G" | grep -aiE 'active:|mask=' | head -1)"
}

flip "NORMAL-MAP ONLY" 128 "03-flip-normalmap-only"
flip "PARALLAX ONLY"   64 "04-flip-parallax-only"
flip "NEITHER"        192 "05-flip-neither"
# one more wraps back to BOTH (4-option carousel)
flip "BOTH"             0 "06-flip-back-to-both"

say "== final settings.ini pbr-isolate: '$(iso_disk)' =="
say "== final diag =="; diag | sed 's/^/    /' | tee -a "$OUT/proof-log.txt" >/dev/null
adb shell am force-stop $PKG; sleep 1
say "[gpbrf11-menu-proof] DONE — screenshots + settings.ini + diag in $OUT"

#!/usr/bin/env bash
# Ghd-skin-origin-stretch CYCLE 6 — UNE JAMBE SUR L'APPAREIL (Redmi eae4df44), MODELES HD INSTALLES,
# QUI COMPTE L'ETIREMENT LUI-MEME ET ENCHAINE LES MOUVEMENTS BRUSQUES.
#
# Porte refondue (superviseur 2026-09-02 18:25) : « compter L'ETIREMENT LUI-MEME (longueur d'os /
# repos) par image et par os, pas les NaN ». Owner 18:35 : « ça arrive en bougeant beaucoup,
# courant, faisant des demis tours, des sauts, des coups de poing » — la course doit ENCHAINER ces
# entrees et publier le COMPTE de chaque action (>= 200 sauts, demi-tours, coups), compte par le
# CODE (entrees d'etat du joueur : HDMOVES), pas par ce script.
#
# DEUX INSTRUMENTS, MEME BINAIRE :
#   - squelette GOAL : HDLEN/HDLEN2 (battement), HDLENG..4 (evenements attribues : chemin d'ecriture,
#     fraicheur de l'os pilote, melange d'animations, etat du joueur) ;
#   - consommation GPU : HDSKINLEN (battement), HDLENEV (evenements : torn/same/nan/null/rep).
# CONTROLE POSITIF, MEME APK : `debug.opengoal.hd.stretch_inject=1` deplace un os HD de 3 m toutes
# les 300 images (HDINJECT) — les deux instruments doivent le compter, sinon leur zero est vide.
#
# usage : ghso6_device_leg.sh <inject 0|1> <tag> [duree_par_scene_s]
#         SCENES="nom:duree:mode ..." (mode : brusque | zoomer | idle) surcharge la liste.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
[ -x "$ADB" ] || ADB=$(command -v adb)
SER=eae4df44
PKG=org.opengoal.gk.jak1
INJ="${1:-0}"; TAG="${2:-dev6-inj$INJ}"; DP="${3:-240}"; SCLARM="${SCLARM:-1}"   # garde d'echelle du mode 1 (0 = bras de controle)
OUT=.autoport/reports/Ghd-skin-origin-stretch/device; mkdir -p "$OUT"
SUM="$OUT/$TAG-resume.txt"
a(){ "$ADB" -s "$SER" "$@"; }
exec > >(tee "$SUM") 2>&1

# Le verrou de livraison : on REMPLACE celui du manager (prefixe ghso, meme campagne) et on le
# REPOSE en sortant, pour que l'auto-constructeur ne batisse jamais l'arbre a moitie edite.
LOCK=.autoport/.deploy-in-progress
PREV_LOCK=""
if [ -f "$LOCK" ]; then
  P=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null && ! grep -q '^ghso' "$LOCK"; then
    echo "FAIL: verrou tenu par pid=$P (pas le notre)"; exit 2
  fi
  PREV_LOCK=$(cat "$LOCK")
fi
printf 'ghso6_device pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"

LCPID=""
cleanup(){
  a shell "setprop debug.opengoal.level.warp ''"        >/dev/null 2>&1
  a shell "setprop debug.opengoal.cpad_inject ''"       >/dev/null 2>&1
  a shell "setprop debug.opengoal.hd.stretch_inject ''" >/dev/null 2>&1
  a shell "setprop debug.opengoal.hd.scale_arm ''"      >/dev/null 2>&1
  [ -n "${LCPID:-}" ] && { kill "$LCPID" 2>/dev/null; sleep 1; kill -9 "$LCPID" 2>/dev/null; }
  a shell am force-stop $PKG >/dev/null 2>&1
  if [ -n "$PREV_LOCK" ]; then printf '%s\n' "$PREV_LOCK" > "$LOCK"; else rm -f "$LOCK"; fi
  return 0
}
trap cleanup EXIT

a devices | grep -qE "^${SER}[[:space:]]+device$" || { echo "FAIL: $SER absent"; exit 1; }
echo "===== appareil $SER — bras stretch_inject=$INJ — $(date -Is) ====="
echo "-- fraicheur de l'installation"
a shell dumpsys package $PKG 2>/dev/null | grep -E "lastUpdateTime|versionName" | head -2 | tr -d '\r'
echo "   pack cgo telephone : $(a exec-out run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')"
echo "   pack cgo arbre     : $(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)"
PATHAPK=$(a shell pm path $PKG 2>/dev/null | tr -d '\r' | sed -n 's/^package://p' | head -1)
if [ -n "$PATHAPK" ]; then
  SCR=/home/emeric/.autoport-scratch; mkdir -p "$SCR"
  a pull "$PATHAPK" "$SCR/ghso6-installed.apk" >/dev/null 2>&1 && \
    echo "   marqueur HDLENEV dans libgk.so INSTALLE : $(unzip -p "$SCR/ghso6-installed.apk" 'lib/arm64-v8a/libgk.so' 2>/dev/null | grep -ac HDLENEV || true)   md5 = $(unzip -p "$SCR/ghso6-installed.apk" 'lib/arm64-v8a/libgk.so' 2>/dev/null | md5sum | cut -c1-12) (arbre build-android : $(md5sum build-android/lib/arm64-v8a/libgk.so | cut -c1-12))"
fi
echo "   marqueur HDLENG dans les CGO du telephone : $(a exec-out run-as $PKG sh -c 'cat files/*/GAME.CGO files/*/*/GAME.CGO 2>/dev/null' 2>/dev/null | grep -ac HDLENG || true)"

SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
a shell cat "$SET" > /tmp/ghso6_settings.ini 2>/dev/null
cp -f /tmp/ghso6_settings.ini "$OUT/.settings.pre-$TAG.ini" 2>/dev/null || true
python3 - /tmp/ghso6_settings.ini <<'PY' || { echo "FAIL: cle absente des reglages de l'appareil"; exit 1; }
import sys
p=sys.argv[1]; lines=open(p).read().split('\n')
want={"recharged-enhanced-models?":"#t","hd-look-jak":"1","hd-look-daxter":"1","hd-look-keira":"1","hd-look-samos":"1"}
seen=set()
for i,l in enumerate(lines):
    for k,v in want.items():
        if l.startswith(k+" = "):
            lines[i]=f"{k} = {v}"; seen.add(k)
missing=set(want)-seen
if missing:
    print("cles absentes :",sorted(missing)); sys.exit(1)
open(p,'w').write('\n'.join(lines))
PY
a push /tmp/ghso6_settings.ini "$SET" >/dev/null 2>&1
echo "-- reglages poses : modeles HD #t, looks HD = 1"

# LA SEQUENCE « BRUSQUE » : etat de pad TENU (relu toutes les 25 ms par android_input_audio.cpp),
# un front de bouton = un jeton absent puis present. Cycle de 5 s : course avant 0,9 s, saut,
# atterrissage + spin, coup de poing, demi-tour (stick inverse a pleine vitesse, target-walk),
# saut, coup de poing, demi-tour. Le demi-tour exige ~0,6 s de course pleine au sol AVANT
# l'inversion et aucun saut concomitant (logic-target.gc:298-331) : d'ou les paliers.
# Mesure dev6-inj1 (premiere version, paliers de 0,25-0,35 s) : `coups=0 demi_tours=1` — CARRE
# tombait encore en l'air (plongeon, pas un coup de poing) et l'inversion du stick arrivait sans
# 0,6 s de course pleine au sol. Paliers allonges : course 1,5 s avant chaque inversion, 0,9 s
# d'atterrissage avant le coup.
BRUSQUE=(
  "ly=0:1.5" "ly=0 x:0.25" "ly=0:0.9" "ly=0 square:0.25" "ly=0:0.4"
  "ly=255:1.5" "ly=255 x:0.25" "ly=255:0.9" "ly=255 circle:0.25" "ly=255:0.4"
)

run_scene(){
  local scene="$1" dur="$2" mode="$3"
  local LOG="$OUT/$TAG-$scene-$mode-logcat.txt"
  a shell am force-stop $PKG >/dev/null 2>&1
  a shell "setprop debug.opengoal.level.warp '$scene'" >/dev/null 2>&1
  a shell "setprop debug.opengoal.hd.stretch_inject '$INJ'" >/dev/null 2>&1
  a shell "setprop debug.opengoal.hd.scale_arm '$SCLARM'" >/dev/null 2>&1
  a shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1
  a logcat -c >/dev/null 2>&1
  a logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' > "$LOG" 2>/dev/null &
  LCPID=$!
  a shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  local W=0
  for i in $(seq 1 240); do
    grep -aq "LEVEL-WARP.*start .play" "$LOG" && { W=1; break; }
    sleep 1
  done
  echo "== scene $scene ($mode) : warp=$W, fenetre ${dur}s, inject=$(grep -a 'HDSTRETCHINJECT' "$LOG" | tail -1 | sed 's/^.*HDSTRETCHINJECT/HDSTRETCHINJECT/' | tr -d '\r'), $(grep -a 'HDSCALEARM' "$LOG" | tail -1 | sed 's/^.*HDSCALEARM/HDSCALEARM/' | tr -d '\r')"
  sleep 12
  local T0=$(date +%s) k=0 n=${#BRUSQUE[@]}
  while [ $(( $(date +%s) - T0 )) -lt "$dur" ]; do
    if [ "$mode" = idle ]; then
      sleep 5
    elif [ "$mode" = zoomer ]; then
      case $((k % 4)) in
        0) a shell "setprop debug.opengoal.cpad_inject 'x ly=0'" ;;
        1) a shell "setprop debug.opengoal.cpad_inject 'x ly=0 lx=30'" ;;
        2) a shell "setprop debug.opengoal.cpad_inject 'x ly=0'" ;;
        3) a shell "setprop debug.opengoal.cpad_inject 'x ly=0 lx=225'" ;;
      esac >/dev/null 2>&1
      sleep 3
    else
      local step="${BRUSQUE[$((k % n))]}"
      a shell "setprop debug.opengoal.cpad_inject '${step%%:*}'" >/dev/null 2>&1
      sleep "${step##*:}"
    fi
    k=$((k + 1))
  done
  a shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1
  local T1=$(date +%s)
  sleep 3
  kill "$LCPID" 2>/dev/null; sleep 1; LCPID=""
  a shell am force-stop $PKG >/dev/null 2>&1
  echo "   lignes capturees : $(grep -ac . "$LOG" || true)   injections pad : $(grep -ac 'F1D-INJECT applied' "$LOG" || true)   fenetre_pad=$((T1 - T0))s"
  echo "   etats joueur : $(grep -a 'JAK-HD-TGT\] st=' "$LOG" | sed 's/^.*st=//' | tr -d '\r' | sort | uniq -c | sort -rn | head -8 | awk '{printf "%s(%s) ", $2, $1}')"
  for m in HDMOVES HDLEN HDLEN2 HDLEN3 HDLEN4 HDSKINLEN HDSKIN; do
    echo "   $m (dernier) : $(grep -a "$m " "$LOG" | tail -1 | sed "s/^.*$m /$m /" | tr -d '\r')"
  done
  echo "   HDLENG : $(grep -ac 'HDLENG ' "$LOG" || true) evenement(s) squelette   HDLENEV : $(grep -ac 'HDLENEV ' "$LOG" || true) HDCMDEV : $(grep -ac 'HDCMDEV ' "$LOG" || true) evenement(s) GPU   HDINJECT : $(grep -ac 'HDINJECT ' "$LOG" || true)   HDLENRIG : $(grep -ac 'HDLENRIG ' "$LOG" || true)"
  grep -a 'HDLENEV ' "$LOG" | sed 's/^.*HDLENEV/HDLENEV/' | tr -d '\r' | head -6
  grep -aE 'HDSKINLEN |HDLENEV |HDLENRIG |HDSKIN |HDSKINEV |HDSKINMODEL |HDHB[0-9]? |HDLEN[234]? |HDLENG[0-9]? |HDSCLEP2? |HDCMDEV |HDMOVES |HDINJECT |HDSTRETCHINJECT|HDSCALEARM|HDNANSRC|HDFINITEARM|LEVEL-WARP|JAK-HD-TGT|F1D-INJECT applied|HDRESET|FATAL|signal [0-9]+' "$LOG" \
    | sed -E 's/^([0-9-]+ [0-9:.]+) +[0-9]+ +[0-9]+ [A-Z] [A-Za-z_-]+: /\1 /' | tr -d '\r' > "$OUT/$TAG-$scene-$mode-marqueurs.txt"
  echo "HDWALL scene=$scene-$mode secondes=$((T1 - T0)) inject=$INJ sclarm=$SCLARM" >> "$OUT/$TAG-$scene-$mode-marqueurs.txt"
}

if [ -n "${SCENES:-}" ]; then
  for sc in $SCENES; do IFS=: read -r nm du mo <<< "$sc"; run_scene "$nm" "$du" "$mo"; done
else
  # les trois niveaux que l'owner nomme (3601 m a 5540 m de l'origine), plus un quatrieme pour
  # que la fenetre depasse 10 minutes REELLES meme avec les chargements.
  run_scene village3-farside "$DP" brusque
  run_scene citadel-start    "$DP" brusque
  run_scene finalboss-start  "$DP" brusque
  run_scene snow-start       "$DP" brusque
  run_scene village3-start   "$DP" brusque
fi
echo "===== fin bras stretch_inject=$INJ — $(date -Is) ====="
echo "== resume du bras (les scenes agregees) =="
python3 .autoport/ghso6_device_resume.py "$TAG" "$INJ" "$OUT"/"$TAG"-*-marqueurs.txt | tee "$OUT/$TAG-hdstretch.txt"

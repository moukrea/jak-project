#!/usr/bin/env bash
# Ghd-skin-origin-stretch CYCLE 4 — UNE JAMBE SUR L'APPAREIL (Redmi eae4df44), MODELES HD INSTALLES.
#
# POURQUOI L'APPAREIL, ET POURQUOI CETTE MESURE. L'owner (2026-09-02) : « Le modèle HD qui s'étire
# c'est pas corrigé du tout. » La preuve du cycle 3 lisait le squelette GOAL sur x86. Ici on lit CE
# QUE LE GPU CONSOMME, sur la machine ou il voit le defaut : la sonde HDSKIN (Merc2.cpp) compte,
# par image, les os merc non finis ou a plus de 40 m du premier os fini de leur paquet — AVANT
# toute reparation — et la colonne HD a part. Le battement GOAL (HDHB4/7/8) donne la meme grandeur
# cote squelette, par branche du reciblage.
#
# DEUX BRAS, MEME APK : `debug.opengoal.hd.finite_arm` (0 = filet DESARME, controle ; 1 = ARME,
# preuve) est lu par kmachine.cpp au moment du warp et pose le symbole GOAL `*hd-finite-arm*`.
#
# LES SCENES SONT JOUEES AU PAD (injection `debug.opengoal.cpad_inject`, etat TENU) : le zoomer
# de lavatube (la ou le cycle 3 a mesure 507 images a os non fini sur x86) et deux niveaux a pied
# loin de l'origine (village3 3601 m, citadel), avec des sauts — un bouton tenu ne saute qu'une
# fois (piege connu : `debug.opengoal.cpad_inject` laisse CROIX coincee), donc l'etat est ALTERNE.
#
# usage : ghso4_device_leg.sh <finite_arm 0|1> <tag> [duree_zoomer_s] [duree_pied_s]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
[ -x "$ADB" ] || ADB=$(command -v adb)
SER=eae4df44
PKG=org.opengoal.gk.jak1
FARM="${1:-1}"; TAG="${2:-dev-farm$FARM}"; DZ="${3:-200}"; DP="${4:-150}"
OUT=.autoport/reports/Ghd-skin-origin-stretch/device; mkdir -p "$OUT"
SUM="$OUT/$TAG-resume.txt"
a(){ "$ADB" -s "$SER" "$@"; }
exec > >(tee "$SUM") 2>&1

LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  P=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then echo "FAIL: verrou tenu par pid=$P"; exit 2; fi
fi
printf 'ghso4_device pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"

LCPID=""
cleanup(){
  a shell "setprop debug.opengoal.level.warp ''"     >/dev/null 2>&1
  a shell "setprop debug.opengoal.cpad_inject ''"    >/dev/null 2>&1
  a shell "setprop debug.opengoal.hd.finite_arm ''"  >/dev/null 2>&1
  [ -n "${LCPID:-}" ] && { kill "$LCPID" 2>/dev/null; sleep 1; kill -9 "$LCPID" 2>/dev/null; }
  # Le jeu est ARRETE en sortant : sinon l'auto-constructeur voit l'application au premier plan et
  # differe l'installation suivante de 1500 s.
  a shell am force-stop $PKG >/dev/null 2>&1
  rm -f "$LOCK"
  return 0
}
trap cleanup EXIT

a devices | grep -qE "^${SER}[[:space:]]+device$" || { echo "FAIL: $SER absent"; exit 1; }
echo "===== appareil $SER — bras finite_arm=$FARM — $(date -Is) ====="
echo "-- fraicheur de l'installation"
a shell dumpsys package $PKG 2>/dev/null | grep -E "lastUpdateTime|versionName" | head -2 | tr -d '\r'
echo "   pack cgo telephone : $(a exec-out run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')"
echo "   pack cgo arbre     : $(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)"
# LE CODE DU CYCLE EST-IL DANS LE LIVRE ? Les bibliotheques restent dans l'APK (extractNativeLibs
# =false) : on lit l'APK installe, et les litteraux GOAL en clair dans le CGO du telephone.
APK=$(ls -t out/artifacts/*jak1*.apk android/app/build/outputs/apk/jak1/debug/*.apk 2>/dev/null | head -1)
if [ -n "$APK" ]; then
  echo "   marqueur HDSKINEV dans libgk.so de $APK : $(unzip -p "$APK" 'lib/arm64-v8a/libgk.so' 2>/dev/null | grep -ac HDSKINEV || true)"
fi
PATHAPK=$(a shell pm path $PKG 2>/dev/null | tr -d '\r' | sed -n 's/^package://p' | head -1)
if [ -n "$PATHAPK" ]; then
  # sur DISQUE, pas /tmp : /tmp est un tmpfs et l'APK de 667 Mo y echoue a 31 % (mesure 16:18)
  SCR=/home/emeric/.autoport-scratch; mkdir -p "$SCR"
  a pull "$PATHAPK" "$SCR/ghso4-installed.apk" >/dev/null 2>&1 && \
    echo "   marqueur HDSKINEV dans libgk.so INSTALLE : $(unzip -p "$SCR/ghso4-installed.apk" 'lib/arm64-v8a/libgk.so' 2>/dev/null | grep -ac HDSKINEV || true)   md5 = $(unzip -p "$SCR/ghso4-installed.apk" 'lib/arm64-v8a/libgk.so' 2>/dev/null | md5sum | cut -c1-12) (arbre build-android : $(md5sum build-android/lib/arm64-v8a/libgk.so | cut -c1-12))"
fi
echo "   marqueur HDNANSRC dans les CGO du telephone : $(a exec-out run-as $PKG sh -c 'cat files/*/GAME.CGO files/*/*/GAME.CGO 2>/dev/null' 2>/dev/null | grep -ac HDNANSRC || true)"

SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
a shell cat "$SET" > /tmp/ghso4_settings.ini 2>/dev/null
cp -f /tmp/ghso4_settings.ini "$OUT/.settings.pre-$TAG.ini" 2>/dev/null || true
# Cles a poser. PAS de regex shell ici : `?` echappe en `\?` devient « optionnel » en BRE GNU, et
# `recharged-enhanced-models?` n'etait plus jamais trouvee (tentative 5, 16:19). Python, litteral.
python3 - /tmp/ghso4_settings.ini <<'PY' || { echo "FAIL: cle absente des reglages de l'appareil"; exit 1; }
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
a push /tmp/ghso4_settings.ini "$SET" >/dev/null 2>&1
echo "-- reglages poses : modeles HD #t, looks HD = 1"

# ---- une scene = un lancement du jeu (le warp est un reglage de demarrage) ---------------------
run_scene(){
  local scene="$1" dur="$2" mode="$3"   # mode : zoomer | pied
  local LOG="$OUT/$TAG-$scene-logcat.txt"
  a shell am force-stop $PKG >/dev/null 2>&1
  a shell "setprop debug.opengoal.level.warp '$scene'" >/dev/null 2>&1
  a shell "setprop debug.opengoal.hd.finite_arm '$FARM'" >/dev/null 2>&1
  a shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1
  a logcat -c >/dev/null 2>&1
  # Les marqueurs GOAL (format 0) et Merc2 (printf) sortent sur stdout, que gk_android_main.cpp
  # route vers logcat sous le tag GK_STDOUT — PAS opengoal-gk (celui-ci porte lg::info). On garde
  # les deux, plus libc/DEBUG pour qu'un plantage natif soit dans la capture.
  a logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I libc:F DEBUG:V '*:S' > "$LOG" 2>/dev/null &
  LCPID=$!
  a shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  local W=0
  for i in $(seq 1 240); do
    grep -aq "LEVEL-WARP.*start .play" "$LOG" && { W=1; break; }
    sleep 1
  done
  echo "== scene $scene ($mode) : warp=$W, fenetre ${dur}s, bras=$(grep -a 'HDFINITEARM' "$LOG" | tail -1 | sed 's/^.*HDFINITEARM/HDFINITEARM/')"
  sleep 12
  local T0=$(date +%s) k=0
  while [ $(( $(date +%s) - T0 )) -lt "$dur" ]; do
    if [ "$mode" = idle ]; then
      # AUCUNE entree : sur le zoomer, l'animation de conduite reste a sa frame neutre, celle ou ND
      # ecrase les chevilles a l'echelle zero (mesure x86 c4ctl : 3968 images sur 10063 SANS pad).
      # C'est ce qui rend la condition du cycle 4 ABONDANTE — le bras de preuve doit la rencontrer.
      sleep 5
    elif [ "$mode" = zoomer ]; then
      # accelerer en continu, virer alternativement : la moto avance et la camera bouge vite.
      case $((k % 4)) in
        0) a shell "setprop debug.opengoal.cpad_inject 'x ly=0'" ;;
        1) a shell "setprop debug.opengoal.cpad_inject 'x ly=0 lx=30'" ;;
        2) a shell "setprop debug.opengoal.cpad_inject 'x ly=0'" ;;
        3) a shell "setprop debug.opengoal.cpad_inject 'x ly=0 lx=225'" ;;
      esac >/dev/null 2>&1
      sleep 3
    else
      # courir, sauter (front de CROIX a chaque cycle), se retourner : « en bougeant, sautant ».
      case $((k % 6)) in
        0) a shell "setprop debug.opengoal.cpad_inject 'ly=0'" ;;
        1) a shell "setprop debug.opengoal.cpad_inject 'ly=0 x'" ;;
        2) a shell "setprop debug.opengoal.cpad_inject 'ly=0'" ;;
        3) a shell "setprop debug.opengoal.cpad_inject 'ly=0 lx=0 x'" ;;
        4) a shell "setprop debug.opengoal.cpad_inject 'ly=255'" ;;
        5) a shell "setprop debug.opengoal.cpad_inject 'ly=255 x'" ;;
      esac >/dev/null 2>&1
      sleep 1.2
    fi
    k=$((k + 1))
  done
  a shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1
  local T1=$(date +%s)
  sleep 2
  kill "$LCPID" 2>/dev/null; sleep 1; LCPID=""
  a shell am force-stop $PKG >/dev/null 2>&1
  echo "   lignes capturees : $(grep -ac . "$LOG" || true)   injections : $(grep -ac 'F1D-INJECT applied' "$LOG" || true)   fenetre_pad=$((T1 - T0))s"
  echo "   etats joueur : $(grep -a 'JAK-HD-TGT\] st=' "$LOG" | sed 's/^.*st=//' | tr -d '\r' | sort | uniq -c | sort -rn | head -6 | awk '{printf "%s(%s) ", $2, $1}')"
  echo "   HDSKIN (dernier) : $(grep -a 'HDSKIN frames=' "$LOG" | tail -1 | sed 's/^.*HDSKIN/HDSKIN/' | tr -d '\r')"
  echo "   HDHB4 (dernier)  : $(grep -a 'HDHB4 ' "$LOG" | tail -1 | sed 's/^.*HDHB4/HDHB4/' | tr -d '\r')"
  echo "   HDHB7 (dernier)  : $(grep -a 'HDHB7 ' "$LOG" | tail -1 | sed 's/^.*HDHB7/HDHB7/' | tr -d '\r')"
  echo "   HDHB8 (dernier)  : $(grep -a 'HDHB8 ' "$LOG" | tail -1 | sed 's/^.*HDHB8/HDHB8/' | tr -d '\r')"
  echo "   HDSKINEV : $(grep -ac 'HDSKINEV ' "$LOG" || true) evenement(s)   HDNANSRC : $(grep -ac 'HDNANSRC ' "$LOG" || true)"
  grep -a 'HDSKINEV ' "$LOG" | sed 's/^.*HDSKINEV/HDSKINEV/' | tr -d '\r' | head -8
  grep -a 'HDNANSRC' "$LOG" | sed 's/^.*HDNANSRC/HDNANSRC/' | tr -d '\r' | head -6
  # marqueurs = HORODATAGE logcat + ligne nue (le tag est retire, quel qu'il soit) : l'horodatage
  # sert a mesurer les minutes REELLES entre le premier paquet HD dessine et le dernier battement.
  grep -aE 'HDSKIN |HDSKINEV |HDSKINMODEL |HDHB[0-9]? |HDNANSRC|HDFINITEARM|LEVEL-WARP|JAK-HD-TGT|F1D-INJECT applied|HDRESET|HDEPISODE|FATAL|signal [0-9]+' "$LOG" \
    | sed -E 's/^([0-9-]+ [0-9:.]+) +[0-9]+ +[0-9]+ [A-Z] [A-Za-z_-]+: /\1 /' | tr -d '\r' > "$OUT/$TAG-$scene-marqueurs.txt"
  echo "HDWALL scene=$scene secondes=$((T1 - T0)) farme=$FARM" >> "$OUT/$TAG-$scene-marqueurs.txt"
}

# QUATRE SCENES, DE 3601 m A 5540 m DE L'ORIGINE (owner : « la ou l'effet est le plus visible »)
# plus le zoomer de lavatube, ou la cause du cycle 4 (chevilles a echelle zero) se presente.
# Surcharge : SCENES="nom:duree:mode nom:duree:mode ..." (mode : zoomer | pied | idle) — sert a
# rejouer une scene seule, p.ex. le zoomer IMMOBILE ou la condition du cycle 4 est abondante.
if [ -n "${SCENES:-}" ]; then
  for sc in $SCENES; do IFS=: read -r nm du mo <<< "$sc"; run_scene "$nm" "$du" "$mo"; done
else
  run_scene lavatube-middle "$DZ" zoomer
  run_scene village3-start  "$DP" pied
  run_scene citadel-start   "$DP" pied
  run_scene finalboss-start "$DP" pied
fi
echo "===== fin bras finite_arm=$FARM — $(date -Is) ====="
echo "== resume du bras (les scenes agregees) =="
python3 .autoport/ghso4_device_resume.py "$TAG" "$FARM" "$OUT"/"$TAG"-*-marqueurs.txt | tee "$OUT/$TAG-hdstale.txt"

#!/usr/bin/env bash
# Gandroid-window-size — mesure sur APPAREIL de la taille de fenetre vue par le moteur
# et des BARRES NOIRES en bord d'image, avec son controle positif.
#
# Trois jambes, dans cet ordre, sur le MEME build :
#   1. CONTROLE POSITIF  — format d'image force a 4:3 (auto OFF) depuis settings.ini,
#      c'est-a-dire exactement ce que le clamp d'hote produisait. La mesure doit rendre
#      un nombre PREDIT : (largeur - 4/3*hauteur)/2 de chaque cote. Un compteur qui rend
#      ce nombre-la sait compter ; un zero sans lui ne prouve rien.
#   2. AUTO au titre     — le reglage de l'owner. Attendu : 0 aux quatre bords.
#   3. CINEMATIQUE       — la seule qui porte le defaut signale. On capture UNIQUEMENT
#      pendant que la trace d'hote publie `movie=1` : un 0 mesure hors cinematique
#      serait vide par construction (le clamp ne pouvait pas y tirer).
#
# Le fichier settings.ini de l'appareil est SAUVEGARDE et RESTAURE, y compris en cas
# d'echec : on ne laisse jamais un appareil de l'owner dans un etat qu'on a impose.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

S="${1:?usage: gaw_run.sh <serial> <label> [install]}"
LABEL="${2:?}"
DO_INSTALL="${3:-0}"
PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
INI=/storage/emulated/0/OpenGOAL/jak1/settings.ini
OUT=.autoport/reports/Gandroid-window-size
SHOTS="$OUT/shots/$LABEL"
LOG="$OUT/$LABEL-logcat.txt"
BAK="/tmp/gaw-$LABEL-settings.ini.bak"
INJECT="/data/data/$PKG/files/cpad_inject"
mkdir -p "$SHOTS" "$OUT"
: > "$LOG"

A(){ adb -s "$S" "$@"; }
say(){ echo "[$LABEL] $*"; }
# CANAL D'INJECTION : la PROPRIETE, pas le fichier. Le `run-as ... > files/cpad_inject`
# est execute par le shell ADB dans SON repertoire courant, pas dans le home de l'app :
# il atterrit silencieusement au mauvais endroit (c'est la panne derriere la demo neutre
# de 71354 frames). La propriete est independante du CWD. Elle est VIDEE a la sortie par
# device_teardown.sh : une valeur laissee la TIENT un bouton enfonce, donc plus aucun front.
inject(){ A shell "setprop debug.opengoal.cpad_inject '$1'" >/dev/null 2>&1 || true; }
clear_inject(){ A shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1 || true; A shell "run-as $PKG rm -f $INJECT" >/dev/null 2>&1 || true; }

cleanup(){
  clear_inject
  [ -f "$BAK" ] && A push "$BAK" "$INI" >/dev/null 2>&1
  A shell am force-stop "$PKG" >/dev/null 2>&1
  bash .autoport/device_teardown.sh "$S" 2>/dev/null || true
  kill "${LC_PID:-0}" 2>/dev/null
}
trap cleanup EXIT

A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
A shell settings put system screen_off_timeout 1800000 >/dev/null 2>&1
A shell svc power stayon true >/dev/null 2>&1
COMP=$(A shell cmd package resolve-activity --brief "$PKG" 2>/dev/null | tr -d '\r' | grep "^${PKG}/" | head -1)
[ -n "$COMP" ] || COMP="$PKG/org.opengoal.gk.LoaderActivity"
say "activite=$COMP"

if [ "$DO_INSTALL" = "1" ]; then
  say "installation de $APK ($(stat -c%s "$APK") octets)"
  A install -r "$APK" 2>&1 | tail -2
  # LoaderActivity, et elle seule, redeballe les packs et reecrit les tampons que
  # deploy_verify relit. Un premier lancement long est OBLIGATOIRE : sans lui la course
  # mesurerait l'ANCIEN pack sous le NOUVEL APK -- la paire depareillee.
  say "premier lancement (deballage des packs)"
  A shell am force-stop "$PKG" >/dev/null 2>&1; sleep 2
  A shell am start -n "$COMP" >/dev/null 2>&1
  WANT_C=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
  WANT_G=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
  for i in $(seq 1 45); do
    sleep 10
    GOT_C=$(A exec-out run-as "$PKG" cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
    GOT_G=$(A exec-out run-as "$PKG" cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
    [ "$GOT_C" = "$WANT_C" ] && [ "$GOT_G" = "$WANT_G" ] && break
  done
  say "TAMPONS appareil custom='$GOT_C' (attendu '$WANT_C')  cgo='$GOT_G' (attendu '$WANT_G')"
  if [ "$GOT_C" != "$WANT_C" ] || [ "$GOT_G" != "$WANT_G" ]; then
    say "PACKS NON DEBALLES — la course mesurerait un pack perime, on s'arrete"
    exit 3
  fi
fi

A pull "$INI" "$BAK" >/dev/null 2>&1 || { say "PAS de settings.ini a sauvegarder"; : > "$BAK"; }
say "settings.ini sauvegarde ($(stat -c%s "$BAK" 2>/dev/null) octets)"

set_aspect(){  # $1 = ligne aspect-state complete
  local tmp=/tmp/gaw-$LABEL-set.ini
  cp "$BAK" "$tmp"
  python3 - "$tmp" "$1" <<'PY'
import sys, io
p, line = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8', errors='replace').read().splitlines()
out=[]
found=False
for l in s:
    if l.strip().startswith('aspect-state'):
        out.append('  ' + line); found=True
    else:
        out.append(l)
if not found:
    out.append('  ' + line)
open(p,'w',encoding='utf-8').write('\n'.join(out)+'\n')
PY
  A push "$tmp" "$INI" >/dev/null 2>&1
  say "aspect-state -> $1"
}

start_logcat(){
  A logcat -G 32M >/dev/null 2>&1 || true
  A logcat -c >/dev/null 2>&1
  ( A logcat -v time '*:V' 2>/dev/null \
      | grep --line-buffered -aE 'GAWIN|GAWIN-ZERO|GD1-PCWIN|bars=|Fatal signal|F1D-LOADSYNC|A36-STR-DIAG' \
      >> "$LOG" ) &
  LC_PID=$!
}

boot_game(){
  A shell am force-stop "$PKG" >/dev/null 2>&1; sleep 2
  A shell am start -n "$COMP" >/dev/null 2>&1
}

shot(){ A exec-out screencap -p > "$SHOTS/$1.png" 2>/dev/null; echo "  shot $1 $(stat -c%s "$SHOTS/$1.png" 2>/dev/null)o"; }

# ---------------------------------------------------------------- jambe 1 + 2
run_static(){  # $1 = nom, $2 = ligne aspect-state, $3 = secondes d'attente
  set_aspect "$2"
  boot_game
  say "$1 : attente ${3}s du titre"
  sleep "$3"
  for i in 1 2 3 4; do shot "$1-$i"; sleep 4; done
  A shell dumpsys window 2>/dev/null | grep -a mCurrentFocus | head -1 | sed 's/^/  focus: /'
}

start_logcat
run_static ctrl43   "aspect-state = aspect4x3 4 3 #f" "${WARM:-75}"
run_static auto     "aspect-state = aspect4x3 4 3 #t" "${WARM:-75}"

# ---------------------------------------------------------------- jambe 3
say "CINEMATIQUE : navigation NEW GAME"
clear_inject
sleep 8
press(){ inject "$1"; sleep 0.5; clear_inject; sleep "${2:-1.2}"; echo "    -> $1"; }
press start 4
press down; press down; press up; press up
press x 4
press down; press down; press down; press down
press x 5

say "CINEMATIQUE : capture cadencee (max ${WATCH:-600}s)"
# POURQUOI LA CADENCE PLUTOT QUE LE BIT. La tentative 1 ne declenchait une capture que
# quand la trace d'hote lisait deja `movie=1`. Ce bit n'a JAMAIS ete lu a 1 de toute la
# course, donc zero image utile -- et les 12 fichiers `movie-*.png` qu'elle a laisses
# sont tous entierement noirs (eclaire=0.000), c'est-a-dire VIDES par construction.
# Depuis que le clamp d'hote est retire, ce bit ne pilote plus RIEN : il ne reste qu'une
# ETIQUETTE. On capture donc a intervalle fixe et on ECRIT le bit a cote de chaque image ;
# c'est l'image qui porte le verdict, l'etiquette qui dit dans quel etat elle a ete prise.
mov_now(){ grep -aoE '(GAWIN-HOST|GD1-PCWIN) movie=[01]' "$LOG" 2>/dev/null | tail -1 | grep -oE '[01]$'; }
NSHOT=0; NLIT=0
: > "$OUT/$LABEL-movieframes.txt"
DEADLINE=$(( $(date +%s) + ${WATCH:-600} ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  M=$(mov_now); M=${M:-0}
  NSHOT=$((NSHOT+1))
  shot "cine-$NSHOT" >/dev/null
  LINE=$(python3 .autoport/gaw_bars.py "$SHOTS/cine-$NSHOT.png" 2>/dev/null)
  echo "movie=$M $LINE" >> "$OUT/$LABEL-movieframes.txt"
  case "$LINE" in
    *verdict=0-BANDE*|*verdict=BANDES*) NLIT=$((NLIT+1)); say "  image eclairee $NLIT/${NEEDLIT:-8} (movie=$M) ${LINE#*gauche}" ;;
  esac
  [ "$NLIT" -ge "${NEEDLIT:-8}" ] && break
  [ "$NSHOT" -ge "${MAXSHOT:-90}" ] && break
  sleep 3
done
say "captures cinematique : $NSHOT (dont eclairees : $NLIT)"

say "--- lignes GAWIN de la course ---"
grep -aE 'GAWIN' "$LOG" | tail -40
echo "GAW_RUN_DONE label=$LABEL shots=$(ls "$SHOTS"/*.png 2>/dev/null | wc -l) movieshots=$NSHOT lit=$NLIT"

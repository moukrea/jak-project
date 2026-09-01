#!/usr/bin/env bash
# Gjak1-crate-collision-2 — MESURE DES CAISSES SUR L'APPAREIL (Redmi eae4df44).
#
# Retour 2 de l'owner : « j'ai toujours le soucis, c'est pas réglé du tout, ptêtre lié
# au jeux qui dépend plus du framerate ». La preuve du cycle precedent avait ete prise
# sur x86 a 60 images/s ; celle-ci est prise SUR SON MATERIEL, a la cadence que
# l'appareil rend vraiment (mediane relevee : 13,9 img/s a Geyser Rock), avec un joueur
# qui COURT — pas un joueur teleporte.
#
# Le pilote est `debug.opengoal.cpad_inject` : de VRAIES entrees manette, donc la
# physique et la collision tournent normalement. On n'utilise PAS
# `debug.opengoal.target.drive`, qui ecrit `trans` directement et court-circuite la
# collision : il fabriquerait des traversees.
#
# usage : gjcc2_device_run.sh <tag> <mode> <duree_s> [pos "X Y Z"]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
[ -x "$ADB" ] || ADB=$(command -v adb)
SER=eae4df44
PKG=org.opengoal.gk.jak1
TAG="${1:-d1}"; MODE="${2:-3}"; DUR="${3:-240}"; POS="${4:-}"   # POS = "X Z" cible du pilote, en metres
OUT=.autoport/reports/Gjak1-crate-collision/device2; mkdir -p "$OUT"
LOG="$OUT/dev-$TAG-logcat.txt"; SUM="$OUT/dev-$TAG-resume.txt"
a(){ "$ADB" -s "$SER" "$@"; }
exec > >(tee "$SUM") 2>&1

pad(){ a shell "setprop debug.opengoal.cpad_inject '$1'" >/dev/null 2>&1; }
cleanup(){
  pad ""
  a shell "setprop debug.opengoal.f1.warp ''"        >/dev/null 2>&1
  a shell "setprop debug.opengoal.level.warp ''"     >/dev/null 2>&1
  a shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
  [ -n "${LCPID:-}" ] && kill "$LCPID" 2>/dev/null
  # On ARRETE le jeu en sortant. Sans ca, l'auto-constructeur voit l'application au
  # premier plan, croit qu'une mesure tourne et REFUSE d'installer pendant 1500 s :
  # une campagne qui ne nettoie pas derriere elle bloque la livraison suivante.
  a shell am force-stop $PKG >/dev/null 2>&1
  return 0
}
trap cleanup EXIT

a devices | grep -qE "^${SER}[[:space:]]+device$" || { echo "FAIL: $SER absent"; exit 1; }
echo "== FRAICHEUR DE L'INSTALLATION =="
a shell dumpsys package $PKG 2>/dev/null | grep -E "lastUpdateTime|versionName" | head -2 | tr -d '\r'
echo "  custom pack sur le telephone : $(a exec-out run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r')"
echo "  cgo    pack sur le telephone : $(a exec-out run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')"
echo "  cgo    pack dans l'arbre     : $(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)"
echo "  la sonde est-elle DANS le CGO deploye ? GJCC-THRU : $(a exec-out run-as $PKG sh -c "grep -c GJCC-THRU files/cgo/jak1/GAME.CGO" 2>/dev/null | tr -d '\r')"

echo "== REGLAGES : gjcc = $MODE =="
SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
a shell cat "$SET" > /tmp/gjcc2_settings.ini 2>/dev/null
# La cle est posee JUSTE APRES `fps`, jamais en fin de fichier : le lecteur de reglages
# est decoupe en GROUPES (`handle-input-settings` et ses freres) et `gjcc` n'est reconnu
# que dans le groupe qui contient `fps`. Ajoutee a la fin, elle tomberait dans un autre
# groupe et serait ignoree en silence — un faux zero.
if grep -q '^gjcc' /tmp/gjcc2_settings.ini; then
  sed -i "s/^gjcc.*/gjcc = $MODE/" /tmp/gjcc2_settings.ini
else
  sed -i "0,/^fps *=/s//gjcc = $MODE\nfps =/" /tmp/gjcc2_settings.ini
fi
grep -q '^gjcc' /tmp/gjcc2_settings.ini || { echo "FAIL: impossible de poser la cle gjcc (pas de ligne 'fps =' ?)"; exit 1; }
a push /tmp/gjcc2_settings.ini /sdcard/gjcc2_settings.ini >/dev/null 2>&1
a shell "cp /sdcard/gjcc2_settings.ini $SET" >/dev/null 2>&1
echo "  relu sur le telephone : $(a shell "grep '^gjcc' $SET" 2>/dev/null | tr -d '\r')"

echo "== DEMARRAGE =="
a shell am force-stop $PKG >/dev/null 2>&1
pad ""
# Le spawn reste le point de depart AUTORISE (`f1.warp`). Deux essais l'imposent :
#  - `level.warp.pos` vers le milieu d'un amas a GELE le joueur — `GJCC-POS dist_m=0.0000`
#    sur 4500 images, position figee a la valeur demandee, cadence 35,9 (rien de rendu) ;
#  - le spawn autorise, lui, charge tout et le joueur bouge (`dist_m=853,7` en 3000 images).
# On part donc de la ou le jeu sait demarrer, et c'est le PILOTE qui amene le joueur sur
# les caisses, avec de vraies entrees manette.
if [ -n "${SPAWN:-}" ]; then
  # `training-warp`, PAS `game-start`. Les deux points de reprise sont a 2,4 m l'un de
  # l'autre, mais `game-start` porte le drapeau `game-start` (level-info.gc:90) qui declenche
  # la sequence de nouvelle partie : mesure v4, le joueur nait bien au milieu des caisses
  # (GJCC-NEAR sur 4 caisses a l'image 642) puis il est REPLACE au depart autorise a
  # l'image 900. `training-warp` ne porte que le drapeau `warp`.
  a shell "setprop debug.opengoal.level.warp training-warp" >/dev/null 2>&1
  a shell "setprop debug.opengoal.level.warp.pos '$SPAWN'" >/dev/null 2>&1
  echo "  spawn force via level.warp a : $SPAWN"
else
  a shell "setprop debug.opengoal.f1.warp 1" >/dev/null 2>&1
fi
[ -n "$POS" ] && echo "  cible du pilote (metres) : $POS"
a shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
a shell svc power stayon true >/dev/null 2>&1
a logcat -c >/dev/null 2>&1
( a logcat -v threadtime > "$LOG" ) & LCPID=$!
sleep 1
a shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "  attente du niveau (GJCC-MODE ou target vivant)…"
ok=0
for i in $(seq 1 150); do
  sleep 2
  grep -qa 'GJCC-MODE' "$LOG" && { echo "  GJCC-MODE vu a ~$((i*2))s"; ok=1; break; }
done
[ "$ok" = 1 ] || echo "  ATTENTION: pas de GJCC-MODE — la sonde n'est peut-etre pas dans ce build"
grep -a 'GJCC-MODE' "$LOG" | tail -1 | sed 's/.*GJCC-MODE/  GJCC-MODE/'
sleep 20

echo "== COURSE : le joueur COURT ${DUR}s vers les caisses (pilote en boucle fermee) =="
if [ -n "$POS" ]; then
  bash .autoport/gjcc2_pilote.sh "$SER" "$PKG" "$DUR" $POS
else
  END=$(( $(date +%s) + DUR ))
  while [ "$(date +%s)" -lt "$END" ]; do pad "ly=0"; sleep 4; pad "ly=0 lx=200"; sleep 1.2; done
fi
pad ""
sleep 6
kill "$LCPID" 2>/dev/null; sleep 1

echo "== RESULTAT $TAG (mode=$MODE) =="
LN=$(wc -l < "$LOG")
echo "  lignes de logcat capturees : $LN"
echo "  GJCC-MODE : $(grep -ac 'GJCC-MODE' "$LOG")   GJCC-RUN : $(grep -ac 'GJCC-RUN' "$LOG")   GJCC-THRU : $(grep -ac 'GJCC-THRU' "$LOG")"
grep -a 'GJCC-RUN' "$LOG" | tail -2 | sed 's/^.*GJCC-RUN/  GJCC-RUN/'
grep -a 'GJCC-THRU' "$LOG" | sed 's/^.*GJCC-THRU/  GJCC-THRU/' | head -12
echo "  cadence [dyn-rs] : $(grep -a 'dyn-rs.*avg-fps' "$LOG" | sed 's/.*avg-fps=\([0-9.]*\).*/\1/' | sort -n | awk '{v[NR]=$1} END{if(NR>0) printf "n=%d min=%s med=%s max=%s", NR, v[1], v[int((NR+1)/2)], v[NR]; else printf "n=0"}')"
echo
echo "  plantages : Fatal=$(grep -ac 'Fatal signal' "$LOG")  ANR=$(grep -ac 'ANR in' "$LOG")"
echo "GJCC2-DEV-DONE tag=$TAG mode=$MODE lignes=$LN"

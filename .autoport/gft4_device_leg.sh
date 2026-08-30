#!/usr/bin/env bash
# =====================================================================================
# Gfixed-tick-interpolation — UNE course SUR L'APPAREIL (Redmi eae4df44).
#
# Le rapport de la tentative 3 nommait lui-meme ce qui manquait : « Aucune course sur
# appareil ce cycle ». Or la phase est `device: true` et le defaut que l'owner decrit se
# produit sur SON telephone. Cette course rejoue LA MEME demo de manette que la campagne
# x86, sur l'appareil, avec l'horloge a pas fixe ARMEE ou DESARMEE — ablation sur LE MEME
# .so, exactement comme sur bureau (la propriete PRIME sur la case du menu, par
# construction : game/graphics/fixed_tick.cpp read_force_flag).
#
# Usage : gft4_device_leg.sh <on|off> <fps> <etiquette> [inputs] [dernier-tick]
#
# Sortie : $OUT/<etiquette>.trace   (une ligne « CAM frame= » par TICK DE LOGIQUE)
#          $OUT/<etiquette>.logcat  (dont les lignes « GFT n= », une par image DESSINEE)
#
# CAPTURE STREAMEE, jamais `logcat -t N` : la fenetre d'un evenement de demarrage se rate
# systematiquement avec une fenetre fixe, et rend un faux ROUGE (piege deja paye).
# NETTOYAGE TOUJOURS : une propriete de debug laissee posee tient un etat pour la course
# SUIVANTE — c'est la classe de bug « bouton coince ».
# =====================================================================================
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
MODE="$1"; FPS="$2"; TAG="$3"
INPUTS="${4:-/tmp/gft_stand.inputs}"
LAST_TICK="${5:-1079}"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gfixed-tick-interpolation; mkdir -p "$OUT"
SET_DEV=/storage/emulated/0/OpenGOAL/jak1/settings.ini
TRACE="$OUT/$TAG.trace"; LC="$OUT/$TAG.logcat"
TIMEOUT="${TIMEOUT:-420}"
say(){ echo "[$TAG] $*"; }
die(){ say "FAIL: $*"; exit 1; }

$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "appareil $S absent d'adb"
$ADB -s "$S" shell svc power stayon true >/dev/null 2>&1 || true
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true

FT=1; [ "$MODE" = off ] && FT=0

cleanup(){
  for p in debug.opengoal.pad_replay debug.opengoal.pad_trace debug.opengoal.f1.warp \
           debug.opengoal.fixed_tick debug.opengoal.fixed_tick_probe \
           debug.opengoal.pad_replay_realtime; do
    $ADB -s "$S" shell setprop "$p" '""' >/dev/null 2>&1 || true
  done
  kill "${LCP:-0}" 2>/dev/null || true
  $ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
}
trap cleanup EXIT

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2

# --- cadence cible, dans le fichier de reglages que le jeu relit au demarrage ---
TMPS=$(mktemp); $ADB -s "$S" pull "$SET_DEV" "$TMPS" >/dev/null 2>&1 || die "pas de $SET_DEV"
sed -i "s/^fps = .*/fps = $FPS/" "$TMPS"
sed -i "s/^vsync = .*/vsync = #f/" "$TMPS"
$ADB -s "$S" push "$TMPS" "$SET_DEV" >/dev/null 2>&1 || die "push settings"; rm -f "$TMPS"
BACK=$($ADB -s "$S" shell "grep -a -E '^(fps|vsync) = ' $SET_DEV" | tr -d '\r' | tr '\n' ' ')
say "reglages relus sur le telephone : $BACK"
[[ "$BACK" == *"fps = $FPS"* ]] || die "fps non applique ($BACK)"

# --- demo de manette (run-as ne lit pas /sdcard sur MIUI : passer par /data/local/tmp) ---
$ADB -s "$S" push "$INPUTS" /data/local/tmp/gft_pad_demo.inputs >/dev/null 2>&1 || die "push demo"
$ADB -s "$S" shell chmod 644 /data/local/tmp/gft_pad_demo.inputs
$ADB -s "$S" shell run-as $PKG cp /data/local/tmp/gft_pad_demo.inputs files/pad_demo.inputs || die "run-as cp"
SZ=$($ADB -s "$S" shell run-as $PKG stat -c %s files/pad_demo.inputs | tr -d '\r')
[ "$SZ" = "$(stat -c%s "$INPUTS")" ] || die "taille demo $SZ != $(stat -c%s "$INPUTS")"
$ADB -s "$S" shell run-as $PKG rm -f "files/$TAG.trace" >/dev/null 2>&1 || true

$ADB -s "$S" shell setprop debug.opengoal.pad_replay replay
$ADB -s "$S" shell setprop debug.opengoal.pad_trace "$TAG.trace"
$ADB -s "$S" shell setprop debug.opengoal.f1.warp 1
$ADB -s "$S" shell setprop debug.opengoal.fixed_tick "$FT"
$ADB -s "$S" shell setprop debug.opengoal.fixed_tick_probe 1
# PACING=realtime : le harnais de rejeu cesse d'epingler le pas de temps, l'accumulateur
# lit la MONTRE et le rattrapage s'exerce vraiment. Le rejeu n'est alors plus deterministe
# — c'est voulu : cette course ne sert pas a comparer des trajectoires mais a montrer que
# le temps de JEU suit le temps REEL quand l'appareil ne tient pas 60 images/s.
if [ "${PACING:-det}" = realtime ]; then
  $ADB -s "$S" shell setprop debug.opengoal.pad_replay_realtime 1
else
  $ADB -s "$S" shell setprop debug.opengoal.pad_replay_realtime '""'
fi
say "proprietes posees : fixed_tick=$FT probe=1 warp=1 replay=1 pacing=${PACING:-det} trace=$TAG.trace"

$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
: > "$LC"
$ADB -s "$S" logcat -v time > "$LC" 2>/dev/null & LCP=$!
COMP=$($ADB -s "$S" shell cmd package resolve-activity --brief $PKG 2>/dev/null | tr -d '\r' | grep "^${PKG}/" | head -1)
[ -n "$COMP" ] || COMP="$PKG/org.opengoal.gk.LoaderActivity"
$ADB -s "$S" shell am start -n "$COMP" >/dev/null 2>&1 || die "am start"
say "lance ($COMP), attente du tick $LAST_TICK (plafond ${TIMEOUT}s)"

t0=$SECONDS; done=0; last=-1
while [ $((SECONDS - t0)) -lt "$TIMEOUT" ]; do
  sleep 10
  PID=$($ADB -s "$S" shell pidof $PKG 2>/dev/null | tr -d '\r')
  if [ -z "$PID" ]; then say "processus MORT a t+$((SECONDS-t0))s"; break; fi
  last=$($ADB -s "$S" exec-out run-as $PKG sh -c "grep -a -c '^CAM frame=' files/$TAG.trace 2>/dev/null" | tr -d '\r')
  last=${last:-0}
  say "  t+$((SECONDS-t0))s pid=$PID ticks=$last"
  [ "${last:-0}" -gt "$LAST_TICK" ] && { done=1; break; }
done

CRASH=$($ADB -s "$S" exec-out run-as $PKG sh -c 'ls files/gk_crash.txt 2>/dev/null' | tr -d '\r')
$ADB -s "$S" exec-out run-as $PKG cat "files/$TAG.trace" > "$TRACE" 2>/dev/null || true
sleep 2; kill "$LCP" 2>/dev/null || true
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true

# Le depouilleur commun (gft_analyze.py) lit un fichier « <etiquette>.log » dont chaque
# ligne de sonde COMMENCE par « GFT n= ». logcat prefixe chaque ligne de sa date et de son
# tag : on republie donc les lignes de sonde sans leur prefixe, dans le format que le
# depouilleur x86 consomme deja. Rien n'est recalcule au passage — c'est un decoupage.
sed -n 's/^.*\(GFT n=\)/\1/p' "$LC" > "$OUT/$TAG.log"

NC=$(grep -ac '^CAM frame=' "$TRACE" 2>/dev/null || echo 0)
NG=$(grep -ac '^GFT n=' "$OUT/$TAG.log" 2>/dev/null || echo 0)
NL=$(wc -l < "$LC")
say "mode=$MODE fps=$FPS duree=$((SECONDS-t0))s complet=$done cam=$NC gft=$NG logcat=$NL crash=${CRASH:-aucun}"
[ "$done" = 1 ] || exit 2
exit 0

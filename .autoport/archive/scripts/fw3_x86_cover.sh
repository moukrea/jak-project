#!/usr/bin/env bash
# Grecharged-foliage-wind3 — D1 : LA BRISE NATIVE, OPTION ETEINTE, SUR LE BINAIRE.
# DIRECTIVES vd9e8b66782
#
# CE QUE CETTE COURSE MESURE, ET POURQUOI ELLE N'A BESOIN D'AUCUN REBUILD C++.
# `update-wind` (goal_src/jak1/engine/gfx/background/wind.gc:14) a ete patchee « for high fps » :
# l'INDEX D'ECRITURE du ring de 64 vecteurs ET l'amplitude sont multiplies par
# `(-> *display* time-adjust-ratio)`. L'INDEX DE LECTURE, lui, est le compteur BRUT
# (`(wind_time + wind_idx) & 63`, Tie3.cpp:1889). Quand le ratio partage un facteur avec 64,
# une partie des slots n'est JAMAIS ecrite et le ressort lit du VIDE.
# Cette course lit les 64 slots depuis la REPL : c'est la grandeur elle-meme, pas un effet.
#
# TROIS COLONNES PAR PALIER, et c'est leur DESACCORD qui porte le verdict :
#   tar  = time-adjust-ratio publie par le moteur
#   nz   = nombre de slots du ring NON NULS (64 = ring sain)
#   dwt  = ticks de `wind-time` par seconde de temps reel (60 = cadence d'auteur)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
# JAMBE : 1 = correctif arme (defaut), 0 = ABLATION, le chemin « high fps » d'avant la phase.
# Les deux jambes tournent sur LE MEME BINAIRE : c'est ce que les directives exigent d'un avant/apres.
# fw3_x86_cover.sh <t|f> — D2 : la COUVERTURE, sur les niveaux ou la vegetation est figee.
# `t` = option Recharged ALLUMEE (le balancement ajoute doit couvrir tout le lexique),
# `f` = ETEINTE (controle : la couverture doit tomber a zero, et le rendu doit etre le stock).
TOG="${1:-t}"
NAT="cover-$TOG"
export OG_WIND_NATIVE_RATE=1
OUT=.autoport/reports/Grecharged-foliage-wind3; mkdir -p "$OUT"
GOALC=build-x86/goalc/goalc; GK=build-x86/game/gk
ISO=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/fw3-iso-$NAT
LOG="$OUT/x86-native-$NAT.log"; GCLOG="$OUT/x86-native-$NAT-goalc.log"; MILOG="$OUT/x86-native-$NAT-mi.log"; DRV="$OUT/x86-native-$NAT-run.log"
: > "$LOG"; : > "$GCLOG"; : > "$MILOG"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }

LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  P=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then say "VERROU TENU par pid=$P — abandon"; exit 2; fi
fi
printf 'fw3_x86_native-$NAT pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"

cleanup(){
  exec 3>&- 2>/dev/null || true
  for p in $(pgrep -f "game/gk --game jak1 --portable -fakeiso" 2>/dev/null); do kill "$p" 2>/dev/null; done
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  rm -f "${FIFO:-/nonexistent}" "$LOCK"
}
trap cleanup EXIT

export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11

say "== (mi) : construction de l'iso x86 =="
stdbuf -oL -eL timeout 1200 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi \
  --cmd '(mi)' >> "$MILOG" 2>&1
echo "MI-EXIT=$?" >> "$MILOG"
grep -q "MI-EXIT=0" "$MILOG" || { say "!! (mi) a echoue, voir $MILOG"; exit 1; }

say "== copie privee de l'iso =="
rm -rf "$SNAP"; mkdir -p "$(dirname "$SNAP")"
cp -a --reflink=auto "$ISO" "$SNAP"
say "copie : GAME.CGO $(md5sum "$SNAP/GAME.CGO" | cut -c1-12)"

say "== gk sur la copie, foliage-wind = #$TOG =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
for i in $(seq 1 240); do grep -qa "Waiting for listener" "$LOG" && break; sleep 1; done
sleep 25
say "gk : $(grep -ac 'link finish:' "$LOG") objets lies"

timeout 1800 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 6
echo '(build-game)' >&3
for i in $(seq 1 300); do grep -qa "Successfully built all" "$GCLOG" && { say "build-game a ~${i}s"; break; }; sleep 1; done
sleep 4

# l'option Recharged reste ETEINTE : D1 est le chemin NATIF.
echo "(set! (-> *pc-settings* recharged-foliage-wind?) #$TOG)" >&3
sleep 2
echo '(format 0 "FW3LEG native=~D fw=~A~%" *wind-native-rate* (-> *pc-settings* recharged-foliage-wind?))' >&3
sleep 2
# ENVELOPPE DE RAFALE : la version « high fps » indexait la table des 32 echelles en passant par un
# FLOTTANT (`(the-as int (/ (* tar wind-time) 120))`). `the-as` est une REINTERPRETATION DE BITS en
# GOAL, pas une conversion : si les deux colonnes ci-dessous different, l'index d'enveloppe que le
# build livre utilisait n'etait PAS la marche de 120 pas que ND a ecrite. On mesure, on ne suppose pas.
echo '(format 0 "FW3ENV wt=~D nd=~D flottant=~D~%" (-> *wind-work* wind-time) (/ (-> *wind-work* wind-time) (the-as uint 120)) (the-as int (/ (* 1.0 (-> *wind-work* wind-time)) (the-as uint 120))))' >&3
sleep 2

say "== chargement de la plage (palmiers animes par ND) =="
echo '(start (quote play) (get-continue-by-name *game-info* "beach-start"))' >&3
sleep 70
echo '(format 0 "FW3LEVEL lev=~A vidmode=~A tarfps=~D~%" (let ((l (level-get-target-inside *level*))) (if l (-> l name) (quote nul))) (get-video-mode) (-> *pc-settings* target-fps))' >&3
sleep 3

# --- LA SONDE. Elle lit le ring LUI-MEME, pas un effet du ring.
probe(){ # $1 = etiquette — DEUX `format` : GOAL refuse un appel a plus de 8 parametres.
  echo "(let ((nz 0) (mx 0.0) (run 0) (worst 0)) (dotimes (i 64) (let* ((v (-> *wind-work* wind-array i)) (m (+ (fabs (-> v x)) (fabs (-> v z))))) (if (> m 0.0) (begin (set! nz (+ nz 1)) (set! run 0)) (begin (set! run (+ run 1)) (if (> run worst) (set! worst run)))) (if (> m mx) (set! mx m)))) (format 0 \"FW3PROBE tag=$1 nz=~D trou=~D amax=~f~%\" nz worst mx))" >&3
  sleep 2
  echo "(format 0 \"FW3RATIO tag=$1 tar=~f tr=~f tpf=~D wt=~D~%\" (-> *display* time-adjust-ratio) (-> *display* time-ratio) *ticks-per-frame* (-> *wind-work* wind-time))" >&3
  sleep 2
}

# LES NIVEAUX QUI PORTENT LA VEGETATION FIGEE (recensement complet, tie-census-full.txt) :
#   swamp   724 instances de vegetation, 0 animee par ND
#   jungle  594 (313 + 281 sur ses deux arbres TIE), 0 animee
#   village1 183, dont 65 animees  <- le niveau ou l'owner voit 27 palmiers figes a cote de 65 qui bougent
for LV in village1-hut jungle-start swamp-start; do
  say "== niveau $LV =="
  echo "(format 0 \"FW3LV lieu=~A~%\" \"$LV\")" >&3
  echo "(start (quote play) (get-continue-by-name *game-info* \"$LV\"))" >&3
  sleep 75
  echo '(let ((l (level-get-target-inside *level*))) (format 0 "FW3IN lev=~A~%" (if l (-> l name) (quote nul))))' >&3
  sleep 25
done


say "== recolte =="
{ echo "### FW3LEVEL / FW3PROBE / FW3WT"; grep -a "FW3LV\|FW3IN\|FW3LEG\|sway-cover\|TIE census\|static sway ACTIVE\|mesh-consolidate.*APPLIED\|does not match" "$LOG" 2>/dev/null; } | tee -a "$DRV"
say "fini — $LOG"

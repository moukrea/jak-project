#!/usr/bin/env bash
# glsw_window_proof.sh — Gloading-screen-window : LES QUATRE INSTANTS DE LA FENETRE, SUR LES DEUX
# TRANSITIONS QUE L'OWNER NOMME, ET L'ABLATION SUR LE MEME BINAIRE.
#
#   D4/D7 « on voit l'interieur de la hutte du Sage Vert AVANT que l'ecran de chargement
#           apparaisse »  -> l'ecran se pose TROP TARD
#   D3    « il disparait avant que tous les elements de la scene soient affiches [...] du pop-in »
#           -> il se leve TROP TOT
#
# DEUX JAMBES, MEME BINAIRE, MEME ETAT DE DEPART :
#   avant   `*ls-window-fix*` = #f  -> comportement livre a l'owner le 2026-08-30 au matin
#   apres   `*ls-window-fix*` = #t  -> la fenetre encadre la transition
# Une jambe « avant » prise sur un AUTRE build ne prouverait rien sur celui qu'on livre.
#
# DEUX TRANSITIONS, DANS LES MOTS DE L'OWNER :
#   save-geyser        chargement d'une sauvegarde a Geyser Rock. Le chemin est
#                      `initialize! *game-info* 'game` (game-info.gc:141), le seul qui passe par
#                      `continue-load-gate!` -- `start` ne le traverse pas.
#   teleport-sagehut   teleporteur de Geyser Rock vers la Hutte du Sage Vert. La derniere ligne du
#                      teleporteur est litteralement `(start 'play (get-continue-by-name
#                      *game-info* "village1-warp"))` (basebutton.gc:349) : on la joue telle quelle.
#
# NE JAMAIS reconstruire out/jak1/iso pendant qu'une course tourne : gk streame depuis ce dossier.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen-window"; mkdir -p "$OUT"
JAMBE="${1:-apres}"          # avant | apres
FIX='#t'; [ "$JAMBE" = "avant" ] && FIX='#f'
# L'ABLATION PORTE SUR LES DEUX MOITIES DU LOT, SUR LE MEME BINAIRE :
#   *ls-window-fix*  (GOAL)  la fenetre encadre la transition
#   OG_GRASS_DIAG    (C++)   les deux passes de diagnostic du champ d'herbe, qui balayent
#                            726 851 instances a chaque chargement de niveau et n'ont aucun effet
#                            sur l'image. =1 rejoue le comportement d'avant.
if [ "$JAMBE" = "avant" ]; then export OG_GRASS_DIAG=1; else unset OG_GRASS_DIAG; fi
LOG="$OUT/window-$JAMBE.log"; GCLOG="$OUT/window-$JAMBE-goalc.log"
: > "$LOG"; : > "$GCLOG"

stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem 2>&1 \
  | python3 -u -c 'import sys,time
t0=time.time()
for l in sys.stdin:
    sys.stdout.write("%9.3f %s" % (time.time()-t0, l))' >> "$LOG" &
PIPEPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){
  exec 3>&- 2>/dev/null || true
  P=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true); [ -n "$P" ] && kill "$P" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  kill "$PIPEPID" 2>/dev/null; wait 2>/dev/null; rm -f "$FIFO"
}
trap cleanup EXIT

echo "== jambe=$JAMBE fix=$FIX OG_GRASS_DIAG=${OG_GRASS_DIAG:-non-pose} =="
echo "== attente de l'ecran titre =="
for i in $(seq 1 180); do
  grep -qaE "BOOTLINE etape=titre-affiche|link finish: default-menu" "$LOG" && { echo "  titre a ~${i}s"; break; }
  sleep 1
done
sleep 3
echo "== goalc (lt) + (build-game) =="
timeout 1800 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 600); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game a ~${i}s"; break; }; done
sleep 3
# VIVACITE : sans listener connecte, goalc compile avec `allow_emit=#f` et jette tout EN SILENCE
# (Compiler.cpp:132) -- la course serait muette et aurait l'air d'un defaut du moteur.
echo '(format 0 "REPL-LIVE~%")' >&3
for i in $(seq 1 20); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && break; done
grep -qa "REPL-LIVE" "$LOG" || { echo "FAIL: listener goalc non connecte — rien ne serait execute"; exit 1; }

# L'ablation se pose APRES `(build-game)` : le rechargement a chaud reexecute les `define` et
# remettrait la valeur par defaut.
echo "(set! *ls-window-fix* $FIX)" >&3
echo '(format 0 "GLSW-JAMBE fix=~A~%" *ls-window-fix*)' >&3
sleep 2

echo "== A : save-geyser (chargement d'une sauvegarde a Geyser Rock) =="
echo '(set! *ls-window-label* "save-geyser")' >&3
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
sleep "${WAIT_A:-55}"
echo '(loading-window-close! "harnais")' >&3
sleep 3

echo "== B : teleport-sagehut (teleporteur Geyser Rock -> Hutte du Sage Vert) =="
# Etat de tache exige par la branche `sage-ecorocks` de target-continue (target-death.gc:186) :
# la cinematique ne se declenche que si `beach-ecorocks` est a need-hint ou need-introduction.
echo '(close-specific-task! (game-task intro) (task-status need-introduction))' >&3
echo '(close-specific-task! (game-task intro) (task-status need-reward-speech))' >&3
echo '(close-specific-task! (game-task intro) (task-status need-resolution))' >&3
echo '(close-specific-task! (game-task beach-ecorocks) (task-status need-hint))' >&3
echo '(open-specific-task! (game-task beach-ecorocks) (task-status need-introduction))' >&3
echo '(format 0 "GLSW-TACHE ecorocks=~D~%" (get-task-status (game-task beach-ecorocks)))' >&3
sleep 3
echo '(set! *ls-window-label* "teleport-sagehut")' >&3
echo '(start (quote play) (get-continue-by-name *game-info* "village1-warp"))' >&3
sleep "${WAIT_B:-75}"
echo '(loading-window-close! "harnais")' >&3
sleep 3

exec 3>&-
sleep 2
echo "---- FENETRE ----"
grep -aE "LSWIN|LSFRAME-BRUT|GLSW-" "$LOG"
echo "---- ECRAN DE CHARGEMENT ----"
grep -aE "LOADSCREEN-FRAME |LOADSCREEN-CONT|LOADGATE " "$LOG" | head -40
echo "---- log: $LOG ----"

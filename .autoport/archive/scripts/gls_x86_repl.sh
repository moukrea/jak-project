#!/usr/bin/env bash
# gls_x86_repl.sh — Gloading-screen : les deux chemins que l'owner nomme, mesures sur x86.
#   PHASE A  chargement de partie vers un AUTRE niveau (controle positif : le noir dure vraiment)
#   PHASE B  sage-intro-sequence-e a 30 fps FORCES, pour capturer le sort des acteurs harvester-*
# Pilotage par le REPL goalc sur FIFO : `goalc --cmd` compile sans listener et ne pilote pas le
# jeu ; `gk` n'accepte aucune commande de demarrage.
# NE JAMAIS reconstruire out/jak1/iso pendant qu'une course tourne : gk streame depuis ce dossier.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen"; mkdir -p "$OUT"
TAG="${1:-apres}"; FPS="${2:-30}"; MISS="${3:-0}"
LOG="$OUT/repl-$TAG.log"; GCLOG="$OUT/repl-$TAG-goalc.log"
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
echo "== attente de l'ecran titre =="
for i in $(seq 1 120); do
  grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && { echo "  titre a ~${i}s"; break; }
  sleep 1
done
sleep 3
echo "== goalc (lt) + (build-game) =="
timeout 1200 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 300); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game a ~${i}s"; break; }; done
sleep 3

echo "== PHASE A : chargement de partie vers un AUTRE niveau (game-start / Geyser Rock) =="
echo '(format 0 "REPL-PHASE A~%")' >&3
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
sleep 40

echo "== PHASE B : ${FPS} fps forces, beach-ecorocks/need-introduction, entree par village1-warp =="
echo '(format 0 "REPL-PHASE B~%")' >&3
echo "(set-frame-rate! *pc-settings* ${FPS} #t)" >&3
echo '(close-specific-task! (game-task intro) (task-status need-introduction))' >&3
echo '(close-specific-task! (game-task intro) (task-status need-reward-speech))' >&3
echo '(close-specific-task! (game-task intro) (task-status need-resolution))' >&3
echo '(close-specific-task! (game-task beach-ecorocks) (task-status need-hint))' >&3
echo '(open-specific-task! (game-task beach-ecorocks) (task-status need-introduction))' >&3
echo '(format 0 "REPL-TASK ecorocks=~D fps=~D~%" (get-task-status (game-task beach-ecorocks)) (-> *pc-settings* target-fps))' >&3
# CONTROLE POSITIF du rattrapage `alive` : forcer la premiere tentative a echouer, exactement comme
# la course le fait quand deux frames d'artiste tombent dans la meme frame de jeu.
if [ "$MISS" = "1" ]; then echo '(set! *alive-force-miss* #t)' >&3; echo '(format 0 "REPL-MISS force=~A~%" *alive-force-miss*)' >&3; fi
sleep 3
echo '(start (quote play) (get-continue-by-name *game-info* "village1-warp"))' >&3
sleep 100

exec 3>&-
sleep 2
echo "---- CHRONOLOGIE / BARRIERES ----"
grep -aE "REPL-PHASE|REPL-TASK|BOOTLINE|LOADGATE|LOADSCREEN-CONT" "$LOG"
echo "---- FRAMES NOIRES ----"
grep -a "BLACKCENSUS" "$LOG"
echo "---- SORT DES ACTEURS ----"
grep -aE "SCENECMD|REPL-MISS" "$LOG"
echo "---- log: $LOG ----"

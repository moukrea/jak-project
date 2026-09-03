#!/usr/bin/env bash
# gba_x86_repl.sh — Gbeach-actors-gate : le sort des acteurs de `beach` a l'ouverture de la
# barriere de scene, mesure sur x86.
#   PHASE A  chargement de partie (exerce continue-load-gate! + target-continue : 3 des 5 chemins)
#   PHASE B  sage-intro-sequence-e a 30 fps FORCES — la scene du retour de Geyser Rock
# Argument 3 : STRICT=0 => ABLATION, `(set! *scene-gate-strict* #f)` avant la scene. La barriere
# retombe sur le predicat d'avant ce cycle ('loaded) et la sonde publie quand meme son verdict :
# c'est le controle positif, et il est DETERMINISTE.
# Derive de .autoport/gls_x86_repl.sh (cycle Gloading-screen), meme pilotage FIFO.
# NE JAMAIS reconstruire out/jak1/iso pendant qu'une course tourne : gk streame depuis ce dossier.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gbeach-actors-gate"; mkdir -p "$OUT"
TAG="${1:-arme}"; FPS="${2:-30}"; STRICT="${3:-1}"
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

echo "== PHASE A : chargement de partie (game-start / Geyser Rock) =="
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
if [ "$STRICT" = "0" ]; then
  echo '(set! *scene-gate-strict* #f)' >&3
fi
echo '(format 0 "REPL-STRICT arme=~A ecorocks=~D fps=~D~%" *scene-gate-strict* (get-task-status (game-task beach-ecorocks)) (-> *pc-settings* target-fps))' >&3
sleep 3
echo '(start (quote play) (get-continue-by-name *game-info* "village1-warp"))' >&3
sleep 100

exec 3>&-
sleep 2
echo "---- BARRIERES ----"
grep -aE "REPL-PHASE|REPL-STRICT|LOADGATE|LOADSCREEN-CONT|SCENEGATE" "$LOG"
echo "---- ACTEURS ----"
grep -aE "SCENEACTOR|SCENECMD" "$LOG"
echo "---- FRAMES NOIRES / CONTROLES ----"
grep -aE "BLACKCENSUS|LOADSCREEN-CTRL" "$LOG"
echo "---- log: $LOG ----"

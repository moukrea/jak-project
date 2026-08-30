#!/usr/bin/env bash
# Gcine-vertical-frame — MESURE DU CHEMIN LIVRE, sur la cinematique que l'owner NOMME
# (teleporteur de Geyser Rock -> Hutte du Sage Vert = spool-anim `sage-intro-sequence-e`).
#
# Pilotage prouve, repris de .autoport/gls_x86_repl.sh : goalc en listener sur FIFO. Les
# close/open-specific-task! sont indispensables — `initialize! 'game` ouvre TOUTES les etapes,
# et sans elles `first-any` retomberait sur intro/need-introduction, donc sur `sage-intro-
# sequence-d1` (l'AUTRE cinematique du sage, celle qui precede Geyser Rock).
#
# NE JAMAIS reconstruire out/jak1/iso pendant la course : gk streame depuis ce dossier.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gcine-vertical-frame"; mkdir -p "$OUT"
TAG="${1:-avant}"
LEGACY="${2:-0}"   # 1 = rejouer la formule d'AVANT le correctif sur CE MEME binaire (ablation)
LOG="$OUT/x86-$TAG.log"; GCLOG="$OUT/x86-$TAG-goalc.log"
: > "$LOG"; : > "$GCLOG"

stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem 2>&1 \
  | stdbuf -oL python3 -u -c 'import sys,time
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

echo "== attente du demarrage de l'affichage =="
for i in $(seq 1 150); do grep -qa "BOOTLINE etape=" "$LOG" && { echo "  affichage a ~${i}s"; break; }; sleep 1; done
sleep 5
echo "== goalc (lt) + (build-game) =="
timeout 1800 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 420); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game a ~${i}s"; break; }; done
sleep 3

echo "== PHASE A : partie neuve -> Geyser Rock (game-start) =="
echo '(format 0 "GCVF-PHASE A~%")' >&3
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
sleep 45

echo "== PHASE B : etat de tache = beach-ecorocks/need-introduction, puis village1-warp =="
echo '(format 0 "GCVF-PHASE B~%")' >&3
echo '(close-specific-task! (game-task intro) (task-status need-introduction))' >&3
echo '(close-specific-task! (game-task intro) (task-status need-reward-speech))' >&3
echo '(close-specific-task! (game-task intro) (task-status need-resolution))' >&3
echo '(close-specific-task! (game-task beach-ecorocks) (task-status need-hint))' >&3
echo '(open-specific-task! (game-task beach-ecorocks) (task-status need-introduction))' >&3
echo '(format 0 "GCVF-TASK ecorocks=~D~%" (get-task-status (game-task beach-ecorocks)))' >&3
sleep 3
# Fenetre REDIMENSIONNABLE : le balayage de formats doit traverser la chaine livree
# (pc-get-window-size -> win-aspect -> set-aspect-ratio! -> update-math-camera -> rendu).
# En plein ecran SDL_SetWindowSize est sans effet, donc la course precedente a rendu cinq fois
# le MEME format -- une mesure qui ne discrimine rien.
echo "(pc-set-display-mode! (quote windowed) 1280 720)" >&3
sleep 4
echo '(format 0 "GCVF-DMODE ~A win=~Dx~D~%" (pc-get-display-mode) (-> *pc-settings* framebuffer-width) (-> *pc-settings* framebuffer-height))' >&3
sleep 2
[ "$LEGACY" = 1 ] && echo '(set! *cine-legacy-y* #t)' >&3
echo '(format 0 "GCVF-LEGACY ~A~%" *cine-legacy-y*)' >&3
sleep 2
echo '(set! *cine-sweep* #t)' >&3
echo '(format 0 "GCVF-SWEEP arme=~A~%" *cine-sweep*)' >&3
sleep 2
echo '(start (quote play) (get-continue-by-name *game-info* "village1-warp"))' >&3
sleep 140

exec 3>&-
sleep 3
echo "---- BRANCHE ----";   grep -a "CINEBRANCH" "$LOG" | head
echo "---- CINEVP ----";    grep -a "CINEVP" "$LOG" | head
echo "---- CINEFIT ----";   grep -a "CINEFIT" "$LOG"
echo "---- CINEWIDE ----";  grep -a "CINEWIDE" "$LOG"
echo "---- CINEVLOSS ----"; grep -a "CINEVLOSS" "$LOG"
echo "---- CINEBARS ----";  grep -a "CINEBARS" "$LOG"
echo "---- comptes ----"
echo "CINELIVE=$(grep -ac '^ *[0-9.]* CINELIVE ' "$LOG")  CINECTL=$(grep -ac '^ *[0-9.]* CINECTL ' "$LOG")"
grep -ao 'CINELIVE scene=[^ ]*' "$LOG" | sort | uniq -c | sort -rn | head
echo "---- log: $LOG ----"

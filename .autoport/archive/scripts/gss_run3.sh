#!/usr/bin/env bash
# Gsubtitle-style — course 3. Deux enseignements des courses precedentes, corriges ici :
#   1. `(lt)` seul ne charge AUCUN symbole du jeu dans goalc : il faut `(build-game)` ensuite
#      (course 05:50 : « No method or function named format for type int »).
#   2. `(send-event ... 'debug)` FIGE le jeu : son `:enter` fait `(set-master-mode 'pause)`,
#      apres quoi gk n'ecrit plus une ligne et la REPL sort en « Timed out waiting for ack »
#      (gk restait vivant, PID 1177721 -- ce n'est pas un plantage, c'est un blocage).
#      Et de toute facon `subtitle?` exige `*master-mode* = 'game` puisque `*debug-segment*`
#      vaut #f dans ce build : l'etat de debug ne pouvait PAS dessiner un sous-titre.
# On appelle donc le chemin de dessin LIVRE (`subtitle-format-into` + `subtitle-print-soft`,
# exactement les deux formes de `draw-subtitle`) sur une VRAIE ligne de `*subtitle-text*`,
# avec la police du process, laissee telle que `setup-subtitle-font` vient de la poser.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gsubtitle-style; mkdir -p "$OUT"
GOALC=build-x86/goalc/goalc; GK=build-x86/game/gk
ISO=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/gss-iso
LOCK=.autoport/.deploy-in-progress
printf 'gss_run3 pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
DRV="$OUT/run3.log"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }
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
LOG="$OUT/x86-run.log"; GCLOG="$OUT/x86-run-goalc.log"; : > "$LOG"; : > "$GCLOG"

say "gk sur la copie privee ($(md5sum "$SNAP/GAME.CGO" | cut -c1-12))"
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
for i in $(seq 1 180); do grep -qa "Waiting for listener" "$LOG" && break; sleep 1; done
sleep 30
say "gk : $(grep -ac 'link finish:' "$LOG") objets lies, die=$(grep -ac 'die\]' "$LOG")"

timeout 1200 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 6
echo '(build-game)' >&3
for i in $(seq 1 300); do grep -qa "Successfully built all" "$GCLOG" && { say "build-game a ~${i}s"; break; }; sleep 1; done
sleep 5

# forme unique, envoyee telle quelle : formatage des DEUX chaines puis dessin, comme draw-subtitle
DRAW='(when *subtitle-text* (let ((kf (-> *subtitle-text* data 0 keyframes 0))) (subtitle-format-into *subtitle-shadow-string* kf SUB_ESC_NONE SUB_ESC_NONE) (format 0 "GSS-CHAINES ombre=~S~%" *subtitle-shadow-string*) (subtitle-print-soft (subtitle-format (-> *subtitle* 0) kf) *subtitle-shadow-string* (-> *subtitle* 0 font))))'

echo '(format 0 "GSS-ETAT subtext=~A speaker=~A dbgseg=~A master=~A police=~D~%" *subtitle-text* (-> *pc-settings* subtitle-speaker?) *debug-segment* *master-mode* (-> *subtitle* 0 font color))' >&3
sleep 3
echo '(set! (-> *pc-settings* subtitle-speaker?) #t)' >&3
sleep 2
say "== dessin 1 : etat LIVRE (dup_alpha=0) =="
echo "$DRAW" >&3
sleep 8
echo '(format 0 "GSS-APRES1 vu=~D trace=~A~%" *subtitle-dup-shadow-seen* *subtitle-style-traced?*)' >&3
sleep 3

say "== dessin 2 : ABLATION, on rallume la duplication dure (dup_alpha=128) =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 128)' >&3
sleep 3
echo "$DRAW" >&3
sleep 8

say "== dessin 3 : retour a l'etat livre (dup_alpha=0) =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 0)' >&3
sleep 3
echo "$DRAW" >&3
sleep 8
echo '(format 0 "GSS-FIN~%")' >&3
sleep 5
say "== fin ; lignes SUB capturees : $(grep -acE '^SUB' "$LOG") ; gk vivant=$(pgrep -cf 'game/gk --game jak1' || echo 0) =="

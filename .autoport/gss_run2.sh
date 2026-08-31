#!/usr/bin/env bash
# Gsubtitle-style — course de mesure seule, sur la copie privee de l'iso deja faite.
# Correction par rapport a la course precedente : `(lt)` NE SUFFIT PAS. Un goalc neuf ne
# connait aucun symbole du jeu tant qu'il n'a pas compile l'arbre -- la course de 05:50 a
# rendu « No method or function named format for type int » sur `(format 0 ...)`, donc AUCUNE
# des formes de pilotage n'a ete evaluee. On fait donc `(lt)` PUIS `(build-game)`, comme les
# scripts de course des phases precedentes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gsubtitle-style; mkdir -p "$OUT"
GOALC=build-x86/goalc/goalc; GK=build-x86/game/gk
ISO=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/gss-iso
LOCK=.autoport/.deploy-in-progress
printf 'gss_run2 pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
DRV="$OUT/run2.log"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }
cleanup(){
  exec 3>&- 2>/dev/null || true
  P=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true); [ -n "$P" ] && kill "$P" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  [ -n "${GKW:-}" ] && kill "$GKW" 2>/dev/null
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
GKW=$!
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
for i in $(seq 1 300); do grep -qa "Successfully built all" "$GCLOG" && { say "build-game a ~${i}s (symboles charges)"; break; }; sleep 1; done
sleep 5

echo '(format 0 "GSS-ETAT subtext=~A subs=~A speaker=~A dbgseg=~A master=~A~%" *subtitle-text* (-> *pc-settings* subtitles?) (-> *pc-settings* subtitle-speaker?) *debug-segment* *master-mode*)' >&3
sleep 3
echo '(set! (-> *pc-settings* subtitles?) #t)' >&3
echo '(set! (-> *pc-settings* subtitle-speaker?) #t)' >&3
sleep 2
echo '(if *subtitle-text* (format 0 "GSS-TEXTE scenes=~D lignes0=~D~%" (length *subtitle-text*) (-> *subtitle-text* data 0 length)))' >&3
sleep 3
say "== etat subtitle-debug =="
echo '(send-event (-> *subtitle* 0) (quote debug))' >&3
sleep 12
echo '(format 0 "GSS-APRES want=~A vu=~D trace=~A prog=~A~%" (-> *subtitle* 0 want-subtitle) *subtitle-dup-shadow-seen* *subtitle-style-traced?* *progress-process*)' >&3
sleep 4

say "== repli : appeler le chemin de dessin sur une VRAIE ligne de sous-titre =="
echo '(when (and *subtitle-text* (not *subtitle-style-traced?*)) (let ((kf (-> *subtitle-text* data 0 keyframes 0))) (subtitle-format-into *subtitle-shadow-string* kf SUB_ESC_NONE SUB_ESC_NONE) (format 0 "GSS-REPLI ombre=~S~%" *subtitle-shadow-string*) (subtitle-print-soft (subtitle-format (-> *subtitle* 0) kf) *subtitle-shadow-string* (-> *subtitle* 0 font))))' >&3
sleep 6

say "== ablation (controle positif) : ombre DURE d'avant, dup_alpha=128 =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 128)' >&3
sleep 8
echo '(when (and *subtitle-text* (not *subtitle-style-traced?*)) (let ((kf (-> *subtitle-text* data 0 keyframes 0))) (subtitle-format-into *subtitle-shadow-string* kf SUB_ESC_NONE SUB_ESC_NONE) (subtitle-print-soft (subtitle-format (-> *subtitle* 0) kf) *subtitle-shadow-string* (-> *subtitle* 0 font))))' >&3
sleep 6

say "== retour a l'ombre floue, dup_alpha=0 =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 0)' >&3
sleep 6
echo '(when (and *subtitle-text* (not *subtitle-style-traced?*)) (let ((kf (-> *subtitle-text* data 0 keyframes 0))) (subtitle-format-into *subtitle-shadow-string* kf SUB_ESC_NONE SUB_ESC_NONE) (subtitle-print-soft (subtitle-format (-> *subtitle* 0) kf) *subtitle-shadow-string* (-> *subtitle* 0 font))))' >&3
sleep 6
echo '(format 0 "GSS-FIN~%")' >&3
sleep 5
say "== fin ; lignes SUB capturees : $(grep -acE '^SUB' "$LOG") =="

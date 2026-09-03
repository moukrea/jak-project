#!/usr/bin/env bash
# Gsubtitle-style — MESURE sur le chemin LIVRE, x86.
# Construit l'iso (les .o sont deja a jour), lance gk, entre dans l'etat `subtitle-debug`
# (dont le :trans repose `want-subtitle` a chaque image depuis `*subtitle-text*`) et capture
# les lignes SUBCOLOR / SUBSHADOW / SUBSCOPE que le chemin de dessin publie lui-meme.
#
# Verrou de livraison pris avec un PID VIVANT : ce script tourne en arriere-plan.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gsubtitle-style"; mkdir -p "$OUT"
LOG="$OUT/x86-run.log"; GCLOG="$OUT/x86-run-goalc.log"; ISOLOG="$OUT/x86-mi.log"
: > "$LOG"; : > "$GCLOG"; : > "$ISOLOG"

LOCK=.autoport/.deploy-in-progress
printf 'gss_x86_run pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"

echo "== (mi) : construction de l'iso =="
stdbuf -oL -eL timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi \
  --cmd '(mi)' >> "$ISOLOG" 2>&1
echo "MI-EXIT=$?" >> "$ISOLOG"
grep -q "MI-EXIT=0" "$ISOLOG" || { echo "!! (mi) a echoue, voir $ISOLOG"; rm -f "$LOCK"; exit 1; }

echo "== lancement de gk =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem >> "$LOG" 2>&1 &
GKWRAP=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){
  exec 3>&- 2>/dev/null || true
  P=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true); [ -n "$P" ] && kill "$P" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  kill "$GKWRAP" 2>/dev/null; wait 2>/dev/null; rm -f "$FIFO" "$LOCK"
}
trap cleanup EXIT

for i in $(seq 1 180); do grep -qa "BOOTLINE etape=\|\[Debugger\]\|nothing in kernel" "$LOG" && break; sleep 1; done
sleep 25

echo "== goalc listener =="
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 8

echo "== etat avant pilotage =="
echo '(format 0 "GSS-ETAT subtext=~A subs=~A speaker=~A dbgseg=~A master=~A prog=~A~%" *subtitle-text* (-> *pc-settings* subtitles?) (-> *pc-settings* subtitle-speaker?) *debug-segment* *master-mode* *progress-process*)' >&3
sleep 3
echo '(set! (-> *pc-settings* subtitles?) #t)' >&3
echo '(set! (-> *pc-settings* subtitle-speaker?) #t)' >&3
sleep 2
echo '(if *subtitle-text* (format 0 "GSS-TEXTE scenes=~D~%" (length *subtitle-text*)))' >&3
sleep 2
echo "== entree dans subtitle-debug (son :trans repose want-subtitle chaque image) =="
echo '(send-event (-> *subtitle* 0) (quote debug))' >&3
sleep 12
echo '(format 0 "GSS-APRES want=~A vu=~D trace=~A~%" (-> *subtitle* 0 want-subtitle) *subtitle-dup-shadow-seen* *subtitle-style-traced?*)' >&3
sleep 5

echo "== ablation : remettre l'ombre DURE d'avant (dup_alpha=128), puis la re-eteindre =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 128)' >&3
sleep 6
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 0)' >&3
sleep 6
echo '(format 0 "GSS-FIN~%")' >&3
sleep 4
echo "== fin =="

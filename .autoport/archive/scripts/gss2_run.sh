#!/usr/bin/env bash
# Gsubtitle-style-2 — MESURE sur le chemin LIVRE, x86.
# Quatre dessins dans LA MEME course :
#   1. etat livre                       -> offset_x/y ~ 0, passes_de_texte = 1
#   2. duplication du moteur REARMEE    -> passes_de_texte doit passer a 2 (controle positif)
#   3. biais de prises (-0,75 ; +1,50)  -> offset_x/y doit SUIVRE (controle positif)
#   4. retour a l'etat livre            -> on revient a 1 et a 0
# Enseignements du cycle 1, appliques : `(lt)` PUIS `(build-game)` ; gk sur une COPIE PRIVEE de
# l'iso ; verrou `.deploy-in-progress` avec un PID VIVANT ; jamais de `pgrep -f` sur un motif
# que nos propres shells contiennent.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gsubtitle-style-2; mkdir -p "$OUT"
GOALC=build-x86/goalc/goalc; GK=build-x86/game/gk
ISO=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/gss2-iso
LOCK=.autoport/.deploy-in-progress
printf 'gss2_run pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
DRV="$OUT/run-driver.log"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }
cleanup(){
  exec 3>&- 2>/dev/null || true
  for p in $(pgrep -x gk 2>/dev/null); do kill "$p" 2>/dev/null; done
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  rm -f "${FIFO:-/nonexistent}" "$LOCK"
}
trap cleanup EXIT
export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11

MILOG="$OUT/mi.log"; : > "$MILOG"
say "(mi) : cuisson de l'iso x86"
stdbuf -oL -eL timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi \
  --cmd '(mi)' >> "$MILOG" 2>&1
echo "MI-EXIT=$?" >> "$MILOG"
grep -q "MI-EXIT=0" "$MILOG" || { say "!! (mi) a echoue"; exit 1; }

rm -rf "$SNAP"; mkdir -p "$SNAP"
cp --reflink=auto -a "$ISO"/. "$SNAP"/
say "copie privee de l'iso : GAME.CGO $(md5sum "$SNAP/GAME.CGO" | cut -c1-12)"

LOG="$OUT/x86-run.log"; GCLOG="$OUT/x86-run-goalc.log"; : > "$LOG"; : > "$GCLOG"
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
for i in $(seq 1 180); do grep -qa "Waiting for listener" "$LOG" && break; sleep 1; done
sleep 30
say "gk : $(grep -ac 'link finish:' "$LOG") objets lies, die=$(grep -ac 'die\]' "$LOG")"

timeout 1500 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 6
echo '(build-game)' >&3
for i in $(seq 1 300); do grep -qa "Successfully built all" "$GCLOG" && { say "build-game a ~${i}s"; break; }; sleep 1; done
sleep 5

DRAW='(when *subtitle-text* (let ((kf (-> *subtitle-text* data 0 keyframes 0))) (subtitle-format-into *subtitle-shadow-string* kf SUB_ESC_NONE SUB_ESC_NONE) (format 0 "GSS-CHAINES ombre=~S~%" *subtitle-shadow-string*) (subtitle-print-soft (subtitle-format (-> *subtitle* 0) kf) *subtitle-shadow-string* (-> *subtitle* 0 font))))'

echo '(format 0 "GSS-ETAT subtext=~A speaker=~A dbgseg=~A master=~A police=~D~%" *subtitle-text* (-> *pc-settings* subtitle-speaker?) *debug-segment* *master-mode* (-> *subtitle* 0 font color))' >&3
sleep 3
echo '(set! (-> *pc-settings* subtitle-speaker?) #t)' >&3
sleep 2

say "== ce que la TABLE DU CYCLE 1 donnait REELLEMENT, une fois tronquee par le contexte =="
echo '(format 0 "GSS-ORIGINE ctx_ox=~f ctx_oy=~f tronque_ox=~f tronque_oy=~f~%%" (-> *subtitle* 0 font origin x) (-> *subtitle* 0 font origin y) (the float (the int (-> *subtitle* 0 font origin x))) (the float (the int (-> *subtitle* 0 font origin y))))' >&3
sleep 2
echo '(format 0 "GSS-CYCLE1 i=0 x_table=1.2 y_table=1.6 dx_dessine=~f dy_dessine=~f~%" (- (the float (the int (+ (-> *subtitle* 0 font origin x) 1.2))) (the float (the int (-> *subtitle* 0 font origin x)))) (- (the float (the int (+ (-> *subtitle* 0 font origin y) 1.6))) (the float (the int (-> *subtitle* 0 font origin y)))))' >&3
echo '(format 0 "GSS-CYCLE1 i=1 x_table=2.3 y_table=1.6 dx_dessine=~f dy_dessine=~f~%" (- (the float (the int (+ (-> *subtitle* 0 font origin x) 2.3))) (the float (the int (-> *subtitle* 0 font origin x)))) (- (the float (the int (+ (-> *subtitle* 0 font origin y) 1.6))) (the float (the int (-> *subtitle* 0 font origin y)))))' >&3
echo '(format 0 "GSS-CYCLE1 i=2 x_table=1.75 y_table=2.55 dx_dessine=~f dy_dessine=~f~%" (- (the float (the int (+ (-> *subtitle* 0 font origin x) 1.75))) (the float (the int (-> *subtitle* 0 font origin x)))) (- (the float (the int (+ (-> *subtitle* 0 font origin y) 2.55))) (the float (the int (-> *subtitle* 0 font origin y)))))' >&3
echo '(format 0 "GSS-CYCLE1 i=3 x_table=0.65 y_table=2.55 dx_dessine=~f dy_dessine=~f~%" (- (the float (the int (+ (-> *subtitle* 0 font origin x) 0.65))) (the float (the int (-> *subtitle* 0 font origin x)))) (- (the float (the int (+ (-> *subtitle* 0 font origin y) 2.55))) (the float (the int (-> *subtitle* 0 font origin y)))))' >&3
echo '(format 0 "GSS-CYCLE1 i=4 x_table=0.1 y_table=1.6 dx_dessine=~f dy_dessine=~f~%" (- (the float (the int (+ (-> *subtitle* 0 font origin x) 0.1))) (the float (the int (-> *subtitle* 0 font origin x)))) (- (the float (the int (+ (-> *subtitle* 0 font origin y) 1.6))) (the float (the int (-> *subtitle* 0 font origin y)))))' >&3
echo '(format 0 "GSS-CYCLE1 i=5 x_table=0.65 y_table=0.65 dx_dessine=~f dy_dessine=~f~%" (- (the float (the int (+ (-> *subtitle* 0 font origin x) 0.65))) (the float (the int (-> *subtitle* 0 font origin x)))) (- (the float (the int (+ (-> *subtitle* 0 font origin y) 0.65))) (the float (the int (-> *subtitle* 0 font origin y)))))' >&3
echo '(format 0 "GSS-CYCLE1 i=6 x_table=1.75 y_table=0.65 dx_dessine=~f dy_dessine=~f~%" (- (the float (the int (+ (-> *subtitle* 0 font origin x) 1.75))) (the float (the int (-> *subtitle* 0 font origin x)))) (- (the float (the int (+ (-> *subtitle* 0 font origin y) 0.65))) (the float (the int (-> *subtitle* 0 font origin y)))))' >&3
sleep 4


say "== dessin 1 : ETAT LIVRE =="
echo '(format 0 "GSS-DESSIN n=1 etat=livre~%")' >&3
echo "$DRAW" >&3
sleep 8

say "== dessin 2 : ABLATION, duplication du moteur REARMEE (dup_alpha=128) =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 128)' >&3
sleep 2
echo '(format 0 "GSS-DESSIN n=2 etat=dup-rearmee~%")' >&3
echo "$DRAW" >&3
sleep 8

say "== dessin 3 : BIAIS de prises (-0,75 ; +1,50), duplication de nouveau eteinte =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 0)' >&3
echo '(set! *subtitle-shadow-bias-x* -0.75)' >&3
echo '(set! *subtitle-shadow-bias-y* 1.5)' >&3
sleep 2
echo '(format 0 "GSS-DESSIN n=3 etat=biais~%")' >&3
echo "$DRAW" >&3
sleep 8

say "== dessin 4 : RETOUR a l'etat livre =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-shadow-bias-x* 0.0)' >&3
echo '(set! *subtitle-shadow-bias-y* 0.0)' >&3
sleep 2
echo '(format 0 "GSS-DESSIN n=4 etat=livre~%")' >&3
echo "$DRAW" >&3
sleep 8
echo '(format 0 "GSS-FIN~%")' >&3
sleep 5
say "== fin ; lignes SUB capturees : $(grep -acE '^SUB' "$LOG") ; gk vivant=$(pgrep -cx gk || echo 0) =="

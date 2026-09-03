#!/usr/bin/env bash
# Gsubtitle-style — TOUTE la mesure sous UN SEUL verrou de livraison tenu par un PID VIVANT.
#
# Pourquoi un seul verrou pour tout : `auto_build_apk.sh` reconstruit `out/jak1/iso` en ARM64
# des que les SOURCES changent (« sources changées → build arm64 cohérent », :348), et passe
# outre la fenetre libre au bout de 25 min (« patience depassee », :286). La course de 05:37
# a ete perdue exactement comme ca : gk a lu un GAME.CGO en cours de reecriture et est mort sur
# `Ptr<Type>` nul. Deux parades, cumulees :
#   1. le verrou, qu'il HONORE (:301-320) tant que le detenteur est vivant ;
#   2. gk tourne sur une COPIE privee de l'iso : meme si le verrou etait ignore, la course ne
#      peut plus etre corrompue.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gsubtitle-style; mkdir -p "$OUT"
GOALC=build-x86/goalc/goalc; GK=build-x86/game/gk
ISO=out/jak1/iso
SNAP=/home/emeric/.autoport-scratch/gss-iso
LOCK=.autoport/.deploy-in-progress
printf 'gss_measure pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
DRV="$OUT/measure.log"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }
cleanup(){
  exec 3>&- 2>/dev/null || true
  P=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true); [ -n "$P" ] && kill "$P" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  [ -n "${GKW:-}" ] && kill "$GKW" 2>/dev/null
  rm -f "${FIFO:-/nonexistent}" "$LOCK"
}
trap cleanup EXIT

say "verrou pose (pid=$$) AVANT toute attente : un nouveau cycle arm64 ne peut plus demarrer"
# ...puis on laisse finir celui qui tournait DEJA quand on a pose le verrou.
for i in $(seq 1 240); do
  n=$(ps -eo comm --no-headers | grep -cE '^(cmake|ninja|cc1plus|clang|aarch64-linux-android)' || true)
  [ "${n:-0}" -eq 0 ] && break
  sleep 15
done
sleep 20
say "arm64 libre ; constructeur : $(tail -1 .autoport/logs/auto_build_apk.txt)"

say "== CENSUS de perimetre (objets compiles, HEAD vs correctif) =="
bash .autoport/gss_scope_census.sh >> "$DRV" 2>&1 || say "!! census KO"

say "== (mi) : iso x86 coherente avec le correctif =="
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi --cmd '(mi)' > "$OUT/x86-mi.log" 2>&1
grep -q "Successfully built all" "$OUT/x86-mi.log" || { say "!! (mi) KO"; exit 1; }

say "== copie privee de l'iso (a l'abri du constructeur arm64) =="
rm -rf "$SNAP"; mkdir -p "$(dirname "$SNAP")"
cp -a --reflink=auto "$ISO" "$SNAP" || { say "!! copie KO"; exit 1; }
say "copie : $(du -sh "$SNAP" | cut -f1), GAME.CGO md5 $(md5sum "$SNAP/GAME.CGO" | cut -c1-12)"

export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11
LOG="$OUT/x86-run.log"; GCLOG="$OUT/x86-run-goalc.log"; : > "$LOG"; : > "$GCLOG"

say "== lancement de gk sur la copie =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
GKW=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
for i in $(seq 1 180); do grep -qa "Waiting for listener\|\[Debugger\]" "$LOG" && break; sleep 1; done
sleep 30
say "gk : $(grep -ac 'link finish:' "$LOG") objets lies, die=$(grep -ac 'die\]' "$LOG")"

timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 10
echo '(format 0 "GSS-ETAT subtext=~A subs=~A speaker=~A dbgseg=~A master=~A~%" *subtitle-text* (-> *pc-settings* subtitles?) (-> *pc-settings* subtitle-speaker?) *debug-segment* *master-mode*)' >&3
sleep 3
echo '(set! (-> *pc-settings* subtitles?) #t)' >&3
echo '(set! (-> *pc-settings* subtitle-speaker?) #t)' >&3
sleep 2
echo '(if *subtitle-text* (format 0 "GSS-TEXTE scenes=~D~%" (length *subtitle-text*)))' >&3
sleep 2
say "== entree dans subtitle-debug =="
echo '(send-event (-> *subtitle* 0) (quote debug))' >&3
sleep 15
echo '(format 0 "GSS-APRES want=~A vu=~D trace=~A~%" (-> *subtitle* 0 want-subtitle) *subtitle-dup-shadow-seen* *subtitle-style-traced?*)' >&3
sleep 5
say "== ablation : ombre DURE d'avant (dup_alpha=128) =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 128)' >&3
sleep 8
say "== retour a l'ombre floue (dup_alpha=0) =="
echo '(set! *subtitle-style-traced?* #f)' >&3
echo '(set! *subtitle-dup-shadow-alpha* 0)' >&3
sleep 8
echo '(format 0 "GSS-FIN~%")' >&3
sleep 5
say "== fin ; lignes SUB capturees : $(grep -acE '^SUB' "$LOG") =="

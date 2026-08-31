#!/usr/bin/env bash
# Gcutscene-skip-all — MESURE SUR LE CHEMIN LIVRE, x86.
#
# Deux courses de la MEME cinematique contextuelle de Geyser Rock ("orbcam", la camera
# d'introduction aux orbes -- levels/training/training-obs.gc:110) :
#   1. SANS le geste  -> controle negatif : `saut=echec`, la scene va au bout ;
#   2. AVEC le geste  -> `saut=ok`, et `images=` doit s'effondrer.
# C'est le RAPPORT des deux qui prouve la causalite, pas la valeur de l'une des deux.
#
# Le geste est injecte EN POSANT LE BIT CERCLE dans le mot de boutons du pad, en amont du
# `cpad-hold?` que le code livre execute : la lecture du pad, les deux secondes, le remplissage,
# l'armement du verrou et l'abandon dans la boucle de scene sont tous exerces tels quels.
#
# Verrou de livraison pris avec un PID VIVANT (ce script), et gk tourne sur une COPIE PRIVEE de
# l'iso : l'auto-constructeur peut reecrire out/jak1/iso sans tuer la course.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gcutscene-skip-all; mkdir -p "$OUT"
GOALC=build-x86/goalc/goalc; GK=build-x86/game/gk
ISO=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/gcs-iso
LOG="$OUT/x86-run.log"; GCLOG="$OUT/x86-run-goalc.log"; MILOG="$OUT/x86-mi.log"; DRV="$OUT/run.log"
: > "$LOG"; : > "$GCLOG"; : > "$MILOG"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }
probe(){
  echo '(let ((p (handle->process (-> *game-info* pov-camera-handle)))) (format 0 "CUTDIAG pov=~A etat=~A in=~A cablable=~A movie=~A~%" (if p 1 0) (if p (-> (the-as process p) state name) (quote nul)) *cutscene-in-cutscene* *cutscene-episode-skippable* (movie?)))' >&3
  sleep 3
}

LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  P=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then say "VERROU TENU par pid=$P — abandon"; exit 2; fi
fi
printf 'gcs_run pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"

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
stdbuf -oL -eL timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi \
  --cmd '(mi)' >> "$MILOG" 2>&1
echo "MI-EXIT=$?" >> "$MILOG"
grep -q "MI-EXIT=0" "$MILOG" || { say "!! (mi) a echoue, voir $MILOG"; exit 1; }

say "== copie privee de l'iso =="
rm -rf "$SNAP"; mkdir -p "$(dirname "$SNAP")"
cp -a --reflink=auto "$ISO" "$SNAP"
say "copie : GAME.CGO $(md5sum "$SNAP/GAME.CGO" | cut -c1-12)"

say "== lancement de gk sur la copie =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
for i in $(seq 1 240); do grep -qa "Waiting for listener" "$LOG" && break; sleep 1; done
sleep 25
say "gk : $(grep -ac 'link finish:' "$LOG") objets lies"

timeout 1500 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 6
echo '(build-game)' >&3
for i in $(seq 1 300); do grep -qa "Successfully built all" "$GCLOG" && { say "build-game a ~${i}s"; break; }; sleep 1; done
sleep 4

echo '(format 0 "CUTBOOT master=~A skip=~A commontext=~A lang=~D~%" *master-mode* (-> *pc-settings* skip-movies?) *common-text* (-> *pc-settings* text-language))' >&3
sleep 3

# --- CONTROLE POSITIF SUR LE CHEMIN `ja-play-spooled-anim` : la scene d'attract du titre joue
# --- ici. La course precedente l'a mesuree SANS geste (`saut=echec`, images=1244 et 3505) : c'est
# --- la ligne de base. On arme maintenant le geste sur la MEME famille de scene.
say "== POSITIF sur la scene du titre (chemin ja-play-spooled-anim) =="
echo '(set! *cutscene-skip-trace* #t)' >&3
echo '(set! *cutscene-skip-inject-circle* #t)' >&3
sleep 10
echo '(set! *cutscene-skip-inject-circle* #f)' >&3
sleep 4

say "== balayage des langues : la chaine localisee, RELUE par le chemin du jeu =="
echo '(dotimes (i 25) (when (and (!= i 17) (!= i 18)) (set! (-> *pc-settings* text-language) (the-as pc-language i)) (load-game-text-info "common" (quote *common-text*) *common-text-heap*) (format 0 "CUTLANG id=~D texte=~S~%" i (lookup-text! *common-text* (text-id pc-text-cutscene-skip) #t))))' >&3
sleep 20
echo '(set! (-> *pc-settings* text-language) (pc-language english))' >&3
echo '(load-game-text-info "common" (quote *common-text*) *common-text-heap*)' >&3
sleep 4

say "== chargement de Geyser Rock (training) =="
echo '(set! *cutscene-skip-trace* #t)' >&3
echo '(start (quote play) (get-continue-by-name *game-info* "game-start"))' >&3
sleep 60
echo '(format 0 "CUTLEVEL lev=~A target=~A sg=~A~%" (-> *level* level-default name) *target* *training-cam-sg*)' >&3
sleep 4

# ---------------------------------------------------------------------------------------------
# LES CINEMATIQUES CONTEXTUELLES DE GEYSER ROCK, DECLENCHEES PAR LE JEU LUI-MEME.
# On ne fabrique PAS la scene : on met Jak sur une `training-cam` et c'est son etat `idle`
# (levels/training/training-obs.gc:63) qui joue toute la sequence d'auteur -- indice vocal,
# saisie du joueur, reglage 'movie, puis `process-spawn pov-camera ... "orbcam"`.
# (Une creation de pov-camera A LA MAIN depuis la REPL fait mourir gk en SIGSEGV : mesure du
#  2026-08-31 07:12. Ce n'est pas le chemin du jeu, on ne s'en sert pas.)
# ---------------------------------------------------------------------------------------------
tcprobe(){
  echo '(let ((p (handle->process (-> *game-info* pov-camera-handle)))) (format 0 "CUTDIAG pov=~A in=~A cablable=~A movie=~A type=~A~%" (if p 1 0) *cutscene-in-cutscene* *cutscene-episode-skippable* (movie?) *cutscene-episode-type*))' >&3
  sleep 3
}
# Les acteurs de niveau portent le nom de leur ENTITE ("training-cam-3", ...), pas celui de leur
# type : `process-by-name "training-cam"` rend #f (mesure du 2026-08-31 07:2x). On cherche donc
# par TYPE dans l'arbre des processus actifs.
gotocam(){
  echo '(let ((tc (search-process-tree *active-pool* (lambda ((var process)) (type-type? (-> var type) training-cam))))) (format 0 "CUTTC tc=~A nom=~S idx=~D hints=~A~%" (if tc 1 0) (if tc (-> tc name) "nul") (if tc (-> (the-as training-cam tc) index) -1) (-> *setting-control* current play-hints)) (if tc (move-to-point! (-> *target* control) (-> (the-as training-cam tc) root trans))))' >&3
  sleep 4
}

say "== CONTEXTUELLE 1 : controle NEGATIF, sans le geste =="
gotocam
tcprobe; tcprobe; tcprobe; tcprobe; tcprobe; tcprobe; tcprobe; tcprobe

say "== on ecarte cette camera-la et on va sur la suivante =="
echo '(let ((tc (search-process-tree *active-pool* (lambda ((var process)) (type-type? (-> var type) training-cam))))) (if tc (deactivate tc)))' >&3
sleep 3

say "== CONTEXTUELLE 2 : la meme famille de scene AVEC le geste =="
echo '(set! *cutscene-skip-inject-circle* #t)' >&3
gotocam
tcprobe; tcprobe; tcprobe; tcprobe; tcprobe; tcprobe; tcprobe; tcprobe; tcprobe; tcprobe
echo '(set! *cutscene-skip-inject-circle* #f)' >&3
sleep 4

echo '(format 0 "CUTFIN gestes=~D abandons=~D~%" *cutscene-skip-count* *cutscene-skip-aborts*)' >&3
sleep 5
say "== fin ; lignes CUT capturees : $(grep -acE '^CUT' "$LOG") ; gk vivant=$(pgrep -cf 'game/gk --game jak1' || echo 0) =="
grep -aE '^CUT' "$LOG" | tee "$OUT/cut-lines.txt" | head -60

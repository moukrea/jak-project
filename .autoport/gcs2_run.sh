#!/usr/bin/env bash
# Gcutscene-skip-polish-2 — MESURE SUR LE CHEMIN LIVRE, x86, EN UNE COURSE.
#
# TROIS CHOSES SONT MESUREES, ET CHACUNE A SON CONTROLE :
#
#  D3  la cartouche dans le MENU PRINCIPAL. Deux bras sur LE MEME BINAIRE :
#        - livre     (`*cutscene-skip-loop-mark*` = #f) -> `CUTHORS`,        doit valoir 0 ;
#        - ablation  (= #t, marquage du cycle precedent) -> `CUTHORS-AVANT`, doit etre > 0.
#      Les deux bras couvrent « Press Start » ET le menu ouvert. Le denominateur (`images_titre`)
#      est publie : un zero obtenu sur zero image de titre ne dirait rien.
#      L'appui de bouton est INJECTE DANS LE PAD (`button0-rel`, HAUT), en amont du
#      `(cpad-pressed 0)` que le code livre execute -- c'est litteralement « l'owner touche un
#      bouton ». HAUT est inerte a « Press Start » (seul START y est lu) et ne fait que deplacer
#      le curseur dans le menu : la course ne peut pas partir ailleurs.
#
#  D1/D2 la FORME et les MARGES. La fenetre est portee a 1200x540, soit l'aspect 2,2222 --
#      EXACTEMENT celui du telephone (mesure `GAWIN win=2400x1080 win-asp=2.2222 scissor=2400x1080`,
#      Gcutscene-npc-flicker/device, 2026-09-01). La forme depend de l'aspect : la mesurer dans la
#      fenetre de 320x240 (qui n'est pas un choix mais le PLANCHER PC_MIN_WIDTH/HEIGHT) decrirait
#      un ecran que l'owner n'a pas.
#
#  ACQUIS le saut lui-meme : cinematique CONTEXTUELLE de Geyser Rock, avec le geste, comme au
#      cycle precedent -- c'est la que `CUTFILL`, `CUTSKIP` et les lignes de geometrie sont
#      relevees SOUS LE CODE LIVRE (les temoins one-shot sont reamorces juste avant).
#
# Verrou de livraison pris avec un PID VIVANT (ce script), et gk tourne sur une COPIE PRIVEE de
# l'iso : l'auto-constructeur peut reecrire out/jak1/iso sans tuer la course.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gcutscene-skip-polish-2; mkdir -p "$OUT"
GOALC=build-x86/goalc/goalc; GK=build-x86/game/gk
ISOSRC=iso_data/jak1; ISOOUT=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/gcs2-iso
LOG="$OUT/x86-run.log"; GCLOG="$OUT/x86-run-goalc.log"; MILOG="$OUT/x86-mi.log"; DRV="$OUT/run.log"
: > "$LOG"; : > "$GCLOG"; : > "$MILOG"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }
r(){ echo "$*" >&3; }
alive(){ pgrep -f "game/gk --game jak1 --portable -fakeiso" >/dev/null 2>&1; }
dbg(){ r '(format 0 "CUTDBG etat=~A progress=~D encinema=~A cablable=~A sortie=~Dx~D~%" (if (and *target* (-> *target* next-state)) (-> *target* next-state name) (quote nul)) (if *progress-process* 1 0) *cutscene-in-cutscene* *cutscene-episode-skippable* (-> *pc-settings* framebuffer-scissor-width) (-> *pc-settings* framebuffer-scissor-height))'; sleep 2; }

LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  P=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then say "VERROU TENU par pid=$P — abandon"; exit 2; fi
fi
printf 'gcs2_run pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"

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
stdbuf -oL -eL timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISOSRC" --disable-ansi \
  --cmd '(mi)' >> "$MILOG" 2>&1
echo "MI-EXIT=$?" >> "$MILOG"
grep -q "MI-EXIT=0" "$MILOG" || { say "!! (mi) a echoue, voir $MILOG"; exit 1; }

say "== copie privee de l'iso =="
rm -rf "$SNAP"; mkdir -p "$(dirname "$SNAP")"
cp -a --reflink=auto "$ISOOUT" "$SNAP"
say "copie : GAME.CGO $(md5sum "$SNAP/GAME.CGO" | cut -c1-12)"

say "== lancement de gk sur la copie =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
for i in $(seq 1 240); do grep -qa "Waiting for listener" "$LOG" && break; sleep 1; done
sleep 25
say "gk : $(grep -ac 'link finish:' "$LOG") objets lies"

timeout 2400 "$GOALC" --game jak1 --proj-path . --iso-path "$ISOSRC" --disable-ansi < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
r '(lt)'; sleep 6
r '(build-game)'
for i in $(seq 1 300); do grep -qa "Successfully built all" "$GCLOG" && { say "build-game a ~${i}s"; break; }; sleep 1; done
sleep 4

# --- LA FENETRE PREND L'ASPECT DE L'APPAREIL ---------------------------------------------------
say "== fenetre 1200x540 (aspect 2,2222, celui du telephone) =="
r '(set-window-size! *pc-settings* 1200 540)'
sleep 6
dbg

r '(format 0 "CUTBOOT master=~A skip=~A commontext=~A lang=~D~%" *master-mode* (-> *pc-settings* skip-movies?) *common-text* (-> *pc-settings* text-language))'
sleep 2

# --- ATTENDRE QUE LE TITRE SOIT A L'ECRAN ------------------------------------------------------
say "== attente de target-title-wait (titre affiche) =="
for i in $(seq 1 40); do
  dbg
  grep -qa 'CUTDBG etat=target-title-wait' "$LOG" && { say "titre affiche a ~$((i*4))s"; break; }
  sleep 2
done

# ================================================================================================
# D3 — LES DEUX BRAS, SUR LE MEME BINAIRE.
#
# L'ORDRE EST IMPOSE PAR UNE MESURE, PAS PAR LE CONFORT : `(current-time)` est
# `base-frame-counter`, et il S'ARRETE en pause (engine/draw/drawable.gc:1019, le bloc est sous
# `(when (not (paused?)))` ; le commentaire d'origine de display.gc:25 le dit deja : « This
# advances when the game is unpaused »). Menu ouvert, la fraicheur de la marque est donc GELEE :
# un episode ouvert avant l'ouverture du menu ne peut plus se fermer. La course de 04:15 l'a
# montre en grandeur nature -- le bras d'ablation avait ouvert un episode, et le bras LIVRE qui le
# suivait heritait de son verrou (`CUTHORS-MENU 838/838` avec `ablation=0`). Le bras livre passe
# donc EN PREMIER, sur un etat vierge.
# ================================================================================================
say "== D3 bras LIVRE : Press Start, puis MENU PRINCIPAL, sans rien avoir ouvert avant =="
r '(set! *cutscene-skip-loop-mark* #f)'
r '(cutscene-skip-hors-reset!)'
r '(set! *cutscene-skip-inject-press* (the int (pad-buttons up)))'
sleep 14
dbg
# `set-setting!` depuis la REPL tue gk (elle deref `pp`, settings-h.gc:149) : on ecrit le champ
# deja calcule et on appelle la meme fonction que `target-title-wait :trans` (title-obs.gc:838).
# `activate-progress` est un `defun`, appele ailleurs depuis un `defun` (`set-master-mode`,
# main.gc:1391) : il ne lit pas `self`.
r '(begin (set! (-> *setting-control* current allow-progress) #t) (activate-progress *dproc* (progress-screen title)))'
sleep 14
dbg
alive || { say "!! gk est mort a l'ouverture du menu"; exit 1; }
r '(cutscene-skip-hors-probe "")'
sleep 3

say "== D3 bras ABLATION, MENU OUVERT : le marquage du cycle precedent est retabli, MEME BINAIRE =="
r '(cutscene-skip-hors-reset!)'
r '(set! *cutscene-skip-inject-press* 0)'
r '(set! *cutscene-skip-loop-mark* #t)'
# L'INDICE N'EST PAS ARME TOUT DE SUITE : l'episode s'ouvre d'abord, et ces images-la comptent
# dans `images_sans_indice`. C'est le controle negatif de « l'indice apparait des qu'on touche UN
# bouton » -- armer le bouton a la premiere image le rendrait vide.
sleep 5
r '(set! *cutscene-skip-inject-press* (the int (pad-buttons up)))'
sleep 14
dbg
r '(cutscene-skip-hors-probe "-AVANT")'
sleep 3

say "== fermeture du menu, puis meme ablation a Press Start =="
r '(set-master-mode (quote game))'
sleep 6
r '(cutscene-skip-hors-reset!)'
sleep 12
dbg
r '(cutscene-skip-hors-probe "-PRESSSTART-AVANT")'
sleep 3
r '(set! *cutscene-skip-loop-mark* #f)'
r '(set! *cutscene-skip-inject-press* 0)'
sleep 3

# ================================================================================================
# LES LANGUES — la chaine localisee, RELUE par le chemin du jeu (CUTFIT).
# ================================================================================================
say "== balayage des langues =="
# `17COMMON.TXT` (coreen) et `18COMMON.TXT` (russe) N'EXISTENT PAS dans l'iso.
r '(dotimes (i 25) (when (and (!= i 17) (!= i 18)) (set! (-> *pc-settings* text-language) (the-as pc-language i)) (load-game-text-info "common" (quote *common-text*) *common-text-heap*) (format 0 "CUTLANG id=~D texte=~S~%" i (lookup-text! *common-text* (text-id pc-text-cutscene-skip) #t)) (cutscene-skip-fit-probe)))'
sleep 25
r '(set! (-> *pc-settings* text-language) (pc-language english))'
r '(load-game-text-info "common" (quote *common-text*) *common-text-heap*)'
sleep 4

# ================================================================================================
# LE SAUT LUI-MEME — cinematique CONTEXTUELLE de Geyser Rock, sous le code LIVRE.
# Les temoins one-shot sont reamorces : les lignes de geometrie de VERDICT viennent donc d'une
# VRAIE cinematique et non de l'ecran de titre.
# ================================================================================================
say "== reamorcage des temoins de geometrie, puis chargement de Geyser Rock =="
r '(set! *cutscene-shape-published* #f)'
r '(set! *cutscene-geom-published* #f)'
r '(set! *cutscene-quads-published* #f)'
r '(set! *cutscene-skip-trace* #t)'
r '(start (quote play) (get-continue-by-name *game-info* "game-start"))'
sleep 60
r '(format 0 "CUTLEVEL lev=~A target=~A sg=~A~%" (-> *level* level-default name) *target* *training-cam-sg*)'
sleep 4
dbg

gotocam(){
  r '(let ((tc (search-process-tree *active-pool* (lambda ((var process)) (type-type? (-> var type) training-cam))))) (format 0 "CUTTC tc=~A nom=~S idx=~D~%" (if tc 1 0) (if tc (-> tc name) "nul") (if tc (-> (the-as training-cam tc) index) -1)) (if tc (move-to-point! (-> *target* control) (-> (the-as training-cam tc) root trans))))'
  sleep 4
}
say "== CONTEXTUELLE 1 : controle NEGATIF -- l'indice apparait, le geste n'est PAS fait =="
gotocam
# L'indice n'est arme qu'APRES quelques images de cinematique : `apparait_sur_bouton` compte
# justement les images passees SANS indice avant la premiere. L'armer des la premiere image
# rendrait ce controle negatif vide.
dbg
r '(set! *cutscene-skip-inject-press* (the int (pad-buttons up)))'
for i in 1 2 3 4 5; do dbg; done
r '(set! *cutscene-skip-inject-press* 0)'
sleep 3

say "== on ecarte cette camera-la et on va sur la suivante =="
r '(let ((tc (search-process-tree *active-pool* (lambda ((var process)) (type-type? (-> var type) training-cam))))) (if tc (deactivate tc)))'
sleep 3

say "== CONTEXTUELLE 2 : la meme famille de scene AVEC le geste =="
r '(set! *cutscene-skip-inject-circle* #t)'
gotocam
for i in 1 2 3 4 5 6 7 8 9 10; do dbg; done
r '(set! *cutscene-skip-inject-circle* #f)'
sleep 4

r '(format 0 "CUTFIN gestes=~D abandons=~D natif=~D~%" *cutscene-skip-count* *cutscene-skip-aborts* *cutscene-native-true*)'
sleep 3
# Filet : si aucun indice n'a ete dessine, les lignes de douceur manqueraient. Meme fonction que
# le chemin de dessin, sur la meme geometrie.
r '(cutscene-skip-smooth-probe 78.0 (the float (cs-box-h)))'
sleep 3
say "== fin ; lignes CUT capturees : $(grep -acE '^CUT' "$LOG") ; gk vivant=$(pgrep -cf 'game/gk --game jak1' || echo 0) =="
grep -aE '^CUT' "$LOG" | tee "$OUT/cut-lines.txt" | tail -70

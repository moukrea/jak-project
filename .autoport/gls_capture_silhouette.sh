#!/usr/bin/env bash
# Gloading-screen — CAPTURE EN JEU de l'animation de course de Jak (+ Daxter), vue de cote,
# sur fond uni, image par image. Owner 2026-08-29 : « capturer cette animation in game (mets un
# fond vert ou whatever) en haute resolution ».
#
# TROIS MECANISMES EXISTANTS, AUCUN CODE NOUVEAU DANS LE JEU :
#   1. `OG_F1_WARP=1`            (game/kernel/jak1/kmachine.cpp:5057) fait apparaitre Jak au point
#                                de reprise `game-start` sans passer par le menu, et pose l'ANCRE
#                                du harnais de manette.
#   2. `OG_PAD_REPLAY_REPLAY`    (game/system/pad_replay.cpp:217) rejoue un fichier de manette
#                                INDEXE PAR FRAME DE LOGIQUE et FORCE un pas de temps fixe de
#                                1/60 s (:313-318). Sans ce pas fixe, la capture par image --
#                                qui ecroule le debit -- echantillonnerait l'animation n'importe
#                                comment. C'est ce qui rend la sequence exacte.
#   3. `AUTOPORT_SHOT_EVERY=1`   (game/graphics/pipelines/opengl.cpp:675) ecrit une PNG par image,
#                                a une resolution libre, en RE-RENDANT la frame a cette resolution
#                                (opengl.cpp:527-541) -- donc du vrai suréchantillonnage, pas un
#                                agrandissement.
#
# LA CAMERA EST `cam-orbit` (cam-states-dbg.gc:323), et ce choix EST le correctif d'un piege :
# elle se replace CHAQUE FRAME a `position de Jak + rayon.(sin rot, 0, cos rot)` et vise Jak.
# Avec le stick droit au repos, `rot` et `radius` ne bougent plus (:345-368 sont les seuls
# ecrivains). Jak reste donc EXACTEMENT au centre, A DISTANCE CONSTANTE, et comme il court vers
# la DROITE-CAMERA sa vitesse est perpendiculaire a l'axe de vue : la vue est laterale par
# CONSTRUCTION, sans avoir a viser un angle. Une camera fixe l'aurait laisse sortir du champ en
# une seconde et aurait fait varier sa taille de 7 % par perspective.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen"; SCR=".autoport/scratch"; mkdir -p "$OUT" "$SCR"
SHOTDIR="build-x86/game/OpenGOAL/jak1/screenshots"
DEMO="$SCR/run-right.padrp"

MODE="${1:-probe}"          # probe | full
if [ "$MODE" = "probe" ]; then
  EVERY=15; W=640; H=360; MSAA=1; START=0; STOP=99999999; WALL=90
else
  EVERY=1;  W=1920; H=1080; MSAA=2; START="${2:-5300}"; STOP="${3:-7000}"; WALL="${4:-330}"
fi
# Couleur de fond, en composantes GOAL (0x80 = 1.0, cf. `rhud-rgba 128 ...`).
# MAGENTA par defaut : l'incrustation doit separer le fond du SUJET, et le sujet porte du vert
# (les cheveux de Jak sont vert-jaune) et de l'orange (Daxter). Le magenta n'apparait sur aucun
# des deux, et la grandeur de separation `min(r,b) - g` y est maximale.
BGR="${BGR:-#x80}"; BGG="${BGG:-0}"; BGB="${BGB:-#x80}"
LOG="$OUT/capture-$MODE.log"; GCLOG="$OUT/capture-$MODE-goalc.log"
: > "$LOG"; : > "$GCLOG"
mkdir -p "$SHOTDIR"; rm -f "$SHOTDIR"/autoport_f*.png 2>/dev/null || true
[ -f "$DEMO" ] || { echo "FAIL: $DEMO absent (lance .autoport/mk_pad_demo.py)"; exit 1; }

echo "== gk : F1-WARP + rejeu de manette + capture (mode=$MODE ${W}x${H} every=$EVERY) =="
env OG_F1_WARP=1 OG_F1_WARP_DELAY="${WARPDELAY:-4800}" OG_PAD_REPLAY_REPLAY="$DEMO" \
    AUTOPORT_SHOT_EVERY="$EVERY" AUTOPORT_SHOT_START="$START" AUTOPORT_SHOT_STOP="$STOP" \
    AUTOPORT_SHOT_W="$W" AUTOPORT_SHOT_H="$H" AUTOPORT_SHOT_MSAA="$MSAA" \
    stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null || true
           kill "$GKPID" 2>/dev/null; [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
           wait 2>/dev/null; rm -f "$FIFO"; }
trap cleanup EXIT

# ATTENDRE QUE LE JEU ECOUTE AVANT (lt). Sans cette attente le socket du listener n'existe pas
# encore, `(lt)` echoue EN SILENCE, et goalc compile alors chaque forme avec `allow_emit=#f`
# (Compiler.cpp:132 : `allow_emit = m_listener.is_connected()`) : les formes sont acceptees, rien
# n'est envoye au jeu, et la seule trace est un avertissement generique. Mesure de la course
# precedente : 11 formes sur 11 « compilees », ZERO ligne CAPSETUP dans les 7045 lignes du jeu.
echo "== attente de l'ecran titre (le listener n'ecoute pas avant) =="
for i in $(seq 1 120); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk est mort"; tail -20 "$LOG"; exit 1; }
  grep -qaE "BOOTLINE etape=titre-affiche" "$LOG" && { echo "  titre a ~${i}s"; break; }
  sleep 1
done
sleep 3

echo "== goalc : (lt) + (build-game) =="
# (build-game) est OBLIGATOIRE avant toute commande : apres un simple (lt) le compilateur n'a
# AUCUN symbole du jeu -- meme `*target*` et `*camera*` sont inconnus (mesure de la course
# precedente : 9 formes sur 9 refusees avec « looked up as a global variable, but it does not
# exist »). L'ordre importe aussi : le warp F1 est retarde (OG_F1_WARP_DELAY) pour qu'il tombe
# APRES ce rechargement de code, sinon Jak courrait pendant qu'on recharge sous ses pieds.
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 300); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game a ~${i}s"; break; }
done
sleep 3
# CONTROLE DE VIVACITE, ET IL VIENT APRES (build-game) EXPRES. Avant lui le compilateur n'a AUCUN
# symbole du jeu -- meme `format` est refuse -- donc un controle place plus tot mesurerait le
# compilateur, pas la liaison. La seule preuve qu'une forme atteint le jeu est une ligne emise
# PAR LE JEU. Sans elle, goalc compile avec `allow_emit=#f` (Compiler.cpp:132) et jette
# silencieusement tout ce qu'on lui envoie : mesure d'une course precedente, 11 formes acceptees,
# ZERO effet, et la seule trace etait un avertissement generique.
echo '(format 0 "REPL-LIVE~%")' >&3
for i in $(seq 1 15); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && break; done
grep -qa "REPL-LIVE" "$LOG" || { echo "FAIL: le listener goalc n'est PAS connecte — rien ne serait execute"; exit 1; }
echo "  listener vivant (REPL-LIVE vu dans la sortie du JEU)"

echo "== attente de l'apparition de Jak (F1-SPAWN) =="
for i in $(seq 1 180); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk est mort"; tail -20 "$LOG"; exit 1; }
  grep -qa "F1-SPAWN" "$LOG" && { echo "  Jak apparu a ~${i}s"; break; }
  sleep 1
done
grep -qa "F1-SPAWN" "$LOG" || { echo "FAIL: pas de F1-SPAWN"; tail -30 "$LOG"; exit 1; }
grep -a "F1-SPAWN\|pad_replay: ANCHOR" "$LOG" | head -3
sleep 2
# FOND UNI : quand le bit `sky` est eteint, drawable.gc:806-818 dessine lui-meme un degrade plein
# ecran dans le bucket `sky-draw` (3), tres en amont des buckets merc (49/52/55) -- donc SOUS le
# personnage. Sa couleur est `(-> *display* bg-clear-color)`, une variable GOAL. `glClearColor`
# n'aurait pas convenu : il est en dur a (0,0,0) dans OpenGLRenderer.cpp:1344.
# Envoye DEUX FOIS et RELU : la premiere forme envoyee apres un chargement de niveau peut partir
# sans acquittement (« Timed out waiting for ack » observe au cycle precedent) et etre perdue.
for _ in 1 2; do
  echo "(dotimes (i 4) (set! (-> *display* bg-clear-color i) (new (quote static) (quote rgba) :r ${BGR} :g ${BGG} :b ${BGB} :a #xff)))" >&3
  sleep 2
done
echo '(format 0 "CAPBG=~D~%" (-> *display* bg-clear-color 0))' >&3
# On POSE le masque au lieu d'en retirer une liste : oublier un nom dans une liste laisse un
# rendu allume sans que rien ne le signale. Ici seuls `merc` et `generic` -- les deux chemins qui
# dessinent des personnages -- restent, tout le reste tombe par construction.
echo '(set! *vu1-enable-user-menu* (vu1-renderer-mask generic merc))' >&3
# CAMERA ORBITE VERROUILLEE SUR JAK, analogique coupe pour que rien ne derive.
echo '(set! *camera-read-analog* #f)' >&3
echo '(set! *camera-orbit-target* (the-as (pointer process-drawable) (process->ppointer *target*)))' >&3
echo '(set! (-> *camera-orbit-info* rot) 0.0)' >&3
echo "(set! (-> *camera-orbit-info* radius) ${CAMRAD:-24576.0})" >&3
echo "(set! (-> *camera-orbit-info* orbit-off y) ${CAMOFF:-4096.0})" >&3
echo "(set! (-> *camera-orbit-info* target-off y) ${CAMOFF:-4096.0})" >&3
echo '(send-event *camera* (quote change-state) cam-orbit 0)' >&3
sleep 2
# L'ANGLE SE POSE APRES LE CHANGEMENT D'ETAT, PAS AVANT : le `:enter` de `cam-orbit`
# (cam-states-dbg.gc:333-335) recalcule `rot` depuis la position courante de la camera et ecrase
# donc toute valeur posee plus tot. Le decalage sert a mettre hors champ un decor du niveau qui
# reste dessine (merc/generic restent allumes, il le faut pour Jak et Daxter) et qui touche la
# silhouette : 65536 = 360 degres.
echo "(+! (-> *camera-orbit-info* rot) ${CAMROTD:-0.0})" >&3
echo '(format 0 "CAPSETUP rot=~f rad=~f cible=~A~%" (-> *camera-orbit-info* rot) (-> *camera-orbit-info* radius) *camera-orbit-target*)' >&3
sleep 6
echo '(format 0 "CAPSETUP2 rot=~f rad=~f mask=~D~%" (-> *camera-orbit-info* rot) (-> *camera-orbit-info* radius) *vu1-enable-user*)' >&3

echo "== course + capture pendant ${WALL}s =="
END=$((SECONDS+WALL))
while [ $SECONDS -lt $END ]; do
  kill -0 "$GKPID" 2>/dev/null || { echo "  gk est mort"; break; }
  sleep 5
done
N=$(ls "$SHOTDIR"/autoport_f*.png 2>/dev/null | wc -l)
echo "== $N images dans $SHOTDIR =="
ls "$SHOTDIR"/autoport_f*.png 2>/dev/null | head -2
ls "$SHOTDIR"/autoport_f*.png 2>/dev/null | tail -2
grep -a "CAPSETUP\|CAPBG\|pad_replay" "$LOG" | head -6

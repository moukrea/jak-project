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
# LA CAMERA EST `cam-orbit` (cam-states-dbg.gc:323) : elle se replace CHAQUE FRAME a
# `position de Jak + rayon.(sin rot, 0, cos rot)` et vise Jak. Jak reste donc au centre, a
# distance constante, et la vue est laterale PAR CONSTRUCTION -- l'axe de vue est `row2` de la
# matrice de camera, le deplacement vaut `-row0` (chaine de signes verifiee de pad.gc:363 a
# math-camera.gc:168), et les deux sont orthogonaux quel que soit `rot`.
#
# TROIS CHOSES QUE LA COURSE PRECEDENTE N'AVAIT PAS FAITES, ET L'OWNER LES A VUES :
#   1. ELLE NE PUBLIAIT RIEN. `grep -c ANIM capture-full.log` rend ZERO : la planche a ete montee
#      sans qu'on sache une seule fois ce que Jak faisait. `*ls-capture-trace*` (allume plus bas)
#      publie desormais par frame l'animation, le MELANGE marche/course, la vitesse, l'abscisse
#      ecran d'un point place 1 m DEVANT lui, l'elevation de la camera et la focale.
#   2. LA FOCALE N'ETAIT PAS POSEE. `cam-orbit` n'ecrit jamais `fov` : elle heritait des 64 degres
#      par defaut, ce qui a 6 m deforme un corps de ~14 % entre son avant et son arriere. On pose
#      donc une focale etroite ET un rayon augmente d'autant : meme taille a l'ecran, profil
#      presque orthographique -- ce que la maquette de l'owner dessine.
#   3. L'AXE OPTIQUE VISAIT LES HANCHES. Mesure sur la planche precedente (silhouette.txt,
#      BOITE_COMMUNE sur 1080 lignes) : l'axe passait a 65 % de la hauteur du sujet en partant du
#      haut. On monte donc LES DEUX decalages ensemble -- monter un seul introduirait une vraie
#      plongee, alors que la vue est aujourd'hui rigoureusement horizontale (les deux `y`
#      s'annulent dans cam-states-dbg.gc:371-380).
#
# ET LE MIROIR DU MONTAGE EST RETIRE : le stick pousse a droite envoie Jak vers la DROITE de
# l'ecran, invariant en `rot`. C'est le miroir qui produisait le « ca va vers la gauche ».
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gloading-screen"; SCR=".autoport/scratch"; mkdir -p "$OUT" "$SCR"
SHOTDIR="build-x86/game/OpenGOAL/jak1/screenshots"
DEMO="$SCR/run-right.padrp"

MODE="${1:-probe}"          # probe | full
if [ "$MODE" = "probe" ]; then
  EVERY=15; W=640; H=360; MSAA=1; START=0; STOP=99999999; WALL="${4:-140}"
else
  EVERY=1;  W="${W:-1600}"; H="${H:-900}"; MSAA=2; START="${2:-5300}"; STOP="${3:-7000}"; WALL="${4:-330}"
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
# ------------------------------------------------------------------------------------------------
# ON CHANGE DE NIVEAU, ET C'EST UNE MESURE QUI L'IMPOSE.
# Le point de reprise du warp F1 est `game-start` = Geyser Rock, une petite ile. Sonde du
# 2026-08-30, trace `CAPRUN` : Jak n'y tient la vitesse de course pleine que **17 frames
# consecutives**, puis sa vitesse s'effondre a ~2 400 et y RESTE pendant 2 300 frames — il est
# plaque contre le decor et joue la marche SUR PLACE. Or le fondu marche/course monte a 2,0/s
# (target.gc:559) : il faut ~30 frames de vitesse pleine rien que pour atteindre la course pure,
# plus une periode de cycle. Le melange n'a donc jamais depasse **0,8459** sur toute la sonde.
# C'EST EXACTEMENT CE QUE L'OWNER A VU : « c'est plus de la marche ». Ce n'etait pas un mauvais
# choix d'animation, c'etait un personnage coince, et rien ne le publiait.
# `beach-start` (Sandover Beach) est une grande plage ouverte : la course peut y tenir.
echo "(start (quote play) (get-continue-by-name *game-info* \"${WARPTO:-beach-start}\"))" >&3
sleep "${WARPWAIT:-18}"
echo "(format 0 \"CAPWARP lev0=~A/~A lev1=~A/~A~%\" (-> *level* level0 name) (-> *level* level0 status) (-> *level* level1 name) (-> *level* level1 status))" >&3
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
echo "(set! (-> *camera-orbit-info* radius) ${CAMRAD:-57344.0})" >&3
# LES DEUX DECALAGES ENSEMBLE : l'elevation reste nulle, seule la hauteur visee monte.
echo "(set! (-> *camera-orbit-info* orbit-off y) ${CAMOFF:-5400.0})" >&3
echo "(set! (-> *camera-orbit-info* target-off y) ${CAMOFF:-5400.0})" >&3
echo '(send-event *camera* (quote change-state) cam-orbit 0)' >&3
sleep 2
# L'ANGLE SE POSE APRES LE CHANGEMENT D'ETAT, PAS AVANT : le `:enter` de `cam-orbit`
# (cam-states-dbg.gc:333-335) recalcule `rot` depuis la position courante de la camera et ecrase
# donc toute valeur posee plus tot. Le decalage sert a mettre hors champ un decor du niveau qui
# reste dessine (merc/generic restent allumes, il le faut pour Jak et Daxter) et qui touche la
# silhouette : 65536 = 360 degres.
echo "(+! (-> *camera-orbit-info* rot) ${CAMROTD:-0.0})" >&3
# FOCALE ETROITE + RAYON AUGMENTE D'AUTANT. 30 degres a 14 m couvrent la meme hauteur d'ecran que
# 64 degres a 6 m (tan 32 / tan 15 = 2,33), et l'ecart d'echelle avant/arriere d'un corps tombe de
# ~14 % a ~2 %. `set-fov` propage a tous les esclaves (cam-master.gc:611-614) ; la trace publie
# `fov=` a chaque frame, donc si quelque chose la repose on le VOIT au lieu de le supposer.
echo "(send-event *camera* (quote set-fov) (degrees ${CAMFOV:-30.0}))" >&3
sleep 1
# L'INSTRUMENT. Sans lui, aucune des quatre grandeurs que l'owner conteste n'est mesuree.
echo '(set! *ls-capture-trace* #t)' >&3
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
echo "== CE QUE LE SUJET FAISAIT (extraits de la trace) =="
grep -a "CAPRUN" "$LOG" | tail -3
grep -a "CAPVUE" "$LOG" | tail -3
echo "  frames a MELANGE plein (course pure, melange >= 0.99) : $(grep -ac 'melange=1\.0' "$LOG")"
echo "  frames tracees au total                               : $(grep -ac 'CAPRUN' "$LOG")"

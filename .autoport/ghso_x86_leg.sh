#!/usr/bin/env bash
# Ghd-skin-origin-stretch — UNE JAMBE DE CAMPAGNE x86.
#
#   ARM=0  garde DESARME  -> bras de CONTROLE : le defaut d'origine
#   ARM=1  garde ARME     -> bras de PREUVE   : meme binaire, meme instrument, meme itineraire
#
# Les deux bras tournent sur LE MEME BINAIRE : ce qui change est un symbole GOAL (`*hd-guard-arm*`),
# pose depuis la REPL. C'est ce qui rend le `episodes=0` du bras ARME falsifiable.
#
# ITINERAIRE : 28 points de reprise couvrant 135 m a 5541 m de l'ORIGINE DU MONDE (distances
# recalculees depuis goal_src/jak1/engine/level/level-info.gc). C'est cet axe qui porte la
# correlation demandee.
#
# ROBUSTESSE DE L'ECOUTEUR (paye au premier essai) : un `(start 'play ...)` qui echoue laisse la
# REPL desynchronisee (« Timed out waiting for ack ») et TOUTES les commandes suivantes sont
# perdues EN SILENCE — la course a tourne 13 minutes sans jamais charger un niveau. Deux parades :
#   (1) chaque chargement est CONFIRME dans le journal de gk avant de continuer ;
#   (2) la sante de l'ecouteur est verifiee a chaque niveau et il est RELANCE s'il est mort.
# Et surtout : les compteurs sortent du battement de coeur GOAL (HDHB, automatique), pas de sondes
# REPL — meme ecouteur mort, la mesure continue.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Ghd-skin-origin-stretch; mkdir -p "$OUT"
GOALC=build-x86/goalc/goalc; GK=build-x86/game/gk
ISO="${ISO:-out/jak1/iso}"; SNAP=/home/emeric/.autoport-scratch/ghso-iso
SETTINGS=build/game/OpenGOAL/jak1/settings/settings.ini
ARM="${ARM:-1}"; TAG="${TAG:-leg$ARM}"; DWELL="${DWELL:-14}"; LOADW="${LOADW:-15}"
LOG="$OUT/$TAG.log"; GCLOG="$OUT/$TAG-goalc.log"; DRV="$OUT/$TAG-driver.log"
: > "$LOG"; : > "$GCLOG"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }

LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  P=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null && ! grep -q '^ghso' "$LOCK"; then
    say "VERROU TENU par pid=$P (pas le notre) — abandon"; exit 2
  fi
fi
printf 'ghso_leg pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"

cp -f "$SETTINGS" "$SETTINGS.ghso-bak"
cleanup(){
  exec 3>&- 2>/dev/null || true
  [ -n "${GKPID:-}" ] && kill "$GKPID" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  sleep 1
  [ -f "$SETTINGS.ghso-bak" ] && mv -f "$SETTINGS.ghso-bak" "$SETTINGS"
  rm -f "${FIFO:-/nonexistent}" "$LOCK"
}
trap cleanup EXIT

for kv in "game-size = 640 480" "render-scale = 25.0000" "min-render-scale = 25.0000" \
          "recharged-grass? = #f" "pbr-materials? = #f" "physics-quality = 0" \
          "recharged-enhanced-models? = #t" "hd-look-jak = 1" "hd-look-daxter = 1" \
          "hd-look-keira = 1" "hd-look-samos = 1" "vsync = #f"; do
  k="${kv%% =*}"; sed -i "s/^$(printf '%s' "$k" | sed 's/[][\.*^$\/?]/\\&/g') = .*/$kv/" "$SETTINGS"
done
for c in jak dax keira samos jak2 jak3 daxp keira3 ysamos jakm jakp; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ 2>/dev/null
done

say "== copie privee de l'iso =="
rm -rf "$SNAP"; mkdir -p "$(dirname "$SNAP")"
cp -a --reflink=auto "$ISO" "$SNAP"
cp -f out/jak1/obj/*-hd-ag.go "$SNAP/" 2>/dev/null
say "GAME.CGO $(md5sum "$SNAP/GAME.CGO" | cut -c1-12)  art-groups HD: $(ls "$SNAP"/*-hd-ag.go | wc -l)"

export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

say "== gk (bras ARM=$ARM) =="
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
GKPID=$!
for i in $(seq 1 240); do grep -qa "Waiting for listener" "$LOG" && break; sleep 1; done
sleep 20

FIFO=""
start_listener(){
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  exec 3>&- 2>/dev/null || true
  rm -f "${FIFO:-/nonexistent}"
  FIFO="$(mktemp -u)"; mkfifo "$FIFO"
  timeout 3000 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi < "$FIFO" >> "$GCLOG" 2>&1 &
  GCPID=$!
  exec 3>"$FIFO"
  # DEUX CHOSES DISTINCTES, ET LES CONFONDRE A COUTE TROIS COURSES :
  #  - `(build-game)` N'EST PAS UNE LIVRAISON. Il compile vers out/jak1/obj alors que le jeu
  #    tourne sur les CGO de l'iso. Mesure (2026-09-02 05:23) : out/jak1/iso/GAME.CGO datait de
  #    04:46, AVANT toute edition du jour, et zero ligne HDHB3/HDEPV sur deux courses completes.
  #    C'est la campagne qui bat et fige l'iso, pas le listener.
  #  - MAIS `(build-game)` RESTE INDISPENSABLE : sans lui, goalc n'a ni table des symboles ni
  #    table des types du jeu, donc `(set! *hd-guard-arm* ...)`, `(hd-stretch-reset!)` et
  #    `(start 'play ...)` ne COMPILENT PAS chez lui et ne sont JAMAIS envoyees. Course de 05:32 :
  #    aucun HDRESET, aucun niveau charge, et les 22 episodes portaient tous `racine_m=238,9985`
  #    — la position de `title-start`. Le jeu etait reste sur l'ecran-titre pendant toute la
  #    course, sans qu'aucun compteur ne s'en plaigne.
  echo '(lt)' >&3; sleep 6
  local before; before=$(grep -ac "Successfully built all" "$GCLOG")
  echo '(build-game)' >&3
  for i in $(seq 1 400); do
    [ "$(grep -ac 'Successfully built all' "$GCLOG")" -gt "$before" ] && { say "  listener pret a ~${i}s"; return 0; }
    sleep 1
  done
  say "  !! listener non pret"
  return 1
}
listener_dead(){ [ "$(grep -ac 'Runtime is not responding' "$GCLOG")" -gt "${ACKS:-0}" ]; }

start_listener
ACKS=$(grep -ac 'Runtime is not responding' "$GCLOG")
sleep 3

AS=1; [ "$ARM" = 0 ] && AS=0
echo "(set! *hd-guard-arm* $AS)" >&3; sleep 3

if [ -n "${LEVELS_OVERRIDE:-}" ]; then
  read -r -a LEVELS <<< "$LEVELS_OVERRIDE"
else
LEVELS=(beach-start firecanyon-start village1-hut village1-warp jungle-start jungle-tower
        misty-start misty-silo misty-bike misty-backside firecanyon-end village2-start
        rolling-start training-start game-start village2-dock sunken-start ogre-start
        swamp-start sunken-tube1 swamp-cave2 darkcave-start robocave-start maincave-start
        snow-start village3-start village3-farside lavatube-start lavatube-middle citadel-warp
        lavatube-end citadel-entrance citadel-start finalboss-start)
fi

# premier niveau AVANT d'ouvrir la fenetre : l'episode du passage titre->jeu n'a pas de position
# monde (le pilote est encore a l'origine) et ne doit pas polluer la mesure.
# CONFIRMATION DE CHARGEMENT — le marqueur utilise au premier essai (`GAMEPLAY: enter <niveau>`)
# n'est emis QUE pour `title` : les 34 chargements sortaient donc tous `charge=0` et attendaient les
# 45 s pleines. Le marqueur qui tire VRAIMENT a chaque chargement de niveau est la ligne de
# consolidation de maillage du moteur (`[global-weld] level=<nom>` / `[mesh-consolidate] level=`).
WELD_RE='\[(global-weld|mesh-consolidate)\] level='
weldn(){ grep -acE "$WELD_RE" "$LOG"; }
n0=$(weldn)
echo "(start (quote play) (get-continue-by-name *game-info* \"beach-start\"))" >&3
for i in $(seq 1 45); do [ "$(weldn)" -gt "$n0" ] && break; sleep 1; done
sleep 10
say "amorce : beach welds=$(weldn) (avant $n0)"

echo '(hd-stretch-reset!)' >&3; sleep 5
# GARDE DURE : `HDRESET` est imprime PAR LE JEU a la reception de la commande. S'il n'apparait pas,
# la REPL ne parle pas au jeu et TOUT ce qui suit est du bruit — c'est exactement ce qui s'est
# produit a 05:32 (aucun niveau charge, 22 episodes releves sur l'ecran-titre). On refuse la course
# au lieu de publier ses chiffres.
if ! grep -qa '^HDRESET' "$LOG"; then
  say "!! HDRESET absent — la REPL n'atteint pas le jeu, jambe ABANDONNEE"
  exit 3
fi
say "  fenetre ouverte, garde arme=$(grep -a '^HDRESET' "$LOG" | tail -1)"
NLOAD=0
T0=$(date +%s)
say "== FENETRE DE MESURE OUVERTE =="

for lv in "${LEVELS[@]}"; do
  kill -0 "$GKPID" 2>/dev/null || { say "!! gk mort a $lv"; break; }
  if listener_dead; then
    say "  ecouteur mort — relance"
    ACKS=$(grep -ac 'Runtime is not responding' "$GCLOG")
    start_listener || break
    ACKS=$(grep -ac 'Runtime is not responding' "$GCLOG")
  fi
  n0=$(weldn)
  echo "(format 0 \"HDLEVEL nom=~S~%\" \"$lv\")" >&3
  echo "(start (quote play) (get-continue-by-name *game-info* \"$lv\"))" >&3
  ok=0
  for i in $(seq 1 "$LOADW"); do
    [ "$(weldn)" -gt "$n0" ] && { ok=1; break; }
    sleep 1
  done
  sleep "$DWELL"
  NLOAD=$((NLOAD + ok))
  say "  $lv charge=$ok ep=$(grep -ac '^HDEPISODE' "$LOG")"
done
# SECONDE GARDE DURE : une jambe ou presque aucun niveau n'a charge n'a pas parcouru l'itineraire,
# donc ses compteurs ne decrivent pas ce qu'on croit. La course du 05:32 rendait charge=0 sur les
# 34 points de reprise et personne ne l'avait vu passer.
say "niveaux effectivement charges : $NLOAD / ${#LEVELS[@]}"
if [ "$NLOAD" -lt $(( ${#LEVELS[@]} / 2 )) ]; then
  say "!! moins de la moitie des niveaux charges — jambe NON CONCLUANTE"
fi

T1=$(date +%s)
sleep 3
kill "$GKPID" 2>/dev/null; wait "$GKPID" 2>/dev/null

SECS=$((T1 - T0))
{ echo "HDWALL secondes=$SECS minutes=$(python3 -c "print(f'{$SECS/60:.4f}')") arme=$ARM"; } >> "$LOG"
say "== fenetre : ${SECS}s ; episodes=$(grep -ac '^HDEPISODE' "$LOG") =="
grep -aE '^(HDEPISODE|HDEPX|HDEPY|HDEPZ|HDEPV|HDEPW|HDHB|HDHB2|HDHB3|HDBIND|HDDRV|HDPOSD|HDLEVEL|HDRESET|HDWALL)' "$LOG" > "$OUT/$TAG-marqueurs.txt"
say "marqueurs -> $OUT/$TAG-marqueurs.txt ($(wc -l < "$OUT/$TAG-marqueurs.txt") lignes)"

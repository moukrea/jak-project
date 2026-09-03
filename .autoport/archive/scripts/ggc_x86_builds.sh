#!/usr/bin/env bash
# ggc_x86_builds.sh — Ggrass-crash : N CONSTRUCTIONS DU CHAMP D'HERBE dans une seule course x86.
#
#   Usage : ggc_x86_builds.sh <on|off> <constructions> <etiquette> [pre=on|off]
#
# POURQUOI CE HARNAIS EXISTE, ET C'EST UNE MESURE, PAS UN CHOIX DE CONFORT.
# `ggc_x86_cycles.sh` comptait des CHARGEMENTS DE NIVEAU. Mesure du 2026-08-30 21:08 sur la course
# `c1-on-live` : 9 chargements de `training` (`link finish: trainingcam` x9) pour **UNE SEULE**
# ligne `PLACE-TIME`. Le `LevelData` est REUTILISE d'un chargement a l'autre, donc
# `render()` ne redeclenche pas `rebuild()` (`GrassRenderer.cpp:1200-1204` : la cle de cache est
# `ld->level.get()` + `ld->load_id`). Douze chargements ne prouvaient donc qu'UNE construction :
# compter des chargements, c'est compter la mauvaise chose.
#
# CE QU'ON COMPTE ICI EST LA GRANDEUR QUI PORTE LE DEFAUT : le nombre de fois ou l'etape de
# CONSOMMATION de `GrassRenderer::rebuild()` s'execute jusqu'au bout — c'est ELLE qui tombait hors
# de la fonction et sautait dans `_Unwind_Resume` sur arm64. Une construction = une ligne
# `PLACE-TIME`, et chaque cycle EXIGE que le compteur monte, sinon la course echoue au lieu de
# passer en silence.
#
# COMMENT ON FORCE UNE CONSTRUCTION SANS RECHARGER LE NIVEAU : le curseur de DENSITE est une cle
# de cache (`m_cached_density != Gfx::g_global_settings.recharged_grass_density`,
# GrassRenderer.cpp:1202) et il est pousse a CHAQUE IMAGE depuis `*pc-settings*`
# (hud-classes-pc.gc:1828-1832). Le bouger est donc un geste de JOUEUR — c'est le meme curseur
# que l'owner deplace dans son menu Recharged — et il rejoue exactement le meme chemin.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
HERBE="${1:-on}"; NBUILD="${2:-12}"; TAG="${3:-builds}"; PRE="${4:-on}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Ggrass-crash"; mkdir -p "$OUT"
SETTINGS="build-x86/game/OpenGOAL/jak1/settings/settings.ini"
export DISPLAY="${DISPLAY:-:0}" SDL_VIDEODRIVER=x11
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.2UGBV3}"
LOG="$OUT/$TAG.log"; GCLOG="$OUT/$TAG-goalc.log"; RSS="$OUT/$TAG.rss"; VERD="$OUT/$TAG.verdict"
: > "$LOG"; : > "$GCLOG"; : > "$RSS"; : > "$VERD"

# PROVENANCE — publiee AVANT la course. Sans elle on ne saurait pas sur quel binaire ni sur
# quelles donnees la mesure a tourne. 92176 = KERNEL.CGO x86 ; 159664 = l'etage arm64 transitoire
# de l'auto-constructeur, sur lequel toute course x86 est un FAUX ROUGE.
KSZ=$(stat -c %s "$ISO/KERNEL.CGO" 2>/dev/null || echo 0)
GKMD5=$(md5sum "$GK" | cut -c1-12)
echo "PROVENANCE kernel_cgo_octets=$KSZ (92176=x86) gk_md5=$GKMD5 date=$(date -Is)"
[ "$KSZ" = 92176 ] || { echo "FAIL: out/jak1/iso n'est PAS x86 (KERNEL.CGO=$KSZ) — course refusee"; exit 1; }

[ -f "$SETTINGS" ] || { echo "FAIL: pas de settings.ini a $SETTINGS"; exit 1; }
sed -i "s/^version = .*/version = #x1000B00000000/" "$SETTINGS"
G='#t'; [ "$HERBE" = off ] && G='#f'
P='#t'; [ "$PRE"   = off ] && P='#f'
sed -i "s/^recharged-grass? = .*/recharged-grass? = $G/" "$SETTINGS"
sed -i "s/^recharged-grass-precomputed? = .*/recharged-grass-precomputed? = $P/" "$SETTINGS"
sed -i "s/^recharged-grass-density = .*/recharged-grass-density = 150.0000/" "$SETTINGS"
grep -qE "^recharged-grass\? = $G\$" "$SETTINGS" || { echo "FAIL: herbe non appliquee"; exit 1; }
echo "== herbe=$HERBE precomputed=$PRE constructions demandees=$NBUILD =="

stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem 2>&1 \
  | stdbuf -oL python3 -u -c 'import sys,time
t0=time.time()
for l in sys.stdin:
    sys.stdout.write("%9.3f %s" % (time.time()-t0, l))' >> "$LOG" &
PIPEPID=$!
sleep 2
GKPID=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true)
[ -n "$GKPID" ] || { echo "FAIL: gk n'a pas demarre"; exit 1; }
echo "  gk pid=$GKPID"
( while [ -d "/proc/$GKPID" ]; do
    r=$(awk '/^VmRSS/{print $2}' /proc/$GKPID/status 2>/dev/null)
    printf '%s %s\n' "$(date +%s)" "${r:-0}" >> "$RSS"; sleep 1
  done ) &
RSSPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){
  exec 3>&- 2>/dev/null || true
  kill "$RSSPID" 2>/dev/null
  [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null
  P=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true); [ -n "$P" ] && kill "$P" 2>/dev/null
  sleep 1; kill "$PIPEPID" 2>/dev/null; rm -f "$FIFO"
}
trap cleanup EXIT

echo "== attente du titre (BOOTLINE etape=titre-affiche) =="
titre=0
for i in $(seq 1 240); do
  [ -d "/proc/$GKPID" ] || { echo "FAIL: gk mort avant le titre (t+${i}s)"; break; }
  grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && { titre=1; echo "  titre a t+${i}s"; break; }
  sleep 1
done
[ "$titre" = 1 ] || { echo "FAIL: pas de titre"; exit 1; }
sleep 3
timeout 3600 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
# `(lt)` SEUL NE SUFFIT PAS, et le silence qu'il produit ressemble a une panne du jeu :
# goalc n'a AUCUN symbole du jeu tant que `(build-game)` n'a pas tourne, donc `(format ...)`
# repond « No method or function named format for type int » et la course s'arrete sur un
# « listener non connecte » alors que le listener EST connecte (`[DECI2] Connected!`).
# Recette eprouvee du depot : .autoport/gcvf_x86_run.sh:46-48.
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 420); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game a ~${i}s"; break; }; done
sleep 3
live=0
for att in 1 2 3; do
  echo "(format 0 \"REPL-LIVE~%\")" >&3
  for i in $(seq 1 15); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && { live=1; break; }; done
  [ "$live" = 1 ] && { echo "  REPL vivant (tentative $att)"; break; }
  echo '(lt)' >&3; sleep 5
done
[ "$live" = 1 ] || { echo "FAIL: listener goalc non connecte — rien ne serait execute"; exit 1; }

# `grep -c` IMPRIME DEJA `0` et SORT EN 1 quand il ne trouve rien : le `|| echo 0` ajoutait
# un SECOND zero, la substitution rendait "0\n0", et tout `[ ... -gt ... ]` echouait avec
# « nombre entier attendu ». `head -1` clot la question.
nplace(){ grep -ac 'PLACE-TIME' "$LOG" 2>/dev/null | head -1; }
died=0; built=0

echo "== construction #1 : chargement de la sauvegarde a Geyser Rock (training) =="
echo '(format 0 "GGC-BUILD n=1 geste=chargement-sauvegarde~%")' >&3
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
for i in $(seq 1 "${WAIT_LOAD:-120}"); do
  sleep 1
  [ -d "/proc/$GKPID" ] || { died=1; break; }
  [ "$(nplace)" -ge 1 ] && { built=1; echo "   construction #1 a t+${i}s"; break; }
done
if [ "$HERBE" = off ]; then
  # herbe DESARMEE : aucune ligne PLACE-TIME n'existe par construction. On compte les
  # chargements comme "cycles" et on verifie seulement la SURVIE — c'est le controle negatif.
  built=1; sleep 20; echo "   (herbe off) chargement termine, aucune construction attendue"
fi
[ "$died" = 1 ] && echo "  >>> MORT pendant la construction #1"

if [ "$died" = 0 ] && [ "$built" = 1 ]; then
  d=150
  for n in $(seq 2 "$NBUILD"); do
    [ -d "/proc/$GKPID" ] || { died=1; echo "  >>> MORT avant la construction $n"; break; }
    before=$(nplace)
    # alterne 148 <-> 150 : deux valeurs sous la densite du bake, donc le MODE (precomputed/live)
    # ne change pas d'une construction a l'autre — seul le declenchement change.
    if [ "$d" = 150 ]; then d=148; else d=150; fi
    echo "(format 0 \"GGC-BUILD n=$n geste=densite-$d~%\")" >&3
    echo "(set! (-> *pc-settings* recharged-grass-density) $d.0)" >&3
    got=0
    for i in $(seq 1 "${WAIT_BUILD:-90}"); do
      sleep 1
      [ -d "/proc/$GKPID" ] || { died=1; break; }
      if [ "$HERBE" = off ]; then [ "$i" -ge 3 ] && { got=1; break; }; fi
      [ "$(nplace)" -gt "$before" ] && { got=1; echo "   construction #$n (densite=$d) a t+${i}s"; break; }
    done
    [ "$died" = 1 ] && { echo "  >>> MORT pendant la construction $n"; break; }
    [ "$got" = 1 ] || { echo "  >>> ECHEC D'INSTRUMENT : la construction $n n'a jamais eu lieu (PLACE-TIME n'a pas monte) — ce n'est PAS une preuve de non-plantage"; break; }
    built=$n
  done
fi

[ -d "/proc/$GKPID" ] || died=1
exec 3>&- 2>/dev/null || true
sleep 2
SIG=""
if [ "$died" = 1 ]; then
  sleep 4
  SIG=$(coredumpctl list --no-pager 2>/dev/null | grep " $GKPID " | tail -1 | awk '{print $5}')
fi
RMAX=$(sort -k2 -n "$RSS" 2>/dev/null | tail -1 | awk '{print $2}')
printf 'tag=%s herbe=%s pre=%s constructions_demandees=%s constructions_faites=%s place_time_lignes=%s mort=%s pid=%s signal=%s rss_max_kb=%s kernel_cgo=%s gk_md5=%s\n' \
  "$TAG" "$HERBE" "$PRE" "$NBUILD" "$built" "$(nplace)" "$died" "$GKPID" "${SIG:-aucun}" "${RMAX:-0}" "$KSZ" "$GKMD5" | tee "$VERD"
echo "---- repli en direct ----"; grep -aE 'PRECOMPUTED unavailable' "$LOG" | tail -3
echo "---- constructions ----"; grep -aE 'PLACE-TIME' "$LOG" | tail -3
exit 0

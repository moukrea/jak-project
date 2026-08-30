#!/usr/bin/env bash
# gdp_x86_run.sh — Ggrass-density-presets : N chargements d'un niveau donne, sur x86,
# avec l'herbe armee/desarmee et une DENSITE donnee. Publie, par chargement :
# le nom du niveau, le mode (precomputed|live), le nombre de brins places, le temps,
# et le RSS max du processus.
#
#   Usage : gdp_x86_run.sh <continue> <cycles> <tag> [grass=on] [pre=on] [density=150]
#
# UN CYCLE = un chargement du niveau vise, puis un depart vers village1 (sans herbe),
# ce qui le DECHARGE. Meme forme que ggc_x86_cycles.sh (phase Ggrass-crash), dont ce
# script est une adaptation parametree par le NIVEAU et la DENSITE.
#
# Sorties :
#   $OUT/$tag.log        journal gk horodate
#   $OUT/$tag.rss        RSS du processus, une ligne par seconde (kB)
#   $OUT/$tag.verdict    une ligne de synthese
#   $OUT/$tag.place      les lignes PLACE-TIME brutes
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
CONT="${1:-training-start}"; CYCLES="${2:-3}"; TAG="${3:-run}"
HERBE="${4:-on}"; PRE="${5:-on}"; PALIER="${6:-medium}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Ggrass-density-presets"; mkdir -p "$OUT"
SETTINGS="build-x86/game/OpenGOAL/jak1/settings/settings.ini"
export DISPLAY="${DISPLAY:-:0}" SDL_VIDEODRIVER=x11
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.2UGBV3}"
LOG="$OUT/$TAG.log"; GCLOG="$OUT/$TAG-goalc.log"; RSS="$OUT/$TAG.rss"
VERD="$OUT/$TAG.verdict"; PLACE="$OUT/$TAG.place"
: > "$LOG"; : > "$GCLOG"; : > "$RSS"; : > "$VERD"; : > "$PLACE"

[ -f "$SETTINGS" ] || { echo "FAIL: pas de settings.ini a $SETTINGS"; exit 1; }
# Les deux lecteurs (Loader.cpp et le pckernel GOAL) JETTENT un fichier de version perimee.
sed -i "s/^version = .*/version = #x1000B00000000/" "$SETTINGS"
G='#t'; [ "$HERBE" = off ] && G='#f'
P='#t'; [ "$PRE"   = off ] && P='#f'
sed -i "s/^recharged-grass? = .*/recharged-grass? = $G/" "$SETTINGS"
sed -i "s/^recharged-grass-precomputed? = .*/recharged-grass-precomputed? = $P/" "$SETTINGS"
# Ggrass-density-presets : la densite n'est plus un pourcentage mais l'INDICE d'un palier nomme.
case "$PALIER" in
  very-low) IDX=0;; low) IDX=1;; medium) IDX=2;; high) IDX=3;; very-high) IDX=4;;
  *) echo "FAIL: palier inconnu '$PALIER' (very-low|low|medium|high|very-high)"; exit 1;;
esac
# la cle flottante d'avant ce lot n'est plus lue : on la retire pour qu'aucune course ne puisse
# croire l'avoir posee.
sed -i '/^recharged-grass-density = /d' "$SETTINGS"
if grep -q '^recharged-grass-density-preset = ' "$SETTINGS"; then
  sed -i "s/^recharged-grass-density-preset = .*/recharged-grass-density-preset = $IDX/" "$SETTINGS"
else
  sed -i "s/^recharged-grass? = $G/recharged-grass? = $G\nrecharged-grass-density-preset = $IDX/" "$SETTINGS"
fi
grep -qE "^recharged-grass-density-preset = $IDX\$" "$SETTINGS" || { echo "FAIL: palier non applique (attendu $IDX)"; exit 1; }
grep -qE "^recharged-grass\? = $G\$" "$SETTINGS" || { echo "FAIL: herbe non appliquee"; exit 1; }
grep -qE "^recharged-grass-precomputed\? = $P\$" "$SETTINGS" || { echo "FAIL: precomputed non applique"; exit 1; }
echo "== niveau=$CONT herbe=$HERBE pre=$PRE palier=$PALIER (idx=$IDX) cycles=$CYCLES =="
grep -E '^recharged-grass' "$SETTINGS" | sed 's/^/   /'

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
  # DIRECTIVES regle 8 : « jamais de kill par motif (auto-match) — PID exacts uniquement ».
  # Le `pgrep -n` d'origine (herite de ggc_x86_cycles.sh) tuait le gk le PLUS RECENT, pas le sien :
  # une course lancee pendant la fin d'une autre se faisait abattre par le nettoyage de la
  # precedente. Mesure : la jambe `apres-beach2` est morte 26 s apres son titre, verdict vide.
  [ -n "${GKPID:-}" ] && kill "$GKPID" 2>/dev/null
  sleep 1; kill "$PIPEPID" 2>/dev/null; rm -f "$FIFO"
}
trap cleanup EXIT

echo "== attente de l'ecran titre (BOOTLINE etape=titre-affiche) =="
titre=0
for i in $(seq 1 240); do
  [ -d "/proc/$GKPID" ] || { echo "FAIL: gk mort avant le titre (t+${i}s)"; break; }
  if grep -qa "BOOTLINE etape=titre-affiche" "$LOG"; then titre=1; echo "  titre a t+${i}s"; break; fi
  sleep 1
done
[ "$titre" = 1 ] || { echo "FAIL: pas de titre — voir $LOG"; exit 1; }
sleep 3
timeout 3600 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 600); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
sleep 3
live=0
for att in 1 2 3; do
  echo "(format 0 \"REPL-LIVE~%\")" >&3
  for i in $(seq 1 15); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && { live=1; break; }; done
  [ "$live" = 1 ] && break
  echo "  (lt) tentative $att sans reponse — on reessaie"
  echo '(lt)' >&3; sleep 5
done
[ "$live" = 1 ] || { echo "FAIL: listener goalc non connecte — rien ne serait execute"; exit 1; }

placed=0; died=0; cyc=0
for c in $(seq 1 "$CYCLES"); do
  cyc=$c
  [ -d "/proc/$GKPID" ] || { died=1; echo "  >>> MORT avant le cycle $c"; break; }
  echo "-- cycle $c : $CONT --"
  echo "(format 0 \"GDP-CYCLE n=$c niveau=$CONT phase=load~%\")" >&3
  echo "(initialize! *game-info* (quote game) (the-as game-save #f) \"$CONT\")" >&3
  for i in $(seq 1 "${WAIT_LOAD:-70}"); do
    sleep 1
    [ -d "/proc/$GKPID" ] || { died=1; break; }
    n=$(grep -ac 'PLACE-TIME' "$LOG" 2>/dev/null | head -1)
    [ "${n:-0}" -gt "$placed" ] && { placed=$n; echo "   herbe placee (place-time #$n) a t+${i}s"; break; }
    if [ "$HERBE" = off ] && [ "$i" -ge 30 ]; then echo "   (herbe off) t+${i}s"; break; fi
    [ "$i" -ge 60 ] && { echo "   (aucun PLACE-TIME apres ${i}s)"; break; }
  done
  [ "$died" = 1 ] && { echo "  >>> MORT pendant le chargement du cycle $c"; break; }
  sleep 4
  [ -d "/proc/$GKPID" ] || { died=1; echo "  >>> MORT apres le chargement du cycle $c"; break; }
  echo "-- cycle $c : village1 (sans herbe) — decharge $CONT --"
  echo "(format 0 \"GDP-CYCLE n=$c phase=leave~%\")" >&3
  echo '(start (quote play) (get-continue-by-name *game-info* "village1-warp"))' >&3
  for i in $(seq 1 "${WAIT_LEAVE:-45}"); do
    sleep 1
    [ -d "/proc/$GKPID" ] || { died=1; break; }
    [ "$i" -ge 22 ] && break
  done
  [ "$died" = 1 ] && { echo "  >>> MORT pendant le depart du cycle $c"; break; }
  rmax=$(sort -k2 -n "$RSS" 2>/dev/null | tail -1 | awk '{print $2}')
  echo "   fin du cycle $c — RSS max ${rmax:-?} kB"
done

[ -d "/proc/$GKPID" ] || died=1
exec 3>&- 2>/dev/null || true
sleep 2
SIG=""
if [ "$died" = 1 ]; then sleep 4; SIG=$(coredumpctl list --no-pager 2>/dev/null | grep " $GKPID " | tail -1 | awk '{print $5}'); fi
RMAX=$(sort -k2 -n "$RSS" 2>/dev/null | tail -1 | awk '{print $2}')
grep -aE 'PLACE-TIME' "$LOG" > "$PLACE" 2>/dev/null
printf 'tag=%s continue=%s herbe=%s pre=%s palier=%s idx=%s cycles_demandes=%s cycles_atteints=%s places=%s mort=%s pid=%s signal=%s rss_max_kb=%s\n' \
  "$TAG" "$CONT" "$HERBE" "$PRE" "$PALIER" "$IDX" "$CYCLES" "$cyc" "$placed" "$died" "$GKPID" "${SIG:-aucun}" "${RMAX:-0}" | tee "$VERD"
echo "---- repli en direct ----"; grep -aE 'PRECOMPUTED unavailable' "$LOG" | tail -5
echo "---- placements ----"; cat "$PLACE" | tail -5
exit 0

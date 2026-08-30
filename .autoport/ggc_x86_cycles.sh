#!/usr/bin/env bash
# ggc_x86_cycles.sh — Ggrass-crash : N CYCLES DE CHARGEMENT D'UN NIVEAU A HERBE, x86,
# avec l'herbe ARMEE ou DESARMEE (la condition que l'owner a isolee par bissection).
#
#   Usage : ggc_x86_cycles.sh <on|off> <cycles> <etiquette> [pre=on|off]
#             $1  herbe   : recharged-grass? dans settings.ini
#             $2  cycles  : nombre de CHARGEMENTS du niveau a herbe (training / Geyser Rock)
#             $3  tag     : nom du journal
#             $4  pre     : recharged-grass-precomputed? (defaut on). `off` force le
#                           placement EN DIRECT — le chemin que l'appareil prend.
#
# UN CYCLE = un chargement de sauvegarde a Geyser Rock (training, niveau a herbe) puis un
# depart vers village1 (sans herbe), ce qui DECHARGE training. C'est exactement la
# transition que l'owner decrit (« quand je charge ma sauvegarde a Geyser Rock »).
#
# Ce qui sort :
#   $OUT/$tag.log        journal gk horodate
#   $OUT/$tag.rss        RSS du processus, une ligne par seconde (kB)
#   $OUT/$tag.verdict    une ligne : cycles demandes / places / mort / signal
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
HERBE="${1:-on}"; CYCLES="${2:-10}"; TAG="${3:-run}"; PRE="${4:-on}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Ggrass-crash"; mkdir -p "$OUT"
SETTINGS="build-x86/game/OpenGOAL/jak1/settings/settings.ini"
export DISPLAY="${DISPLAY:-:0}" SDL_VIDEODRIVER=x11
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.2UGBV3}"
LOG="$OUT/$TAG.log"; GCLOG="$OUT/$TAG-goalc.log"; RSS="$OUT/$TAG.rss"; VERD="$OUT/$TAG.verdict"
: > "$LOG"; : > "$GCLOG"; : > "$RSS"; : > "$VERD"

[ -f "$SETTINGS" ] || { echo "FAIL: pas de settings.ini a $SETTINGS"; exit 1; }
# Les deux lecteurs (Loader.cpp et le pckernel GOAL) JETTENT un fichier de version perimee :
# sans ce bump, le reglage n'est jamais applique et les deux jambes seraient identiques.
sed -i "s/^version = .*/version = #x1000B00000000/" "$SETTINGS"
G='#t'; [ "$HERBE" = off ] && G='#f'
P='#t'; [ "$PRE"   = off ] && P='#f'
sed -i "s/^recharged-grass? = .*/recharged-grass? = $G/" "$SETTINGS"
sed -i "s/^recharged-grass-precomputed? = .*/recharged-grass-precomputed? = $P/" "$SETTINGS"
grep -qE "^recharged-grass\? = $G\$" "$SETTINGS" || { echo "FAIL: herbe non appliquee"; exit 1; }
grep -qE "^recharged-grass-precomputed\? = $P\$" "$SETTINGS" || { echo "FAIL: precomputed non applique"; exit 1; }
echo "== herbe=$HERBE (recharged-grass? = $G) precomputed=$PRE cycles=$CYCLES =="

# stdout REDIRIGE = bufferise par BLOCS : stdbuf -oL, sinon on compte 0 ligne sur 70 produites.
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

# PIEGE PAYE UNE FOIS : `link finish: default-menu` sort a t=4 s, BIEN AVANT le titre. Attendre
# dessus faisait envoyer `(lt)` a un jeu qui chargeait encore KERNEL.CGO, le listener n'etait pas la,
# et TOUT ce qui suivait etait compile avec allow_emit=#f puis jete EN SILENCE. Le seul marqueur
# fiable est `BOOTLINE etape=titre-affiche`.
echo "== attente de l'ecran titre (marqueur BOOTLINE etape=titre-affiche) =="
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
# VIVACITE : sans listener connecte, goalc compile avec allow_emit=#f et jette tout EN SILENCE.
# On REESSAIE `(lt)` au lieu d'abandonner : la connexion depend du moment ou goalc a fini de demarrer.
# ORDRE : `(lt)` D'ABORD, `(build-game)` ENSUITE (recette du depot, gcvf_x86_run.sh:46-48).
# Sans `(build-game)`, goalc n'a AUCUN symbole du jeu et `(format ...)` repond « No method or
# function named format for type int » : la course s'arrete sur « listener non connecte » alors
# que le listener EST connecte (`[DECI2] Connected!` dans le journal de gk).
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 420); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
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
  echo "-- cycle $c : Geyser Rock (training) --"
  echo "(format 0 \"GGC-CYCLE n=$c phase=load~%\")" >&3
  echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
  for i in $(seq 1 "${WAIT_LOAD:-60}"); do
    sleep 1
    [ -d "/proc/$GKPID" ] || { died=1; break; }
    n=$(grep -ac 'PLACE-TIME' "$LOG" 2>/dev/null | head -1)
    [ "${n:-0}" -gt "$placed" ] && { placed=$n; echo "   herbe placee (place-time #$n) a t+${i}s"; break; }
    # herbe=off : pas de PLACE-TIME. On attend que le niveau soit lie.
    if [ "$HERBE" = off ] && [ "$i" -ge 25 ]; then echo "   (herbe off) t+${i}s"; break; fi
  done
  [ "$died" = 1 ] && { echo "  >>> MORT pendant le chargement du cycle $c"; break; }
  sleep 4
  [ -d "/proc/$GKPID" ] || { died=1; echo "  >>> MORT apres le chargement du cycle $c"; break; }
  echo "-- cycle $c : village1 (sans herbe) — decharge training --"
  echo "(format 0 \"GGC-CYCLE n=$c phase=leave~%\")" >&3
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
if [ "$died" = 1 ]; then
  sleep 4
  SIG=$(coredumpctl list --no-pager 2>/dev/null | grep " $GKPID " | tail -1 | awk '{print $5}')
fi
RMAX=$(sort -k2 -n "$RSS" 2>/dev/null | tail -1 | awk '{print $2}')
printf 'tag=%s herbe=%s pre=%s cycles_demandes=%s cycles_atteints=%s places=%s mort=%s pid=%s signal=%s rss_max_kb=%s\n' \
  "$TAG" "$HERBE" "$PRE" "$CYCLES" "$cyc" "$placed" "$died" "$GKPID" "${SIG:-aucun}" "${RMAX:-0}" | tee "$VERD"
echo "---- repli en direct ----"; grep -aE 'PRECOMPUTED unavailable' "$LOG" | tail -3
echo "---- placements ----"; grep -aE 'PLACE-TIME' "$LOG" | tail -3
exit 0

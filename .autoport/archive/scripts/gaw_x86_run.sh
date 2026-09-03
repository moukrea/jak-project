#!/usr/bin/env bash
# Gandroid-window-size — jambe x86 : la derivation du format d'image sur PLUSIEURS
# ratios de fenetre, avec le comptage de bandes noires sur la fenetre REELLE.
#
# POURQUOI x86 ET PAS UN SECOND APPAREIL. La consigne de l'owner du 2026-08-28 23h
# interdit la Shield (c'est sa television). La variete de ratios se prend donc ici :
# une fenetre de bureau se dimensionne a volonte, sans toucher a un appareil.
#
# DEUX INSTRUMENTS PAR RATIO, ET ILS SONT INDEPENDANTS :
#   1. la ligne `GAWIN` que le moteur publie (fenetre, ratio derive, rectangle de
#      decoupe) — c'est ce que GOAL CROIT ;
#   2. le comptage de colonnes/lignes noires sur la capture de la fenetre — c'est ce
#      que l'ECRAN montre. Un desaccord entre les deux est le defaut lui-meme.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$(ls -1 /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1)}"
export SDL_VIDEODRIVER=x11

OUT=.autoport/reports/Gandroid-window-size
SHOTS="$OUT/shots/x86"
CFG=build-x86/game/OpenGOAL/jak1/settings
GK=build-x86/game/gk
mkdir -p "$SHOTS" "$OUT"
RES="$OUT/x86-ratios.txt"
: > "$RES"

BAK=/tmp/gaw-x86-cfg.bak
rm -rf "$BAK"; mkdir -p "$BAK"; cp -a "$CFG/settings.ini" "$CFG/display-settings.json" "$BAK/" 2>/dev/null

GK_PID=""
cleanup(){
  [ -n "$GK_PID" ] && kill -KILL "$GK_PID" 2>/dev/null
  cp -a "$BAK/settings.ini" "$BAK/display-settings.json" "$CFG/" 2>/dev/null
  echo "[x86] config restauree"
}
trap cleanup EXIT

# fenetre : mode WINDOWED (0). En 2 (borderless) la taille est imposee par l'ecran et
# il n'y aurait qu'un seul ratio possible.
cat > "$CFG/display-settings.json" <<'JSON'
{
  "display_id": 0,
  "display_mode": 0,
  "renderer": 0,
  "version": "1.2",
  "window_xpos": 20,
  "window_ypos": 40
}
JSON

set_size(){ # $1=W $2=H $3=aspect-state
  python3 - "$CFG/settings.ini" "$1" "$2" "$3" <<'PY'
import sys
p, w, h, asp = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
out = []
for l in open(p, encoding='utf-8', errors='replace').read().splitlines():
    s = l.strip()
    if s.startswith('window-size'):
        out.append('  window-size = %s %s' % (w, h))
    elif s.startswith('aspect-state'):
        out.append('  aspect-state = %s' % asp)
    else:
        out.append(l)
open(p, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY
}

run_one(){ # $1=tag $2=W $3=H $4=aspect-state
  local tag=$1 W=$2 H=$3 ASP=$4
  local L="$OUT/x86-$tag.log"
  set_size "$W" "$H" "$ASP"
  : > "$L"
  "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
        -iso-data out/jak1/iso -- -boot -debug-mem > "$L" 2>&1 &
  GK_PID=$!
  local ok=0
  for i in $(seq 1 "${BOOTWAIT:-70}"); do
    kill -0 "$GK_PID" 2>/dev/null || break
    grep -qa "link finish: logo$" "$L" && { ok=1; break; }
    sleep 2
  done
  # laisser le titre se composer (le logo est lie bien avant d'etre dessine)
  sleep "${SETTLE:-25}"
  local G B
  G=$(grep -a "GAWIN win=" "$L" | tail -1)
  python3 .autoport/gaw_x86_grab.py OpenGOAL "$SHOTS/$tag.png" "$W" "$H" > "$OUT/x86-$tag.grab" 2>&1
  B=$(python3 .autoport/gaw_bars.py "$SHOTS/$tag.png" 2>/dev/null)
  kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill -KILL "$GK_PID" 2>/dev/null; wait "$GK_PID" 2>/dev/null
  GK_PID=""
  {
    echo "---- $tag  demande=${W}x${H}  aspect-state='$ASP'  linkok=$ok"
    echo "  MOTEUR   ${G:-AUCUNE LIGNE GAWIN}"
    echo "  $(cat "$OUT/x86-$tag.grab" | head -1)"
    echo "  ECRAN    ${B:-PAS DE CAPTURE}"
  } | tee -a "$RES"
}

for spec in "$@"; do
  IFS=: read -r tag w h asp <<< "$spec"
  run_one "$tag" "$w" "$h" "${asp:-aspect4x3 4 3 #t}"
done
echo "GAW_X86_DONE"

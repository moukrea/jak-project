#!/usr/bin/env bash
# Gloading-screen — jambe x86 : CONTROLE POSITIF DU CHEMIN DE DESSIN.
#
# POURQUOI UN CONTROLE FORCE, ET PAS UNE VRAIE ATTENTE. Sur cette machine tout est deja
# resident : `__pc-scene-ready?` rend 1 au premier tour, la barriere ne se ferme JAMAIS
# (0 ligne LOADGATE sur une course x86 complete) et le chemin de dessin ne s'executerait
# donc jamais. Un zero sans controle positif qui a tire ne prouve rien — d'ou
# `loading-screen-force!`, qui met le systeme dans l'etat EXACT ou la barriere le met.
#
# CE QUE LA MESURE LIT QUAND LE DEFAUT EST ABSENT : `LOADSCREEN-SHOW frames=` qui monte,
# et une fenetre qui n'est PAS noire (l'ecran de chargement a du contenu).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$(ls -1 /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1)}"
export SDL_VIDEODRIVER=x11

OUT=.autoport/reports/Gloading-screen
SHOTS="$OUT/shots"; mkdir -p "$SHOTS"
CFG=build-x86/game/OpenGOAL/jak1/settings
GK=build-x86/game/gk
L="$OUT/x86-force.log"
W=${W:-1280}; H=${H:-720}

BAK=/tmp/gls-x86-cfg.bak; rm -rf "$BAK"; mkdir -p "$BAK"
cp -a "$CFG/settings.ini" "$CFG/display-settings.json" "$BAK/" 2>/dev/null
GK_PID=""
cleanup(){ [ -n "$GK_PID" ] && kill -KILL "$GK_PID" 2>/dev/null
           cp -a "$BAK/settings.ini" "$BAK/display-settings.json" "$CFG/" 2>/dev/null; }
trap cleanup EXIT

cat > "$CFG/display-settings.json" <<'JSON'
{ "display_id": 0, "display_mode": 0, "renderer": 0, "version": "1.2",
  "window_xpos": 20, "window_ypos": 40 }
JSON
python3 - "$CFG/settings.ini" "$W" "$H" <<'PY'
import sys
p,w,h = sys.argv[1], sys.argv[2], sys.argv[3]
out=[]
for l in open(p,encoding='utf-8',errors='replace').read().splitlines():
    s=l.strip()
    if s.startswith('window-size'): out.append('  window-size = %s %s'%(w,h))
    elif s.startswith('aspect-state'): out.append('  aspect-state = aspect16x9 16 9 #t')
    else: out.append(l)
open(p,'w',encoding='utf-8').write('\n'.join(out)+'\n')
PY

: > "$L"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data out/jak1/iso -- -boot -debug > "$L" 2>&1 &
GK_PID=$!
ok=0
for i in $(seq 1 70); do
  kill -0 "$GK_PID" 2>/dev/null || break
  grep -qa "link finish: logo$" "$L" && { ok=1; break; }
  sleep 2
done
echo "[gls] boot linkok=$ok"
sleep "${SETTLE:-28}"

# Le controle positif du chemin de dessin est DANS le moteur (loading-screen-draw-probe,
# engine/game/main.gc) : un seul tir, segment de debug uniquement, declenche des que la banque
# de texte est chargee. Pas de pilotage par le listener -- `goalc --cmd` ne fait tourner que le
# FRONT END (goalc/main.cpp:150, run_front_end_on_string) : il compile la forme et ne l'execute
# jamais sur la cible. Mesure : la connexion s'ouvre, et aucune ligne LOADSCREEN-FORCE n'arrive.
python3 .autoport/gaw_x86_grab.py OpenGOAL "$SHOTS/forced.png" "$W" "$H" > "$OUT/x86-force.grab" 2>&1
echo "[gls] capture: $(head -1 "$OUT/x86-force.grab")"
sleep 3
kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill -KILL "$GK_PID" 2>/dev/null; wait "$GK_PID" 2>/dev/null
GK_PID=""
echo "---- traces ----"
grep -aE "LOADSCREEN" "$L" | head -30
echo "GLS_X86_DONE"

#!/usr/bin/env bash
# Ghd-skin-origin-stretch cycle 7b — JAMBE x86 QUI BOUGE. Toutes les jambes x86 precedentes avaient
# HDMOVES distance=0 (la REPL ne pilote pas Jak) : le melange d'animations en mouvement, source du
# w != 1, ne s'y est jamais presente (normocc=0). Ici Jak est pilote par un pad replay SYNTHETISE
# (game/system/pad_replay.cpp, v2, meme sequence « brusque » que ghso6_device_leg.sh) arme par
# OG_PAD_REPLAY_REPLAY, un niveau par lancement (OG_LEVEL_WARP).
# usage : ARM=<0|1|2> TAG=<tag> DUR=<s> SCENES="a b c" bash .autoport/ghso7_x86_move.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Ghd-skin-origin-stretch; mkdir -p "$OUT"
GK=build-x86/game/gk; ISO=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/ghso7-iso
SETTINGS=build/game/OpenGOAL/jak1/settings/settings.ini
ARM="${ARM:-2}"; FPS="${FPS:-60}"; TAG="${TAG:-c7move-arm$ARM-fps$FPS}"; DUR="${DUR:-240}"
SCENES="${SCENES:-village3-farside citadel-start finalboss-start}"
DRV="$OUT/$TAG-driver.log"; : > "$DRV"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$DRV"; }
INPUTS=/home/emeric/.autoport-scratch/ghso7-brusque.inputs
python3 - "$INPUTS" "$DUR" <<'PY'
import struct, sys
out, dur = sys.argv[1], int(sys.argv[2])
X, SQ, CI = 1 << 14, 1 << 15, 1 << 13
fr = []
def hold(n, b=0, lx=127, ly=127): fr.extend([(b, lx, ly, 127, 127)] * n)
hold(900)                                   # amorce : warp + blackout de spawn (index ancre sur *target*)
# la sequence « brusque » du Redmi (cycle de 5 s) : course 1,5 s, saut, 0,9 s, coup, 0,4 s ; demi-tour idem
cyc = [(90, 0, 0), (15, X, 0), (54, 0, 0), (15, SQ, 0), (24, 0, 0),
       (90, 0, 255), (15, X, 255), (54, 0, 255), (15, CI, 255), (24, 0, 255)]
n = 0
while n < dur * 60:
    for k, b, ly in cyc: hold(k, b, 127, ly); n += k
hold(300)
with open(out, 'wb') as f:
    f.write(struct.pack('<8sIIIIq32s', b'OGPADRP1', 2, 6, 0x1234, 0, 0, b'\x00' * 32))
    for b0, lx, ly, rx, ry in fr: f.write(struct.pack('<HBBBB', b0, lx, ly, rx, ry))
print(f"{out}: {len(fr)} images ({len(fr)/60:.1f} s), cycle brusque 5 s x {n//300}")
PY
cp -f "$SETTINGS" "$SETTINGS.ghso7-bak"
GKPID=""
cleanup(){ [ -n "${GKPID:-}" ] && kill "$GKPID" 2>/dev/null; sleep 1; [ -f "$SETTINGS.ghso7-bak" ] && mv -f "$SETTINGS.ghso7-bak" "$SETTINGS"; return 0; }
trap cleanup EXIT
for kv in "game-size = 640 480" "render-scale = 25.0000" "min-render-scale = 25.0000" \
          "recharged-grass? = #f" "pbr-materials? = #f" "physics-quality = 0" \
          "recharged-enhanced-models? = #t" "hd-look-jak = 1" "hd-look-daxter = 1" \
          "hd-look-keira = 1" "hd-look-samos = 1" "vsync = #f" "fps = $FPS"; do
  k="${kv%% =*}"; sed -i "s/^$(printf '%s' "$k" | sed 's/[][\.*^$\/?]/\\&/g') = .*/$kv/" "$SETTINGS"
done
say "== copie privee de l'iso =="
rm -rf "$SNAP"; mkdir -p "$(dirname "$SNAP")"; cp -a --reflink=auto "$ISO" "$SNAP"
# loado(jak-hd-ag) lit out/jak1/obj/ (pas l'iso) et le cycle [full] du constructeur vide ce cache : recopier les deux
for c in jak dax keira samos jak2 jak3 daxp keira3 ysamos jakm jakp; do cp -f "recharged_assets/hd_anim/$c-hd-ag.go" "$SNAP/" 2>/dev/null; cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ 2>/dev/null; done
say "GAME.CGO $(md5sum "$SNAP/GAME.CGO" | cut -c1-12) HDLEN11=$(grep -ac HDLEN11 "$SNAP/GAME.CGO") art-groups HD: $(ls "$SNAP"/*-hd-ag.go | wc -l)"
export DISPLAY="${DISPLAY:-:0}"
[ -n "${XAUTHORITY:-}" ] || for x in /run/user/1000/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
for scene in $SCENES; do
  LOG="$OUT/$TAG-$scene.log"; : > "$LOG"
  say "== scene $scene (arm=$ARM, ${DUR}s) =="
  envs=(OG_LEVEL_WARP="$scene" OG_PAD_REPLAY_REPLAY="$INPUTS" OG_PAD_REPLAY_REALTIME=1)
  [ "$ARM" != 2 ] && envs+=(OG_HD_AFFINE_ARM="$ARM")
  env "${envs[@]}" stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data "$SNAP" -- -boot -debug-mem >> "$LOG" 2>&1 &
  GKPID=$!
  w=0
  for i in $(seq 1 240); do
    kill -0 "$GKPID" 2>/dev/null || break
    grep -aq 'LEVEL-WARP-SPAWN' "$LOG" && { w=1; break; }
    sleep 1
  done
  say "   warp=$w apres ${i}s ; $(grep -a 'HDAFFINEARM' "$LOG" | tail -1)"
  T0=$(date +%s)
  sleep $((DUR + 20))
  T1=$(date +%s)
  kill "$GKPID" 2>/dev/null; wait "$GKPID" 2>/dev/null; GKPID=""
  echo "HDWALL scene=$scene-x86 secondes=$((T1 - T0)) inject=0 affarm=$ARM fps=$FPS plateforme=x86" >> "$LOG"
  grep -aE '^(HDWGARB|HDLEN[0-9]*|HDMTXREF[23]?|HDAFFINEARM|HDDRAWDEV|HDMTXDEV|HDHB[0-9]?|HDLENG[0-9]?|HDLENRIG|HDMOVES|HDINJECT|HDSKINLEN|HDLENEV|HDCMDEV|HDRESET|HDWALL|HDSKINMODEL|HDBLEND2?|HDRJEV2?|HDTPEV2?|HDANGTAB|HDSCLEP2?|HDSTRETCHINJECT|LEVEL-WARP[A-Z-]*)|^\[JAK-HD-TGT\]' "$LOG" > "$OUT/$TAG-$scene-marqueurs.txt"
  say "   etats joueur : $(grep -a 'JAK-HD-TGT\] st=' "$LOG" | sed 's/^.*st=//' | sort | uniq -c | sort -rn | head -6 | awk '{printf "%s(%s) ", $2, $1}')"
  for m in HDMOVES HDLEN7 HDLEN8 HDLEN9 HDLEN10 HDLEN11 HDLEN HDLEN3; do say "   $(grep -a "^$m " "$LOG" | tail -1 | cut -c1-200)"; done
  say "   HDBLEND=$(grep -ac '^HDBLEND ' "$LOG") HDRJEV=$(grep -ac '^HDRJEV ' "$LOG") HDTPEV=$(grep -ac '^HDTPEV ' "$LOG") HDLENG=$(grep -ac '^HDLENG ' "$LOG") HDCMDEV=$(grep -ac '^HDCMDEV ' "$LOG") HDSKINLEN=$(grep -a '^HDSKINLEN ' "$LOG" | tail -1 | grep -o 'cmd_bones=[0-9]* .*stock_w_bad=[0-9]* hd_w_bad=[0-9]*' | cut -c1-120)"
done
say "== fin $TAG =="

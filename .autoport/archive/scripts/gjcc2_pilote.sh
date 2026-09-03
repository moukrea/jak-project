#!/usr/bin/env bash
# Gjak1-crate-collision-2 — PILOTE EN BOUCLE FERMEE, A CHAINE DE POINTS DE PASSAGE.
#
# Il ecrit dans `debug.opengoal.cpad_inject` : de VRAIES entrees manette, donc la physique
# et la collision tournent normalement. La position est LUE dans `files/pos_dump.txt`
# (sonde `debug.opengoal.dump.pos`, ~4 Hz) — jamais ecrite. On n'utilise PAS
# `debug.opengoal.target.drive`, qui ecrit `trans` et court-circuite la collision : il
# fabriquerait des traversees.
#
# POURQUOI UNE CHAINE ET PLUS UN SEUL POINT. Mesure des cinq courses du 2026-09-01 13:2x :
# 16 caisses distinctes vivantes par course, TOUJOURS LES MEMES (aid 17622 a 17637), et
# quinze autres (17638 a 17652) jamais nees — elles sont a 70-173 m et le joueur, une fois
# arrive sur son unique amas, n'en repart plus. Une chaine le fait TRAVERSER le rocher :
# elle augmente la couverture ET multiplie les naissances/morts de caisses, qui sont
# exactement l'evenement qui fabrique une sphere de collision perdue.
#
# DEUX REGIMES, et le second est celui qui mesure :
#   APPROCHE  — loin du point courant : plein avant, cap corrige par l'erreur d'angle mesuree.
#   SUR PLACE — a moins de 10 m : on ne pousse plus a fond (mesure v5 : le plein avant
#               ejectait le joueur de l'amas et il tombait). On BALAYE LA CAMERA et on
#               avance par petites impulsions. Le balayage de camera est le geste meme que
#               l'owner decrit : il fait naitre et mourir les caisses autour du joueur.
#
# On avance au point suivant quand on est arrive (< 10 m, apres un sejour) OU quand le
# budget du point est epuise : un pilote qui se bloque sur le relief ne doit pas manger
# toute la course, sinon la couverture retombe a un seul amas.
#
# usage : gjcc2_pilote.sh <serial> <pkg> <duree_s> <tx1> <tz1> [tx2 tz2 ...]
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb; [ -x "$ADB" ] || ADB=$(command -v adb)
SER="$1"; PKG="$2"; DUR="$3"; shift 3
WPS=("$@")
NW=$(( ${#WPS[@]} / 2 ))
[ "$NW" -ge 1 ] || { echo "    pilote: aucun point de passage"; exit 1; }
a(){ "$ADB" -s "$SER" "$@"; }
pad(){ a shell "setprop debug.opengoal.cpad_inject '$1'" >/dev/null 2>&1; }
getpos(){ a exec-out run-as "$PKG" cat files/pos_dump.txt 2>/dev/null | head -1 | tr -d '\r'; }

a shell "setprop debug.opengoal.dump.pos 1" >/dev/null 2>&1
START=$(date +%s); END=$(( START + DUR ))
# budget par point : de quoi y aller sans jamais consommer toute la course
BUDGET=$(( DUR / NW )); [ "$BUDGET" -lt 45 ] && BUDGET=45
WI=0; WSTART=$START; SEJOUR=0; STUCK=0
PX=""; PZ=""; K=0
while [ "$(date +%s)" -lt "$END" ]; do
  K=$((K+1))
  TX="${WPS[$((WI*2))]}"; TZ="${WPS[$((WI*2+1))]}"
  NOW=$(date +%s)
  P=$(getpos); set -- $P; X="${1:-}"; Y="${2:-}"; Z="${3:-}"
  if [ -z "$X" ]; then pad "ly=0"; sleep 1.2; continue; fi
  OUT=$(python3 - "$X" "$Y" "$Z" "${PX:-}" "${PZ:-}" "$TX" "$TZ" "$K" <<'PY'
import sys,math
x,y,z=float(sys.argv[1]),float(sys.argv[2]),float(sys.argv[3])
px,pz=sys.argv[4],sys.argv[5]
tx,tz=float(sys.argv[6]),float(sys.argv[7])
k=int(sys.argv[8])
d=math.hypot(tx-x,tz-z)
mv=-1.0
if px:
    mv=math.hypot(x-float(px),z-float(pz))
if d<10.0:
    seq=["rx=235","rx=235","ly=45","rx=20","rx=20","ly=45","ly=45 lx=190","rx=235","ly=45 lx=66","ly=45"]
    print(f"{seq[k%len(seq)]}|{d:.1f}|{mv:.2f}|SURPLACE y={y:.1f}")
    sys.exit()
lx=128; msg=""
if px and mv>=0 and mv<0.4:
    lx=210 if k%2 else 46
    print(f"ly=45 lx={lx}|{d:.1f}|{mv:.2f}|bloque y={y:.1f}"); sys.exit()
if px and mv>=0.4:
    head=math.atan2(z-float(pz),x-float(px)); want=math.atan2(tz-z,tx-x)
    e=(want-head+math.pi)%(2*math.pi)-math.pi
    lx=int(max(0,min(255,128+110*(e/math.pi))))
    msg=f" err={math.degrees(e):+.0f}deg"
print(f"ly=45 lx={lx}|{d:.1f}|{mv:.2f}|route{msg} y={y:.1f}")
PY
)
  TOK="${OUT%%|*}"; R="${OUT#*|}"; D="${R%%|*}"; R="${R#*|}"; MV="${R%%|*}"; MSG="${R#*|}"
  PX="$X"; PZ="$Z"
  pad "$TOK"
  # arrive ? on sejourne un peu (le balayage camera fait naitre/mourir des caisses), puis suivant
  if [ "${D%%.*}" -lt 10 ] 2>/dev/null; then SEJOUR=$((SEJOUR+1)); else SEJOUR=0; fi
  ADV=0
  [ "$SEJOUR" -ge 12 ] && ADV=1
  [ $(( NOW - WSTART )) -ge "$BUDGET" ] && ADV=1
  if [ "$ADV" = 1 ] && [ "$NW" -gt 1 ]; then
    WI=$(( (WI + 1) % NW )); WSTART=$NOW; SEJOUR=0
    echo "    pilote: -> point $((WI+1))/$NW (${WPS[$((WI*2))]}, ${WPS[$((WI*2+1))]})"
  fi
  [ $((K % 6)) -eq 0 ] && echo "    pilote: pt=$((WI+1))/$NW d=${D}m dep=${MV}m $MSG -> '$TOK'"
  sleep 1.2
done
pad ""
a shell "setprop debug.opengoal.dump.pos ''" >/dev/null 2>&1

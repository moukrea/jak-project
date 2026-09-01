#!/usr/bin/env bash
# Gjak1-crate-collision-2 — PILOTE EN BOUCLE FERMEE.
#
# Il ecrit dans `debug.opengoal.cpad_inject` : de VRAIES entrees manette, donc la physique
# et la collision tournent normalement. La position est LUE dans `files/pos_dump.txt`
# (sonde `debug.opengoal.dump.pos`, ~4 Hz) — jamais ecrite. On n'utilise PAS
# `debug.opengoal.target.drive`, qui ecrit `trans` et court-circuite la collision : il
# fabriquerait des traversees.
#
# DEUX REGIMES, et le second est celui qui mesure :
#   APPROCHE  — loin des caisses : plein avant, cap corrige par l'erreur d'angle mesuree.
#   SUR PLACE — a moins de 10 m : on ne pousse plus a fond (mesure v5 : le plein avant
#               ejectait le joueur de l'amas et il tombait). On BALAYE LA CAMERA et on
#               avance par petites impulsions. Le balayage de camera est le geste meme que
#               l'owner decrit : il fait naitre et mourir les caisses autour du joueur,
#               donc il rejoue la condition qui produit une sphere de collision perdue.
#
# usage : gjcc2_pilote.sh <serial> <pkg> <duree_s> <tx_m> <tz_m>
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb; [ -x "$ADB" ] || ADB=$(command -v adb)
SER="$1"; PKG="$2"; DUR="$3"; TX="$4"; TZ="$5"
a(){ "$ADB" -s "$SER" "$@"; }
pad(){ a shell "setprop debug.opengoal.cpad_inject '$1'" >/dev/null 2>&1; }
getpos(){ a exec-out run-as "$PKG" cat files/pos_dump.txt 2>/dev/null | head -1 | tr -d '\r'; }

a shell "setprop debug.opengoal.dump.pos 1" >/dev/null 2>&1
END=$(( $(date +%s) + DUR ))
PX=""; PZ=""; PH=0; K=0
while [ "$(date +%s)" -lt "$END" ]; do
  K=$((K+1))
  P=$(getpos); set -- $P; X="${1:-}"; Y="${2:-}"; Z="${3:-}"
  if [ -z "$X" ]; then pad "ly=0"; sleep 1.2; continue; fi
  OUT=$(python3 - "$X" "$Y" "$Z" "${PX:-}" "${PZ:-}" "$TX" "$TZ" "$PH" "$K" <<'PY'
import sys,math
x,y,z=float(sys.argv[1]),float(sys.argv[2]),float(sys.argv[3])
px,pz=sys.argv[4],sys.argv[5]
tx,tz=float(sys.argv[6]),float(sys.argv[7])
ph=int(sys.argv[8]); k=int(sys.argv[9])
d=math.hypot(tx-x,tz-z)
if d<10.0:
    # SUR PLACE : balayage camera + petites impulsions. Jamais de plein avant.
    seq=["rx=235","rx=235","ly=45","rx=20","rx=20","ly=45","ly=45 lx=190","rx=235","ly=45 lx=66","ly=45"]
    tok=seq[k%len(seq)]
    print(f"{tok}|1|d={d:.1f}m y={y:.1f} SURPLACE")
    sys.exit()
lx=128; msg=f"d={d:.1f}m y={y:.1f}"
if px:
    mx,mz=x-float(px),z-float(pz)
    if math.hypot(mx,mz)<0.4:
        lx=210 if k%2 else 46; msg+=" bloque"
        print(f"ly=45 x lx={lx}|0|{msg}"); sys.exit()
    head=math.atan2(mz,mx); want=math.atan2(tz-z,tx-x)
    e=(want-head+math.pi)%(2*math.pi)-math.pi
    lx=int(max(0,min(255,128+110*(e/math.pi))))
    msg+=f" err={math.degrees(e):+.0f}deg"
print(f"ly=45 lx={lx}|0|{msg}")
PY
)
  TOK="${OUT%%|*}"; REST="${OUT#*|}"; PH="${REST%%|*}"; MSG="${REST#*|}"
  PX="$X"; PZ="$Z"
  pad "$TOK"
  [ $((K % 6)) -eq 0 ] && echo "    pilote: $MSG -> '$TOK'"
  sleep 1.2
done
pad ""
a shell "setprop debug.opengoal.dump.pos ''" >/dev/null 2>&1

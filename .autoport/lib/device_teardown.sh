#!/usr/bin/env bash
# lib/device_teardown.sh — REND L'APPAREIL A L'ETAT NEUTRE. Appele en `trap EXIT` par
# lib/proof_run.sh et par tout script qui touche l'appareil.
#
# POURQUOI CE FICHIER EXISTE. Une propriete `debug.opengoal.cpad_inject` laissee posee par
# notre outillage a tenu le bouton CROIX ENFONCE pendant des semaines : jamais de front, donc
# jamais de saut, et trois hypotheses refutees avant qu'on regarde la propriete. 94 des 101
# scripts qui la posent ne la vident pas. Une liste de proprietes ECRITE A LA MAIN a deja
# rate `echo.intro`, `level.warp.pos`, `gjcc`, `grass.census`, `gcine.cam`. Donc ici on
# n'efface pas une liste : on efface TOUT ce qui commence par `debug.opengoal.`, lu sur
# l'appareil lui-meme, et on ajoute une liste de secours pour le cas ou l'enumeration echoue.
#
# Usage : lib/device_teardown.sh [serial]   (defaut : $ANDROID_SERIAL, sinon eae4df44)
# Sortie : TOUJOURS 0. Un teardown qui echoue ne doit jamais transformer une course reussie
#          en rouge, ni faire mourir le `trap EXIT` qui l'appelle.
set -uo pipefail

SERIAL="${1:-${ANDROID_SERIAL:-eae4df44}}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="${AUTOPORT_PKG:-org.opengoal.gk.jak1}"
[ -x "$ADB" ] || ADB=adb

# La SHIELD est interdite : on ne s'y connecte pas, meme pour nettoyer. Un serial en forme
# d'adresse reseau est refuse par principe — seul un appareil branche en USB est autorise.
case "$SERIAL" in
  *[0-9].[0-9]*.[0-9]*|*:*)
    echo "[teardown] serial '$SERIAL' ressemble a une adresse reseau : on ne touche pas (SHIELD interdite)."
    exit 0 ;;
esac
[ -n "$SERIAL" ] || { echo "[teardown] aucun serial : rien a nettoyer."; exit 0; }

# --- 1. les logcat que NOUS avons laisses tourner cote hote ---------------------------------
# Les pid deposes par proof_run.sh d'abord (c'est le seul ensemble dont on est SUR qu'il est
# de notre fait), puis un filet de securite sur le motif exact, en classe de caracteres pour
# que le grep ne se matche pas lui-meme.
PIDDIR="${AUTOPORT_LOGCAT_PIDDIR:-.autoport/.logcat}"
if [ -d "$PIDDIR" ]; then
  for f in "$PIDDIR"/*.pid; do
    [ -e "$f" ] || continue
    p=$(cat "$f" 2>/dev/null)
    if [ -n "${p:-}" ] && kill -0 "$p" 2>/dev/null; then
      kill "$p" 2>/dev/null && echo "[teardown] logcat pid=$p tue (depuis $f)"
    fi
    rm -f "$f"
  done
fi
pkill -f "[a]db -s $SERIAL logcat" 2>/dev/null && echo "[teardown] logcat orphelin sur $SERIAL tue"

# --- 2. l'appareil est-il la ? ---------------------------------------------------------------
state=$(timeout 15 "$ADB" -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')
if [ "$state" != "device" ]; then
  echo "[teardown] $SERIAL absent (etat='${state:-aucun}') : rien a effacer sur l'appareil."
  exit 0
fi

# --- 3. TOUTES les debug.opengoal.*, lues sur l'appareil -------------------------------------
cleared=0
props=$(timeout 20 "$ADB" -s "$SERIAL" shell getprop 2>/dev/null | tr -d '\r' \
        | sed -n 's/^\[\(debug\.opengoal\.[^]]*\)\]:.*/\1/p')
# Liste de SECOURS : si `getprop` ne rend rien (adb capricieux, appareil occupe), on efface au
# moins ce que notre outillage pose le plus souvent. cpad_inject en tete, c'est celle qui a coute.
fallback="debug.opengoal.cpad_inject debug.opengoal.pad_replay debug.opengoal.pad_trace
debug.opengoal.f1.warp debug.opengoal.level.warp debug.opengoal.level.warp.pos
debug.opengoal.echo.intro debug.opengoal.gjcc debug.opengoal.feature debug.opengoal.feature.armed
debug.opengoal.pace.measure debug.opengoal.gspeed.measure debug.opengoal.gspeed.off
debug.opengoal.render.scale debug.opengoal.grass.census debug.opengoal.gcine.cam
debug.opengoal.perf.buckets debug.opengoal.perf.nobatch debug.opengoal.f3.measure
debug.opengoal.grass_async debug.opengoal.grass_dbg debug.opengoal.grass_gpusync
debug.opengoal.grass_maxinst debug.opengoal.tod.hour"
for p in $props $fallback; do
  v=$(timeout 10 "$ADB" -s "$SERIAL" shell "getprop $p" 2>/dev/null | tr -d '\r')
  [ -n "$v" ] || continue
  timeout 10 "$ADB" -s "$SERIAL" shell "setprop $p ''" >/dev/null 2>&1
  after=$(timeout 10 "$ADB" -s "$SERIAL" shell "getprop $p" 2>/dev/null | tr -d '\r')
  if [ -z "$after" ]; then
    echo "[teardown] $SERIAL: $p etait '$v' -> vide"
    cleared=$((cleared+1))
  else
    echo "[teardown] $SERIAL: $p RESISTE (encore '$after') — a signaler, pas a ignorer" >&2
  fi
done

# --- 4. les marqueurs fichier que le moteur LIT comme des interrupteurs ----------------------
# `run-as PKG rm -f a b` rend 0 SANS RIEN FAIRE : il faut passer par `sh -c`.
timeout 20 "$ADB" -s "$SERIAL" exec-out run-as "$PKG" sh -c \
  'rm -f files/cpad_inject files/f1a_merc_nodraw files/f1a_merc_noubo files/f1a_merc_notex files/gpose files/f1b_trs files/gnd_noblerc' \
  >/dev/null 2>&1

echo "[teardown] $SERIAL: $cleared propriete(s) effacee(s), marqueurs fichier retires."
exit 0

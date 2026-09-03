#!/usr/bin/env bash
# ggc_redmi_cycles.sh — Ggrass-crash : N CONSTRUCTIONS DU CHAMP D'HERBE sur le Redmi eae4df44,
# chacune obtenue comme l'owner l'obtient : lancer le jeu, CHARGER LA SAUVEGARDE a Geyser Rock.
#
#   Usage : ggc_redmi_cycles.sh <cycles> <etiquette>
#
# POURQUOI UN LANCEMENT PAR CYCLE. Mesure x86 du 2026-08-30 : 9 chargements de `training` dans la
# MEME session n'ont produit qu'UNE ligne `PLACE-TIME` — le `LevelData` est reutilise, donc
# `render()` ne redeclenche pas `rebuild()` (cle de cache `ld->level.get()` + `ld->load_id`,
# GrassRenderer.cpp:1200-1204). Recharger en boucle sans relancer l'application ne reexerce donc
# PAS le defaut. Une construction = une ligne `[recharged-grass] PLACE-TIME`, et c'est CETTE
# grandeur qu'on compte : un cycle qui n'en produit pas ne prouve rien et est declare comme tel.
#
# LA SHIELD EST INTERDITE : ANDROID_SERIAL est epingle sur eae4df44, sur chaque commande.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
N="${1:-10}"; TAG="${2:-redmi}"
ADB=/home/emeric/Android/platform-tools/adb
SER=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=".autoport/reports/Ggrass-crash"; mkdir -p "$OUT"
LOG="$OUT/$TAG.logcat"; VERD="$OUT/$TAG.verdict"; : > "$LOG"; : > "$VERD"

a(){ "$ADB" -s "$SER" "$@"; }
# PIEGE CONNU, il a coute une phase entiere : `debug.opengoal.cpad_inject` laissee non videe TIENT
# UN BOUTON ENFONCE — plus aucun front, donc plus aucune validation. On la remet a `neutral` apres
# CHAQUE impulsion, et une derniere fois a la sortie.
pulse(){ a shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; sleep "${2:-0.4}"; a shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1; sleep "${3:-1.0}"; }
cleanup(){ a shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1; [ -n "${LCPID:-}" ] && kill "$LCPID" 2>/dev/null; }
trap cleanup EXIT

a devices | grep -qE "^${SER}[[:space:]]+device$" || { echo "FAIL: $SER absent"; exit 1; }
echo "PROVENANCE apk_installe_maj=$(a shell dumpsys package $PKG 2>/dev/null | grep -m1 lastUpdateTime | tr -d '\r')"
echo "PROVENANCE stamp=$(a exec-out run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')"

# CAPTURE STREAMEE, jamais `logcat -t N` : une fenetre `-t` a deja rendu « 0 occurrence » sur une
# course a 16 393 lignes. On publie le nombre de lignes capturees a cote de tout compte.
a logcat -c >/dev/null 2>&1
( a logcat -v threadtime > "$LOG" 2>/dev/null ) & LCPID=$!
sleep 2

# `grep -c` imprime DEJA 0 et sort en 1 : un `|| echo 0` rendrait "0\n0" et tout test entier
# echouerait avec « nombre entier attendu ». `head -1` clot la question.
nplace(){ grep -ac 'PLACE-TIME' "$LOG" 2>/dev/null | head -1; }
alive(){ [ -n "$(a shell pidof $PKG 2>/dev/null | tr -d '\r')" ]; }

built=0; morts=0; tentatives=0
for c in $(seq 1 "$N"); do
  tentatives=$c
  echo "== tentative $c/$N : lancement + chargement de la sauvegarde a Geyser Rock =="
  a shell am force-stop $PKG >/dev/null 2>&1
  a shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  sleep 2
  before=$(nplace)
  a shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  ok_title=0
  for i in $(seq 1 "${WAIT_TITLE:-120}"); do
    sleep 1
    grep -aq 'link finish: logo-loop' "$LOG" && { ok_title=1; break; }
  done
  [ "$ok_title" = 1 ] || { echo "   ECHEC D'INSTRUMENT : pas d'ecran titre (t+${i}s) — ce n'est pas une mesure"; continue; }
  sleep 4
  pulse start 0.4 2.0      # ecran titre -> menu principal
  pulse down  0.35 0.8     # Nouvelle partie -> Charger une partie
  pulse x     0.4 2.0
  pulse x     0.4 2.0      # premiere sauvegarde (ROCHER DU GEYSER)
  pulse x     0.4 2.0      # confirmation eventuelle
  got=0
  for i in $(seq 1 "${WAIT_PLACE:-150}"); do
    sleep 2
    if [ "$(nplace)" -gt "$before" ]; then got=1; echo "   construction du champ d'herbe a t+$((i*2))s"; break; fi
    alive || { echo "   MORT a t+$((i*2))s AVANT toute construction"; break; }
  done
  if [ "$got" = 0 ]; then
    if alive; then echo "   ECHEC D'INSTRUMENT : aucune construction et le jeu vit — navigation ratee ?"; else morts=$((morts+1)); echo "   >>> MORT SANS CONSTRUCTION (a chercher ailleurs que dans l'herbe)"; fi
    continue
  fi
  built=$((built+1))
  # LA QUESTION EST : SURVIT-IL A LA CONSTRUCTION ? On observe 25 s apres la ligne PLACE-TIME.
  dead=0
  for i in $(seq 1 25); do sleep 1; alive || { dead=1; break; }; done
  if [ "$dead" = 1 ]; then
    morts=$((morts+1)); echo "   >>> MORT ${i}s APRES la construction"
    echo "   --- 25 dernieres lignes ---"; tail -25 "$LOG" | cut -c1-200
  else
    echo "   survit (25 s apres la construction)"
  fi
done

LINES=$(wc -l < "$LOG")
printf 'tag=%s tentatives=%s constructions=%s morts=%s lignes_logcat=%s\n' "$TAG" "$tentatives" "$built" "$morts" "$LINES" | tee "$VERD"
echo "---- PLACE-TIME ----"; grep -a 'PLACE-TIME' "$LOG" | tail -3 | cut -c1-260
echo "---- repli en direct ----"; grep -a 'PRECOMPUTED unavailable' "$LOG" | tail -3 | cut -c1-200
echo "---- signaux fatals ----"; grep -aE 'Fatal signal|signal [0-9]+ \(SIG|>>> org.opengoal' "$LOG" | tail -10 | cut -c1-200
exit 0

#!/usr/bin/env bash
# keira_room_device.sh — LA MEME SALLE DE TEST, SUR LE REDMI eae4df44.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean.
# x86 ne prouve pas arm64 : ce script rejoue la course de .autoport/keira_room_x86.sh sur le
# device, sans rien cliquer (prop debug.opengoal.phys.room), et ramene la trace. Il ne juge RIEN —
# c'est .autoport/physics_room_table.py qui en fait un tableau, et lui seul a le droit de refuser
# une ligne que la trace ne soutient pas.
#
# Prealable : APK installe + jeu de CGO arm64 coherent pousse + physics_chains.txt pousse
# (.autoport/physics_deploy_fresh.sh s'en charge et le prouve).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-secondary-motion
LOG="$OUT/keira-room-device.log"
mkdir -p "$OUT"
say(){ echo "$*"; }
die(){ echo "[room-device FAIL] $*"; exit 1; }

$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S absent"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
# le trap Honor/MIUI : dumpsys trust liste plusieurs users, seul '(current)' compte
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then
  die "device PIN-LOCKED — attendre l'owner"
fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true

# ---- les six art-groups de Keira, en fichiers isoles, dans le repertoire ou `loado` regarde -----
# Sur le device, seul le jeu de CGO/DGO est extrait : `files/out/jak1/obj/` ne contient AUCUN
# <name>-ag.go de personnage stock, et `loado` echoue (mesure du 2026-08-11 : la salle est repartie
# sans art-group). L'art-group du niveau vivant suffit pour `assistant` (la salle le trouve
# resident), mais pas pour les cinq variantes qui n'apportent que leurs animations. On les stage
# donc, et on VERIFIE par md5 en relisant — `run-as` rend 0 meme quand il a echoue.
DEVOBJ=files/out/jak1/obj
$ADB -s "$S" shell run-as $PKG mkdir -p "$DEVOBJ" >/dev/null 2>&1 || true
STAGED=0; STAGEFAIL=0
for n in assistant assistant-village2 assistant-village3 assistant-firecanyon \
         assistant-lavatube-start assistant-lavatube-end; do
  f="out/jak1/obj/$n-ag.go"
  [ -f "$f" ] || { say "MANQUANT localement: $f"; STAGEFAIL=$((STAGEFAIL+1)); continue; }
  $ADB -s "$S" push "$f" "/data/local/tmp/$n-ag.go" >/dev/null 2>&1 || { STAGEFAIL=$((STAGEFAIL+1)); continue; }
  $ADB -s "$S" shell "run-as $PKG cp /data/local/tmp/$n-ag.go $DEVOBJ/$n-ag.go" >/dev/null 2>&1 || true
  LM=$(md5sum "$f" | cut -d' ' -f1)
  DM=$($ADB -s "$S" shell run-as $PKG md5sum "$DEVOBJ/$n-ag.go" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
  if [ "$LM" = "$DM" ]; then STAGED=$((STAGED+1)); else say "MD5 MISMATCH $n: local=$LM device=$DM"; STAGEFAIL=$((STAGEFAIL+1)); fi
  $ADB -s "$S" shell rm -f "/data/local/tmp/$n-ag.go" >/dev/null 2>&1 || true
done
say "art-groups stages et md5-verifies: $STAGED/6 (echecs: $STAGEFAIL)"

$ADB -s "$S" shell setprop debug.opengoal.phys.room 1 || die "setprop failed"
$ADB -s "$S" shell setprop debug.opengoal.phys.room.delay "${ROOM_DELAY:-900}" >/dev/null 2>&1 || true
say "prop debug.opengoal.phys.room = $($ADB -s "$S" shell getprop debug.opengoal.phys.room)"

$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
: > "$LOG"
# PID exact du sous-shell de capture : jamais de kill par motif (DIRECTIVES 8)
$ADB -s "$S" logcat -v time >> "$LOG" 2>&1 &
CAP=$!
say "logcat capture pid=$CAP -> $LOG"

$ADB -s "$S" shell am start -n "$PKG/$ACT" >/dev/null 2>&1 || die "am start failed"
say "lance $PKG/$ACT"

DEADLINE="${ROOM_TIMEOUT:-1800}"
ok=0
for i in $(seq 1 "$DEADLINE"); do
  if grep -aq 'PHYSEND' "$LOG" 2>/dev/null; then ok=1; say "PHYSEND vu apres ${i}s"; break; fi
  if grep -aq 'PHYSFAIL reason=' "$LOG" 2>/dev/null; then say "PHYSFAIL vu"; break; fi
  sleep 1
done

kill "$CAP" 2>/dev/null
$ADB -s "$S" shell setprop debug.opengoal.phys.room 0 >/dev/null 2>&1 || true
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
say "app arretee, prop remise a 0"

# la trace GOAL arrive sous le tag opengoal-gk : on la deroute vers un fichier au meme format que
# la course x86, pour que le MEME script en fasse le tableau (un seul instrument, pas deux).
# Le prefixe de `logcat -v time` est `MM-JJ HH:MM:SS.mmm P/tag( pid): ` — le PID entre parentheses
# est AVANT le deux-points, donc un motif `s/^.*opengoal-gk: //` ne matche JAMAIS et la trace sortait
# identique au log (mesure du 2026-08-11 : md5 identiques, et l'instrument refusait la course pour
# « PHYSEND absent » alors que PHYSEND etait la, prefixe). On retire le prefixe complet, quel que
# soit le tag, et on VERIFIE que ca a marche.
sed -E 's/^[0-9]{2}-[0-9]{2} [0-9:.]+ [A-Z]\/[A-Za-z0-9_-]+ *\( *[0-9]+\): //' "$LOG" \
  > "$OUT/keira-room-device.trace"
if ! grep -aq '^PHYSEND' "$OUT/keira-room-device.trace"; then
  say "FAIL: le prefixe logcat n'a pas ete retire (aucune ligne ^PHYSEND dans la trace)."
  say "      premiere ligne PHYS du log brut :"
  grep -am1 'PHYS' "$LOG" | sed 's/^/      /'
  die "trace inexploitable — corriger le sed avant de recommencer"
fi
say "---- marqueurs ----"
for m in PHYSROOM-START PHYSFAIL PHYSSUBJECT PHYSANIM PHYSCHAIN PHYSROW PHYSIDLE PHYSAUTH PHYSNOPLAY PHYSCOUNTS PHYSPC PHYSLIM PHYSEND 'HD-PHYS'; do
  printf '%-16s %s\n' "$m" "$(grep -ac "$m" "$OUT/keira-room-device.trace" 2>/dev/null || echo 0)"
done
grep -aE 'signal|SIGSEGV|SIGILL|FATAL|abort' "$LOG" | head -5
[ "$ok" = 1 ] || die "PHYSEND jamais atteint"
say "OK"

#!/usr/bin/env bash
# gmam_c5_boot_proof.sh — PREUVE D'EXECUTION sur la Shield, ecran REVEILLE.
#
# POURQUOI LE REVEIL EST UNE PRECONDITION, ET PAS UN DETAIL. La premiere passe du cycle 5 a
# rendu « master-mode=game jamais atteint » sur un build sain. Cause lue dans le log, pas
# supposee :
#   dumpsys power -> mWakefulness=Asleep · Display Power: state=OFF
#   ActivityTaskManager: Background activity start [... callingUidProcState: TOP_SLEEPING ...]
# LoaderActivity deballe bien le pack (les tampons sont ecrits), puis son `am start` de
# MainActivity part depuis un process EN VEILLE : Android le classe demarrage d'activite en
# arriere-plan et le jeu ne rend jamais rien. Un ecran eteint produit donc exactement la
# signature d'un moteur mort. On REVEILLE, on VERIFIE que l'ecran est ON, et on refuse de
# mesurer sinon — un faux rouge coute autant qu'un faux vert.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=${S:-192.168.1.32:5555}
PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-managed-assets-merge
WATCH=${WATCH:-240}
mkdir -p "$OUT"
say(){ echo "[$(date +%T)] $*"; }

timeout 30 "$ADB" connect "$S" >/dev/null 2>&1 || true
say "reveil de l'appareil"
timeout 30 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
timeout 30 "$ADB" -s "$S" shell wm dismiss-keyguard >/dev/null 2>&1 || true
sleep 3
WAKE=$(timeout 30 "$ADB" -s "$S" shell dumpsys power 2>/dev/null | grep -a 'mWakefulness=' | head -1 | tr -d '\r' | xargs)
DISP=$(timeout 30 "$ADB" -s "$S" shell dumpsys power 2>/dev/null | grep -a 'Display Power' | head -1 | tr -d '\r' | xargs)
say "etat: $WAKE | $DISP"
case "$WAKE" in *Awake*) ;; *) say "FAIL: l'appareil n'est pas reveille — mesure REFUSEE"; exit 2;; esac

CRASH_BEFORE=$(timeout 30 "$ADB" -s "$S" exec-out run-as "$PKG" stat -c '%Y %s' files/gk_crash.txt 2>/dev/null | tr -d '\r' || true)
say "gk_crash.txt AVANT = '${CRASH_BEFORE:-absent}'"

COMP=$(timeout 30 "$ADB" -s "$S" shell cmd package resolve-activity --brief "$PKG" 2>/dev/null | tr -d '\r' | grep "^${PKG}/" | head -1)
[ -n "$COMP" ] || COMP="${PKG}/org.opengoal.gk.LoaderActivity"
timeout 30 "$ADB" -s "$S" shell am force-stop "$PKG" >/dev/null 2>&1
timeout 30 "$ADB" -s "$S" shell logcat -c >/dev/null 2>&1
say "lancement $COMP — observation ${WATCH}s"
timeout 40 "$ADB" -s "$S" shell am start -n "$COMP" >/dev/null 2>&1
timeout $((WATCH + 90)) "$ADB" -s "$S" shell logcat -v time > "$OUT/c5-boot-logcat.txt" 2>&1 &
LOGPID=$!
sleep "$WATCH"
kill "$LOGPID" 2>/dev/null || true; wait "$LOGPID" 2>/dev/null || true

PID=$(timeout 30 "$ADB" -s "$S" shell pidof "$PKG" 2>/dev/null | tr -d '\r')
CRASH_AFTER=$(timeout 30 "$ADB" -s "$S" exec-out run-as "$PKG" stat -c '%Y %s' files/gk_crash.txt 2>/dev/null | tr -d '\r' || true)
L="$OUT/c5-boot-logcat.txt"
say "--- deballage / assets geres ---";  grep -aE 'custom pack unpack|managed assets:' "$L" | tail -5
say "--- entrees GL gatees ---";         grep -a 'A36-GLGATED' "$L" | tail -2
say "--- premieres images / mode ---";   grep -aE 'A35-RENDER frame=|master-mode=' "$L" | head -3
say "--- derniere image ---";            grep -a 'A35-RENDER frame=' "$L" | tail -1
say "--- process du logo ---";           grep -a 'F1A-CAMJOINT' "$L" | tail -2
say "--- signaux fatals ---";            grep -aiE 'Fatal signal|GK-DIAG sig=|beginning of crash' "$L" | tail -6 || true
FATAL=$(grep -acE 'Fatal signal|GK-DIAG sig=' "$L" || true)
MASTER=$(grep -ac 'master-mode=game' "$L" || true)
FRAMES=$(grep -ac 'A35-RENDER frame=' "$L" || true)
say "bilan : fatals=${FATAL:-0} master-mode=game=${MASTER:-0} lignes-image=${FRAMES:-0} pid='${PID:-MORT}' crash='${CRASH_AFTER:-absent}'"
RC=0
[ "${FATAL:-0}" -eq 0 ] || { say "VERDICT: signal fatal present"; RC=1; }
[ -n "$PID" ] || { say "VERDICT: process mort"; RC=1; }
[ "$CRASH_AFTER" = "$CRASH_BEFORE" ] || { say "VERDICT: le fichier du handler a change"; RC=1; }
[ "${MASTER:-0}" -gt 0 ] || { say "VERDICT: master-mode=game jamais atteint"; RC=1; }
say "RC=$RC"
exit $RC

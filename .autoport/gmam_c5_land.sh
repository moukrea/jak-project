#!/usr/bin/env bash
# gmam_c5_land.sh — cycle 5 : reconstruire le pack (fr3 REPRODUCTIBLE), reassembler
# l'APK, et le POSER SUR LES DEUX APPAREILS, avec la preuve d'execution sur la Shield.
#
# POURQUOI CE SCRIPT EXISTE. Le cycle 4 a echoue non pas sur la fusion mais sur la
# gate de cloture : `deploy_verify` compare le TAMPON du pack sur l'appareil avec la
# version que l'ARBRE vient de batir. Trois causes empilees, toutes mesurees :
#   1. `out/jak1/fr3/test-zone.fr3` n'etait PAS reproductible (memoire non initialisee
#      serialisee) : chaque reconstruction changeait la version du pack ;
#   2. le jeu avait ete laisse AU PREMIER PLAN sur le Redmi, ce qui bloque la
#      reconciliation de l'auto-constructeur (garde de 25 min) ;
#   3. personne ne reposait l'APK sur la SHIELD, qui est l'appareil de cette phase.
# Ce script traite (2) et (3) ; (1) est corrige dans le code, en amont.
#
# ORDRE IMPOSE : on batit AVANT, on pose APRES. L'installation est la DERNIERE action.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
SHIELD=192.168.1.32:5555
REDMI=eae4df44
PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
REMOTE=/data/local/tmp/gk-jak1.apk
OUT=.autoport/reports/Grecharged-managed-assets-merge
RUNLOG=.autoport/logs/gmam-c5-land.log
WATCH=${WATCH:-180}

mkdir -p .autoport/logs "$OUT"
exec > >(tee -a "$RUNLOG") 2>&1
say(){ echo "[$(date +%T)] $*"; }
die(){ say "FAIL: $*"; exit 1; }

say "=== c5 : APK gradle (clean + assemble) ==="
# LE `clean` N'EST PAS FACULTATIF. Un `assembleJak1Debug` incremental repete gonfle l'APK
# d'espace mort : mesure du cycle 5, 586 235 921 o avec clean contre 1 015 459 590 o sans,
# soit +73 %, et l'installation sur la Shield tombe en INSTALL_FAILED_INSUFFICIENT_STORAGE.
# L'auto-constructeur porte deja cette garde (auto_build_apk.sh:325) ; l'omettre ici a coute
# une pose. C'est aussi ce qui doublerait le telechargement de l'owner sans que ca se voie.
( cd android && timeout 900 ./gradlew :app:clean ) >/dev/null 2>&1
( cd android && timeout 3000 ./gradlew assembleJak1Debug ) > .autoport/logs/gmam-c5-gradle.log 2>&1 \
  || { tail -40 .autoport/logs/gmam-c5-gradle.log; die "gradle"; }
[ -f "$APK" ] || die "pas d'APK"
APK_MD5=$(md5sum "$APK" | cut -d' ' -f1)
WANT_C=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
WANT_G=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
APK_C=$(unzip -p "$APK" assets/bundle/jak1_custom.manifest.properties | grep -E '^version=' | cut -d= -f2)
[ "$APK_C" = "$WANT_C" ] || die "l'APK embarque '$APK_C' et l'arbre a bati '$WANT_C'"
APK_SZ=$(stat -c %s "$APK")
[ "$APK_SZ" -le 700000000 ] || die "APK anormalement gros ($APK_SZ o) — espace mort de gradle, on ne pose pas"
say "APK $APK_SZ o md5=${APK_MD5:0:12} custom=$WANT_C cgo=$WANT_G"

# --- pose sur un appareil, puis relit LES TAMPONS SUR L'APPAREIL (trace, pas intention)
poser(){
  local S=$1 label=$2 push=$3 i got_c got_g comp
  say "--- $label ($S) : installation"
  timeout 30 "$ADB" connect "$S" >/dev/null 2>&1 || true
  timeout 30 "$ADB" devices | grep -qE "^${S}[[:space:]]+device$" || { say "$label ABSENT"; return 1; }
  if [ "$push" = push ]; then
    timeout 60 "$ADB" -s "$S" shell rm -f "$REMOTE" >/dev/null 2>&1 || true
    timeout 1800 "$ADB" -s "$S" push "$APK" "$REMOTE" 2>&1 | tail -1
    local dm; dm=$(timeout 180 "$ADB" -s "$S" shell md5sum "$REMOTE" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
    [ "$dm" = "$APK_MD5" ] || { say "$label: md5 pousse '$dm' != '$APK_MD5'"; return 1; }
    local oi; oi=$(timeout 1800 "$ADB" -s "$S" shell pm install -r -d -t "$REMOTE" 2>&1 | tr -d '\r' | tail -2)
    say "$label pm install -> $oi"
    echo "$oi" | grep -q Success || return 1
    timeout 60 "$ADB" -s "$S" shell rm -f "$REMOTE" >/dev/null 2>&1 || true
  else
    timeout 1800 "$ADB" -s "$S" install -r "$APK" 2>&1 | tail -2 | grep -q Success || return 1
  fi
  # REVEILLER L'ECRAN AVANT DE LANCER. Un appareil endormi classe le `am start` de
  # MainActivity en demarrage d'activite EN ARRIERE-PLAN (TOP_SLEEPING) et le jeu ne rend
  # jamais rien : signature identique a celle d'un moteur mort. Mesure du cycle 5.
  timeout 30 "$ADB" -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  timeout 30 "$ADB" -s "$S" shell wm dismiss-keyguard >/dev/null 2>&1 || true
  sleep 3
  local wk; wk=$(timeout 30 "$ADB" -s "$S" shell dumpsys power 2>/dev/null | grep -a 'mWakefulness=' | head -1 | tr -d '\r' | xargs)
  say "$label etat ecran : $wk"
  case "$wk" in *Awake*) ;; *) say "$label PAS REVEILLE — la mesure qui suit serait un faux rouge"; return 1;; esac

  # LoaderActivity, JAMAIS MainActivity : elle seule deballe les packs et ecrit les tampons.
  comp=$(timeout 30 "$ADB" -s "$S" shell cmd package resolve-activity --brief "$PKG" 2>/dev/null \
           | tr -d '\r' | grep "^${PKG}/" | head -1)
  [ -n "$comp" ] || comp="${PKG}/org.opengoal.gk.LoaderActivity"
  timeout 30 "$ADB" -s "$S" shell am force-stop "$PKG" >/dev/null 2>&1
  timeout 30 "$ADB" -s "$S" shell logcat -c >/dev/null 2>&1
  timeout 40 "$ADB" -s "$S" shell am start -n "$comp" >/dev/null 2>&1 || { say "$label am start KO"; return 1; }
  for i in $(seq 1 60); do
    sleep 10
    got_c=$(timeout 30 "$ADB" -s "$S" exec-out run-as "$PKG" cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
    got_g=$(timeout 30 "$ADB" -s "$S" exec-out run-as "$PKG" cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r\n')
    [ "$got_c" = "$WANT_C" ] && [ "$got_g" = "$WANT_G" ] && break
  done
  say "$label tampons relus SUR L'APPAREIL : custom='$got_c' cgo='$got_g' (attendus '$WANT_C' '$WANT_G')"
  [ "$got_c" = "$WANT_C" ] && [ "$got_g" = "$WANT_G" ]
}

RC=0

# 1. SHIELD — appareil de cette phase, et c'est la que se fait la preuve d'execution.
CRASH_BEFORE=$(timeout 30 "$ADB" -s $SHIELD exec-out run-as $PKG stat -c '%Y %s' files/gk_crash.txt 2>/dev/null | tr -d '\r' || true)
say "Shield gk_crash.txt AVANT = '${CRASH_BEFORE:-absent}'"
poser "$SHIELD" SHIELD push || { say "VERDICT: la pose sur la Shield a echoue"; RC=1; }

say "=== c5 : observation ${WATCH}s sur la Shield (l'application vient d'etre lancee) ==="
timeout $((WATCH + 90)) "$ADB" -s $SHIELD shell logcat -v time > "$OUT/c5-boot-logcat.txt" 2>&1 &
LOGPID=$!
sleep "$WATCH"
kill "$LOGPID" 2>/dev/null || true; wait "$LOGPID" 2>/dev/null || true

PID=$(timeout 30 "$ADB" -s $SHIELD shell pidof $PKG 2>/dev/null | tr -d '\r')
CRASH_AFTER=$(timeout 30 "$ADB" -s $SHIELD exec-out run-as $PKG stat -c '%Y %s' files/gk_crash.txt 2>/dev/null | tr -d '\r' || true)
L="$OUT/c5-boot-logcat.txt"
say "--- balayage des entrees GL gatees ---";        grep -a 'A36-GLGATED' "$L" | tail -2
say "--- assets geres ---";                          grep -aE 'managed assets:|managed_assets:' "$L" | tail -6
say "--- master-mode / images ---";                  grep -aE 'master-mode=|A35-RENDER frame=' "$L" | tail -4
say "--- process logo ---";                          grep -a 'F1A-CAMJOINT' "$L" | tail -2
say "--- signaux fatals ---";                        grep -aiE 'Fatal signal|GK-DIAG sig=|beginning of crash' "$L" | tail -6 || true
FATAL=$(grep -acE 'Fatal signal|GK-DIAG sig=' "$L" || true)
MASTER=$(grep -ac 'master-mode=game' "$L" || true)
say "bilan Shield : fatals=${FATAL:-0} master-mode=game=${MASTER:-0} pid='${PID:-MORT}' crash='${CRASH_AFTER:-absent}'"
[ "${FATAL:-0}" -eq 0 ] || { say "VERDICT: signal fatal present"; RC=1; }
[ -n "$PID" ]           || { say "VERDICT: process mort avant la fin"; RC=1; }
[ "$CRASH_AFTER" = "$CRASH_BEFORE" ] || { say "VERDICT: gk_crash.txt a change"; RC=1; }
[ "${MASTER:-0}" -gt 0 ] || { say "VERDICT: master-mode=game jamais atteint"; RC=1; }

# 2. REDMI — c'est le serial par defaut de deploy_verify ; il doit porter le meme build.
poser "$REDMI" REDMI install || { say "VERDICT: la pose sur le Redmi a echoue"; RC=1; }

# 3. NE PAS LAISSER LE JEU AU PREMIER PLAN : c'est ce qui a bloque la reconciliation
#    de l'auto-constructeur pendant 25 min au cycle 4.
for S in $SHIELD $REDMI; do timeout 30 "$ADB" -s "$S" shell am force-stop "$PKG" >/dev/null 2>&1; done
say "jeu arrete sur les deux appareils (la reconciliation ne peut plus etre bloquee)"

say "=== c5 : deploy_verify sur LES DEUX appareils ==="
for S in $SHIELD $REDMI; do
  if timeout 2400 bash .autoport/lib/deploy_verify.sh "$S" jak1; then say "DEPLOY-VERIFY PASS $S"; else say "DEPLOY-VERIFY FAIL $S"; RC=1; fi
done

say "=== c5 : RC=$RC ==="
exit "$RC"

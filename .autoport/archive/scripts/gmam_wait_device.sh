#!/usr/bin/env bash
# Attendre le retour de la appareil de test (elle est tombee : ping 100 % de perte), puis rejouer
# UNE fois install + lancement + deploy_verify. Borne a 30 min d'attente, une seule
# tentative : une boucle non bornee sur un appareil casse ne prouve rien et masque l'etat.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=eae4df44; PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
LOCK=.autoport/.deploy-in-progress
printf 'gmam_wait_device pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
exec > >(tee -a .autoport/logs/gmam-wait-device.log) 2>&1
say(){ echo "[$(date +%T)] $*"; }
WANT=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
say "attente du retour de $S (pack attendu $WANT)"
UP=0
for i in $(seq 1 60); do
  if "${ADB:-adb}" -s eae4df44 get-state >/dev/null 2>&1; then
    "$ADB" disconnect $S >/dev/null 2>&1; sleep 2
    "$ADB" connect $S >/dev/null 2>&1; sleep 3
    if [ "$(timeout 20 "$ADB" -s $S shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
      say "revenue apres $((i*30))s"; UP=1; break
    fi
  fi
  sleep 30
done
[ "$UP" = 1 ] || { say "TOUJOURS INJOIGNABLE apres 30 min — arret, l'appareil demande une intervention physique"; exit 2; }
say "volume: $(timeout 20 "$ADB" -s $S shell sm list-volumes all 2>/dev/null | grep ff091cb1 | tr -d '\r' || echo absent)"
say "install"
timeout 600 "$ADB" -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3
say "lancement"
timeout 30 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1
timeout 30 "$ADB" -s $S shell logcat -c >/dev/null 2>&1
timeout 30 "$ADB" -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null 2>&1
for i in $(seq 1 30); do
  sleep 6
  ST=$(timeout 20 "$ADB" -s $S exec-out run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n' || true)
  M=$(timeout 20 "$ADB" -s $S shell logcat -d -s opengoal-gk 2>/dev/null | grep -cE 'master-mode=game' || echo 0)
  say "  [$i] stamp='${ST:-vide}' master=$M"
  [ "$ST" = "$WANT" ] && [ "${M:-0}" -gt 0 ] && break
done
say "deploy_verify"
timeout 900 bash .autoport/lib/deploy_verify.sh $S jak1
say "deploy_verify RC=$?"

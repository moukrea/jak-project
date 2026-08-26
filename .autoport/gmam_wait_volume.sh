#!/usr/bin/env bash
# Attendre que le volume adopte de la Shield sorte de l'etat `checking` : tant qu'il y
# est, Zygote echoue a monter /mnt/expand/<uuid>/user et AUCUNE application ne peut
# demarrer (shieldbeta et tegrazone3 de NVIDIA tombent pareil). Puis re-tester le
# demarrage du jeu et deploy_verify.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=192.168.1.32:5555
LOG=.autoport/logs/gmam-volume-wait.log
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date -Is) attente du volume adopte ==="
for i in $(seq 1 120); do   # jusqu'a 60 min
  sleep 30
  "$ADB" connect $S >/dev/null 2>&1
  V=$("$ADB" -s $S shell sm list-volumes all 2>/dev/null | grep ff091cb1 | tr -d '\r')
  echo "[$(date +%T)] ${V:-<absent de la liste>}"
  case "$V" in
    *mounted*) echo "MONTE"; break;;
    "") echo "ABSENT (vold a lache) — Zygote ne tentera plus le montage"; break;;
  esac
done
echo "--- test de demarrage ---"
"$ADB" -s $S shell am force-stop org.opengoal.gk.jak1
"$ADB" -s $S shell logcat -c
T0=$(date +%s)
"$ADB" -s $S shell am start -n org.opengoal.gk.jak1/org.opengoal.gk.LoaderActivity >/dev/null 2>&1
for i in $(seq 1 20); do
  sleep 4
  M=$("$ADB" -s $S shell logcat -d -s opengoal-gk 2>/dev/null | grep -cE 'master-mode=game')
  if [ "${M:-0}" -gt 0 ]; then echo "BOOT OK apres $(( $(date +%s) - T0 ))s"; break; fi
done
echo "--- deploy_verify ---"
bash .autoport/lib/deploy_verify.sh $S jak1
echo "RC=$?"

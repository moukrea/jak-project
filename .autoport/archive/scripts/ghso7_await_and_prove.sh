#!/usr/bin/env bash
# Ghd-skin-origin-stretch cycle 7 — attend le DEVERROUILLAGE du Redmi (action owner), puis lance
# les trois jambes (ablation affine_arm=1, controle positif inject=2, preuve affine_arm=2),
# assemble report.txt et lance le validateur. Ne touche a rien tant que l'ecran est verrouille.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; [ -x "$ADB" ] || ADB=$(command -v adb)
SER=eae4df44; R=.autoport/reports/Ghd-skin-origin-stretch; D=$R/device
a(){ "$ADB" -s "$SER" "$@"; }
locked(){ a shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; }
say(){ echo "$(date +%H:%M:%S) $*"; }

say "attente du deverrouillage du Redmi (l'owner doit deverrouiller une fois)…"
for i in $(seq 1 720); do            # jusqu'a ~6 h (30 s x 720)
  a devices 2>/dev/null | grep -qE "^${SER}[[:space:]]+device$" || { sleep 30; continue; }
  a shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  if ! locked; then say "DEVERROUILLE — lancement des jambes"; break; fi
  sleep 30
done
if locked; then say "TOUJOURS VERROUILLE apres l'attente — abandon, l'owner doit deverrouiller"; exit 3; fi

# garder eveille
a shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1
a shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1

say "== JAMBE 1/3 : ABLATION (affine_arm=0, defaut brut -> os_etires>=1 et sauts de racine)"
SCENES="citadel-start:150:brusque finalboss-start:150:brusque" AFFARM=0 bash .autoport/ghso6_device_leg.sh 0 dev7-abl0 150
say "== JAMBE 2/3 : CONTROLE POSITIF des detecteurs (inject=2 pose de bind, affine_arm=2)"
SCENES="village3-start:120:brusque" AFFARM=2 bash .autoport/ghso6_device_leg.sh 2 dev7-inj2 120
say "== JAMBE 3/3 : PREUVE (affine_arm=2, 5 scenes, >= 10 min)"
AFFARM=2 bash .autoport/ghso6_device_leg.sh 0 dev7-prf 240

say "== assemblage de report.txt"
python3 .autoport/ghso7_assemble_report.py
say "== validateur"
bash .autoport/validators/phase-Ghd-skin-origin-stretch.sh; rc=$?
say "validateur exit=$rc"
exit $rc

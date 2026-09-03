#!/usr/bin/env bash
# Ghd-skin-origin-stretch cycle 7b — attend (1) le DEVERROUILLAGE du Redmi (action owner, aucun
# contournement : memoire device-pin-lock-wait-for-owner) et (2) un auto-constructeur au repos avec le
# pack CGO du telephone == celui de l'arbre ; puis enchaine les quatre jambes sur le MEME APK :
#   abl1 : affine_arm=1 (l'ancien correctif, celui que l'owner a teste le 03/09) -> le SAUT DE RACINE
#          doit reapparaitre (translation du modele entier de (1-s).|t|) ;
#   abl0 : affine_arm=0 (defaut brut) -> l'ETIREMENT doit reapparaitre (os_etires >= 1) ;
#   inj2 : controle positif des deux detecteurs (pose de bind ecrite une image sur 300) ;
#   prf  : affine_arm=2 (normalisation a la production + consommateur projectif), 5 scenes, >= 10 min.
# Puis assemble report.txt et lance le validateur. Rien n'est fabrique : sans course, porte rouge.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; [ -x "$ADB" ] || ADB=$(command -v adb)
SER=eae4df44; PKG=org.opengoal.gk.jak1
R=.autoport/reports/Ghd-skin-origin-stretch; D=$R/device; mkdir -p "$D"
LOGB=.autoport/logs/auto_build_apk.txt
LOCK=.autoport/.deploy-in-progress
a(){ "$ADB" -s "$SER" "$@"; }
say(){ echo "$(date +%H:%M:%S) $*"; }
locked(){ a shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; }
present(){ a devices 2>/dev/null | grep -qE "^${SER}[[:space:]]+device$"; }
builder_idle(){
  local last; last=$(tail -1 "$LOGB" 2>/dev/null)
  case "$last" in
    *"installe et deballe"*|*"prets pour le commit"*|*"a jour"*|*"ignore"*|*"absent"*|*"on ne rebatit pas"*) ;;
    *) return 1 ;;
  esac
  local ph tr
  ph=$(a exec-out run-as $PKG cat files/.cgo_pack_stamp_jak1 2>/dev/null | tr -d '\r')
  tr=$(grep '^version=' android/app/src/jak1/assets-slim/bundle/jak1_cgo.manifest.properties | cut -d= -f2)
  [ -n "$ph" ] && [ "$ph" = "$tr" ]
}
wait_unlocked(){
  local i
  for i in $(seq 1 1440); do            # jusqu'a ~12 h (30 s x 1440)
    if present; then
      a shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1   # ecran allume = le signal pour l'owner
      if ! locked; then
        if builder_idle; then return 0; fi
        say "deverrouille mais constructeur occupe / pack telephone != arbre ($(tail -1 "$LOGB" | cut -c1-80)) — attente"
      fi
    fi
    sleep 30
  done
  return 1
}

say "attente du deverrouillage du Redmi (l'owner doit deverrouiller une fois) + constructeur au repos…"
wait_unlocked || { say "TOUJOURS VERROUILLE apres l'attente — abandon, l'owner doit deverrouiller"; exit 3; }
say "DEVERROUILLE, constructeur au repos, pack telephone == arbre — lancement des jambes"
a shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1
a shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1
a shell svc power stayon true >/dev/null 2>&1

# verrou de livraison tenu pour TOUTE la sequence (les jambes le remplacent puis le reposent)
printf 'ghso7b pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

leg(){
  local label="$1"; shift
  if locked; then say "reverrouille avant $label — nouvelle attente"; wait_unlocked || exit 3; printf 'ghso7b pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"; fi
  say "== $label"
  "$@"
  say "== fin $label (rc=$?)"
}
leg "JAMBE 1/4 : ABLATION affine_arm=1 (ancien correctif : saut de racine attendu)" \
  env SCENES="citadel-start:150:brusque finalboss-start:150:brusque" AFFARM=1 bash .autoport/ghso6_device_leg.sh 0 dev7-abl1 150
leg "JAMBE 2/4 : ABLATION affine_arm=0 (defaut brut : etirement attendu)" \
  env SCENES="citadel-start:120:brusque finalboss-start:120:brusque" AFFARM=0 bash .autoport/ghso6_device_leg.sh 0 dev7-abl0 120
leg "JAMBE 3/4 : CONTROLE POSITIF inject=2 (pose de bind, affine_arm=2)" \
  env SCENES="village3-start:120:brusque" AFFARM=2 bash .autoport/ghso6_device_leg.sh 2 dev7-inj2 120
leg "JAMBE 4/4 : PREUVE affine_arm=2, 5 scenes, >= 10 min" \
  env AFFARM=2 bash .autoport/ghso6_device_leg.sh 0 dev7-prf 240

say "== assemblage de report.txt"
python3 .autoport/ghso7_assemble_report.py
say "== validateur"
bash .autoport/validators/phase-Ghd-skin-origin-stretch.sh; rc=$?
say "validateur exit=$rc"
touch "$R/dev7-DONE"
exit $rc

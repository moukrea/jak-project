#!/usr/bin/env bash
# gmam_c3_land.sh — cycle 3 : saisir la premiere fenetre saine de la appareil de test et y
# poser l'APK COURANT, puis prouver par deploy_verify.
#
# DIFFERENCE AVEC gmam_grab_window.sh (cycle 2, qui a echoue 4 fois) :
#   (a) l'APK est POUSSE d'abord (`adb push`, simple transfert de fichier), et
#       seulement ENSUITE installe (`pm install <chemin>`). Le cycle 2 streamait
#       les 586 Mo A TRAVERS le service package (`adb install`), qui meurt en
#       cours de route : « Failure calling service package: Broken pipe (32) ».
#       Separer les deux reduit le temps ou le service package doit rester vivant
#       de plusieurs minutes a quelques dizaines de secondes ;
#   (b) le pousse est REPRENABLE : si /data/local/tmp/gk-jak1.apk a deja le bon
#       md5, on ne le repousse pas — une fenetre suivante n'a plus que l'install ;
#   (c) un paquet Wake-on-LAN est envoye a chaque tour. La appareil de test le supporte ; si
#       elle est en veille (et non plantee), ca ouvre la fenetre au lieu de
#       l'attendre. Aucun effet si elle est plantee, aucun risque si elle dort ;
#   (d) l'etat du service package est SONDE et JOURNALISE a chaque fenetre
#       (`pm path`), pour distinguer « appareil injoignable » de « appareil
#       joignable mais system_server casse » — les deux se presentent au validateur
#       comme « package not installed », et les confondre envoie chercher une
#       regression fantome.
#
# CE QU'IL NE FAIT PAS, DELIBEREMENT : aucun `sm unmount`, `sm forget`, ni aucune
# manipulation du volume adopte de l'owner (114 Go). La panne est materielle (e2fsck
# bloque en etat D sur des E/S) ; la defaire demande son accord et sa main.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44
IP=eae4df44
MAC=48:b0:2d:33:9b:53
PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
REMOTE=/data/local/tmp/gk-jak1.apk
LOCK=.autoport/.deploy-in-progress
DEADLINE_MIN="${1:-240}"

printf 'gmam_c3_land pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
mkdir -p .autoport/logs .autoport/reports
exec > >(tee -a .autoport/logs/gmam-c3-land.log) 2>&1
say(){ echo "[$(date +%T)] $*"; }

WANT=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
APK_MD5=$(md5sum "$APK" | cut -d' ' -f1)
say "=== c3 : chasse a la fenetre. pack attendu=$WANT  apk_md5=${APK_MD5:0:12}  deadline=${DEADLINE_MIN}min"

wol(){ python3 - "$MAC" <<'PY' 2>/dev/null || true
import socket,sys
mac=sys.argv[1].replace(':','')
pkt=b'\xff'*6+bytes.fromhex(mac)*16
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1)
for port in (9,7):
    for host in ('192.168.1.255','255.255.255.255'):
        try: s.sendto(pkt,(host,port))
        except OSError: pass
PY
}

END=$(( $(date +%s) + DEADLINE_MIN*60 ))
ROUND=0
while [ "$(date +%s)" -lt "$END" ]; do
  ROUND=$((ROUND+1))
  wol
  if ! ping -c 1 -W 2 "$IP" >/dev/null 2>&1; then
    [ $((ROUND % 10)) -eq 0 ] && say "tour $ROUND : injoignable (ping)"
    sleep 20; continue
  fi
  say "tour $ROUND : la appareil de test repond au ping — tentative de fenetre"
  timeout 20 "$ADB" disconnect $S >/dev/null 2>&1; sleep 1
  timeout 25 "$ADB" connect $S >/dev/null 2>&1; sleep 2
  BC=$(timeout 20 "$ADB" -s $S shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$BC" != "1" ]; then say "   boot_completed='$BC' — pas encore"; sleep 15; continue; fi

  # --- sonde du service package : la distinction qui compte ---
  PMPATH=$(timeout 30 "$ADB" -s $S shell pm path $PKG 2>&1 | tr -d '\r' | head -1)
  say "   service package : pm path -> '${PMPATH:-VIDE}'"

  # --- (b) pousse reprenable ---
  DEV_MD5=$(timeout 60 "$ADB" -s $S shell md5sum "$REMOTE" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
  if [ "$DEV_MD5" != "$APK_MD5" ]; then
    say "   pousse de l'APK (586 Mo) vers $REMOTE — md5 appareil='${DEV_MD5:-absent}'"
    timeout 1800 "$ADB" -s $S push "$APK" "$REMOTE" 2>&1 | tail -1
    DEV_MD5=$(timeout 60 "$ADB" -s $S shell md5sum "$REMOTE" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
  fi
  if [ "$DEV_MD5" != "$APK_MD5" ]; then say "   pousse INCOMPLET (md5 '${DEV_MD5:-vide}') — on retente au tour suivant"; sleep 20; continue; fi
  say "   APK present et INTEGRE sur l'appareil (md5 verifie)"

  # --- installation courte, depuis le fichier deja pose ---
  say "   pm install depuis $REMOTE"
  OUT=$(timeout 900 "$ADB" -s $S shell pm install -r -d -t "$REMOTE" 2>&1 | tr -d '\r' | tail -3)
  say "   pm install -> $OUT"
  echo "$OUT" | grep -q 'Success' || { say "   install refusee — on retente au tour suivant"; sleep 30; continue; }

  # --- lancement + attente du depaquetage ---
  timeout 20 "$ADB" -s $S shell am force-stop $PKG >/dev/null 2>&1
  timeout 20 "$ADB" -s $S shell logcat -c >/dev/null 2>&1
  timeout 25 "$ADB" -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null 2>&1
  for i in $(seq 1 40); do
    sleep 15
    ST=$(timeout 20 "$ADB" -s $S exec-out run-as $PKG cat files/.custom_pack_stamp_jak1 2>/dev/null | tr -d '\r\n' || true)
    M=$(timeout 25 "$ADB" -s $S shell logcat -d -s opengoal-gk 2>/dev/null | grep -c 'master-mode=game' || true)
    [ $((i % 4)) -eq 0 ] && say "   attente depaquetage : stamp='${ST:-vide}' (veut $WANT)  master-mode=game x${M:-0}"
    if [ "$ST" = "$WANT" ] && [ "${M:-0}" -gt 0 ]; then
      say "   PACK A JOUR + master-mode=game — verification"
      if timeout 1800 bash .autoport/lib/deploy_verify.sh $S jak1; then
        say "DEPLOY-VERIFY PASS — gate de cloture satisfaite"
        date -Is > .autoport/reports/gmam-c3-deploy-ok.txt
        exit 0
      fi
      say "   deploy_verify a echoue malgre stamp+master — voir sa sortie ci-dessus"
      break
    fi
  done
  say "   fenetre perdue avant la preuve — on repart"
  sleep 20
done
say "ABANDON apres ${DEADLINE_MIN} min : aucune fenetre saine. Intervention PHYSIQUE requise sur la cle USB adoptee."
exit 2

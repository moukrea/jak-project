#!/usr/bin/env bash
# gls_wait_device.sh — Gloading-screen: wait for the Redmi eae4df44 ONLY.
#
# La Shield (192.168.1.32) est INTERDITE (owner 2026-08-28) : c'est sa television.
# On ne s'y connecte jamais, on ne substitue jamais son serial. Verifie a chaque tour.
#
# POURQUOI ON N'INSTALLE PAS NOUS-MEMES. Le telephone a ete debranche EN PLEINE
# installation (03:13:43), il porte donc un APK pose avec des packs NON deballes.
# `auto_build_apk.sh` (demon vivant) refait sa reconciliation a chaque tour et est le
# SEUL ecrivain de cette installation : lancer un second installeur en parallele
# ferait deux ecrivains sur le meme paquet. On attend donc que SON travail aboutisse
# — tampon custom == version batie — puis on mesure.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
FORBIDDEN=192.168.1.32          # Shield — jamais, sous aucun pretexte
PKG=org.opengoal.gk.jak1
WAIT_S="${1:-3000}"
OUT=.autoport/reports/Gloading-screen/device-wait.txt
mkdir -p "$(dirname "$OUT")"
WANT=$(grep -E '^version=' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties | cut -d= -f2)
t0=$(date +%s)
say(){ echo "[$(date '+%F %T')] $*" >> "$OUT"; }
: > "$OUT"
say "attente de $S (et de lui seul) jusqu'a ${WAIT_S}s — Shield $FORBIDDEN exclue par consigne owner"
say "version de pack attendue sur l'appareil : $WANT"
while :; do
  # Garde-fou : si la Shield s'est invitee dans la liste (adb connect d'un autre outil),
  # on la retire au lieu de risquer qu'un pas suivant la vise.
  if "$ADB" devices 2>/dev/null | grep -q "^${FORBIDDEN}:"; then
    say "GARDE : $FORBIDDEN (Shield) presente dans adb — deconnexion immediate, rien ne lui est envoye"
    "$ADB" disconnect "${FORBIDDEN}:5555" >/dev/null 2>&1 || true
  fi
  if "$ADB" devices 2>/dev/null | grep -qE "^${S}[[:space:]]+device$"; then
    say "$S EST REVENU sur le bus"
    # Laisser le demon finir SA reconciliation (installation + depaquetage).
    for i in $(seq 1 120); do
      ST=$("$ADB" -s "$S" exec-out run-as "$PKG" cat "files/.custom_pack_stamp_jak1" 2>/dev/null | tr -d '\r\n' || true)
      say "  [$((i*15))s] tampon custom='${ST:-vide}' attendu='$WANT'"
      [ "$ST" = "$WANT" ] && break
      "$ADB" devices 2>/dev/null | grep -qE "^${S}[[:space:]]+device$" || { say "  $S reparti pendant l'attente du depaquetage"; break; }
      sleep 15
    done
    say "--- deploy_verify ---"
    bash .autoport/lib/deploy_verify.sh "$S" jak1 >> "$OUT" 2>&1
    rc=$?
    say "deploy_verify exit=$rc"
    exit $rc
  fi
  now=$(date +%s); [ $((now - t0)) -ge "$WAIT_S" ] && break
  sleep 20
done
say "TIMEOUT apres ${WAIT_S}s — $S n'est jamais reapparu sur le bus USB"
exit 2

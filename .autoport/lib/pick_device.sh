#!/usr/bin/env bash
# pick_device.sh — QUEL appareil sert de preuve, decide a l'execution.
#
# Owner 2026-09-06 : « C'est debile de bloquer la validation quand le HONOR est branche a la
# place du Redmi ! Le jeu est plus performant sur le HONOR, c devrait etre mieux pour collecter
# des preuves ! » Il a raison : le harnais ecrivait eae4df44 en dur et une nuit entiere de
# travail a ete perdue parce que son Honor occupait le port USB.
#
# REGLES :
#   1. ANDROID_SERIAL, s'il est pose ET que l'appareil repond, gagne toujours.
#   2. Sinon on prend un appareil JOINT PAR USB, en etat `device`. S'il y en a plusieurs, on
#      prefere le plus rapide connu (table ci-dessous), puis l'ordre d'apparition.
#   3. Tout ce qui se joint par une ADRESSE RESEAU est ecarte, sans exception et sans lire
#      laquelle : c'est ce qui tient la SHIELD dehors, et ca reste vrai si son adresse change.
#   4. Aucun appareil -> code 3 et un message qui dit quoi faire. Jamais de repli silencieux
#      sur un numero de serie ecrit en dur : c'est ainsi qu'on prouve sur un telephone absent.
#
# Sortie : le numero de serie sur stdout. Les explications vont sur stderr.
set -uo pipefail
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; [ -x "$ADB" ] || ADB=adb

# Cadence mesuree, du plus rapide au plus lent. Un appareil inconnu passe apres les connus
# mais reste parfaitement utilisable : la preuve dit sur quoi elle a tourne.
rang() {
  case "$1" in
    AREE026206000788) echo 0 ;;   # Honor, Snapdragon 8 Elite, 60-120 Hz
    eae4df44)         echo 1 ;;   # Redmi Note 9 Pro, ~20-30 img/s
    *)                echo 5 ;;
  esac
}

attache() { [ "$(timeout 10 "$ADB" -s "$1" get-state 2>/dev/null | tr -d '\r')" = device ]; }

if [ -n "${ANDROID_SERIAL:-}" ]; then
  case "$ANDROID_SERIAL" in
    *:*|*_adb-tls-*) echo "[pick_device] ANDROID_SERIAL='$ANDROID_SERIAL' est une adresse reseau : refuse." >&2; exit 3 ;;
  esac
  if attache "$ANDROID_SERIAL"; then echo "$ANDROID_SERIAL"; exit 0; fi
  echo "[pick_device] ANDROID_SERIAL='$ANDROID_SERIAL' ne repond pas ; on cherche autre chose." >&2
fi

MEILLEUR=""; MEILLEUR_RANG=99
while read -r s etat _; do
  [ "$etat" = device ] || continue
  case "$s" in *:*|*_adb-tls-*|'') continue ;; esac
  r=$(rang "$s")
  if [ "$r" -lt "$MEILLEUR_RANG" ]; then MEILLEUR="$s"; MEILLEUR_RANG="$r"; fi
done < <(timeout 15 "$ADB" devices 2>/dev/null | tail -n +2)

if [ -z "$MEILLEUR" ]; then
  echo "[pick_device] AUCUN appareil joint par USB. Branche-en un (n'importe lequel : le harnais" >&2
  echo "              s'adapte et la preuve dira lequel). Une adresse reseau ne compte pas." >&2
  exit 3
fi
echo "$MEILLEUR"

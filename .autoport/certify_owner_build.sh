#!/usr/bin/env bash
# CERTIFIE UN BUILD POUR L'OWNER, ET LE MET HORS D'ATTEINTE DU FLUX CONTINU.
#
# 2026-08-20 21:05 — POURQUOI CE SCRIPT EXISTE. J'ai annonce a l'owner de tester le build de 18:48,
# dont j'avais verifie le contenu ligne a ligne. Quand il a demande « j'ai quoi a tester
# concretement ? », **ce build n'existait plus** : `app-jak1-HD-recharged.apk` est un nom UNIQUE,
# et les publications suivantes (dont un point de sauvegarde pris au milieu d'une edition) l'avaient
# ecrase, localement ET sur la release. Je l'envoyais tester un fichier disparu.
#
# Un build CERTIFIE porte donc son propre nom, que le demon de publication ne touche jamais.
set -uo pipefail
cd "$(dirname "$0")/.."
SRC=.autoport/dist/app-jak1-HD-recharged.apk
DST=.autoport/dist/app-jak1-HD-OWNER-TEST.apk
[ -f "$SRC" ] || { echo "pas d'APK a certifier"; exit 1; }
h=$(md5sum "$SRC" | cut -d' ' -f1)
cp -f "$SRC" "$DST"
{ echo "certifie=$(date '+%F %H:%M')"
  echo "md5=$h"
  echo "raison=${1:-non precisee}"
} > .autoport/dist/OWNER-TEST-INFO.txt
echo "certifie ${h:0:8} -> $DST"
gh release upload jak1-rtlight-wip "$DST" .autoport/dist/OWNER-TEST-INFO.txt \
   --repo moukrea/jak-builds --clobber && echo "publie sous app-jak1-HD-OWNER-TEST.apk"

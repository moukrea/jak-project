#!/usr/bin/env bash
# build_tag.sh — un identifiant COURT et VERIFIABLE du build, ecrit la ou l'owner peut le lire.
#
# Probleme resolu (2026-08-11 17:45) : l'owner a juge un build vieux de 28 minutes en croyant
# tester le dernier, et a conclu « aucune différence » sur des reglages qui n'y etaient pas.
# Personne ne pouvait dire quel APK il avait. Desormais chaque build porte un tag de 6 caracteres,
# ecrit dans le nom du fichier publie ET dans BUILD-INFO.txt, et lisible sur le device dans le
# marqueur d'extraction : il suffit de comparer.
set -euo pipefail
cd "$(dirname "$0")/.."
sha=$(git rev-parse --short=6 HEAD)
# Le manifeste est un PRODUIT du build (2026-09-20) : il n'est plus suivi par git, donc il
# n'existe pas tant que rien n'a ete empaquete. Sous `set -e` + `pipefail`, le rc=2 du grep
# tuait ce script sur un clone frais — pour un tag dont la moitie est de toute facon vide.
# `|| true` rend l'absence LISIBLE (`<sha>-`) au lieu de fatale.
pack=$( { grep -E '^version' android/app/src/jak1/assets-slim/bundle/jak1_custom.manifest.properties 2>/dev/null || true; } | cut -d= -f2 | cut -c1-6)
echo "${sha}-${pack}"

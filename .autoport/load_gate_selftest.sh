#!/usr/bin/env bash
# Gplayability-input-and-loadgate — controle positif de la barriere de chargement.
# Prouve les proprietes de SURETE de game/system/load_gate.cpp sans appareil :
# fail-open, ouverture au premier tour quand tout est resident, liberation au
# delai, et expiration d'un armement abandonne. Une barriere qui peut bloquer le
# jeu serait pire que le defaut qu'elle corrige — donc ca se prouve, pas ca se dit.
set -euo pipefail
cd "$(dirname "$0")/.."
g++ -std=c++17 -I. -Ithird-party/fmt/include -DFMT_HEADER_ONLY=1 \
    .autoport/load_gate_selftest.cpp game/system/load_gate.cpp -o /tmp/load_gate_selftest
exec /tmp/load_gate_selftest

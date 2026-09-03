#!/usr/bin/env bash
# Enchaine les courses restantes, une a la fois (un seul gk, un seul verrou de livraison).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
bash .autoport/gjcc_x86_run.sh b60 60 0   # 60 img/s, comportement d'ORIGINE (bracket haut)
bash .autoport/gjcc_x86_run.sh p2  10 1   # 10 img/s, correctif arme
bash .autoport/gjcc_x86_run.sh p3  10 1   # 10 img/s, correctif arme
echo "GJCC-CHAIN-DONE"

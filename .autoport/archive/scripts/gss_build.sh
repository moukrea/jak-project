#!/usr/bin/env bash
# Gsubtitle-style : build GOAL x86 (changement GOAL SEUL -> pas de rebuild C++/NDK).
# Prend le verrou de livraison avec SON PROPRE PID VIVANT (DIRECTIVES 2026-08-14 07:10) :
# ce script tourne en arriere-plan, donc `$$` designe un processus reellement en vie tant
# que le build dure -- contrairement au shell d'un appel d'outil, qui sort dans la seconde.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=.autoport/.deploy-in-progress
printf 'gss_build pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
OUT=.autoport/reports/Gsubtitle-style
mkdir -p "$OUT"
: > "$OUT/build.log"
stdbuf -oL -eL timeout 1800 build-x86/goalc/goalc --game jak1 --proj-path . --disable-ansi \
  --cmd '(build-game)' >> "$OUT/build.log" 2>&1
echo "EXIT=$?" >> "$OUT/build.log"

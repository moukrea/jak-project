#!/usr/bin/env bash
# Gsubtitle-style-2 : build GOAL x86 (changement GOAL SEUL -> pas de rebuild C++/NDK).
# Verrou de livraison pose avec un PID VIVANT (DIRECTIVES 2026-08-14 07:10) : ce script
# tourne en arriere-plan, donc `$$` designe un processus reellement en vie.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=.autoport/.deploy-in-progress
printf 'gss2_build pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
OUT=.autoport/reports/Gsubtitle-style-2
mkdir -p "$OUT"
: > "$OUT/build.log"
stdbuf -oL -eL timeout 1800 build-x86/goalc/goalc --game jak1 --proj-path . --disable-ansi \
  --cmd '(build-game)' >> "$OUT/build.log" 2>&1
echo "EXIT=$?" >> "$OUT/build.log"

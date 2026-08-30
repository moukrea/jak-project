#!/usr/bin/env bash
# Gfixed-tick-interpolation : construction GOAL + repack ISO, sous le verrou de
# deploiement. Le verrou porte son PID et son nettoyage (convention DIRECTIVES
# 2026-08-14 07:10) : un verrou sans detenteur est une panne silencieuse de la chaine
# de livraison, pas un verrou.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=.autoport/.deploy-in-progress
if [ -e "$LOCK" ]; then echo "LOCK deja pris:"; cat "$LOCK"; exit 3; fi
printf 'gft_goal_build pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
build/goalc/goalc --user-auto --game jak1 --disable-ansi -c '(make-group "iso")' 2>&1 | tail -40

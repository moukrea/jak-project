#!/usr/bin/env bash
# Porte-verrou honor-boot-crash essai 2 : empeche auto_build_apk.sh de rebatir/reinstaller
# SOUS la course de preuve. Le shell d'un appel d'outil meurt dans la seconde : c'est CE
# processus long qui detient le verrou, et il ecrit SON pid.
LOCK=.autoport/.deploy-in-progress
printf 'honor-boot-crash-essai2 pid=%s\n' "$$" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
sleep "${1:-3600}"

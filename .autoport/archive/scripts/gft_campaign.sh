#!/usr/bin/env bash
# Gfixed-tick-interpolation — campagne de mesure x86, UN verrou pour toute la serie.
# Le verrou porte son PID et son nettoyage : l'auto-constructeur remet out/jak1/iso en
# ARM64 pendant ~2 min a chaque commit, et une course x86 qui tomberait la-dedans
# serait un FAUX ROUGE (DIRECTIVES, verrou lu au sommet du cycle).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=.autoport/.deploy-in-progress
if [ -e "$LOCK" ]; then echo "LOCK deja pris:"; cat "$LOCK"; exit 3; fi
printf 'gft_campaign pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"; pkill -TERM -f "build/game/gk --game jak1" 2>/dev/null' EXIT
for leg in "$@"; do
  IFS=: read -r fps mode pacing <<< "$leg"
  tag="${TAGPFX:-}f${fps}_${mode}_${pacing}"
  echo "== leg $tag =="
  TIMEOUT="${TIMEOUT:-420}" bash .autoport/gft_x86_leg.sh "$fps" "$mode" "$pacing" "$tag"
done
echo "CAMPAGNE TERMINEE"

#!/usr/bin/env bash
# Gfixed-tick-anim-interp — campagne x86, UN verrou pour toute la serie (un commit
# declenche un cycle [full] qui remet out/jak1/iso en ARM64 pendant ~2 min ; une course
# x86 tombee la-dedans serait un FAUX ROUGE).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=.autoport/.deploy-in-progress
if [ -e "$LOCK" ]; then echo "LOCK deja pris:"; cat "$LOCK"; exit 3; fi
printf 'ajp_campaign pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"; pkill -TERM -f "build/game/gk --game jak1" 2>/dev/null' EXIT
for leg in "$@"; do
  IFS=: read -r fps anim <<< "$leg"
  tag="${TAGPFX:-}f${fps}_${anim}"
  echo "== leg $tag =="
  TIMEOUT="${TIMEOUT:-420}" bash .autoport/ajp_x86_leg.sh "$fps" "$anim" "$tag"
done
echo "CAMPAGNE TERMINEE"

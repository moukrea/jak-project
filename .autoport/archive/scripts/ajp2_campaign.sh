#!/usr/bin/env bash
# Gfixed-tick-anim-interp-2 — campagne x86, UN verrou pour toute la serie (un commit
# declenche un cycle [full] qui remet out/jak1/iso en ARM64 pendant ~2 min ; une course
# x86 tombee la-dedans serait un FAUX ROUGE).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=.autoport/.deploy-in-progress
if [ -e "$LOCK" ]; then echo "LOCK deja pris:"; cat "$LOCK"; exit 3; fi
printf 'ajp2_campaign pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"; pkill -TERM -f "build/game/gk --game jak1" 2>/dev/null' EXIT
for leg in "$@"; do
  IFS=: read -r fps jit anim tl <<< "$leg"
  tl="${tl:-1}"
  tag="f${fps}j${jit}_${anim}"
  [ "$tl" = 0 ] && tag="f${fps}j${jit}_${anim}_livre"
  echo "== leg $tag =="
  bash .autoport/ajp2_x86_leg.sh "$fps" "$jit" "$anim" "$tag" "$tl"
done
echo "CAMPAGNE TERMINEE"

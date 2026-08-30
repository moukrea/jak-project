#!/usr/bin/env bash
# Gjak-hd-rig-strap — re-cuisson du mesh HD + re-empaquetage du pack EXTERNE.
# Le verrou porte son PID et son nettoyage (convention DIRECTIVES 2026-08-14 07:10) : un verrou
# sans detenteur n'est pas un verrou, c'est une panne silencieuse de la chaine de livraison.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then echo "VERROU DEJA PRIS: $(cat "$LOCK")"; exit 3; fi
printf 'Gjak-hd-rig-strap-bake pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
LOG=.autoport/reports/Gjak-hd-rig-strap/bake.log
mkdir -p "$(dirname "$LOG")"
{
  echo "=== $(date -Is) BAKE build_enhanced_models.sh ==="
  bash scripts/shell/build_enhanced_models.sh; echo "BAKE_EXIT=$?"
  echo "=== $(date -Is) PACK package_hd_assets.sh jak1 ==="
  bash scripts/package_hd_assets.sh jak1; echo "PACK_EXIT=$?"
  echo "=== $(date -Is) FIN ==="
} > "$LOG" 2>&1
tail -3 "$LOG"

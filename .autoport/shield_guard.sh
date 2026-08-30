#!/usr/bin/env bash
# INTERDICTION OWNER 2026-08-30 : « Interdit de toucher a la SHIELD a nouveau.
# Assures toi que vraiment rien n'y touche. »
# Balaye par VALEUR (l'adresse), pas par une liste de fichiers ecrite a la main :
# une liste manuelle rend zero des qu'un script est ajoute (voir PITFALLS, audit par SITE).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SHIELD='192\.168\.1\.32'
rc=0
# a) aucune connexion adb vivante
if adb devices 2>/dev/null | grep -q "$SHIELD"; then
  echo "[SHIELD-GUARD FAIL] la Shield est CONNECTEE en adb — deconnexion exigee" >&2; rc=1
fi
# b) aucun script/config VIVANT ne la cible (les .bak-* et rapports sont de l'archive)
HITS=$(grep -rIln --exclude-dir=.git --include='*.sh' --include='*.py' --include='*.yaml' --include='*.json' \
        "$SHIELD" . 2>/dev/null | grep -vE '\.bak|/reports/|/logs/|shield_guard\.sh' || true)
for f in $HITS; do
  # une ligne qui INTERDIT l'adresse est legitime ; une ligne qui la CIBLE ne l'est pas
  if grep -n "$SHIELD" "$f" | grep -qvE 'INTERDIT|FORBIDDEN|keep_out|jamais|disconnect|Shield INTERDITE'; then
    echo "[SHIELD-GUARD FAIL] $f cible encore la Shield :" >&2
    grep -n "$SHIELD" "$f" | grep -vE 'INTERDIT|FORBIDDEN|keep_out|jamais|disconnect' | head -3 | sed 's/^/    /' >&2
    rc=1
  fi
done
[ $rc -eq 0 ] && echo "[SHIELD-GUARD ok] aucune connexion, aucun script vivant ne cible la Shield"
exit $rc

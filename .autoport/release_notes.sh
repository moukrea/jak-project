#!/usr/bin/env bash
# DESCRIPTION DE RELEASE TOUJOURS A JOUR (owner 2026-09-01) : « assures toi que la description
# de la release aient des info à jour systématiquement avec ce qu'il y a à tester EXACTEMENT ».
#
# 2026-09-03 — la description vient desormais du BACKLOG, plus de state.json + milestones.yaml.
# L'ancienne version listait des IDENTIFIANTS DE PHASE (« Gandroid-window-size ») que l'owner
# n'a jamais employes, et portait une liste `bruit` tenue a la main pour masquer les doublons :
# c'est exactement le « super flou ce que t'as livre et ce que j'ai a tester » du 2026-08-31.
# `./.autoport/autoport status` rend les memes trois rubriques que le digest, dans SES mots,
# et n'affiche jamais ce qu'il a deja valide.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=$(mktemp); trap 'rm -f "$OUT"' EXIT
INFO=out/artifacts/BUILD-INFO.txt
COMMIT=$(sed -n 's/.*commit: \([0-9a-f]\{7,\}\).*/\1/p' "$INFO" 2>/dev/null | head -1)
DATE=$(sed -n 's/^date: \([^ ]*\).*/\1/p' "$INFO" 2>/dev/null | head -1)
PACK=$(sed -n 's/.*PACK HD EXTERNE : \(.*\)/\1/p' "$INFO" 2>/dev/null | head -1)
{
  echo "## Build courant"
  echo
  echo "- APK : \`app-jak1-HD-recharged.apk\` — commit \`${COMMIT:-?}\`, ${DATE:-?}"
  echo "- Assets HD : \`jak1_hd_assets.zip\` — version \`${PACK:-?}\`"
  echo "  **Retelecharge-le si sa version a change** : les correctifs de geometrie et de poids"
  echo "  de peau ne voyagent QUE par ce fichier, jamais par l'APK."
  if [ "${AUTOPORT_BUILD_IS_WIP:-0}" = "1" ]; then
    echo
    echo "> Ce build vient d'un point d'etape, pas d'une livraison finie. Il est publie quand"
    echo "> meme (tu l'as demande) : ce qui est ci-dessous peut etre incomplet."
  fi
  echo
  if [ -x ./.autoport/autoport ] && [ -f .autoport/backlog.yaml ]; then
    ./.autoport/autoport status 2>/dev/null \
      || echo "_Etat du backlog indisponible — voir \`./.autoport/autoport status\`._"
  else
    echo "## A tester"
    echo
    echo "_Backlog absent : lance \`python3 .autoport/tools/migrate_backlog.py\` puis republie._"
  fi
  echo
  echo "_Description regeneree automatiquement a chaque publication, depuis \`.autoport/backlog.yaml\`._"
} > "$OUT"
gh release edit jak1-rtlight-wip --repo moukrea/jak-builds --notes-file "$OUT" >/dev/null 2>&1 \
  && echo "$(date +%H:%M:%S) description de release mise a jour" \
  || echo "$(date +%H:%M:%S) ECHEC mise a jour de la description"

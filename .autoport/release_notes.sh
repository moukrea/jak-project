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
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# Le quota utilisateur de /tmp peut refuser les ecritures alors que mktemp reussit.
# Le publieur deja vivant relit ce script a chaque tour : corriger ici couvre sa reprise.
export TMPDIR="$HOME/.cache/autoport/release-notes"
mkdir -p "$TMPDIR"
OUT=$(mktemp); trap 'rm -f "$OUT"' EXIT
# 2026-09-13 — LE BUILD NOMME EST CELUI PUBLIE, pas le dernier construit : le publieur photographie
# BUILD-INFO au moment du televersement dans .autoport/.published_build_info.txt et nous le passe.
INFO="${AUTOPORT_RELEASE_INFO:-out/artifacts/BUILD-INFO.txt}"
# GARDE PAR EMPREINTE : appele a chaque cycle du publieur, ce script ne parle a GitHub que si le texte
# a change. `--force` (a la publication) court-circuite la garde.
HASHMEMO=.autoport/.release_notes_hash
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
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
    # 2026-09-13 : la rubrique « Bloque » ne figure PAS dans une description de build. Elle listait
    # les items supplantes ou parques par l'owner (« L'occlusion ambiante (le relief dans les creux) »
    # a cote de l'occlusion ambiante A TESTER) : deux fois le meme nom sur une page, l'owner ne sait
    # plus quoi tester. Ici : le build, ce qui est en cours, ce qu'il y a a tester. Le reste est au backlog.
    ./.autoport/autoport status 2>/dev/null | sed '/^## Bloque/,$d' \
      || echo "_Etat du backlog indisponible — voir \`./.autoport/autoport status\`._"
    echo "_Les items bloques ou supplantes ne sont pas listes ici : ils sont dans le backlog, pas dans ce build._"
  else
    echo "## A tester"
    echo
    echo "_Backlog absent : lance \`python3 .autoport/tools/migrate_backlog.py\` puis republie._"
  fi
  echo
  echo "_Description regeneree automatiquement a chaque publication ET des que la liste a tester change (cycle de 5 min), depuis \`.autoport/backlog.yaml\`._"
} > "$OUT"
H=$(sha256sum "$OUT" | cut -d" " -f1)
if [ "$FORCE" = 0 ] && [ -f "$HASHMEMO" ] && [ "$(cat "$HASHMEMO" 2>/dev/null)" = "$H" ]; then
  exit 0   # rien n'a change : silence, pas d'appel a GitHub
fi
if gh release edit jak1-rtlight-wip --repo moukrea/jak-builds --notes-file "$OUT" >/dev/null 2>&1; then
  printf '%s\n' "$H" > "$HASHMEMO"
  echo "$(date +%H:%M:%S) description de release mise a jour ($([ "$FORCE" = 1 ] && echo publication || echo liste changee))"
else
  echo "$(date +%H:%M:%S) ECHEC mise a jour de la description"
fi

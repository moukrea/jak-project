#!/usr/bin/env bash
# DESCRIPTION DE RELEASE TOUJOURS A JOUR (owner 2026-09-01) : « assures toi que la
# description de la release aient des info à jour systématiquement avec ce qu'il y a à
# tester EXACTEMENT ». Regenere le corps de la pre-release a partir de l'ETAT REEL :
# ce qui attend son verdict, et rien de ce qu'il a deja valide.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=$(mktemp)
COMMIT=$(sed -n 's/.*commit: \([0-9a-f]\{7,\}\).*/\1/p' out/artifacts/BUILD-INFO.txt 2>/dev/null | head -1)
DATE=$(sed -n 's/^date: \([^ ]*\).*/\1/p' out/artifacts/BUILD-INFO.txt 2>/dev/null | head -1)
PACK=$(sed -n 's/.*PACK HD EXTERNE : \(.*\)/\1/p' out/artifacts/BUILD-INFO.txt 2>/dev/null | head -1)
{
  echo "## Build courant"
  echo
  echo "- APK : \`app-jak1-HD-recharged.apk\` — commit \`${COMMIT:-?}\`, ${DATE:-?}"
  echo "- Assets HD : \`jak1_hd_assets.zip\` — version \`${PACK:-?}\`"
  echo "  **Retelecharge-le si sa version a change** : les correctifs de geometrie et de"
  echo "  poids de peau ne voyagent QUE par ce fichier, jamais par l'APK."
  echo
  echo "## A TESTER dans ce build"
  echo
  python3 - <<'PY'
import json,os,yaml,textwrap
s=json.load(open('.autoport/state.json'))
m=yaml.safe_load(open('.autoport/milestones.yaml'))
byid={p['id']:p for p in m['phases']}
bruit={'Grecharged-menu-overhaul','Grecharged-secondary-motion','Gloadgate-crash-regression',
       'Grecharged-materials-modern-parity','Gbuild-from-scratch',
       'Gpbr-per-texture-materials','Gpbr-material-props',
       # versions DEPASSEES par un cycle suivant deja valide ou en cours
       'Gjak1-crate-collision','Gfixed-tick-anim-interp','Gcutscene-skip-all','Gsubtitle-style'}
att=[p for p in s['validator_passed']
     if p not in set(s['completed'])
     and not os.path.exists('.autoport/owner-ok/'+p)
     and p not in bruit]
if not att:
    print("_Rien de nouveau a juger : tout ce qui est fini a deja ete valide._")
else:
    for p in att:
        nm=' '.join(str(byid.get(p,{}).get('name','')).split())
        print(f"- **{p}** — {nm[:220]}")
PY
  echo
  echo "## Deja valide (ne pas re-tester)"
  echo
  ls .autoport/owner-ok 2>/dev/null | grep -v README | tr '\n' ' ' | fold -s -w 100 | sed 's/^/  /'
  echo
  echo
  echo "_Description regeneree automatiquement a chaque publication._"
} > "$OUT"
gh release edit jak1-rtlight-wip --repo moukrea/jak-builds --notes-file "$OUT" >/dev/null 2>&1 \
  && echo "$(date +%H:%M:%S) description de release mise a jour" \
  || echo "$(date +%H:%M:%S) ECHEC mise a jour de la description"
rm -f "$OUT"

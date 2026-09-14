#!/usr/bin/env bash
# Le producteur de preuve recolte stdout ; aucun champ de proof.txt ecrit ici.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel) || exit 1
D=${AUTOPORT_CENSUS_DIR:-$ROOT/.autoport/reports/harness-delivery-stale-bake-recovery}
mkdir -p "$D/notes" "$HOME/.autoport-tmp" || exit 1
D=$(cd "$D" && pwd)
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"
cd "$ROOT" || exit 1
# Le nommeur suit les chemins lib/, tests/, acquis/ et validators/. Les chemins
# lib/../ ci-dessous lui rendent visibles les producteurs situes a la racine.
for source in .autoport/lib/../auto_build_apk.sh .autoport/lib/../auto_push_builds.sh \
              .autoport/lib/../prepare_delivery_bakes.sh .autoport/lib/../delivery_artifact.py \
              .autoport/lib/../build_arm64_full_consistent.sh; do
  key=$(basename "$source" | tr '.-' '__')
  printf 'delivery_source_%s=%s\n' "$key" "$(sha256sum "$source" | cut -d' ' -f1)"
done
python3 -m pytest .autoport/tests/harness/test_delivery_stale_bake.py -q -p no:cacheprovider \
  --junitxml="$D/notes/delivery-stale-bake.xml" > "$D/notes/delivery-stale-bake.log" 2>&1
rc=$?
python3 - "$D/notes/delivery-stale-bake.xml" "$rc" <<'PY'
import sys
import xml.etree.ElementTree as ET
try:
    cases=ET.parse(sys.argv[1]).findall('.//testcase')
except (OSError,ET.ParseError):
    cases=[]
failed=sum(c.find('failure') is not None or c.find('error') is not None or c.find('skipped') is not None for c in cases)
passed=len(cases)-failed
defects=failed+int(not cases)+int(int(sys.argv[2]) not in (0,1))
if int(sys.argv[2])==1 and not failed:
    defects+=1
populations={category:sum(category in c.get('name','') for c in cases)
             for category in ('stale','retry','success','unchanged','publication')}
defects+=sum(count==0 for count in populations.values())
print(f'delivery_stale_bake_defects={defects}')
print(f'delivery_stale_bake_cases={len(cases)}')
print(f'delivery_stale_bake_passed={passed}')
print(f'delivery_stale_bake_pytest_rc={sys.argv[2]}')
for category,count in populations.items():
    print(f'delivery_stale_bake_{category}_cases={count}')
PY

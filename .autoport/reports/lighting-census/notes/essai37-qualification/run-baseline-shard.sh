#!/usr/bin/env bash
# DIRECTIVES v6fca51fe40
set -euo pipefail
main=/home/emeric/code/jak-project
base=/home/emeric/code/jak-lighting-baseline
notes=$main/.autoport/reports/lighting-census/notes/essai37-qualification
LOCK=$main/.autoport/.deploy-in-progress
builder=2541075
python3 - <<'PY'
from pathlib import Path
import subprocess
pid=2541075
assert Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[:2] == [b'bash',b'.autoport/auto_build_apk.sh']
assert subprocess.check_output(['ps','--ppid',str(pid),'-o','comm='],text=True).split()==['sleep']
assert not Path('/home/emeric/code/jak-project/.autoport/.deploy-in-progress').exists()
PY
cleanup() { rm -f "$LOCK"; kill -CONT "$builder"; }
trap cleanup EXIT
kill -STOP "$builder"
printf '%s pid=%s\n' "$0" "$$" > "$LOCK"
cmake --build "$base/build" --target gk -j 6 > "$notes/build-baseline-gk.log" 2>&1
rm -f "$LOCK"
python3 "$main/.autoport/tools/refset_provenance.py" seal --root "$base" --role baseline \
  --output "$notes/baseline-source.json" > "$notes/baseline-source-seal.log" 2>&1
python3 - <<'PY'
from pathlib import Path
import json
n=Path('/home/emeric/code/jak-project/.autoport/reports/lighting-census/notes/essai37-qualification')
env=json.loads((n/'capture-env.json').read_text())
env['OG_REFSET_PHASES']='1'
env['OG_REFSET_BUILD_PROVENANCE']=str(n/'baseline-source.json')
(n/'baseline-capture-env.json').write_text(json.dumps(env,indent=2)+'\n')
PY
python3 "$main/.autoport/tools/refset_campaign.py" run --campaign "$notes/baseline-campaign" \
  --name baseline-legacy-capture --root "$base" --env-json "$notes/baseline-capture-env.json" \
  --timeout 100 --data "$base/custom_assets" --data "$base/managed_assets" \
  --proof-run "$main/.autoport/lib/proof_run.sh" > "$notes/baseline-capture-run.log" 2>&1
python3 - <<'PY'
from pathlib import Path
import json
n=Path('/home/emeric/code/jak-project/.autoport/reports/lighting-census/notes/essai37-qualification')
r=json.loads(sorted((n/'baseline-campaign').glob('attempt-*/receipt.json'))[-1].read_text())
assert r['state']=='complete'
env=json.loads((n/'baseline-capture-env.json').read_text())
env.update(OG_REFSET='replay',OG_REFSET_DIR=r['reference_root'])
(n/'baseline-replay-env.json').write_text(json.dumps(env,indent=2)+'\n')
PY
python3 "$main/.autoport/tools/refset_campaign.py" run --campaign "$notes/baseline-campaign" \
  --name baseline-legacy-replay-1 --root "$base" --env-json "$notes/baseline-replay-env.json" \
  --timeout 100 --data "$base/custom_assets" --data "$base/managed_assets" \
  --proof-run "$main/.autoport/lib/proof_run.sh" > "$notes/baseline-replay-run.log" 2>&1

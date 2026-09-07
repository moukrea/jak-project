#!/usr/bin/env bash
# DIRECTIVES v6fca51fe40
set -euo pipefail
cd /home/emeric/code/jak-project
notes=.autoport/reports/lighting-census/notes/essai37-qualification
LOCK=.autoport/.deploy-in-progress
builder=2541075
python3 - <<'PY'
from pathlib import Path
import subprocess
pid=2541075
assert Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[:2] == [b'bash',b'.autoport/auto_build_apk.sh']
assert subprocess.check_output(['ps','--ppid',str(pid),'-o','comm='],text=True).split()==['sleep']
assert not Path('.autoport/.deploy-in-progress').exists()
PY
cleanup() { rm -f "$LOCK"; kill -CONT "$builder"; }
trap cleanup EXIT
kill -STOP "$builder"
printf '%s pid=%s\n' "$0" "$$" > "$LOCK"
cmake --build build --target gk -j 6 > "$notes/build-gk.log" 2>&1
rm -f "$LOCK"
python3 .autoport/tools/refset_provenance.py seal --root "$PWD" --role candidate \
  --output "$notes/candidate-source.json" > "$notes/source-seal.log" 2>&1
python3 - <<'PY'
from pathlib import Path
import json
root=Path.cwd(); n=root/'.autoport/reports/lighting-census/notes/essai37-qualification'
env={
 'OG_REFSET':'capture', 'OG_REFSET_VANTAGES':'legacy', 'OG_REFSET_PHASES':'1,2,3',
 'OG_REFSET_HOURS':'0,3,6,9,12,15,18,21', 'OG_REFSET_REQUIRE_LOADED':'1',
 'OG_REFSET_QUALIFY_STATE':'1', 'OG_REFSET_LOAD_SETTLE':'1200',
 'OG_REFSET_BUILD_PROVENANCE':str(n/'candidate-source.json'),
 'OG_BOOT_REPLAY_BOUNDARY':'actors-sweep','OG_BOOT_REPLAY_CONTINUE':'village1-hut',
 'OG_BOOT_REPLAY_REPLAY':str(root/'.autoport/reports/lighting-census/notes/essai17-rpc/fork-bootstrap.bin'),
 'OG_PAD_REPLAY_REPLAY':str(root/'.autoport/refset/neutral.inputs')}
(n/'capture-env.json').write_text(json.dumps(env,indent=2)+'\n')
PY
python3 .autoport/tools/refset_campaign.py run --campaign "$notes/campaign" --name candidate-legacy-capture \
  --root "$PWD" --env-json "$notes/capture-env.json" --timeout 150 --data custom_assets --data managed_assets \
  > "$notes/capture-run.log" 2>&1
python3 - <<'PY'
from pathlib import Path
import json
n=Path('.autoport/reports/lighting-census/notes/essai37-qualification')
receipt=json.loads(sorted((n/'campaign').glob('attempt-*/receipt.json'))[-1].read_text())
assert receipt['state']=='complete'
env=json.loads((n/'capture-env.json').read_text())
env.update(OG_REFSET='replay',OG_REFSET_DIR=receipt['reference_root'])
# An explicit incomplete manifest exercises the fail-closed transition, not an adoption.
manifest=(n/'qualification-plan.json').resolve()
manifest.write_text(json.dumps({'version':1,'pairs':[{'baseline':str((n/'pending-baseline-legacy').resolve()),'candidate':receipt['reference_root']}]},indent=2)+'\n')
env['OG_REFSET_QUALIFICATION']=str(manifest)
(n/'replay-env.json').write_text(json.dumps(env,indent=2)+'\n')
PY
python3 .autoport/tools/refset_campaign.py run --campaign "$notes/campaign" --name candidate-legacy-replay-1 \
  --root "$PWD" --env-json "$notes/replay-env.json" --timeout 150 --data custom_assets --data managed_assets \
  > "$notes/replay-run.log" 2>&1

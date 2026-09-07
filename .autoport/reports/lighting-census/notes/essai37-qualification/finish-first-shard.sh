#!/usr/bin/env bash
# DIRECTIVES v6fca51fe40
set -euo pipefail
cd /home/emeric/code/jak-project
main=$PWD
base=/home/emeric/code/jak-lighting-baseline
notes=$main/.autoport/reports/lighting-census/notes/essai37-qualification
builder=2541075
python3 - <<'PY'
from pathlib import Path
import subprocess,json
pid=2541075
assert Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[:2] == [b'bash',b'.autoport/auto_build_apk.sh']
assert subprocess.check_output(['ps','--ppid',str(pid),'-o','comm='],text=True).split()==['sleep']
assert not Path('.autoport/.deploy-in-progress').exists()
n=Path('.autoport/reports/lighting-census/notes/essai37-qualification')
comparison=json.loads((n/'independent-state-comparison.json').read_text())
assert comparison['image_compare_exit_code']==0 and comparison['summary']['state_bytes_equal']==8
(n/'qualification-plan.json').write_text(json.dumps({'version':1,'pairs':[{
 'baseline':comparison['baseline'],'candidate':comparison['candidate']}]},indent=2)+'\n')
PY
trap 'kill -CONT "$builder"' EXIT
kill -STOP "$builder"
for replay in 2 3 4 5; do
  python3 .autoport/tools/refset_campaign.py run --campaign "$notes/campaign" \
    --name "candidate-legacy-replay-$replay" --root "$main" --env-json "$notes/replay-env.json" \
    --timeout 150 --data custom_assets --data managed_assets > "$notes/candidate-replay-$replay.log" 2>&1
  # Stop on a rejected qualification artifact; more equal self-replays cannot repair it.
  python3 - <<'PY'
from pathlib import Path
import re
p=Path('.autoport/reports/lighting-census/proof.txt').read_text()
m=re.search(r'^refset_qualification_gate=(\d+)$',p,re.M)
assert m and int(m[1]) != 255, 'producer rejected qualification artifacts; inspect its missing log'
PY
  python3 .autoport/tools/refset_campaign.py run --campaign "$notes/baseline-campaign" \
    --name "baseline-legacy-replay-$replay" --root "$base" --env-json "$notes/baseline-replay-env.json" \
    --timeout 100 --data "$base/custom_assets" --data "$base/managed_assets" \
    --proof-run "$main/.autoport/lib/proof_run.sh" > "$notes/baseline-replay-$replay.log" 2>&1
done

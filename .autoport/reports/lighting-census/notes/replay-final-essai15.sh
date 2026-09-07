#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
notes=.autoport/reports/lighting-census/notes
data="$notes/essai15-data"
python3 - <<'PY'
from pathlib import Path
import shutil, subprocess
p = 2541075
assert Path(f'/proc/{p}/cmdline').read_bytes().split(b'\0')[:2] == [b'bash', b'.autoport/auto_build_apk.sh']
assert subprocess.check_output(['ps', '--ppid', str(p), '-o', 'comm='], text=True).split() == ['sleep']
assert not Path('.autoport/.deploy-in-progress').exists()
root = Path('.autoport/reports/lighting-census')
archive = root / 'notes/essai15-avant-ledger'
archive.mkdir()
for name in ('proof.txt', 'proof-engine.log'):
    shutil.copy2(root / name, archive / name)
print('Builder identity/idle verified; first essai15 proof archived', flush=True)
PY
builder=2541075
trap 'kill -CONT "$builder"; ps -p "$builder" -o pid,ppid,stat,args' EXIT
kill -STOP "$builder"
export OG_REFSET_VANTAGES=legacy OG_REFSET_PHASES=1 OG_REFSET_HOURS=0
export OG_BOOT_REPLAY_REPLAY="$data/fork-bootstrap.bin"
AUTOPORT_PROOF_WAIT_MAX=300 bash .autoport/lib/proof_run.sh lighting-census x86 --timeout 60 \
  > "$notes/proof-final-essai15.log" 2>&1
sha256sum -c "$notes/refs-before-essai12.sha256" > "$data/historical-final.log"
sha256sum build/game/gk out/jak1/iso/GAME.CGO out/jak1/iso/ENGINE.CGO \
  out/jak1/iso/KERNEL.CGO .autoport/refset/neutral.inputs > "$data/fork-final-inputs.sha256"
grep -aE '^BOOTREPLAY (finish|error)|^REFSET done' .autoport/reports/lighting-census/proof-engine.log

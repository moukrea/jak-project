#!/usr/bin/env bash
# DIRECTIVES v6fca51fe40
# One fresh, unqualified reference arm. proof_run.sh remains the sole proof producer.
set -euo pipefail
root=${1:?worktree}
arm=${2:?baseline or candidate}
main=/home/emeric/code/jak-project
cd "$root"
notes=.autoport/reports/lighting-census/notes/essai30-baseline
mkdir -p "$notes"
export ARM_ROOT="$root" ARM_NAME="$arm"
export ARM_CAPTURE_DIR=".autoport/refset-candidates/essai30-$arm"
export ARM_SAVED_ENV="$root/$notes/proof-env-before.json"
test ! -e "$ARM_CAPTURE_DIR"
test ! -e "$ARM_SAVED_ENV"
test ! -e "$root/$notes/consumed.tsv"
# Stop only the identified idle builder, with restoration owned by this long process.
python3 - <<'PY'
from pathlib import Path
import subprocess
pid=2541075
assert Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[:2] == [b'bash',b'.autoport/auto_build_apk.sh']
assert subprocess.check_output(['ps','--ppid',str(pid),'-o','comm='],text=True).split()==['sleep']
assert not Path('/home/emeric/code/jak-project/.autoport/.deploy-in-progress').exists()
PY
builder=2541075
restore() {
  python3 "$main/.autoport/reports/lighting-census/notes/essai30-baseline/run-config.py" restore || true
  kill -CONT "$builder"
}
trap restore EXIT
kill -STOP "$builder"
# Select this fresh output in the task's runtime configuration because proof_run
# deliberately reapplies proof_env after the environment. Restore only our exact edit.
python3 "$main/.autoport/reports/lighting-census/notes/essai30-baseline/run-config.py" select
export OG_REFSET_VANTAGES=legacy OG_REFSET_PHASES=1 OG_REFSET_HOURS=0
export OG_REFSET_REQUIRE_LOADED=1
export OG_RECHARGED=0 OG_LIGHTING=0 OG_RT_LIGHT=0
export OG_BOOT_REPLAY_BOUNDARY=actors-sweep OG_BOOT_REPLAY_CONTINUE=village1-hut
export OG_BOOT_REPLAY_REPLAY="$root/.autoport/reports/lighting-census/notes/essai17-rpc/fork-bootstrap.bin"
export OG_REFSET_ASSET_MANIFEST="$root/$notes/consumed.tsv"
sha256sum build/game/gk out/jak1/iso/{GAME,ENGINE,KERNEL}.CGO "$OG_BOOT_REPLAY_REPLAY" > "$notes/arm-inputs.sha256"
AUTOPORT_PROOF_WAIT_MAX=60 bash "$main/.autoport/lib/proof_run.sh" lighting-census x86 --timeout 60 > "$notes/proof-run.log" 2>&1
sha256sum -c "$notes/arm-inputs.sha256" > "$notes/arm-inputs-after.log"
grep -aE 'BOOTREPLAY (finish|error|actors-sweep)|REFSET (loaded-state|start|done|provenance)|ASSET_MANIFEST' .autoport/reports/lighting-census/proof-engine.log > "$notes/runtime-extract.log" || true

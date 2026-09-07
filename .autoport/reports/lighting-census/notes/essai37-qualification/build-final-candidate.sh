#!/usr/bin/env bash
# DIRECTIVES v6fca51fe40
set -euo pipefail
cd /home/emeric/code/jak-project
notes=$PWD/.autoport/reports/lighting-census/notes/essai37-qualification
builder=2541075
LOCK=$PWD/.autoport/.deploy-in-progress
python3 - <<'PY'
from pathlib import Path
import subprocess
pid=2541075
assert Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[:2] == [b'bash',b'.autoport/auto_build_apk.sh']
assert subprocess.check_output(['ps','--ppid',str(pid),'-o','comm='],text=True).split()==['sleep']
assert not Path('.autoport/.deploy-in-progress').exists()
PY
trap 'rm -f "$LOCK"; kill -CONT "$builder"' EXIT
kill -STOP "$builder"
printf '%s pid=%s\n' "$0" "$$" > "$LOCK"
cmake --build build --target gk -j 6 > "$notes/build-final-gk.log" 2>&1
python3 .autoport/tools/refset_provenance.py seal --root "$PWD" --role candidate \
  --output "$notes/candidate-final-source.json" > "$notes/final-source-seal.log" 2>&1

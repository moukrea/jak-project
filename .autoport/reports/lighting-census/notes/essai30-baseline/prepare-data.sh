#!/usr/bin/env bash
set -euo pipefail
source_root=/home/emeric/code/jak-project
baseline_root=/home/emeric/code/jak-lighting-baseline
cd "$source_root"
python3 - <<'PY'
from pathlib import Path
import subprocess
pid=2541075
assert Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[:2] == [b'bash', b'.autoport/auto_build_apk.sh']
assert subprocess.check_output(['ps','--ppid',str(pid),'-o','comm='],text=True).split() == ['sleep']
assert not Path('.autoport/.deploy-in-progress').exists()
PY
builder=2541075
trap 'kill -CONT "$builder"' EXIT
kill -STOP "$builder"
# Independent CoW copies: writes by either worktree never change the other.
mkdir -p "$baseline_root/out/jak1" "$baseline_root/build/game" "$baseline_root/.autoport/reports/lighting-census/notes/essai17-rpc"
# FileUtil's portable data-root mechanism, pointing only inside this isolated tree.
ln -s ../.. "$baseline_root/build/game/data"
for path in out/jak1/iso out/jak1/fr3 out/jak1/obj build/game/OpenGOAL managed_assets; do
  test ! -e "$baseline_root/$path"
  cp -a --reflink=always "$source_root/$path" "$baseline_root/$path"
done
cp -a --reflink=always "$source_root/custom_assets/jak1/." "$baseline_root/custom_assets/jak1/"
cp -a --reflink=always "$source_root/.autoport/refset/neutral.inputs" "$baseline_root/.autoport/reports/lighting-census/notes/essai17-rpc/neutral.inputs"
cp -a --reflink=always "$source_root/.autoport/reports/lighting-census/notes/essai17-rpc/fork-bootstrap.bin" "$baseline_root/.autoport/reports/lighting-census/notes/essai17-rpc/fork-bootstrap.bin"
sha256sum build/game/gk out/jak1/iso/{GAME,ENGINE,KERNEL}.CGO .autoport/refset/neutral.inputs .autoport/reports/lighting-census/notes/essai17-rpc/fork-bootstrap.bin
find build/game/OpenGOAL/jak1/settings -type f -exec sha256sum {} +

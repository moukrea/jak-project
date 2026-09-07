#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
notes=.autoport/reports/lighting-census/notes
exec > >(tee "$notes/session-essai13.log") 2>&1
builder=2541075
python3 - <<'PY'
import pathlib, subprocess
p=2541075
cmd=pathlib.Path(f'/proc/{p}/cmdline').read_bytes().split(b'\0')
assert cmd[:2]==[b'bash', b'.autoport/auto_build_apk.sh'], cmd
rows=subprocess.check_output(['ps','-eo','pid=,ppid=,stat=,comm='],text=True).splitlines()
children=[r for r in rows if int(r.split()[1])==p]
assert len(children)==1 and children[0].split()[3]=='sleep', children
for r in rows:
    assert r.split()[3] not in ('ninja','ninja-build','cc1','cc1plus','goalc','clang','clang++','gcc','g++','cmake','make'), r
for f in ('.autoport/.deploy-in-progress','.autoport/.build-in-progress'):
    assert not pathlib.Path(f).exists(), f
print('Builder identity and idle child verified:',children)
PY
trap 'kill -CONT "$builder"; ps -p "$builder" -o pid,ppid,stat,args' EXIT
kill -STOP "$builder"
sha256sum -c "$notes/refs-before-essai12.sha256" > "$notes/refs-preflight-essai13.log"
git rev-parse HEAD > "$notes/source-head-essai13.txt"
git diff --binary HEAD -- game common goal_src goalc android > "$notes/source-diff-essai13.patch"
sha256sum game/graphics/refset.cpp .autoport/refset/neutral.inputs > "$notes/source-input-essai13.sha256"
echo "build_start=$(date -Iseconds)"
set +e
cmake --build build --target gk -j6 > "$notes/build-essai13.log" 2>&1
rc=$?
set -e
echo "build_rc=$rc"
[ "$rc" -eq 0 ] || exit "$rc"
sha256sum build/game/gk | tee "$notes/gk-essai13.sha256"
# Production d'un candidat PARTIEL, jamais une qualification ni une adoption.
set +e
REFSET_DIR=.autoport/refset-candidates/essai13-provenance-v2 \
REFSET_VANTAGES=legacy REFSET_PHASES=1 REFSET_HOURS=0 \
  bash .autoport/lib/refset.sh capture 150 > "$notes/candidate-capture-essai13.log" 2>&1
capture_rc=$?
set -e
echo "candidate_capture_rc=$capture_rc"
echo "proof_start=$(date -Iseconds)"
set +e
bash .autoport/lib/proof_run.sh lighting-census x86 --timeout 150 > "$notes/proof-run-essai13.log" 2>&1
proof_rc=$?
set -e
echo "proof_run_rc=$proof_rc"
sha256sum -c "$notes/refs-before-essai12.sha256" > "$notes/refs-check-essai13.log"
echo "refs_check_rc=$?"
exit "$proof_rc"

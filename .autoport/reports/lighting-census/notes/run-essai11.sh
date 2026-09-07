#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
notes=.autoport/reports/lighting-census/notes
exec > >(tee "$notes/session-essai11.log") 2>&1
builder=2541075
python3 - <<'PY'
import pathlib, subprocess
p=2541075
cmd=pathlib.Path(f'/proc/{p}/cmdline').read_bytes().split(b'\0')
assert cmd[:2]==[b'bash', b'.autoport/auto_build_apk.sh'], cmd
rows=subprocess.check_output(['ps','-eo','pid=,ppid=,stat=,comm=,args='],text=True).splitlines()
children=[r for r in rows if int(r.split(None,4)[1])==p]
assert len(children)==1 and children[0].split(None,4)[3]=='sleep', children
for r in rows:
    assert r.split(None,4)[3] not in ('ninja','ninja-build','cc1plus','goalc','clang++','g++'), r
for f in ('.autoport/.deploy-in-progress','.autoport/.build-in-progress'):
    assert not pathlib.Path(f).exists(), f
print('Builder identity and idle child verified:',children)
PY
trap 'kill -CONT "$builder"; ps -p "$builder" -o pid,ppid,stat,args' EXIT
kill -STOP "$builder"
ps -p "$builder" -o pid,ppid,stat,args
sha256sum -c "$notes/refs-before-essai11.sha256" > "$notes/refs-preflight-essai11.log"
set +e
cmake --build build --target gk -j6 > "$notes/build-essai11.log" 2>&1
rc=$?
set -e
echo "build_rc=$rc"
[ "$rc" -eq 0 ] || exit "$rc"
sha256sum build/game/gk | tee "$notes/gk-essai11.sha256"
set +e
OG_REFSET_TRACE_ROI=1 bash .autoport/lib/proof_run.sh lighting-census x86 --timeout 150 > "$notes/proof-run-essai11.log" 2>&1
rc=$?
set -e
echo "proof_run_rc=$rc"
sha256sum -c "$notes/refs-before-essai11.sha256" > "$notes/refs-check-essai11.log"
echo "refs_check_rc=$?"
exit "$rc"

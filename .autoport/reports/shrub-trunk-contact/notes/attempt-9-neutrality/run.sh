#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
D=.autoport/reports/shrub-trunk-contact/notes/attempt-9-neutrality
python3 "$D/prepare.py" > "$D/sources.log"
c++ -std=c++17 -O2 "$D/bench.cpp" -lEGL -lGLESv2 -o "$D/bench"
set +e
"$D/bench" "$D" > "$D/run.log" 2>&1
rc=$?
set -e
printf 'rc=%s\n' "$rc" >> "$D/run.log"
cat "$D/run.log"
exit "$rc"

#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
D=.autoport/reports/shrub-trunk-contact/notes/attempt-9-neutrality
python3 "$D/prepare_grass.py" > "$D/grass-sources.log"
python3 "$D/make_grass_full.py"
c++ -std=c++17 -O2 "$D/grassfull.cpp" -lEGL -lGLESv2 -o "$D/grassfull"
set +e
"$D/grassfull" "$D" > "$D/grass-full.log" 2>&1
rc=$?
set -e
printf 'rc=%s\n' "$rc" >> "$D/grass-full.log"
cat "$D/grass-full.log"
exit "$rc"

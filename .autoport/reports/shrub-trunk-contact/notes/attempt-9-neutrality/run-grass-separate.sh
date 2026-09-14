#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
D=.autoport/reports/shrub-trunk-contact/notes/attempt-9-neutrality
python3 "$D/prepare_grass.py" > "$D/grass-separate-sources.log"
sed '/^#define OG_GRASS_CONTACT_PROBE$/d' "$D/grass-1.vert" > "$D/grass-color.vert"
sha256sum "$D/grass-color.vert" >> "$D/grass-separate-sources.log"
python3 "$D/make_grass_full.py"
python3 "$D/make_grass_separate.py"
c++ -std=c++17 -O2 "$D/grass-separate.cpp" -lEGL -lGLESv2 -o "$D/grass-separate"
set +e
"$D/grass-separate" "$D" > "$D/grass-separate.log" 2>&1
rc=$?
set -e
printf 'rc=%s\n' "$rc" >> "$D/grass-separate.log"
cat "$D/grass-separate.log"
exit "$rc"

#!/usr/bin/env bash
# gpbrf_r24_assemble.sh — build the round-24 report section from the pieces + the measured tables,
# append it to report.txt, and run the phase validator. Idempotent: re-running replaces the section.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
D=.autoport/reports/Grecharged-pbr-realtime-fusion
R=$D/report.txt
CAP=${CAP:-$D/device/r24f}
MARK="== ROUND 24 — THE COVERAGE METRIC REBUILT"

# drop any previous round-24 section so this can be re-run
python3 - "$R" "$MARK" <<'PY'
import sys
p, mark = sys.argv[1], sys.argv[2]
s = open(p).read()
i = s.find(mark)
if i > 0:
    j = s.rfind("\n", 0, i)
    k = s.rfind("=====", 0, j)          # the banner line above it
    cut = s.rfind("\n", 0, k) if k > 0 else j
    open(p, "w").write(s[:cut] + "\n")
    print("removed previous round-24 section")
PY

{
  cat "$D/r24_section_head.txt"
  cat "$D/r24_section_mid.txt"
  echo
  echo "THE MEASUREMENTS — 4 vantages x 2 tiers, one boot each, all on libgk $(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -c1-16)"
  python3 .autoport/gpbrf_r24_final.py "$CAP"
  echo
  python3 - "$CAP" <<'GATE'
import subprocess, sys, re
out = subprocess.run(["python3", ".autoport/gpbrf_r24_final.py", sys.argv[1]],
                     capture_output=True, text=True).stdout
m = re.search(r"WORST of all (\d+) vantage/tier pairs: (\S+) / (\S+) at ([0-9.]+)%, sham false-positive ([0-9.]+)%", out)
w = re.findall(r"WORST vantage, (\w+) tier, raw over every maps-bearing pixel at any distance: (\w+) at ([0-9.]+)%", out)
if not m:
    sys.exit("could not extract the worst-pair figure")
n, v, tier, val, fp = m.groups()
print("THE ROUND-24 GATE FIGURE, stated once and scoped in the sentence itself:")
print(f"  {val}% of the maps-bearing pixels inside the displacement LOD range that can resolve a change at all actually moved, at the WORST of {n} vantage/tier pairs ({v}, {tier} tier), sham-measured false-positive {fp}%.")
print(f"  Scope, both halves MEASURED on the device per pixel and quantified in TABLE 2: inside 20 m (the band the tessellation tier drives at full amplitude), and excluding the pixels the 10x saturation probe proves cannot respond to a displacement of ANY size (clipped highlights and surfaces minified past resolvability).")
for t, vv, raw in w:
    print(f"  For contrast, the UNSCOPED raw rate over every maps-bearing pixel at any distance, {t} tier, worst vantage {vv}: {raw}% - TABLE 1 carries all eight, and the three causes of the difference are itemised below.")
GATE
  echo
  cat "$D/r24_section_tail.txt"
} >> "$R"

echo "== validator =="
bash .autoport/validators/phase-Grecharged-pbr-realtime-fusion.sh
echo "VALIDATOR_EXIT=$?"

#!/usr/bin/env bash
# Cycle-4 evidence harvester. Reads one or more gk/logcat logs and prints the numbers the
# cycle-4 report has to carry — the ones the owner's verdict says must not be able to lie.
# Usage: bash .autoport/physics_c4_harvest.sh <log> [<log>...]
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <log>..." >&2; exit 1; }

for f in "$@"; do
  echo "############ $(basename "$f") ############"
  [ -s "$f" ] || { echo "  (empty/missing)"; continue; }

  echo "--- window counts ---"
  echo "  [HD-PHYS]  windows : $(grep -ac '\[HD-PHYS\].*window: chains=' "$f")"
  echo "  [HD-PHYS2] lines   : $(grep -ac '\[HD-PHYS2\]' "$f")"
  echo "  [HD-PHYS3] lines   : $(grep -ac '\[HD-PHYS3\]' "$f")"
  echo "  actors seen        : $(grep -ao 'ag=[a-z0-9-]*' "$f" | sort -u | tr '\n' ' ')"

  echo "--- SAFETY (must all be 0) ---"
  echo "  nan-resets != 0    : $(grep -a 'nan-resets=' "$f" | grep -cv 'nan-resets=0 ')"
  echo "  rootdev   != 0     : $(grep -a 'rootdev=' "$f" | grep -cv 'rootdev=0\.0000 ')"
  echo "  resid     != 0     : $(grep -a 'resid=' "$f" | grep -cv 'resid=0 ')"
  echo "  burst     != 0     : $(grep -a 'burst=' "$f" | grep -cv 'burst=0 ')"
  echo "  frozen    != 0     : $(grep -a 'frozen=' "$f" | grep -cv 'frozen=0 ')"
  echo "  nomask    != 0     : $(grep -a 'nomask=' "$f" | grep -cv 'nomask=0 ')"
  echo "  noncol    != 0     : $(grep -a 'noncol=' "$f" | grep -cv 'noncol=0 ')"

  echo "--- (R) gravity, measured out of the integrator ---"
  grep -ao 'gdir=([^)]*)' "$f" | sort | uniq -c | sort -rn | head -4 | sed 's/^/  /'
  echo "  distinct gloc (must NOT be a single value if actors turn):"
  grep -ao 'gloc=([^)]*)' "$f" | sort -u | wc -l | sed 's/^/    /'
  grep -ao 'gloc=([^)]*)' "$f" | sort -u | head -4 | sed 's/^/    /'

  echo "--- (S) the metrics that replaced the contact-only jitter count ---"
  for k in idledrift settletime unsettled freering jitter stickmax rested clamped; do
    v=$(grep -ao "$k=[0-9.]*" "$f" | sed "s/$k=//" | sort -g | tail -1)
    lo=$(grep -ao "$k=[0-9.]*" "$f" | sed "s/$k=//" | sort -g | head -1)
    echo "  $k: max=${v:-n/a} min=${lo:-n/a}"
  done

  echo "--- (T/G) chest amplitude + base motion, per actor ---"
  python3 - "$f" <<'PY'
import re,sys,collections
txt=open(sys.argv[1],errors='ignore').read()
# chain index of chestR/chestL per model from the data file
data=open('recharged_assets/physics_chains.txt',errors='ignore').read().split('\n')
model=None; idx={}; n=0
for l in data:
    m=re.match(r'\[model\s+([^\]]+)\]',l.strip())
    if m: model=m.group(1).split()[0]; n=0; continue
    m=re.match(r'\s*chain\s+(\S+)',l)
    if m:
        idx[(model,m.group(1))]=n; n+=1
best=collections.defaultdict(float)
base=collections.defaultdict(float)
for line in txt.split('\n'):
    m=re.search(r'ag=(\S+).*?cdev:(.*)$',line)
    if m:
        ag=m.group(1)
        vals=dict((int(a),float(b)) for a,b in re.findall(r'(\d+)=([0-9.]+)',m.group(2)))
        for cn in ('chestR','chestL'):
            i=idx.get((ag,cn))
            if i is not None and i in vals: best[(ag,cn)]=max(best[(ag,cn)],vals[i])
    m=re.search(r'ag=(\S+).*?jdev:(.*)$',line)
    if m:
        ag=m.group(1)
        for cm in re.finditer(r'c(\d+)((?::[0-9.]+)+)',m.group(2)):
            ci=int(cm.group(1)); links=[float(x) for x in cm.group(2).split(':')[1:]]
            for cn in ('chestR','chestL'):
                if idx.get((ag,cn))==ci and links:
                    base[(ag,cn)]=max(base[(ag,cn)],links[0])
for k in sorted(set(list(best)+list(base))):
    print(f"    {k[0]:20s} {k[1]:7s} cdev-max={best[k]:9.4f}  link0(base)={base[k]:9.4f}")
PY

  echo "--- (U) per-chain clearance, min over the window (negative = inside the body) ---"
  python3 - "$f" <<'PY'
import re,sys,collections
txt=open(sys.argv[1],errors='ignore').read()
data=open('recharged_assets/physics_chains.txt',errors='ignore').read().split('\n')
model=None; names=collections.defaultdict(dict); n=0
for l in data:
    m=re.match(r'\[model\s+([^\]]+)\]',l.strip())
    if m: model=m.group(1).split()[0]; n=0; continue
    m=re.match(r'\s*chain\s+(\S+)',l)
    if m: names[model][n]=m.group(1); n+=1
worst=collections.defaultdict(lambda:1e9)
for line in txt.split('\n'):
    m=re.search(r'\[HD-PHYS3\] ag=(\S+).*?cclr:(.*)$',line)
    if not m: continue
    ag=m.group(1)
    for a,b in re.findall(r'(\d+)=([0-9.-]+)',m.group(2)):
        i=int(a); v=float(b)
        if v>=999999: continue          # never tested against anything
        nm=names.get(ag,{}).get(i,f'c{i}')
        worst[(ag,nm)]=min(worst[(ag,nm)],v)
for k in sorted(worst):
    print(f"    {k[0]:20s} {k[1]:12s} min-clearance={worst[k]:10.2f}")
if not worst: print("    (no [HD-PHYS3] cclr data in this log)")
PY

  echo "--- (P) influence profile as BUILT ---"
  grep -ao '\[HD-PHYS-INFL\][^|]*' "$f" | sort -u | head -6 | sed 's/^/  /'
  echo "  inflstep max: $(grep -ao 'inflstep=[0-9.]*' "$f" | sed 's/inflstep=//' | sort -g | tail -1)"
  echo
done

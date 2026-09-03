#!/usr/bin/env bash
# Grecharged-pbr-realtime-fusion ROUND 32 — the whole-game sweep.
#
# Owner: "pars du principe que absolument tous les mesh auront du PBR" and "le nombre de mesh
# couverts doit égaler le nombre de mesh existants". So every level of jak1 is graded, and every
# mesh of every level is graded, with --all-textures: the SYNTHETIC CHECKER makes every texture
# displaceable, so a mesh does not have to carry a height map today to be covered.
#
# Two stages, in this order, because the second measures what the first produced:
#   bake   tools/mesh_audit --bake   -> out/jak1/fr3/<level>.meshweld   (what SHIPS)
#   grade  tools/tess_sign          -> .autoport/reports/.../r32/<level>.txt
#
# The grade runs --force-live (the default), i.e. it re-runs mesh_consolidate itself rather than
# reading the sidecar, so the numbers describe THE CODE. The bake stage then proves the sidecar the
# device loads carries the same answer: mesh_audit re-applies its own bake and verifies the round
# trip. Both stages are deterministic, so a level can be re-run in isolation and must reproduce.
#
# Parallelism is deliberately low: a village1-sized grade holds ~1.5 GB and the evaluate loop is
# single-threaded, so the limit is RAM, not cores. Override with JOBS=n.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/r32
mkdir -p "$OUT"
JOBS=${JOBS:-2}
STAGE=${1:-all}          # bake | grade | all
LEVELS=${LEVELS:-$(ls out/jak1/fr3/*.fr3 | xargs -n1 basename | sed 's/\.fr3$//')}

TESS=build/tools/tess_sign/tess_sign
AUDIT=build/tools/mesh_audit/mesh_audit
for b in "$TESS" "$AUDIT"; do
  [ -x "$b" ] || { echo "missing $b — cmake --build build --target tess_sign mesh_audit -j8"; exit 2; }
done

bake_one() {
  local L="$1"
  # --verify-bake is not optional here: it re-loads the fr3, applies the sidecar it just wrote and
  # compares it field-by-field against the live pass. That is the only check that proves the bytes
  # the DEVICE will load carry the same answer as the code this round changed — four earlier rounds
  # shipped as no-ops because nobody verified exactly this.
  "$AUDIT" --game jak1 --level "$L" --bake --verify-bake \
      --out "$OUT/bake_$L.txt" > "$OUT/bake_$L.log" 2>&1
  echo "bake  $L exit=$? sidecar_bytes=$(stat -c%s "out/jak1/fr3/$L.meshweld" 2>/dev/null || echo none)"
}

grade_one() {
  local L="$1"
  "$TESS" --fr3 "out/jak1/fr3/$L.fr3" --all-textures --summary-only \
      --out "$OUT/$L.txt" > "$OUT/$L.log" 2>&1
  echo "grade $L exit=$?"
}

run_stage() {
  local fn="$1"
  local n=0
  for L in $LEVELS; do
    "$fn" "$L" &
    n=$((n + 1))
    if [ "$n" -ge "$JOBS" ]; then
      wait -n 2>/dev/null || wait
      n=$((n - 1))
    fi
  done
  wait
}

case "$STAGE" in
  bake)  run_stage bake_one ;;
  grade) run_stage grade_one ;;
  all)   run_stage bake_one; run_stage grade_one ;;
  *) echo "usage: $0 [bake|grade|all]"; exit 2 ;;
esac

# ---- the whole-game roll-up. One line per level, then the gate over all of them. -----------------
python3 - "$OUT" <<'PY'
import re, sys, glob, os
out = sys.argv[1]
pat = {
  'A_cons':  r'^A_cons OVERALL\s+:\s+([0-9.]+)%',
  'P_sign':  r'^P_sign OVERALL\s+:\s+([0-9.]+)%',
  'B_perm':  r'^B_perm OVERALL\s+:\s+([0-9.]+)%',
  'A_sign':  r'^A_sign OVERALL\s+:\s+([0-9.]+)%',
  'B_live':  r'^B_live  OVERALL\s+:\s+([0-9.]+)%',
  'wA':      r'^WORST A_cons\s+:\s+([0-9.]+)%',
  'wP':      r'^WORST P_sign\s+:\s+([0-9.]+)%',
  'wB':      r'^WORST B_perm\s+:\s+([0-9.]+)%',
  'mA':      r'^meshes at A_cons = 100%\s+:\s+(\d+)\s+of\s+(\d+)',
  'mP':      r'^meshes at P_sign = 100%\s+:\s+(\d+)\s+of\s+(\d+)',
  'mB':      r'^meshes at B_perm = 100%\s+:\s+(\d+)\s+of\s+(\d+)',
}
rows, tot = [], {'mA':[0,0],'mP':[0,0],'mB':[0,0]}
for f in sorted(glob.glob(os.path.join(out, '*.txt'))):
    name = os.path.basename(f)[:-4]
    if name.startswith('bake_'):
        continue
    txt = open(f, errors='replace').read()
    g = {}
    for k, p in pat.items():
        m = re.search(p, txt, re.M)
        g[k] = m.groups() if m else None
    if g['A_cons'] is None:
        rows.append((name, 'NO RESULT')); continue
    for k in ('mA','mP','mB'):
        if g[k]:
            tot[k][0] += int(g[k][0]); tot[k][1] += int(g[k][1])
    rows.append((name, g))
print('%-14s %9s %9s %9s | %9s %9s %9s | %s' %
      ('level','A_cons','P_sign','B_perm','wA_cons','wP_sign','wB_perm','meshes@100 A/P/B'))
for name, g in rows:
    if g == 'NO RESULT':
        print('%-14s %s' % (name, g)); continue
    f = lambda k: (g[k][0] if g[k] else 'n/a')
    m = lambda k: ('%s/%s' % g[k]) if g[k] else 'n/a'
    print('%-14s %9s %9s %9s | %9s %9s %9s | %s %s %s' %
          (name, f('A_cons'), f('P_sign'), f('B_perm'), f('wA'), f('wP'), f('wB'),
           m('mA'), m('mP'), m('mB')))
print()
for k, lab in (('mA','A_cons'), ('mP','P_sign'), ('mB','B_perm')):
    ok, den = tot[k]
    print('WHOLE GAME meshes at %s = 100%%: %d of %d (%.4f%%)' %
          (lab, ok, den, 100.0*ok/den if den else 0.0))
PY

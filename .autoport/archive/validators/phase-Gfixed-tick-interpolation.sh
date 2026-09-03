#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="Gfixed-tick-interpolation"
REP=".autoport/reports/$TAG/report.txt"
F=0
fail(){ F=$((F+1)); echo "[$TAG FAIL] $1"; }
ok(){ echo "[$TAG ok] $1"; }

# 1. Un accumulateur a pas fixe doit exister dans le chemin de simulation.
if grep -rqE 'kFixedTickSeconds|FIXED_TICK_SECONDS|fixed_tick_dt' game/ common/ --include=*.cpp --include=*.h 2>/dev/null \
   && grep -rqE 'while *\(.*(acc|accumulator).*>=' game/ common/ --include=*.cpp 2>/dev/null; then
  ok "une constante de pas fixe ET une boucle de rattrapage existent"
else
  fail "aucun accumulateur a pas fixe — la simulation avance encore au temps de frame reel"
fi

# 2. Une interpolation de rendu doit exister (alpha entre deux etats).
if grep -rqE 'render_alpha|interp_alpha|lerp_pose|slerp' game/graphics/ --include=*.cpp --include=*.h 2>/dev/null; then
  ok "une interpolation de rendu existe"
else
  fail "aucune interpolation de rendu (alpha entre tick precedent et courant)"
fi

# 3. La preuve doit etre une MESURE a plusieurs framerates, pas une capture.
if [ -f "$REP" ]; then
  N=0
  for f in 25 60 90 120; do grep -qE "(^|[^0-9])${f}\s*(fps|FPS)" "$REP" && N=$((N+1)); done
  if [ "$N" -ge 3 ]; then
    ok "le rapport compare au moins 3 framerates ($N/4)"
  else
    fail "le rapport ne compare que $N framerate(s) sur 25/60/90/120 — la preuve exige la comparaison"
  fi
else
  fail "aucun rapport dans $REP"
fi

# 4. La trajectoire (saut) doit etre identique entre framerates.
if [ -f "$REP" ] && grep -qiE 'saut|jump' "$REP" && grep -qiE 'identique|ecart|delta' "$REP"; then
  ok "le rapport publie une comparaison de trajectoire de saut"
else
  fail "aucune comparaison chiffree de hauteur/longueur de saut entre framerates dans $REP"
fi

# 5. Le judder de camera doit etre chiffre avant/apres.
if [ -f "$REP" ] && grep -qiE 'camera' "$REP" && grep -qiE 'avant|apres|before|after' "$REP"; then
  ok "le rapport chiffre la camera avant/apres"
else
  fail "aucune mesure avant/apres du judder de camera dans $REP (voir kmachine.cpp:4507)"
fi

# 6. Non-regression a 60 fps : la reference ne doit pas bouger.
if [ -f "$REP" ] && grep -qiE '60\s*(fps|FPS).*(identique|inchange|reference)|reference.*60' "$REP"; then
  ok "la non-regression a 60 fps est demontree"
else
  fail "le rapport ne demontre pas que la sortie a 60 fps est INCHANGEE — c'est la reference"
fi

[ "$F" -gt 0 ] && { echo "[$TAG] $F verdict(s) en echec"; exit 1; }
echo "[$TAG] toutes les gates passent"
exit 0

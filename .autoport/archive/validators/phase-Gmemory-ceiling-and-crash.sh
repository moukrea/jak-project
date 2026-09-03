#!/usr/bin/env bash
# Chaque gate nomme un fait mesurable. Aucune ne passe "par construction".
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="Gmemory-ceiling-and-crash"
REP=".autoport/reports/$TAG/report.txt"
F=0
fail(){ F=$((F+1)); echo "[$TAG FAIL] $1"; }
ok(){ echo "[$TAG ok] $1"; }

# --- DEFAUT 1 : le decodage PNG au chargement doit avoir disparu -----------------------
if grep -rq 'custom_tex::lookup' game/graphics/opengl_renderer/loader/LoaderStages.cpp 2>/dev/null \
   && ! grep -rqiE 'cache|baked|precompute|prebaked' game/graphics/opengl_renderer/loader/CustomTextureReplacements.cpp 2>/dev/null; then
  fail "les textures de remplacement sont encore decodees depuis le PNG au chargement (aucun cache/bake dans CustomTextureReplacements.cpp)"
else
  ok "un chemin pre-cuit existe pour les textures de remplacement"
fi

# La mesure APPARIEE doit etre publiee : total de mise en place et pire etape.
if [ -f "$REP" ] && grep -qE 'stage[- ]texture|A5[23]-TEX' "$REP"; then
  WORST=$(grep -oE 'pire[^0-9]*([0-9]+)' "$REP" | grep -oE '[0-9]+' | sort -rn | head -1)
  if [ -n "${WORST:-}" ] && [ "$WORST" -lt 200 ]; then
    ok "pire etape de texture ${WORST} ms (< 200)"
  else
    fail "pire etape de texture ${WORST:-inconnue} ms — la reference avant correctif est 2072 ms, la cible < 200 ms"
  fi
else
  fail "aucune mesure de mise en place de texture publiee dans $REP"
fi

# --- DEFAUT 2 : le crash au chargement ------------------------------------------------
# Le pic RSS mesure doit passer sous la barre qui declenche le tueur.
if [ -f "$REP" ] && grep -qiE 'pic|peak' "$REP"; then
  PEAK=$(grep -oiE '(pic|peak)[^0-9]{0,12}([0-9]{3,5})' "$REP" | grep -oE '[0-9]{3,5}' | sort -rn | head -1)
  if [ -n "${PEAK:-}" ] && [ "$PEAK" -lt 800 ]; then
    ok "pic RSS ${PEAK} Mo (< 800)"
  else
    fail "pic RSS ${PEAK:-inconnu} Mo — references avant correctif 1212-1234 Mo, cible < 800 Mo"
  fi
else
  fail "aucun pic RSS mesure publie dans $REP"
fi

# Les deux blocs de 150 Mo doivent etre identifies (nommes) ou disparus.
if [ -f "$REP" ] && grep -qE '150[.,]3|150 ?Mo' "$REP"; then
  ok "les blocs de 150 Mo sont traites dans le rapport"
else
  fail "les deux blocs residents de 150,32 Mo ne sont ni identifies ni elimines dans $REP"
fi

# --- Non-regression des autres cibles --------------------------------------------------
if [ -f "$REP" ] && grep -qiE 'x86|redmi|honor' "$REP"; then
  ok "le rapport parle des autres cibles"
else
  fail "aucune verification de non-regression sur x86 / Redmi / Honor dans $REP"
fi

[ "$F" -gt 0 ] && { echo "[$TAG] $F verdict(s) en echec"; exit 1; }
echo "[$TAG] toutes les gates passent"
exit 0

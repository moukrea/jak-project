#!/usr/bin/env bash
# Valide le pre-calcul deterministe. Aucune gate ne "passe par construction" :
# chaque verdict nomme un fait verifiable dans l'arbre ou dans le rapport.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="Gprecompute-deterministic-bake"
FAILURES=0
fail(){ FAILURES=$((FAILURES+1)); echo "[$TAG FAIL] $1"; }
ok(){ echo "[$TAG ok] $1"; }

# 1. Les tangentes doivent etre SERIALISEES dans le fr3, plus reconstruites au chargement.
if grep -q 'tangents' common/custom_data/TFrag3Data.cpp && \
   grep -A2 'void TfragTree::serialize' common/custom_data/TFrag3Data.cpp | grep -q 'tangents'; then
  ok "les tangentes sont serialisees dans le fr3"
else
  fail "les tangentes ne sont PAS serialisees dans le fr3 (TfragTree::serialize) — encore reconstruites a chaque chargement"
fi

# 2. Le chemin de chargement ne doit plus appeler la reconstruction.
# La reconstruction est appelee depuis TfragTree::unpack(), pas depuis le dossier du
# chargeur : chercher au mauvais endroit rendait un FAUX VERT (essai a blanc 2026-08-26).
if grep -rn 'reconstruct_tfrag_tangents(' common/custom_data/TFrag3Data.cpp \
     game/graphics/opengl_renderer/loader/ 2>/dev/null | grep -qv 'void reconstruct_tfrag_tangents'; then
  fail "reconstruct_tfrag_tangents est encore appelee au chargement (TfragTree::unpack) — travail refait a chaque lancement"
else
  ok "plus aucune reconstruction de tangentes au chargement"
fi

# 3. Le niveau de subdivision doit etre une OPTION, pas un defaut impose a 3 tours.
DEF=$(grep -oE 'int max_rounds = [0-9]+' common/custom_data/MeshSubdivide.h 2>/dev/null | grep -oE '[0-9]+$')
if [ "${DEF:-3}" -ge 3 ]; then
  fail "max_rounds vaut encore ${DEF:-3} par defaut — multiplicateur de geometrie impose a toutes les cibles"
else
  ok "le defaut de subdivision est descendu a ${DEF}"
fi
if grep -rqE 'subdiv' game/graphics/gfx.h game/graphics/pipelines/*.h 2>/dev/null; then
  ok "la subdivision est exposee comme reglage"
else
  fail "la subdivision n'est exposee nulle part comme reglage utilisateur — encore un comportement automatique"
fi

# 4. Une mesure APPARIEE doit exister (meme scene avant/apres), pas une capture.
REP=".autoport/reports/$TAG/report.txt"
if [ -f "$REP" ] && grep -qE 'lvl=[a-z0-9]+' "$REP" && grep -qE 'tris=[0-9]+' "$REP"; then
  ok "le rapport contient une mesure nommant sa scene"
else
  fail "aucune mesure appariee (scene + triangles) dans $REP"
fi

if [ "$FAILURES" -gt 0 ]; then
  echo "[$TAG] $FAILURES verdict(s) en echec"
  exit 1
fi
echo "[$TAG] toutes les gates passent"
exit 0

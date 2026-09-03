#!/usr/bin/env bash
# ============================================================================================
# SUPERSEDE — NE PAS RELANCER. Cette version desarme LES DEUX chaines et ne produit AUCUNE
# mesure : `jak-hd-physics-init` sort sur « no chain data for keira-hd », aucun slot n'est
# alloue, et `physroom-tick` reste indefiniment dans PHYSROOM-PH-SETTLE dont la sortie exige
# `(> (-> self nchain) 0)` (phys-room.gc:3026). 13 minutes de course, zero PHYSJTW.
# Remplace par .autoport/c82_ablate_one.sh, qui desarme UNE chaine a la fois.
# Conserve pour que la tentative ratee reste auditable, pas pour etre rejoue.
# ============================================================================================
# c82_ablate_chains.sh — DIRECTIVES v3fee554599, cycle 82.
#
# ABLATION DE DONNEE PURE : les deux chaines de poitrine sont mises en commentaire dans
# recharged_assets/physics_chains.txt. Plus rien n'ecrit lBoob/lBooc/rBoob/rBooc, donc la 4x4 que
# `PHYSJTW` publie pour ces quatre joints DEVIENT la pose d'auteur, image par image.
# ZERO build : le fichier est lu a l'execution (kmachine.cpp:1282), le CGO n'est pas touche.
#
# Predictions ecrites AVANT : .autoport/c82-predictions.txt (md5 c0cb2a10151e2be626e503e796a31416)
#
# Le verrou de livraison est pose ICI, pour toute la duree ou l'arbre porte la donnee ablatee :
# l'auto-constructeur est vivant et il livre ce qu'il trouve. Convention DIRECTIVES 2026-08-14
# 07:10 : PID + horodatage + trap, jamais un `touch` nu.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=.autoport/reports/Grecharged-secondary-motion
CH=recharged_assets/physics_chains.txt
DLOCK=.autoport/.deploy-in-progress

restore(){
  cp -f "$OUT/c82-chains-armed.txt" "$CH"
  echo "== RESTAURE : $(grep -c '^chain ' "$CH") chaines dans $CH"
  md5sum "$CH" "$OUT/c82-chains-armed.txt"
  cp -f "$OUT/keira-room-x86.c81-armed.log"   "$OUT/keira-room-x86.log"
  cp -f "$OUT/keira-room-table.c81-armed.txt" "$OUT/keira-room-table.txt"
  echo "== log/table remis sur la course ARMEE du cycle 81"
  [ "$_own" = 1 ] && rm -f "$DLOCK"
  git status --porcelain -- recharged_assets/ | head
  return 0
}
_own=0
if [ ! -f "$DLOCK" ]; then
  printf 'c82_ablate_chains pid=%s started=%s\n' "$$" "$(date -Is)" > "$DLOCK"; _own=1
else
  echo "FAIL: verrou de livraison deja detenu : $(cat "$DLOCK")"; exit 1
fi
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- 0. LA COURSE ARMEE ET SA DONNEE SONT ARCHIVEES SOUS LEUR PROPRE NOM AVANT TOUT ------------
cp -f "$OUT/keira-room-x86.log"   "$OUT/keira-room-x86.c81-armed.log"
cp -f "$OUT/keira-room-table.txt" "$OUT/keira-room-table.c81-armed.txt"
cp -f "$CH"                        "$OUT/c82-chains-armed.txt"
echo "== ARMEE : log md5 $(md5sum "$OUT/keira-room-x86.c81-armed.log" | cut -d' ' -f1)"
echo "==         chains md5 $(md5sum "$OUT/c82-chains-armed.txt" | cut -d' ' -f1)"

# --- 1. l'ablation : les 6 lignes qui declarent les deux chaines -------------------------------
python3 - "$CH" <<'PY'
import sys, re
p = sys.argv[1]
out, n = [], 0
for ln in open(p):
    if re.match(r'^(chain (chestL|chestR) |j (lBoob|lBooc|rBoob|rBooc)\s*$)', ln):
        out.append('#C82-ABLATED# ' + ln); n += 1
    else:
        out.append(ln)
open(p, 'w').writelines(out)
print(f"lignes mises en commentaire : {n} (attendu 6)")
PY
echo "== chaines restantes : $(grep -c '^chain ' "$CH")  (attendu 0)"
[ "$(grep -c '^chain ' "$CH")" = "0" ] || { echo "FAIL: l'ablation n'a pas pris"; exit 1; }
grep -c '^collider \|^capsule ' "$CH" | sed 's/^/== volumes intacts : /'

# --- 2. la course. AUCUN build : le CGO livre est inchange, on le prouve -----------------------
ls -la out/jak1/iso/GAME.CGO goal_src/jak1/pc/phys-room.gc goal_src/jak1/pc/jak-hd-physics.gc
git diff --stat -- goal_src/ | tail -2

ROOM_TIMEOUT=1500 bash .autoport/keira_room_x86.sh > "$OUT/c82-run.out" 2>&1
rc=$?
echo "== runner rc=$rc (6 = la course est faite, l'analyseur a refuse le tableau : attendu a 0 chaine)"
tail -25 "$OUT/c82-run.out"

# --- 3. la trace desarmee est mise a l'abri AVANT la restauration ------------------------------
if [ -s "$OUT/keira-room-x86.log" ] && grep -aq '^PHYSJTWN' "$OUT/keira-room-x86.log"; then
  cp -f "$OUT/keira-room-x86.log" "$OUT/keira-room-x86.c82-desarme.log"
  echo "== DESARMEE : $(md5sum "$OUT/keira-room-x86.c82-desarme.log" | cut -d' ' -f1)"
  echo "== PHYSJTW  : $(grep -ac '^PHYSJTW ' "$OUT/keira-room-x86.c82-desarme.log") lignes"
  echo "== PHYSCHAIN: $(grep -ac '^PHYSCHAIN' "$OUT/keira-room-x86.c82-desarme.log") (attendu 0)"
else
  echo "FAIL: la course desarmee n'a pas produit de PHYSJTWN — rien a analyser."
  exit 1
fi

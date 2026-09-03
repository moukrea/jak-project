#!/usr/bin/env bash
# c82_ablate_one.sh <chestL|chestR> <tag> — DIRECTIVES v3fee554599, cycle 82.
#
# DESARME UNE SEULE chaine de poitrine, par DELETION seule, dans recharged_assets/physics_chains.txt.
# L'autre reste armee : la salle alloue son slot et parcourt ses phases (sans quoi elle reste
# indefiniment dans PHYSROOM-PH-SETTLE, mesure de la premiere tentative). Les deux joints de la
# chaine desarmee ne sont ecrits par RIEN : leur `PHYSJTW` EST la pose d'auteur.
# ZERO build : le fichier est lu a l'execution (kmachine.cpp:1282).
#
# Predictions ecrites AVANT : .autoport/c82-predictions.txt (md5 1a3231a4ba714f33fabf8184efe1868c)
set -uo pipefail
cd "$(dirname "$0")/.."
CH_OFF="${1:?chestL ou chestR}"
TAG="${2:?tag}"
case "$CH_OFF" in
  chestL) J1=lBoob; J2=lBooc;;
  chestR) J1=rBoob; J2=rBooc;;
  *) echo "FAIL: chaine inconnue $CH_OFF"; exit 1;;
esac
OUT=.autoport/reports/Grecharged-secondary-motion
CH=recharged_assets/physics_chains.txt
DLOCK=.autoport/.deploy-in-progress

restore(){
  cp -f "$OUT/c82-chains-armed.txt" "$CH"
  echo "== RESTAURE : $(grep -c '^chain ' "$CH") chaines ; md5 $(md5sum "$CH" | cut -d' ' -f1)"
  cp -f "$OUT/keira-room-x86.c81-armed.log"   "$OUT/keira-room-x86.log"
  cp -f "$OUT/keira-room-table.c81-armed.txt" "$OUT/keira-room-table.txt"
  echo "== log/table remis sur la course ARMEE du cycle 81"
  [ "$_own" = 1 ] && rm -f "$DLOCK"
  git status --porcelain -- recharged_assets/ | head
  return 0
}
_own=0
if [ ! -f "$DLOCK" ]; then
  printf 'c82_ablate_one pid=%s started=%s\n' "$$" "$(date -Is)" > "$DLOCK"; _own=1
else
  echo "FAIL: verrou de livraison deja detenu : $(cat "$DLOCK")"; exit 1
fi
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[ -s "$OUT/c82-chains-armed.txt" ] || cp -f "$CH" "$OUT/c82-chains-armed.txt"
[ -s "$OUT/keira-room-x86.c81-armed.log" ] || { echo "FAIL: la course armee de reference manque"; exit 1; }

# --- 1. l'ablation : 3 lignes, par deletion seule ---------------------------------------------
python3 - "$CH" "$CH_OFF" "$J1" "$J2" <<'PY'
import sys, re
p, c, j1, j2 = sys.argv[1:5]
out, n = [], 0
for ln in open(p):
    if re.match(rf'^chain {c} ', ln) or re.match(rf'^j ({j1}|{j2})\s*$', ln):
        out.append('#C82-ABLATED# ' + ln); n += 1
    else:
        out.append(ln)
open(p, 'w').writelines(out)
print(f"lignes mises en commentaire : {n} (attendu 3)")
PY
echo "== chaines restantes : $(grep -c '^chain ' "$CH") (attendu 1) -> $(grep '^chain ' "$CH" | cut -d' ' -f2)"
[ "$(grep -c '^chain ' "$CH")" = "1" ] || { echo "FAIL: l'ablation n'a pas pris"; exit 1; }

# --- 2. la course. AUCUN build : le CGO livre est inchange -------------------------------------
git diff --stat -- goal_src/ | tail -2
ROOM_TIMEOUT=1500 bash .autoport/keira_room_x86.sh > "$OUT/c82-run-$TAG.out" 2>&1
echo "== runner rc=$? "
tail -12 "$OUT/c82-run-$TAG.out"

# --- 3. la trace est mise a l'abri AVANT la restauration ---------------------------------------
if [ -s "$OUT/keira-room-x86.log" ] && grep -aq '^PHYSJTWN' "$OUT/keira-room-x86.log"; then
  cp -f "$OUT/keira-room-x86.log" "$OUT/keira-room-x86.c82-$TAG.log"
  echo "== $TAG md5 $(md5sum "$OUT/keira-room-x86.c82-$TAG.log" | cut -d' ' -f1)"
  echo "== PHYSJTW  $(grep -ac '^PHYSJTW ' "$OUT/keira-room-x86.c82-$TAG.log")"
  echo "== PHYSCHAIN $(grep -a '^PHYSCHAIN' "$OUT/keira-room-x86.c82-$TAG.log")"
else
  echo "FAIL: pas de PHYSJTWN dans la course $TAG — rien a analyser."
  exit 1
fi

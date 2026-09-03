#!/usr/bin/env bash
# c78_ablate_fwall.sh — ABLATION DU MUR DE FORCE DE SPEC 21 (`*phys-fwall*` 1 -> 0), UNE COURSE,
# puis RESTAURATION INTEGRALE de l'arbre livre. Predictions : .../c78-predictions.txt (md5
# fbc84958a5919de56ac997e7dcf8101d), ecrites avant cette edition.
#
# Le verrou de livraison est pose ICI, pour toute la duree ou l'arbre porte le moteur ABLATE :
# l'auto-constructeur est vivant (pid dans .autoport/.auto_build_apk.pid) et il livre ce qu'il
# trouve. Convention DIRECTIVES 2026-08-14 07:10 : PID + horodatage + trap, jamais un `touch` nu.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=.autoport/reports/Grecharged-secondary-motion
ENG=goal_src/jak1/pc/jak-hd-physics.gc
DLOCK=.autoport/.deploy-in-progress
GOALC="./build/goalc/goalc --user-auto --game jak1 -c (mi)"

restore(){
  sed -i 's/^(define \*phys-fwall\* 0)/(define *phys-fwall* 1)/' "$ENG"
  echo "== RESTAURE : $(grep -n 'define \*phys-fwall\*' "$ENG")"
  ./build/goalc/goalc --user-auto --game jak1 -c '(mi)' >"$OUT/c78-rebuild.out" 2>&1
  echo "== rebuild livre : $(grep -c . "$OUT/c78-rebuild.out") lignes ; $(tail -2 "$OUT/c78-rebuild.out" | tr '\n' ' ')"
  # la table et le log que le validateur lit doivent redecrire l'arbre LIVRE, pas l'ablation
  cp -f "$OUT/keira-room-x86.c77-baseline.log"   "$OUT/keira-room-x86.log"
  cp -f "$OUT/keira-room-table.c77-baseline.txt" "$OUT/keira-room-table.txt"
  echo "== table/log remis sur la ligne de base c77"
  [ "$_own" = 1 ] && rm -f "$DLOCK"
  git diff --stat -- goal_src/ | tail -3
  return 0
}
_own=0
if [ ! -f "$DLOCK" ]; then
  printf 'c78_ablate_fwall pid=%s started=%s\n' "$$" "$(date -Is)" > "$DLOCK"; _own=1
else
  echo "FAIL: verrou de livraison deja detenu : $(cat "$DLOCK")"; exit 1
fi
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- 0. la LIGNE DE BASE est archivee sous son propre nom AVANT que la course l'ecrase ---------
cp -f "$OUT/keira-room-x86.log"   "$OUT/keira-room-x86.c77-baseline.log"
cp -f "$OUT/keira-room-table.txt" "$OUT/keira-room-table.c77-baseline.txt"
echo "== base c77 : log md5 $(md5sum "$OUT/keira-room-x86.c77-baseline.log" | cut -d' ' -f1)"
echo "==           table md5 $(md5sum "$OUT/keira-room-table.c77-baseline.txt" | cut -d' ' -f1)"

# --- 1. l'ablation : UN caractere -------------------------------------------------------------
before=$(wc -l < "$ENG")
sed -i 's/^(define \*phys-fwall\* 1)/(define *phys-fwall* 0)/' "$ENG"
after=$(wc -l < "$ENG")
echo "== ablation : $(grep -n 'define \*phys-fwall\*' "$ENG")"
echo "== lignes moteur $before -> $after (doit etre identique)"
[ "$before" = "$after" ] || { echo "FAIL: le compte de lignes a bouge"; exit 1; }
git diff --numstat -- "$ENG"

# --- 2. build GOAL ----------------------------------------------------------------------------
./build/goalc/goalc --user-auto --game jak1 -c '(mi)' >"$OUT/c78-build.out" 2>&1
tail -3 "$OUT/c78-build.out"
grep -qiE '^\[?error|failed' "$OUT/c78-build.out" && { echo "FAIL: build"; exit 1; }

# --- 3. la course -----------------------------------------------------------------------------
ROOM_TIMEOUT=1500 bash .autoport/keira_room_x86.sh > "$OUT/c78-run.out" 2>&1
rc=$?
tail -20 "$OUT/c78-run.out"
[ "$rc" = 0 ] || { echo "FAIL: course rc=$rc"; exit 1; }

# --- 4. on met la course ABLATEE de cote sous son propre nom -----------------------------------
cp -f "$OUT/keira-room-x86.log"   "$OUT/keira-room-x86.c78-fwalloff.log"
cp -f "$OUT/keira-room-table.txt" "$OUT/keira-room-table.c78-fwalloff.txt"
echo "== ablation : log md5 $(md5sum "$OUT/keira-room-x86.c78-fwalloff.log" | cut -d' ' -f1)"
echo "== P1 armement : $(grep -a '^PHYSLIM4' "$OUT/keira-room-x86.c78-fwalloff.log")"
echo "== OK"

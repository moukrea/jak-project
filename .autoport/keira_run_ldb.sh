#!/usr/bin/env bash
# keira_run_ldb.sh — UNE course complete de la salle, du (mi) au tableau, sous verrou.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean.
# Cycle du 2026-08-14 : livrer `PHYSRINGBX` (deviation NON normalisee) a cote de `PHYSRINGAX`
# (deviation normalisee) pour que la selectivite de SPEC 24 soit lisible sur un instrument qui
# porte les trois degres de liberte.
#
# Pourquoi ce script existe alors que `keira_room_x86.sh` existe deja : trois pieges connus, tous
# payes, qu'un enchainement a la main re-paye a chaque fois.
#   1. `keira_room_x86.sh` NE CONSTRUIT PAS le tableau — c'est un appel separe a
#      physics_room_table.py. L'oublier laisse le tableau de la course PRECEDENTE en place, ce qui
#      se lit exactement comme « mon changement n'a rien fait ».
#   2. `ROOM_TIMEOUT` vaut 420 s par defaut et la course en demande ~520 : le depassement ecrase
#      le LOG avant de sortir en erreur, donc on ne peut meme pas re-deriver le tableau.
#   3. L'auto-constructeur POSSEDE l'arbre de mesure et le bascule en arm64 en pleine course
#      (il efface out/jak1/obj/*.o *.go et reecrit out/jak1/iso). Le verrou qu'il relit lui-meme
#      est `.autoport/.deploy-in-progress` — pose ici AVEC SON DETENTEUR (PID + date), jamais un
#      `touch` nu : un verrou sans detenteur a deja coute 108 minutes de livraison a l'owner.
set -uo pipefail
cd "$(dirname "$0")/.."

OUT=.autoport/reports/Grecharged-secondary-motion
LOG="$OUT/keira-room-x86.log"
TBL="$OUT/keira-room-table.txt"
TAG="${TAG:-LDB}"
LOCK=.autoport/.deploy-in-progress

mkdir -p "$OUT"

# --- le verrou, a la convention des DIRECTIVES du 2026-08-14 07:10 ----------------------------
if [ -e "$LOCK" ]; then
  _h=$(cat "$LOCK" 2>/dev/null)
  _p=$(printf '%s' "$_h" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')
  if [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null; then
    echo "FAIL: verrou tenu par un processus VIVANT: $_h"; exit 1
  fi
  echo "verrou PERIME (detenteur mort ou anonyme), je le reprends: ${_h:-<vide>}"
fi
printf 'keira_run_ldb pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# --- 0. l'etat d'AVANT, garde pour la comparaison ----------------------------------------------
# Le diff avec le tableau precedent est le seul controle de non-regression qui tourne vraiment.
[ -f "$TBL" ] && cp -f "$TBL" "$OUT/keira-room-table.PRE-$TAG.txt"
[ -f "$LOG" ] && cp -f "$LOG" "$OUT/keira-room-x86.PRE-$TAG.log"

# --- 1. compilation GOAL ------------------------------------------------------------------------
echo "=== (mi) ==="
./build/goalc/goalc --user-auto --game jak1 -c '(mi)' > "$OUT/mi-$TAG.log" 2>&1
_rc=$?
tail -5 "$OUT/mi-$TAG.log"
if [ "$_rc" -ne 0 ]; then
  echo "FAIL: (mi) a echoue (rc=$_rc). Erreurs:"
  grep -aiE "error|erreur|failed" "$OUT/mi-$TAG.log" | head -30
  exit 1
fi

# --- 2. l'ARCHITECTURE de l'arbre de mesure, pas seulement sa date ------------------------------
# La gate de fraicheur de keira_room_x86.sh compare des DATES : elle ne verrait pas un GAME.CGO
# arm64 tout frais. On garde l'empreinte des deux bouts de la course et on les compare a la fin.
MD5_BEFORE=$(md5sum out/jak1/iso/GAME.CGO | cut -d' ' -f1)
echo "GAME.CGO avant course: $MD5_BEFORE"

# --- 3. la course --------------------------------------------------------------------------------
echo "=== salle ==="
ROOM_TIMEOUT="${ROOM_TIMEOUT:-1500}" bash .autoport/keira_room_x86.sh
_rcroom=$?

MD5_AFTER=$(md5sum out/jak1/iso/GAME.CGO | cut -d' ' -f1)
echo "GAME.CGO apres course: $MD5_AFTER"
if [ "$MD5_BEFORE" != "$MD5_AFTER" ]; then
  echo "FAIL: GAME.CGO A CHANGE PENDANT LA COURSE — la mesure porte sur un arbre qui a bouge."
  echo "  (auto-constructeur ? verifier .autoport/.auto_build_apk.pid)"
  exit 1
fi
[ "$_rcroom" -eq 0 ] || { echo "FAIL: la course a echoue (rc=$_rcroom)"; exit 1; }

# --- 4. le tableau, qui est un appel SEPARE ------------------------------------------------------
echo "=== tableau ==="
python3 .autoport/physics_room_table.py "$LOG" "$TBL" || { echo "FAIL: physics_room_table.py"; exit 1; }

# --- 5. ce que la course a vraiment produit ------------------------------------------------------
echo "=== compte des series d'impulsion ==="
for t in PHYSRINGAX PHYSRINGAX2 PHYSRINGBX PHYSRINGBX2 PHYSRINGAZ PHYSRINGBZ; do
  printf '  %-12s %6d\n' "$t" "$(grep -ac "^$t " "$LOG")"
done
echo "PHYSEND: $(grep -ac '^PHYSEND' "$LOG")"
echo "OK"

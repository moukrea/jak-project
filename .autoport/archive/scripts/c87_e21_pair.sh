#!/usr/bin/env bash
# c87_e21_pair.sh — LA PAIRE APPARIEE DE LA BORNE DE SPEC 21/22 SUR LE POINT DE CHAIR.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean.
# DIRECTIVES v3fee554599.
#
# Le cycle 87 fait DEUX choses dans le meme moteur, et elles doivent etre attribuables
# SEPAREMENT — sinon le resultat ne vaut rien (`attribution-harness-outlives-its-defect`) :
#   (1) RETRAIT de `phys-apex-scale`, la borne de §22 posee sur la POINTE (un JOINT) ;
#   (2) AJOUT de la borne de §21/§22 sur le POINT DE CHAIR livre (section 6, [NOTE-471]).
#
# D'ou deux jambes, et l'ordre compte :
#   JAMBE B (`*phys-e21-off* 1`) : (1) seul.  B contre la trace ARCHIVEE c81 = le prix du RETRAIT.
#   JAMBE A (`*phys-e21-off* 0`) : (1)+(2).   A contre B                     = ce que l'AJOUT rend.
# B tourne EN PREMIER pour que la derniere course — donc le log et le tableau que le validateur
# lit — decrive l'ARBRE LIVRE, qui est la jambe ARMEE. C'est la regle du cycle 78.
set -uo pipefail
cd "$(dirname "$0")/.."
ENG=goal_src/jak1/pc/jak-hd-physics.gc
OUT=.autoport/reports/Grecharged-secondary-motion

_restore(){ sed -i 's/^(define \*phys-e21-off\* 1)/(define *phys-e21-off* 0)/' "$ENG"; }
trap _restore EXIT

grep -q '^(define \*phys-e21-off\* 0)' "$ENG" || { echo "FAIL: l'arbre ne part pas ARME"; exit 1; }
BEFORE=$(wc -l < "$ENG")
echo "== moteur : $BEFORE lignes (plafond CLEAN 4800)"

run_leg(){ # $1 = nom de jambe
  local tag="$1"
  ./build/goalc/goalc --user-auto --game jak1 -c '(mi)' > "$OUT/c87-build-$tag.out" 2>&1
  tail -2 "$OUT/c87-build-$tag.out"
  sed 's/\x1b\[[0-9;]*m//g' "$OUT/c87-build-$tag.out" | grep -qiE '^\[?error|Compilation Error|Fatal' \
    && { echo "FAIL: build $tag"; return 1; }
  ROOM_TIMEOUT=1500 bash .autoport/keira_room_x86.sh > "$OUT/c87-run-$tag.out" 2>&1
  local rc=$?
  tail -8 "$OUT/c87-run-$tag.out"
  [ "$rc" = 0 ] || { echo "FAIL: course $tag rc=$rc"; return 1; }
  cp -f "$OUT/keira-room-x86.log"   "$OUT/keira-room-x86.c87-$tag.log"
  cp -f "$OUT/keira-room-table.txt" "$OUT/keira-room-table.c87-$tag.txt"
  echo "== $tag : log md5 $(md5sum "$OUT/keira-room-x86.c87-$tag.log" | cut -d' ' -f1)"
  echo "== $tag : $(grep -a -m1 '^PHYSE21' "$OUT/keira-room-x86.c87-$tag.log")"
  echo "== $tag : $(grep -a -m1 '^PHYSE22' "$OUT/keira-room-x86.c87-$tag.log")"
  return 0
}

# ---- JAMBE B : la borne neuve DESARMEE. Un caractere, le compte de lignes ne bouge pas. -------
sed -i 's/^(define \*phys-e21-off\* 0)/(define *phys-e21-off* 1)/' "$ENG"
[ "$(wc -l < "$ENG")" = "$BEFORE" ] || { echo "FAIL: le compte de lignes a bouge"; exit 1; }
echo "== JAMBE B (desarmee) : $(grep -n 'define \*phys-e21-off\*' "$ENG")"
run_leg B || exit 1

# ---- JAMBE A : l'arbre LIVRE, arme. C'est la derniere course, donc celle que le validateur lit.
_restore
[ "$(wc -l < "$ENG")" = "$BEFORE" ] || { echo "FAIL: le compte de lignes a bouge"; exit 1; }
echo "== JAMBE A (armee, LIVREE) : $(grep -n 'define \*phys-e21-off\*' "$ENG")"
run_leg A || exit 1

echo "== OK : deux jambes, arbre laisse ARME"

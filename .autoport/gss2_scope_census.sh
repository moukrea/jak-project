#!/usr/bin/env bash
# Gsubtitle-style-2 — PERIMETRE, mesure CAUSALE au niveau du code compile.
# On recompile l'arbre GOAL avec et sans le seul fichier modifie, et on compare le md5 de
# CHAQUE objet produit. Le nombre d'objets qui changent EST le perimetre : s'il vaut 1
# (subtitle.o), aucun autre chemin de texte du jeu ne peut avoir bouge.
# Controle de determinisme inclus : A vs C doit etre vide, sinon la mesure ne vaut rien.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gsubtitle-style-2; mkdir -p "$OUT"
LOCK=.autoport/.deploy-in-progress
printf 'gss2_census pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
GOALC=build-x86/goalc/goalc
SRC=goal_src/jak1/pc/subtitle.gc
KEEP=/tmp/gss2-patched-subtitle.gc
build() { timeout 900 "$GOALC" --game jak1 --proj-path . --disable-ansi --cmd '(build-game)' > "$1" 2>&1; grep -q "Successfully built all" "$1"; }

cp "$SRC" "$KEEP"
echo "== A : arbre AVEC le correctif =="
build "$OUT/census-A.log" || { echo "build A KO"; exit 1; }
md5sum out/jak1/obj/*.o | sort -k2 > "$OUT/census-A.md5"

echo "== B : arbre SANS le correctif (subtitle.gc de HEAD) =="
git checkout -- "$SRC"
build "$OUT/census-B.log" || { echo "build B KO"; cp "$KEEP" "$SRC"; exit 1; }
md5sum out/jak1/obj/*.o | sort -k2 > "$OUT/census-B.md5"

echo "== C : correctif remis (controle de determinisme) =="
cp "$KEEP" "$SRC"
build "$OUT/census-C.log" || { echo "build C KO"; exit 1; }
md5sum out/jak1/obj/*.o | sort -k2 > "$OUT/census-C.md5"

echo "== resultats =="
{
  echo "--- determinisme : objets differents entre A et C (doit etre VIDE) ---"
  diff <(cut -d' ' -f1,3 "$OUT/census-A.md5") <(cut -d' ' -f1,3 "$OUT/census-C.md5") || true
  echo "--- objets GOAL dont le code compile CHANGE entre HEAD et le correctif ---"
  join -j 2 <(awk '{print $1" "$2}' "$OUT/census-B.md5" | sort -k2) <(awk '{print $1" "$2}' "$OUT/census-A.md5" | sort -k2) \
    | awk '$2 != $3 {print $1}' | sort
  echo "--- comptes ---"
  echo "objets_total=$(wc -l < "$OUT/census-A.md5")"
  echo "objets_changes=$(join -j 2 <(awk '{print $1" "$2}' "$OUT/census-B.md5" | sort -k2) <(awk '{print $1" "$2}' "$OUT/census-A.md5" | sort -k2) | awk '$2 != $3' | wc -l)"
  echo "determinisme_A_vs_C_diffs=$(diff <(cut -d' ' -f1,3 "$OUT/census-A.md5") <(cut -d' ' -f1,3 "$OUT/census-C.md5") | grep -c '^[<>]' || true)"
} | tee "$OUT/census.txt"

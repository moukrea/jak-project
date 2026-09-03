#!/usr/bin/env bash
# Validator — Gfont-urbanist
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gfu FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gfu ok] $*"; }
R=.autoport/reports/Gfont-urbanist/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*URBANIST[[:space:]]+LIVE[[:space:]]+MIXED[[:space:]]+CASE' "$R" || fail "report lacks RESULT: URBANIST LIVE MIXED CASE"
grep -qiE 'font12-table' "$R" || fail "font24-table|uv|la table UV branchee doit etre nommee"
grep -qiE 'lowercase' "$R" || fail "minuscule|la correspondance des minuscules doit etre prouvee"
grep -qiE '4.?bit' "$R" || fail "8.?bit|profondeur|depth|le format retenu doit etre justifie par une mesure"
grep -qiE 'japon' "$R" || fail "ja-JP|CJK|le japonais doit rester sur sa police d origine"
grep -qiE 'acronym' "$R" || fail "exception|PS2|la regle de casse et ses exceptions doivent etre publiees"
grep -qiE 'by|bearing|ordonnee|baseline' "$R" || fail "l'\''ordonnee par glyphe (by) doit etre traitee"
grep -qiE 'adv|avance' "$R" || fail "l'\''avance par glyphe (adv) doit etre traitee"
grep -qiE "table.*(runtime|execution|reel)|reel.*table|cote a cote" "$R" || fail "il faut publier les valeurs REELLEMENT utilisees a cote de celles de la table"
grep -qiE '\bh\b.*\ba\b|glyphe' "$R" || fail "la preuve doit porter sur des glyphes nommes"
ok "report markers present"
SUP=$(git log --format=%H --grep="\[autoport/supervisor\]" | head -1); ANCHOR=${SUP:-HEAD~1}
CHG=$(git diff --name-only "$ANCHOR" -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null; git status --porcelain -- goal_src/ game/ android/ recharged_assets/ 2>/dev/null | awk "{print \$2}")
echo "$CHG" | grep -qE "goal_src/|game/|android/|recharged_assets/" || fail "no code/asset change for this phase"
ok "code change present"

# ---- GATE MECANIQUE : le texte ANGLAIS embarque dans l'APK porte-t-il des minuscules ? ----
# L'owner a vu du TOUT-MAJUSCULES sur le Redmi le 2026-08-28 alors que son x86 etait correct :
# `out/jak1-android-text/` est un chemin de sortie DISTINCT de `out/jak1/iso/` et il datait du
# 11 aout. Une affirmation ne vaut rien ici, seul le CONTENU du fichier livre compte.
APK=$(find android -name 'app-jak1-*.apk' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
[ -n "$APK" ] || fail "aucun APK bati : impossible de prouver le contenu livre"
TMPD=$(mktemp -d)
unzip -p "$APK" assets/bundle/jak1_cgo.zip > "$TMPD/cgo.zip" 2>/dev/null || { rm -rf "$TMPD"; fail "pas de bundle cgo dans l'APK"; }
unzip -p "$TMPD/cgo.zip" 0COMMON.TXT > "$TMPD/0.txt" 2>/dev/null || { rm -rf "$TMPD"; fail "0COMMON.TXT absent du bundle"; }
LOW=$(strings -n 6 "$TMPD/0.txt" | grep -acE '[a-z]')
TOT=$(strings -n 6 "$TMPD/0.txt" | wc -l)
rm -rf "$TMPD"
echo "[Gfu] 0COMMON.TXT (anglais) livre dans l'APK : $LOW chaines avec minuscules sur $TOT"
[ "$LOW" -ge 100 ] || fail "le texte ANGLAIS livre est encore en majuscules ($LOW/$TOT) — out/jak1-android-text/ n'a pas ete regenere"
ok "texte anglais livre en casse normale ($LOW/$TOT)"

SMOKE=$(mktemp); timeout 150 build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -q "link finish: logo$" "$SMOKE" || { rm -f "$SMOKE"; fail "x86 smoke regressed"; }; rm -f "$SMOKE"
ok "x86 unbroken"
echo "[Gfu PASS] Gfont-urbanist"

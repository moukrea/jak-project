#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="Grecharged-managed-assets-merge"
F=0
fail(){ F=$((F+1)); echo "[$TAG FAIL] $1"; }
ok(){ echo "[$TAG ok] $1"; }

# 1. Les blocs neufs de la branche doivent exister dans l'arbre.
MISSING=""
for f in common/assets/AssetManager.cpp common/assets/AssetManager.h common/assets/Manifest.cpp \
         common/util/RPack.cpp common/util/Ktx2Subset.cpp common/util/AssetsLock.cpp \
         android/app/src/main/java/org/opengoal/gk/AssetPackDownloader.java assets.lock.json; do
  [ -f "$f" ] || MISSING="$MISSING $f"
done
if [ -n "$MISSING" ]; then
  fail "fichiers de la branche absents :$MISSING"
else
  ok "les 8 blocs de la branche sont dans l'arbre"
fi

# 2. NOS mesures doivent avoir survecu a la fusion (elles instruisent les phases suivantes).
LOST=""
grep -q 'A50-LEVRAM' game/graphics/opengl_renderer/loader/Loader.cpp 2>/dev/null || LOST="$LOST A50-LEVRAM"
grep -q 'A51-FR3' game/graphics/opengl_renderer/loader/Loader.cpp 2>/dev/null || LOST="$LOST A51-FR3"
grep -q 'release_uploaded_tangents' game/graphics/opengl_renderer/loader/Loader.cpp 2>/dev/null || LOST="$LOST liberation-tangentes"
if [ -n "$LOST" ]; then
  fail "la fusion a perdu nos ajouts :$LOST — ils mesurent les deux phases suivantes"
else
  ok "nos mesures (A50-LEVRAM, A51-FR3, liberation des tangentes) ont survecu"
fi

# 3. Aucun de nos commits ne doit avoir disparu.
if git merge-base --is-ancestor 47c8fd3f2a HEAD 2>/dev/null; then
  ok "la pointe de la branche est un ancetre de HEAD (fusion effective)"
else
  fail "47c8fd3f2a (pointe de feat/recharged-managed-assets) n'est pas un ancetre de HEAD — pas fusionnee"
fi

# 4. L'arbre doit compiler pour les deux cibles.
REP=".autoport/reports/$TAG/report.txt"
if [ -f "$REP" ] && grep -qiE 'x86' "$REP" && grep -qiE 'arm64|android' "$REP"; then
  ok "le rapport couvre les deux cibles de build"
else
  fail "le rapport ne demontre pas que l'arbre compile pour x86 ET arm64/Android ($REP)"
fi

# 5. Les tests apportes par la branche doivent passer.
if [ -f "$REP" ] && grep -qiE 'test_asset_manager|test_rpack_ktx2' "$REP"; then
  ok "les tests de la branche sont mentionnes dans le rapport"
else
  fail "aucune trace de test_asset_manager / test_rpack_ktx2 dans $REP"
fi

# 6. REGRESSION D'EXECUTION (ajoutee 2026-08-26 apres coup) — la fusion a passe les cinq
# gates ci-dessus et le jeu PLANTAIT quand meme a l'ecran-titre :
#   GK-DIAG sig=11 fault=0x0 pc=0x0 lr=0x2aecd02ef4
#   F1A-CAMJOINT f=60 proc=0x1ebfb4 logo skel=0x1ed114 fg=0x904d4(#f)
# `pc=0x0` = appel indirect vers un pointeur de fonction NUL ; `fg=#f` = le groupe d'art du
# logo n'est pas charge. Avant la fusion le jeu mourait par manque de RAM SANS signal : le
# mode de defaillance a change, donc c'est bien une regression de la fusion.
# Une gate de mecanique de merge ne suffit pas : exiger une preuve d'EXECUTION.
if [ -f "$REP" ] && grep -qiE 'sig=11|SIGSEGV|SIG_DFL' "$REP"; then
  fail "le rapport contient encore une trace de SIGSEGV — le jeu plante a l'execution"
elif [ -f "$REP" ] && grep -qiE 'ecran.titre|title.screen|logo' "$REP" && grep -qiE 'sans plantage|no crash|aucun signal' "$REP"; then
  ok "le rapport demontre un demarrage jusqu'a l'ecran-titre sans plantage"
else
  fail "aucune preuve d'execution : il faut un demarrage jusqu'a l'ecran-titre SANS SIGSEGV, mesure sur l'appareil"
fi

[ "$F" -gt 0 ] && { echo "[$TAG] $F verdict(s) en echec"; exit 1; }
echo "[$TAG] toutes les gates passent"
exit 0

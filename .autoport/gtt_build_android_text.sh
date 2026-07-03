#!/usr/bin/env bash
# Phase Gtitle-tap (autoport 2026-07-03): build the Android-only localized title
# text banks that override the title prompt (text-id 366 / #x16e) to
# "PRESS START OR TAP SCREEN" (EN) / "APPUYEZ SUR START OU TOUCHEZ L'ÉCRAN" (FR).
#
# The DESKTOP build must keep "PRESS START", so we do NOT mutate the pristine
# desktop banks. Instead we:
#   1. temporarily append two android JSON override lines to game_text.gp,
#   2. rebuild the text banks (later file-json wins -> android string overwrites),
#   3. copy the resulting *COMMON.TXT into out/jak1-android-text/ (the overlay
#      dir that android/build_asset_bundle.sh lays over the staged desktop copies),
#   4. RESTORE game_text.gp to pristine and rebuild so out/jak1/iso/*COMMON.TXT
#      are the untouched desktop banks again.
#
# goal_src is untouched; the game source stays 1-to-1 with upstream. The override
# lives only in the Android asset bundle.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

GP="game/assets/jak1/game_text.gp"
GOALC="build/goalc/goalc"
MAKE_TARGET="out/jak1/iso/0COMMON.TXT"
ANDROID_TEXT_DIR="out/jak1-android-text"
BANKS=(0 1 2 3 4 5 6)

fail(){ echo "[gtt] FATAL: $*" >&2; exit 1; }

[ -x "$GOALC" ] || fail "no $GOALC — build goalc first"
[ -f "$GP" ]    || fail "no $GP"

# The script edits $GP in place then restores it; abort if it's already dirty so
# we never clobber uncommitted work or restore to the wrong state.
git diff --quiet -- "$GP" || fail "$GP has uncommitted changes — commit/stash first (this script edits then restores it)"

make_banks(){
  "$GOALC" --user-auto --game jak1 --disable-ansi \
    -c "(make \"$MAKE_TARGET\" :force #t)" 2>&1 | tail -3
}

echo "[gtt] === 1/4 append android override lines to $GP ==="
# The (text ...) form is the whole file; the last file-json line is on the line
# ending with the ")". Insert our two android lines BEFORE the final closing ")"
# so later-file-wins makes the android string overwrite the base EN/FR string.
# Language 0 = EN(-US), language 1 = FR(-FR): match those two banks only.
python3 - "$GP" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
# find the LAST line that is exactly the closing ")" of the (text ...) form
close_idx = max(i for i, l in enumerate(lines) if l.strip() == ")")
inject = [
    '  (file-json 0 jak1-v2 "common" \'("game/assets/jak1/text/game_custom_text_android_en-US.json"))\n',
    '  (file-json 1 jak1-v2 "common" \'("game/assets/jak1/text/game_custom_text_android_fr-FR.json"))\n',
]
lines[close_idx:close_idx] = inject
open(p, "w", encoding="utf-8").write("".join(lines))
print("[gtt] injected 2 android file-json lines before closing paren (line %d)" % (close_idx + 1))
PY

echo "[gtt] === 2/4 rebuild text banks WITH android override ==="
make_banks

echo "[gtt] verify override present in freshly-built banks"
grep -a "TAP SCREEN"  out/jak1/iso/0COMMON.TXT >/dev/null || fail "EN 'TAP SCREEN' not found in 0COMMON.TXT after android build"
grep -a "TOUCHEZ L"   out/jak1/iso/1COMMON.TXT >/dev/null || fail "FR 'TOUCHEZ L' not found in 1COMMON.TXT after android build"
# ID-SPECIFIC proof the override landed on #x16e itself (JSON keys parse as HEX,
# text_ser.cpp:250 — a decimal key would put the string at the WRONG id while the
# greps above still pass): the stock FR press-start string must be GONE, replaced.
if grep -a "APPUYER SUR LA TOUCHE START" out/jak1/iso/1COMMON.TXT >/dev/null; then
  fail "FR stock press-start string still present — override did NOT land on id #x16e (check JSON hex keys)"
fi
echo "[gtt]   EN 0COMMON.TXT has 'TAP SCREEN'  OK"
echo "[gtt]   FR 1COMMON.TXT has 'TOUCHEZ L'   OK"
echo "[gtt]   FR stock press-start string replaced at id #x16e  OK"

echo "[gtt] === 3/4 copy android banks -> $ANDROID_TEXT_DIR ==="
mkdir -p "$ANDROID_TEXT_DIR"
for b in "${BANKS[@]}"; do
  cp -f "out/jak1/iso/${b}COMMON.TXT" "$ANDROID_TEXT_DIR/${b}COMMON.TXT"
done

echo "[gtt] === 4/4 RESTORE pristine $GP and rebuild desktop banks ==="
git checkout -- "$GP"
touch "$GP"
make_banks

echo "[gtt] verify desktop banks are pristine again"
if grep -a "TAP SCREEN" out/jak1/iso/0COMMON.TXT >/dev/null; then
  fail "RESTORE FAILED: desktop 0COMMON.TXT STILL contains 'TAP SCREEN'"
fi
grep -a "PRESS START" out/jak1/iso/0COMMON.TXT >/dev/null || fail "RESTORE FAILED: desktop 0COMMON.TXT missing 'PRESS START'"
echo "[gtt]   desktop 0COMMON.TXT has 'PRESS START' and NOT 'TAP SCREEN'  OK"

# sanity: $GP is clean again
git diff --quiet -- "$GP" || fail "$GP is still dirty after restore"

echo "[gtt] === produced android-text overlay banks ==="
ls -la "$ANDROID_TEXT_DIR"/*COMMON.TXT
echo "[gtt] DONE — overlay banks in $ANDROID_TEXT_DIR/, desktop banks restored pristine."

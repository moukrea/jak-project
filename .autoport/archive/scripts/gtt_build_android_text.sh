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
# Grecharged-loader-packfix: EN(0) and FR(1) ONLY. An android override json exists for
# exactly those two languages, so a copy of any OTHER bank carries no override at all —
# it merely shadows the freshly built desktop bank in build_cgo_pack.sh and freezes that
# language's text at the day this script last ran (that is how #x1728 MESH BROWSER
# rendered as "UNKNOWN ID 5928" on device). Languages with no override must fall
# through to the fresh banks, so we neither build nor copy them.
BANKS=(0 1)

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
# --- Gtext-tone 2026-08-28 : ce controle etait des LITTERAUX, il est devenu EXACT PAR ID ---
# L'ancienne version faisait `grep -ai "touchez l"` et, comme controle negatif, exigeait
# l'ABSENCE de la chaine "appuyer sur la touche start". Deux defauts, tous deux realises
# aujourd'hui :
#   1. les litteraux PERIMENT. La phase Gtext-tone passe la variante FR au tutoiement
#      ("touche l'ecran"), et `grep "touchez l"` se met a echouer sur une banque JUSTE ;
#   2. le controle negatif devient VIDE des que la chaine de bureau est un PREFIXE de la
#      variante android. C'est exactement le cas maintenant : bureau "Appuie sur start",
#      android "Appuie sur start ou touche l'ecran". Un `grep` d'absence ne peut plus
#      distinguer les deux, donc il aurait passe QUOI QU'IL ARRIVE — un faux vert.
# Le remplacant lit l'id #x16e DANS la banque construite (.autoport/gtt_bank_probe.py) et le
# compare a la source. Il ne peut ni perimer ni devenir vide, et il garde la propriete que
# l'ancien controle negatif visait : une cle JSON DECIMALE (text_ser.cpp:250 parse en HEX)
# poserait la chaine a un AUTRE id, et l'egalite echouerait.
bank_id(){ python3 .autoport/gtt_bank_probe.py "$1" --ids 16e | sed -n 's/^  #x16e *w= *[0-9.]* *//p'; }
json_id(){ python3 -c "import json,sys;print(json.load(open(sys.argv[1],encoding='utf-8'))['16e'])" "$1"; }
for b in "${BANKS[@]}"; do
  case "$b" in 0) L=en-US ;; 1) L=fr-FR ;; *) fail "bank $b has no android override json" ;; esac
  WANT=$(json_id "game/assets/jak1/text/game_custom_text_android_${L}.json")
  GOT=$(bank_id "out/jak1/iso/${b}COMMON.TXT")
  [ "$GOT" = "$WANT" ] || fail "android bank ${b}COMMON.TXT #x16e = '$GOT', attendu '$WANT' (l'override n'a PAS atterri sur #x16e — cles JSON en hex ?)"
  echo "[gtt]   ${b}COMMON.TXT (${L}) #x16e = '$GOT'  == la surcharge android  OK"
done

echo "[gtt] === 3/4 copy android banks -> $ANDROID_TEXT_DIR ==="
mkdir -p "$ANDROID_TEXT_DIR"
# Clear first: an earlier, wider run of this script left banks 2..24 here, and
# build_cgo_pack.sh prefers ANY file found in this dir over the freshly built desktop
# bank — so those leftovers silently froze every other language's text. Only the banks
# we are about to write (the ones that actually have an override) may live here.
rm -f "$ANDROID_TEXT_DIR"/*COMMON.TXT
for b in "${BANKS[@]}"; do
  cp -f "out/jak1/iso/${b}COMMON.TXT" "$ANDROID_TEXT_DIR/${b}COMMON.TXT"
done

echo "[gtt] === 4/4 RESTORE pristine $GP and rebuild desktop banks ==="
git checkout -- "$GP"
touch "$GP"
make_banks

echo "[gtt] verify desktop banks are pristine again"
# Meme instrument, sens inverse : apres restauration, #x16e des banques de BUREAU doit avoir
# repris la valeur de la chaine JSON normale (case -> custom), et surtout NE PLUS etre la
# variante android. Compare des CHAINES ENTIERES par id : un prefixe ne peut pas passer.
for b in "${BANKS[@]}"; do
  case "$b" in 0) L=en-US ;; 1) L=fr-FR ;; esac
  ANDROID=$(json_id "game/assets/jak1/text/game_custom_text_android_${L}.json")
  DESKTOP=$(bank_id "out/jak1/iso/${b}COMMON.TXT")
  [ "$DESKTOP" != "$ANDROID" ] || fail "RESTORE FAILED: la banque de bureau ${b}COMMON.TXT porte ENCORE la variante android '$ANDROID'"
  [ -n "$DESKTOP" ] || fail "RESTORE FAILED: #x16e illisible dans la banque de bureau ${b}COMMON.TXT"
  echo "[gtt]   bureau ${b}COMMON.TXT (${L}) #x16e = '$DESKTOP'  != variante android  OK"
done

# sanity: $GP is clean again
git diff --quiet -- "$GP" || fail "$GP is still dirty after restore"

# --- PROVENANCE (autoport Gfont-urbanist 2026-08-28) ------------------------------
# Record the md5 of the PRISTINE desktop bank each override was derived from, at the
# moment it was derived. android/build_cgo_pack.sh prefers any bank found here over
# the freshly built desktop bank, so an overlay that stops being regenerated FREEZES
# that language's text — measured: out/jak1-android-text/{0,1}COMMON.TXT sat at
# 2026-08-11 02:05 for 17 days while the desktop banks were rebuilt daily, which is
# why the owner read mixed case on his laptop and ALL CAPS on the Redmi. The packer
# compares these md5 against the current desktop banks and refuses to ship a frozen
# overlay. Signed by CONTENT, never by mtime.
PROV="$ANDROID_TEXT_DIR/PROVENANCE"
: > "$PROV"
for b in "${BANKS[@]}"; do
  printf '%s %s\n' "${b}COMMON.TXT" "$(md5sum "out/jak1/iso/${b}COMMON.TXT" | cut -d' ' -f1)" >> "$PROV"
done
echo "[gtt] provenance written ($PROV):"; sed 's/^/[gtt]   /' "$PROV"

echo "[gtt] === produced android-text overlay banks ==="
ls -la "$ANDROID_TEXT_DIR"/*COMMON.TXT
echo "[gtt] DONE — overlay banks in $ANDROID_TEXT_DIR/, desktop banks restored pristine."

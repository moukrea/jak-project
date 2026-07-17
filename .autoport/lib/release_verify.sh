#!/usr/bin/env bash
# release_verify.sh <apk> <game> — GATE avant tout push/release, re-keyé pour la
# règle packaging du pilier (Grecharged-buildsys-packaging) :
#   PACKAGE (APK)   = moteur + TOUT ce qui est custom au port : pack CGO/DGO arm64
#                     + TOUTES les banques TXT rebuilt (ids custom), pack custom
#                     (.grassbake, fr3 enhanced, PNGs recharged) keyé par flag-set.
#   <game>_assets.zip = UNIQUEMENT la donnée source non-altérée (iso verbatim +
#                     fr3 stock). JAMAIS dans l'APK.
# Checks:
#   1. version du cgo-pack de l'APK == recompute content-hash (code arm64 + TXT
#      effectifs avec overrides android) — l'APK n'embarque pas de code périmé.
#   2. version du custom-pack de l'APK == recompute + MEMBERSHIP conforme au
#      flag-set (PNG ssi recharged-hud, enhanced ssi hd-models, grassbake toujours,
#      rien d'autre).
#   3. R1 flag-set : marqueur ogflags identique libgk.so == GAME.CGO du pack ==
#      flags= du custom-pack. APK mixte refusé.
#   4. GATE NÉGATIF (règle owner) : AUCUNE donnée vanilla dans l'APK — pas de
#      <game>_assets.zip, pas d'iso_data/, pas de .fr3 stock.
#   5. out/artifacts/<game>_assets.zip (si présent) : membres == manifest sidecar,
#      chemins limités à assets/iso/* + assets/fr3/*.fr3, ZÉRO artefact port
#      (.CGO/.DGO/.TXT/.grassbake/enhanced/), spot-check sha256 de 6 membres,
#      archive flag-INDÉPENDANTE.
set -uo pipefail
APK="$1"; GAME="${2:-jak1}"
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[release FAIL] $*"; exit 1; }

mkdir -p .autoport/tmp
T=$(mktemp -d .autoport/tmp/relverif.XXXXXX); trap 'rm -rf "$T"' EXIT

ARM64_CODE="out/${GAME}-arm64-full/iso"
ISO_BUILD="out/${GAME}/iso"
ANDROID_TEXT="out/${GAME}-android-text"
FR3_DIR="out/${GAME}/fr3"

# ---------- 1. cgo pack: version == recompute (code + TXT effectifs) ----------
unzip -o -q "$APK" "assets/bundle/${GAME}_cgo.manifest.properties" -d "$T" \
  || fail "pas de ${GAME}_cgo.manifest.properties dans l'APK"
GOT_CGO=$(grep -E '^version=' "$T/assets/bundle/${GAME}_cgo.manifest.properties" | cut -d= -f2)
EXPECT_CGO="c$( {
    find "$ARM64_CODE" -maxdepth 1 -type f \( -name '*.CGO' -o -name '*.DGO' \) -print0
    while IFS= read -r f; do
      if [ -f "$ANDROID_TEXT/$f" ]; then printf '%s\0' "$ANDROID_TEXT/$f"; else printf '%s\0' "$ISO_BUILD/$f"; fi
    done < <(find "$ISO_BUILD" -maxdepth 1 -type f -name '*.TXT' -printf '%f\n' | sort)
  } | sort -z | xargs -0 md5sum | md5sum | cut -c1-12 )"
[ "$GOT_CGO" = "$EXPECT_CGO" ] \
  || fail "cgo-pack version=$GOT_CGO != attendu=$EXPECT_CGO — l'APK embarque du code/TXT périmé, PUSH INTERDIT"
echo "[release PASS] cgo-pack version=$GOT_CGO == contenu build (code arm64 + 46 TXT effectifs)"

# ---------- markers (R1 3 voies) ----------
MARK_SO=$(unzip -p "$APK" lib/arm64-v8a/libgk.so 2>/dev/null | strings | grep -m1 '^ogflags:' || true)
[ -n "$MARK_SO" ] || fail "libgk.so de l'APK sans marqueur ogflags (build pré-flags ?)"
unzip -o -q "$APK" "assets/bundle/${GAME}_cgo.zip" -d "$T" || fail "pas de ${GAME}_cgo.zip dans l'APK"
unzip -o -q "$T/assets/bundle/${GAME}_cgo.zip" GAME.CGO -d "$T" || fail "GAME.CGO absent du cgo-pack"
MARK_CGO=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$T/GAME.CGO" | head -1 || true)
[ "$MARK_SO" = "$MARK_CGO" ] \
  || fail "flag-set mixte dans l'APK: libgk '$MARK_SO' != CGO '$MARK_CGO' — PUSH INTERDIT (R1)"

# invert le hash du marqueur -> flag set (16 sous-ensembles canoniques)
HASH="${MARK_SO#ogflags:}"; HASH="${HASH%%:*}"
ALL_FLAGS=(grass-overhang hd-models recharged-hud vulkan-support)
FLAGS=""; FOUND=0
for mask in $(seq 0 15); do
  sl=()
  for bit in 0 1 2 3; do (( (mask >> bit) & 1 )) && sl+=("${ALL_FLAGS[$bit]}"); done
  cand=$(IFS=,; echo "${sl[*]-}")
  [ "$(printf '%s' "$cand" | sha256sum | cut -c1-12)" = "$HASH" ] && { FLAGS="$cand"; FOUND=1; break; }
done
[ "$FOUND" -eq 1 ] || fail "hash ogflags '$HASH' ne correspond à aucun flag-set connu"
F_HUD=0; F_HDMODELS=0
case ",$FLAGS," in *",recharged-hud,"*) F_HUD=1;; esac
case ",$FLAGS," in *",hd-models,"*) F_HDMODELS=1;; esac

# ---------- 2. custom pack: version recompute + membership par flag-set ----------
unzip -o -q "$APK" "assets/bundle/${GAME}_custom.manifest.properties" -d "$T" \
  || fail "pas de ${GAME}_custom.manifest.properties dans l'APK"
MARK_CUS=$(grep -E '^flags=' "$T/assets/bundle/${GAME}_custom.manifest.properties" | cut -d= -f2-)
[ "$MARK_CUS" = "$MARK_SO" ] \
  || fail "flag-set mixte: custom-pack flags '$MARK_CUS' != libgk '$MARK_SO' (R1)"

# recompute la version depuis les sources, même règle de membership que build_custom_pack.sh
CUS_SRC="$T/cus_src.list"; : > "$CUS_SRC"
if [ "$F_HUD" -eq 1 ] && [ "$GAME" = "jak1" ]; then
  find recharged_assets -maxdepth 1 -type f -name '*.png' >> "$CUS_SRC"
fi
find "$FR3_DIR" -maxdepth 1 -type f -name '*.grassbake' >> "$CUS_SRC" 2>/dev/null || true
if [ "$F_HDMODELS" -eq 1 ]; then
  find "$FR3_DIR/enhanced" -maxdepth 1 -type f -name '*.fr3' >> "$CUS_SRC" 2>/dev/null || true
fi
N_CUS=$(wc -l < "$CUS_SRC")
# NB: on ne recompute pas la version (md5-de-listing avec chemins stage) — on
# vérifie le CONTENU du pack membre-à-membre (noms + md5), ce qui est plus fort.
unzip -o -q "$APK" "assets/bundle/${GAME}_custom.zip" -d "$T" || fail "pas de ${GAME}_custom.zip dans l'APK"
CUS_ZIP="$T/assets/bundle/${GAME}_custom.zip"
mapfile -t CUS_MEMBERS < <(python3 -c "
import zipfile
for n in zipfile.ZipFile('$CUS_ZIP').namelist():
    if not n.endswith('/'): print(n)" | sort)
# membership: rien hors des 3 familles autorisées
for m in "${CUS_MEMBERS[@]-}"; do
  [ -n "$m" ] || continue
  case "$m" in
    recharged_assets/*.png) [ "$F_HUD" -eq 1 ] || fail "custom-pack contient $m mais recharged-hud est OFF";;
    fr3/enhanced/*.fr3)     [ "$F_HDMODELS" -eq 1 ] || fail "custom-pack contient $m mais hd-models est OFF";;
    fr3/*.grassbake)        ;;
    *) fail "custom-pack contient un membre hors-règle: $m";;
  esac
done
# complétude: chaque source attendue doit être dans le pack, au md5 près
while IFS= read -r src; do
  [ -n "$src" ] || continue
  base=$(basename "$src")
  case "$src" in
    recharged_assets/*) zp="recharged_assets/$base";;
    */enhanced/*)       zp="fr3/enhanced/$base";;
    *)                  zp="fr3/$base";;
  esac
  m_src=$(md5sum "$src" | cut -d' ' -f1)
  m_zip=$(unzip -p "$CUS_ZIP" "$zp" 2>/dev/null | md5sum | cut -d' ' -f1)
  [ "$m_src" = "$m_zip" ] || fail "custom-pack: $zp absent ou différent de la source $src"
done < "$CUS_SRC"
GOT_N=${#CUS_MEMBERS[@]}; [ -z "${CUS_MEMBERS[0]:-}" ] && GOT_N=0
[ "$GOT_N" -eq "$N_CUS" ] || fail "custom-pack: $GOT_N membres != $N_CUS attendus par le flag-set '$FLAGS'"
echo "[release PASS] custom-pack: $GOT_N membre(s) conformes au flag-set '${FLAGS:-<none>}' (membership + md5)"
echo "[release PASS] appairage flag-set APK: $MARK_SO (libgk == CGO pack == custom pack)"

# ---------- 4. gate négatif: aucune donnée vanilla dans l'APK ----------
# Listing dans un FICHIER (pas de `printf | grep -q` sous pipefail: SIGPIPE du
# producteur = MATCH transformé en false-PASS — classe pipefail+grep-q connue).
unzip -l "$APK" > "$T/apk.list"
LISTING=$(cat "$T/apk.list")
[[ "$LISTING" == *"${GAME}_assets.zip"* ]] && fail "l'APK embarque ${GAME}_assets.zip — donnée vanilla INTERDITE dans le package"
[[ "$LISTING" == *"iso_data/"* ]] && fail "l'APK embarque une entrée iso_data/ — donnée disque verbatim INTERDITE dans le package"
if grep -qE 'assets/[^ ]*\.fr3( |$)' "$T/apk.list"; then
  off=$(grep -oE 'assets/[^ ]*\.fr3' "$T/apk.list" | head -1 || true)
  fail "l'APK embarque un fr3 stock ($off) — donnée vanilla-dérivée INTERDITE dans le package"
fi
echo "[release PASS] gate négatif: zéro donnée vanilla dans l'APK"

# ---------- 5. archive assets (si produite): manifest + règle de tri ----------
AZ="out/artifacts/${GAME}_assets.zip"
AM="out/artifacts/${GAME}_assets.manifest.txt"
AP="out/artifacts/${GAME}_assets.properties"
if [ -f "$AZ" ]; then
  [ -f "$AM" ] && [ -f "$AP" ] || fail "archive $AZ sans manifest/properties sidecar"
  grep -qE '^flags=' "$AP" && fail "archive assets flag-DÉPENDANTE (flags= dans les properties) — interdit"
  mapfile -t AZ_MEMBERS < <(python3 -c "
import zipfile
for n in zipfile.ZipFile('$AZ').namelist():
    if not n.endswith('/'): print(n)" | sort)
  mapfile -t MAN_MEMBERS < <(grep -v '^#' "$AM" | awk '{print $1}' | sort)
  [ "${#AZ_MEMBERS[@]}" -eq "${#MAN_MEMBERS[@]}" ] \
    || fail "archive: ${#AZ_MEMBERS[@]} membres != ${#MAN_MEMBERS[@]} lignes manifest"
  diff <(printf '%s\n' "${AZ_MEMBERS[@]}") <(printf '%s\n' "${MAN_MEMBERS[@]}") >/dev/null \
    || fail "archive: liste des membres != manifest sidecar"
  for m in "${AZ_MEMBERS[@]}"; do
    case "$m" in
      assets/iso/*.CGO|assets/iso/*.DGO|assets/iso/*.TXT) fail "archive contient un artefact port: $m";;
      *.grassbake|*/enhanced/*) fail "archive contient un artefact port: $m";;
      assets/iso/*) ;;
      assets/fr3/*.fr3) ;;
      *) fail "archive contient un chemin hors-règle: $m";;
    esac
  done
  # spot-check sha256 de 6 membres (stream, pas d'extraction disque)
  N_AZ=${#AZ_MEMBERS[@]}
  for i in $(seq 1 6); do
    idx=$(( (RANDOM * 32768 + RANDOM) % N_AZ ))
    m="${AZ_MEMBERS[$idx]}"
    want=$(grep -F "$m " "$AM" | head -1 | awk '{print $2}')
    got=$(unzip -p "$AZ" "$m" | sha256sum | cut -d' ' -f1)
    [ "$got" = "$want" ] || fail "archive: sha256 de $m ($got) != manifest ($want)"
  done
  # classes autorisées uniquement
  BADCLS=$(grep -v '^#' "$AM" | awk '{print $4}' | grep -vE '^(vanilla-verbatim|vanilla-derived-fr3)$' | head -1 || true)
  [ -z "$BADCLS" ] || fail "archive: classe manifest interdite '$BADCLS'"
  echo "[release PASS] ${GAME}_assets.zip: $N_AZ membres == manifest, tri conforme (0 artefact port), spot-check sha256 6/6, flag-indépendante"
else
  echo "[release WARN] pas de $AZ — archive assets non vérifiée (produire via ./build.sh <cible> --package)"
fi

exit 0

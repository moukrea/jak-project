#!/usr/bin/env bash
# Grecharged-buildsys-packaging (autoport 2026-07-17): build the SOURCE-DERIVED
# asset archive <game>_assets.zip.
#
# Owner rule: the game PACKAGE (APK / desktop tarball) carries the engine + ALL
# port-custom artifacts (compiled CGO/DGO, rebuilt TXT banks, .grassbake, enhanced
# HD fr3, recharged PNGs). This SEPARATE archive carries ONLY unaltered
# source-derived data: verbatim disc files (byte-identical to iso_data/<game>/)
# and stock .fr3 packs (the fr3 builder proven unmodified vs upstream). The zip
# therefore contains NOTHING that isn't unaltered source-derived data — in
# particular NO manifest is stored inside it; the manifest/properties are written
# as SIDECAR files under out/artifacts/.
#
# Target-INDEPENDENT (pure data; no arch code, no flags).
#
# Sources (authoritative PC build outputs):
#   out/<game>/iso   flat runtime set; members = every file EXCEPT *.CGO/*.DGO/*.TXT
#                    (those are port artifacts and ride the game PACKAGE instead).
#                    Each member MUST be byte-identical to a file under
#                    iso_data/<game>/ (verbatim disc data) or the archive DIES.
#   out/<game>/fr3   stock *.fr3 texture packs (class vanilla-derived-fr3).
#                    EXCLUDES *.grassbake and fr3/enhanced/ (port artifacts).
#
# Output:
#   out/artifacts/<game>_assets.zip          data members only, NO manifest inside
#   out/artifacts/<game>_assets.manifest.txt one line per member
#   out/artifacts/<game>_assets.properties   version/game/counts/bytes
set -euo pipefail

GAME="${1:-}"
[ -n "$GAME" ] || { echo "[assets-archive] usage: $0 <game>" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"

fail(){ echo "[assets-archive] FATAL: $*" >&2; exit 1; }

ISO_DIR="out/${GAME}/iso"
FR3_DIR="out/${GAME}/fr3"
ISO_DATA="iso_data/${GAME}"
[ -d "$ISO_DIR" ] || fail "no $ISO_DIR — run the PC extract/build first"
[ -d "$FR3_DIR" ] || fail "no $FR3_DIR — run the PC fr3 build first"
[ -d "$ISO_DATA" ] || fail "no $ISO_DATA — the verbatim disc data root is required for vanilla classification"

OUT_DIR="out/artifacts"
mkdir -p "$OUT_DIR"
ZIP_REL="${OUT_DIR}/${GAME}_assets.zip"
MANIFEST="${OUT_DIR}/${GAME}_assets.manifest.txt"
PROPS="${OUT_DIR}/${GAME}_assets.properties"
ZIP_ABS="${ROOT}/${ZIP_REL}"
STAGE="out/${GAME}-assets-stage"

# --- vanilla-derived-fr3 attestation: the fr3 builder must be unchanged since the
# proven-stock baseline. Recompute the diff live; DIE if it ever becomes non-empty.
FR3_BASELINE="107f26a44"
DIFF_FILES="$(git diff --name-only "${FR3_BASELINE}..HEAD" -- decompiler/level_extractor decompiler/config || true)"
if [ -n "$DIFF_FILES" ]; then
  echo "[assets-archive] fr3 attestation FAILED: the fr3 builder changed since ${FR3_BASELINE}:" >&2
  echo "$DIFF_FILES" | sed 's/^/  /' >&2
  fail "stock .fr3 can no longer be attested vanilla-derived — a builder change may alter fr3 bytes"
fi

# --- sha256 index of the verbatim disc data (iso_data/<game>, recursive). Cached;
# rebuilt only when a file under iso_data/<game> is newer than the cached index. ---
IDX="out/${GAME}/.iso_data_sha_index"
need_idx=1
if [ -f "$IDX" ]; then
  idx_mt=$(stat -c %Y "$IDX")
  # awk max-mtime in one pass (no sort|head SIGPIPE).
  newest=$(find "$ISO_DATA" -type f -printf '%T@\n' 2>/dev/null | awk 'BEGIN{m=0}{t=int($1); if(t>m)m=t} END{print m}')
  if [ -n "$newest" ] && [ "$idx_mt" -ge "$newest" ]; then
    need_idx=0
  fi
fi
if [ "$need_idx" -eq 1 ]; then
  echo "[assets-archive] building sha256 index of $ISO_DATA (recursive)…"
  find "$ISO_DATA" -type f -print0 | sort -z | xargs -0 sha256sum > "$IDX"
fi
# Load the index into an associative array: sha -> a source path (first wins).
declare -A VANILLA
declare -A VANILLA_PATH
while IFS=' ' read -r sha path; do
  [ -n "$sha" ] || continue
  VANILLA["$sha"]=1
  [ -n "${VANILLA_PATH[$sha]:-}" ] || VANILLA_PATH["$sha"]="$path"
done < <(sed 's/  / /' "$IDX")
echo "[assets-archive] index: $(wc -l < "$IDX") verbatim disc files"

# --- member selection ---
# iso members: every out/<game>/iso file EXCEPT *.CGO/*.DGO/*.TXT
mapfile -t ISO_MEMBERS < <(find "$ISO_DIR" -maxdepth 1 -type f ! -name '*.CGO' ! -name '*.DGO' ! -name '*.TXT' -printf '%f\n' | sort)
N_ISO=${#ISO_MEMBERS[@]}
# fr3 members: every TOP-LEVEL *.fr3 (excludes *.grassbake and fr3/enhanced/)
mapfile -t FR3_MEMBERS < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.fr3' -printf '%f\n' | sort)
N_FR3=${#FR3_MEMBERS[@]}

[ "$N_ISO" -ge 1 ] || fail "no iso data members found in $ISO_DIR"
[ "$N_FR3" -ge 1 ] || fail "no fr3 members found in $FR3_DIR"
if [ "$GAME" = "jak1" ]; then
  [ "$N_ISO" -eq 247 ] || fail "jak1 expects exactly 247 iso data members, found $N_ISO"
  [ "$N_FR3" -eq 26 ]  || fail "jak1 expects exactly 26 fr3 members, found $N_FR3"
fi
WANT_FC=$((N_ISO + N_FR3))

# --- classify + build manifest lines; DIE on any unclassifiable iso member ---
echo "[assets-archive] classifying $N_ISO iso members against the verbatim index…"
# manifest rows collected in an array; also stage a symlink farm.
rm -rf "$STAGE"
mkdir -p "$STAGE/assets/iso" "$STAGE/assets/fr3"
MAN_LINES=()
# accumulate member shas (in zip-path order) for the content-derived version.
VERSION_INPUT=""

for f in "${ISO_MEMBERS[@]}"; do
  src="$ISO_DIR/$f"
  sha=$(sha256sum "$src" | cut -d' ' -f1)
  bytes=$(stat -c %s "$src")
  if [ -z "${VANILLA[$sha]:-}" ]; then
    fail "unclassifiable — neither vanilla-verbatim nor known port artifact: $src (sha256=$sha)"
  fi
  srcpath="${VANILLA_PATH[$sha]}"
  MAN_LINES+=("assets/iso/$f  $sha  $bytes  vanilla-verbatim  $srcpath")
  VERSION_INPUT+="$sha"$'\n'
  ln -s "$ROOT/$src" "$STAGE/assets/iso/$f"
done

for f in "${FR3_MEMBERS[@]}"; do
  src="$FR3_DIR/$f"
  sha=$(sha256sum "$src" | cut -d' ' -f1)
  bytes=$(stat -c %s "$src")
  MAN_LINES+=("assets/fr3/$f  $sha  $bytes  vanilla-derived-fr3  $src")
  VERSION_INPUT+="$sha"$'\n'
  ln -s "$ROOT/$src" "$STAGE/assets/fr3/$f"
done

# content-derived version (md5 of member sha list — same c<hash> scheme style as
# build_cgo_pack.sh:37-41). Order is deterministic (iso sorted, then fr3 sorted).
VERSION="c$(printf '%s' "$VERSION_INPUT" | md5sum | cut -c1-12)"
RAW_BYTES=$(find -L "$STAGE" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')

# --- idempotent skip: zip+properties present, version+file_count match, zip newer
#     than newest source. ---
if [ -f "$ZIP_REL" ] && [ -f "$PROPS" ]; then
  cv=$(grep -E '^version=' "$PROPS" | cut -d= -f2 || echo "")
  cfc=$(grep -E '^file_count=' "$PROPS" | cut -d= -f2 || echo "")
  newest_src=$(find "$ISO_DIR" "$FR3_DIR" -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null | awk 'BEGIN{m=0}{t=int($1); if(t>m)m=t} END{print m}')
  zmt=$(stat -c %Y "$ZIP_REL")
  if [ "$cv" = "$VERSION" ] && [ "$cfc" = "$WANT_FC" ] && [ -n "$newest_src" ] && [ "$zmt" -ge "$newest_src" ]; then
    echo "[assets-archive] up to date: $ZIP_REL (version=$VERSION file_count=$cfc)"
    rm -rf "$STAGE"
    exit 0
  fi
fi

# --- write manifest sidecar (NOT inside the zip) ---
{
  echo "# Generated by scripts/packaging/build_assets_archive.sh — do not edit."
  echo "# <game>_assets.zip = UNALTERED source-derived data only."
  echo "# columns: <zip-path>  <sha256>  <bytes>  <class>  <source-path>"
  echo "# class vanilla-verbatim  = byte-identical to a file under $ISO_DATA."
  echo "# class vanilla-derived-fr3 = stock .fr3; attested (git diff ${FR3_BASELINE}..HEAD of"
  echo "#   decompiler/level_extractor + decompiler/config is empty => builder unchanged)."
  for l in "${MAN_LINES[@]}"; do echo "$l"; done
} > "$MANIFEST"

# --- pack (symlink farm, zip dereferences) ---
echo "[assets-archive] packing $WANT_FC members → $ZIP_REL (DEFLATE)…"
rm -f "$ZIP_ABS"
(
  cd "$STAGE"
  # -r recurse assets/, -6 balanced DEFLATE, -X drop metadata, -q quiet.
  zip -r -6 -X -q "$ZIP_ABS" "assets"
)
ZIP_BYTES=$(stat -c %s "$ZIP_ABS")

cat > "$PROPS" <<EOF
# Generated by scripts/packaging/build_assets_archive.sh — do not edit.
version=${VERSION}
game=${GAME}
file_count=${WANT_FC}
raw_bytes=${RAW_BYTES}
zip_bytes=${ZIP_BYTES}
EOF

rm -rf "$STAGE"

echo "[assets-archive] done: $ZIP_REL"
echo "[assets-archive]   members=$WANT_FC (iso=$N_ISO fr3=$N_FR3)  raw=${RAW_BYTES}B  zip=${ZIP_BYTES}B  version=$VERSION"

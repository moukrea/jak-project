#!/usr/bin/env bash
# Phase Gpkg-distributable (autoport 2026-06-27): build the COMPRESSED
# runtime-asset bundle shipped inside the self-contained jak1 APK.
#
# HARDENED after a false-green: a prior version packed the on-disk STAGING dirs
# (android/app/src/jak1/assets/{iso_data,fr3}), which had drifted to a SLIM/stale
# set — 4 of 26 fr3 + the June-11 CGO/DGO. It booted but DROPPED assets, so the
# main-menu orange tint backdrop rendered broken on device. This version instead
# assembles the bundle straight from the AUTHORITATIVE PC build outputs, so it is
# COMPLETE and internally CONSISTENT by construction, and FAILS LOUD if anything
# is missing or stale.
#
# Authoritative sources (NOT the staging dirs — those drift):
#   out/<game>/iso/            full extracted runtime set (321 files):
#                                293 arch-independent data (STR/VAG/TXT/VIS/...)
#                                + 28 *.CGO/*.DGO (x86 oracle copies — replaced)
#   out/<game>-arm64-full/iso/ the 28 ARM64-compiled CGO/DGO, internally
#                                consistent (built in one pass by
#                                .autoport/build_arm64_full_consistent.sh) so the
#                                device runs them with the matching HEAD libgk.so
#                                without the mixed-build sparticle SIGILL.
#   out/<game>/fr3/            the FULL 26 renderer texture packs (all levels).
#
# Bundle layout (== the full PC build, arm64 code overlaid on the x86 data):
#   iso_data/<game>/*  = 293 data files + 28 ARM64 *.CGO/*.DGO   (= 321)
#   fr3/*              = 26 *.fr3                                  (= 26)
# Total = 347 files. LoaderActivity maps these on device:
#   iso_data/<game>/* -> <filesDir>/iso_data/<game>/*   (fakeiso data root)
#   fr3/*             -> <filesDir>/out/<game>/fr3/*     (renderer textures)
#
# Assembly is a SYMLINK FARM under out/<game>-bundle-stage/: `zip` dereferences
# symlinks (verified) and stores the real content under the link path, so we pack
# the full ~1.6 GiB set into one DEFLATE zip with NO multi-GiB intermediate copy
# (PC disk is tight). The farm always points at the current build outputs, so the
# bundle can never drift to a stale staging copy again.
#
# Idempotent: rebuilds only when the zip is missing/older than any source OR the
# version/file_count changed. goal_src is untouched — packaging only.
set -euo pipefail

GAME="${1:-jak1}"
# BUNDLE_VERSION stamps the on-device unpack; a bump forces a clean re-decompress
# on the next launch (a new APK shipped a new payload). Bumped 1 -> 2 to replace
# the slim/stale v1 unpack on devices that ran the false-green build. Bumped 2 -> 3
# (autoport 2026-06-29) so the collision-fix arm64 CGO/DGO payload re-unpacks over a
# device that still holds the pre-fix v2 data. Bumped 3 -> 4 (autoport 2026-07-02,
# final owner-validation APK) so the camera-interp + touch-menus + warp-dpad arm64
# CGO/DGO payload re-unpacks over a device that still holds older v3 data.
# Bumped 4 -> 5 (autoport 2026-07-03, v2 owner-validation APK) so the
# blue-eco-crash-fix + full-touch-menus arm64 CGO/DGO payload re-unpacks over a
# device that still holds the v1/bundle-v4 data. Bumped 5 -> 6 (autoport
# 2026-07-03, v3 owner-validation APK: draw-batching + orb-in-split + eco-sphere
# fixes) so devices holding v5 data re-unpack a guaranteed-consistent payload.
# Bumped 6 -> 7 (autoport 2026-07-03, Glang-mixed): new TXT/SUBTIT banks (menu-label
# text-ids #x1700-#x1705 EN+FR, French subtitle completeness) + CGO/DGOs with the
# localized name-override label plumbing must re-unpack over v6 devices.
VERSION="${BUNDLE_VERSION:-7}"

cd "$(git rev-parse --show-toplevel)"

ISO_BUILD="out/${GAME}/iso"
ARM64_CODE="out/${GAME}-arm64-full/iso"
FR3_BUILD="out/${GAME}/fr3"
OUT_DIR="android/app/src/${GAME}/assets-bundled/bundle"
STAGE="out/${GAME}-bundle-stage"
ZIP_REL="${OUT_DIR}/${GAME}_assets.zip"
MANIFEST="${OUT_DIR}/manifest.properties"
ZIP_ABS="$(pwd)/${ZIP_REL}"
ROOT="$(pwd)"

fail(){ echo "[asset-bundle] FATAL: $*" >&2; exit 1; }

[ -d "$ISO_BUILD" ]  || fail "no $ISO_BUILD — run the PC extract/build first"
[ -d "$FR3_BUILD" ]  || fail "no $FR3_BUILD — run the PC fr3 build first"
[ -d "$ARM64_CODE" ] || fail "no $ARM64_CODE — run .autoport/build_arm64_full_consistent.sh first (need the consistent arm64 CGO/DGO set)"

# The code files = every *.CGO/*.DGO present in the iso build; each MUST also
# exist in the arm64 set (so we can overlay an arm64 copy of every code file).
mapfile -t CODE_FILES < <(find "$ISO_BUILD" -maxdepth 1 -type f \( -name '*.CGO' -o -name '*.DGO' \) -printf '%f\n' | sort)
N_CODE=${#CODE_FILES[@]}
[ "$N_CODE" -gt 0 ] || fail "no CGO/DGO in $ISO_BUILD"
for f in "${CODE_FILES[@]}"; do
  [ -f "$ARM64_CODE/$f" ] || fail "arm64 set missing $f — rerun .autoport/build_arm64_full_consistent.sh"
done

N_ISO=$(find "$ISO_BUILD" -maxdepth 1 -type f | wc -l | tr -d ' ')
N_FR3=$(find "$FR3_BUILD" -maxdepth 1 -type f -name '*.fr3' | wc -l | tr -d ' ')
WANT_FC=$((N_ISO + N_FR3))

mkdir -p "$OUT_DIR"

# --- Staleness skip: zip current vs all sources AND version+count match. ---
if [ -f "$ZIP_REL" ] && [ -f "$MANIFEST" ]; then
  # awk computes the max mtime in one pass — no `sort | head` (whose early
  # pipe close SIGPIPEs `sort` and trips `set -o pipefail` under Gradle).
  newest=$(find "$ISO_BUILD" "$ARM64_CODE" "$FR3_BUILD" -type f -printf '%T@\n' 2>/dev/null | awk 'BEGIN{m=0}{t=int($1); if(t>m)m=t} END{print m}')
  zmt=$(stat -c %Y "$ZIP_REL")
  cv=$(grep -E '^version=' "$MANIFEST" | cut -d= -f2 || echo "")
  cfc=$(grep -E '^file_count=' "$MANIFEST" | cut -d= -f2 || echo "")
  if [ -n "$newest" ] && [ "$zmt" -ge "$newest" ] && [ "$cv" = "$VERSION" ] && [ "$cfc" = "$WANT_FC" ]; then
    echo "[asset-bundle] up to date: $ZIP_REL (version=$VERSION file_count=$cfc)"
    exit 0
  fi
fi

echo "[asset-bundle] assembling FULL consistent arm64 set for $GAME (symlink farm)…"
rm -rf "$STAGE"
mkdir -p "$STAGE/iso_data/$GAME" "$STAGE/fr3"

# 1. data files: everything in the iso build EXCEPT the 28 code files (these are
#    arch-independent — same in x86 and arm64 builds).
while IFS= read -r f; do
  base="$(basename "$f")"
  case "$base" in *.CGO|*.DGO) continue;; esac
  ln -s "$ROOT/$f" "$STAGE/iso_data/$GAME/$base"
done < <(find "$ISO_BUILD" -maxdepth 1 -type f)

# 2. code files: overlay the ARM64-compiled CGO/DGO (NOT the x86 oracle copies).
for f in "${CODE_FILES[@]}"; do
  ln -s "$ROOT/$ARM64_CODE/$f" "$STAGE/iso_data/$GAME/$f"
done

# 3. fr3: the FULL set (all levels), arch-independent texture packs.
while IFS= read -r f; do
  ln -s "$ROOT/$f" "$STAGE/fr3/$(basename "$f")"
done < <(find "$FR3_BUILD" -maxdepth 1 -type f -name '*.fr3')

# --- HARD completeness + consistency gates (the false-green guard) ---
got_iso=$(find -L "$STAGE/iso_data/$GAME" -type f | wc -l | tr -d ' ')
got_fr3=$(find -L "$STAGE/fr3" -type f | wc -l | tr -d ' ')
[ "$got_iso" -eq "$N_ISO" ] || fail "iso incomplete: staged $got_iso != full $N_ISO"
[ "$got_fr3" -eq "$N_FR3" ] || fail "fr3 incomplete: staged $got_fr3 != full $N_FR3 (slim regression?)"
[ "$got_fr3" -ge 26 ]       || fail "fr3 looks slim ($got_fr3 < 26) — the bundle MUST ship the full fr3 set"
# arm64 consistency: KERNEL.CGO must == the arm64 build and must NOT == x86 oracle.
k_arm=$(md5sum "$ARM64_CODE/KERNEL.CGO" | cut -d' ' -f1)
k_x86=$(md5sum "$ISO_BUILD/KERNEL.CGO"  | cut -d' ' -f1)
k_stg=$(md5sum "$STAGE/iso_data/$GAME/KERNEL.CGO" | cut -d' ' -f1)
[ "$k_stg" = "$k_arm" ]  || fail "staged KERNEL.CGO != arm64 build (mixed/stale code)"
[ "$k_stg" != "$k_x86" ] || fail "staged KERNEL.CGO == x86 oracle (would SIGILL on the arm64 device)"
echo "[asset-bundle] completeness OK: iso=$got_iso (==$N_ISO) fr3=$got_fr3 (==$N_FR3); arm64 CGO/DGO verified."

# Raw totals (dereferenced) drive the device progress bar + storage precheck + integrity check.
RAW_BYTES=$(find -L "$STAGE" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')
FILE_COUNT=$(find -L "$STAGE" -type f | wc -l | tr -d ' ')
[ "$FILE_COUNT" -eq "$WANT_FC" ] || fail "assembled $FILE_COUNT files, expected $WANT_FC"

echo "[asset-bundle] packing $FILE_COUNT files → $ZIP_REL (one-time; cached after)…"
rm -f "$ZIP_ABS"
# -6 = balanced DEFLATE (STR/VAG audio + fr3 textures dominate and compress
# poorly, so a higher level buys little for a lot more time). -X drops extra
# metadata, -q quiet. zip dereferences the farm's symlinks and stores real
# content under the iso_data/<game>/* and fr3/* entry paths.
(
  cd "$STAGE"
  zip -r -6 -X -q "$ZIP_ABS" "iso_data/${GAME}" "fr3"
)

ZIP_BYTES=$(stat -c %s "$ZIP_ABS")
RATIO=$(awk "BEGIN{ if($RAW_BYTES>0) printf \"%.1f\", 100.0*$ZIP_BYTES/$RAW_BYTES; else print \"0\" }")

cat > "$MANIFEST" <<EOF
# Generated by android/build_asset_bundle.sh — do not edit.
version=${VERSION}
game=${GAME}
file_count=${FILE_COUNT}
raw_bytes=${RAW_BYTES}
zip_bytes=${ZIP_BYTES}
EOF

# Phase Glauncher-collection (autoport 2026-07-02): also emit a PER-GAME manifest
# (bundle/<game>.manifest.properties) so multiple games' bundles can coexist in
# one COLLECTION APK's bundle dir without their manifests colliding. LoaderActivity
# prefers the per-game manifest and falls back to the legacy manifest.properties
# (which is kept for the single-game path). Byte-identical content, per-game name.
cp -f "$MANIFEST" "${OUT_DIR}/${GAME}.manifest.properties"

rm -rf "$STAGE"   # the symlink farm is transient; the zip + manifest are the artifacts

echo "[asset-bundle] done: ${ZIP_REL}"
echo "[asset-bundle]   files=${FILE_COUNT} (iso=${N_ISO} fr3=${N_FR3})  raw=${RAW_BYTES}B  zip=${ZIP_BYTES}B  (${RATIO}% of raw)  version=${VERSION}"

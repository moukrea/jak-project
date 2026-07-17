#!/usr/bin/env bash
# External-asset-root feature (autoport 2026-07): build the SLIM "CGO pack" that
# the assets-slim APK ships. Unlike build_asset_bundle.sh (which packs the FULL
# ~1.6 GiB runtime set — iso data + fr3 + arm64 code), this packs ONLY the tiny
# arch-specific code layer: every *.CGO/*.DGO from the ARM64 build, plus any
# android *COMMON.TXT text overrides. The bulky iso data + fr3 come from the
# user's external asset root instead; the CGO pack is unpacked to
# <filesDir>/cgo/<game>/ and handed to fake_iso as the FIRST-scanned overlay dir,
# so the freshly-built arm64 code (matching HEAD libgk.so) always wins over any
# x86/older CGOs sitting in the external iso dir.
#
# Layout (zip root, FLAT — no subdirs):
#   *.CGO / *.DGO   the 28 ARM64-compiled code files (jak1; >0 for jak2)
#   *.TXT           ALL rebuilt text banks (out/<game>/iso/*.TXT — COMMON + SUBTIT,
#                   every language; they carry port-custom text ids so they are
#                   PACKAGE artifacts per the Grecharged-buildsys-packaging rule;
#                   the source-derived <game>_assets.zip ships NO TXT), with the
#                   android *COMMON.TXT overrides (out/<game>-android-text/)
#                   overlaid over the same-named desktop banks.
#
# Output:
#   android/app/src/<game>/assets-slim/bundle/<game>_cgo.zip           (DEFLATE)
#   android/app/src/<game>/assets-slim/bundle/<game>_cgo.manifest.properties
#
# HARD-FAILS if the arm64 iso dir is missing, if the code-file count is wrong
# (jak1: exactly 28; jak2: >0), or if the arm64 KERNEL.CGO is missing / equals
# the x86 oracle copy (a mixed/x86 pack would SIGILL on the arm64 device).
# Mirrors build_asset_bundle.sh's rigor: content-derived VERSION, staleness skip,
# completeness gates, KERNEL.CGO arm64!=x86 assertion.
set -euo pipefail

GAME="${1:-jak1}"

cd "$(git rev-parse --show-toplevel)"

ARM64_CODE="out/${GAME}-arm64-full/iso"
# x86 oracle copies — used ONLY for the "arm64 != x86" KERNEL.CGO assertion.
ISO_BUILD="out/${GAME}/iso"
# android-only localized text overrides (per-arch-independent, but they ride the
# CGO pack so a slim build still overlays them via fake_iso precedence).
ANDROID_TEXT="out/${GAME}-android-text"
OUT_DIR="android/app/src/${GAME}/assets-slim/bundle"
STAGE="out/${GAME}-cgo-pack-stage"
ZIP_REL="${OUT_DIR}/${GAME}_cgo.zip"
MANIFEST="${OUT_DIR}/${GAME}_cgo.manifest.properties"
ZIP_ABS="$(pwd)/${ZIP_REL}"
ROOT="$(pwd)"

fail(){ echo "[cgo-pack] FATAL: $*" >&2; exit 1; }

[ -d "$ARM64_CODE" ] || fail "no $ARM64_CODE — run .autoport/build_arm64_full_consistent.sh first (need the consistent arm64 CGO/DGO set)"

# Every *.CGO/*.DGO in the arm64 iso dir is a pack member.
mapfile -t CODE_FILES < <(find "$ARM64_CODE" -maxdepth 1 -type f \( -name '*.CGO' -o -name '*.DGO' \) -printf '%f\n' | sort)
N_CODE=${#CODE_FILES[@]}
[ "$N_CODE" -gt 0 ] || fail "no CGO/DGO in $ARM64_CODE"
if [ "$GAME" = "jak1" ]; then
  [ "$N_CODE" -eq 28 ] || fail "jak1 expects exactly 28 CGO/DGO, found $N_CODE in $ARM64_CODE"
fi
[ -f "$ARM64_CODE/KERNEL.CGO" ] || fail "arm64 set missing KERNEL.CGO"

# ALL rebuilt text banks from the desktop iso build (COMMON + SUBTIT, every
# language). Grecharged-buildsys-packaging: the separate <game>_assets.zip ships
# ONLY vanilla data (no TXT), so the pack is now the ONLY delivery path for the
# rebuilt banks — a missing bank here = missing language/subtitles on device.
mapfile -t DESKTOP_TXT < <(find "$ISO_BUILD" -maxdepth 1 -type f -name '*.TXT' -printf '%f\n' 2>/dev/null | sort)
N_DTXT=${#DESKTOP_TXT[@]}
[ "$N_DTXT" -gt 0 ] || fail "no *.TXT banks in $ISO_BUILD — run the PC text build first"
if [ "$GAME" = "jak1" ]; then
  [ "$N_DTXT" -eq 46 ] || fail "jak1 expects exactly 46 TXT banks (23 COMMON + 23 SUBTIT), found $N_DTXT in $ISO_BUILD"
fi

# android *COMMON.TXT overrides (optional; present for jak1). They REPLACE the
# same-named desktop banks (no count change).
mapfile -t TEXT_FILES < <([ -d "$ANDROID_TEXT" ] && find "$ANDROID_TEXT" -maxdepth 1 -type f -name '*COMMON.TXT' -printf '%f\n' | sort || true)
N_TEXT=${#TEXT_FILES[@]}

WANT_FC=$((N_CODE + N_DTXT))

# Content-derived VERSION (md5 of all pack member contents), like
# build_asset_bundle.sh — any code/text change forces on-device re-unpack.
VERSION="${CGO_PACK_VERSION:-}"
if [ -z "$VERSION" ]; then
  # Hash the EFFECTIVE member contents: arm64 code + every TXT bank, where an
  # android override (same name) wins over the desktop copy.
  VERSION="c$( {
      for f in "${CODE_FILES[@]}"; do printf '%s\0' "$ARM64_CODE/$f"; done
      for f in "${DESKTOP_TXT[@]}"; do
        if [ -f "$ANDROID_TEXT/$f" ]; then printf '%s\0' "$ANDROID_TEXT/$f"; else printf '%s\0' "$ISO_BUILD/$f"; fi
      done
    } | sort -z | xargs -0 md5sum | md5sum | cut -c1-12 )"
fi

mkdir -p "$OUT_DIR"

# All source trees whose mtimes gate a repack (ISO_BUILD gates the desktop TXT
# banks; over-invalidation from unrelated iso files is safe, stale reuse is not).
SRC_DIRS=("$ARM64_CODE" "$ISO_BUILD")
[ -d "$ANDROID_TEXT" ] && SRC_DIRS+=("$ANDROID_TEXT")

# --- Staleness skip: zip current vs all sources AND version+count match. ---
if [ -f "$ZIP_REL" ] && [ -f "$MANIFEST" ]; then
  newest=$(find "${SRC_DIRS[@]}" -type f -printf '%T@\n' 2>/dev/null | awk 'BEGIN{m=0}{t=int($1); if(t>m)m=t} END{print m}')
  zmt=$(stat -c %Y "$ZIP_REL")
  cv=$(grep -E '^version=' "$MANIFEST" | cut -d= -f2 || echo "")
  cfc=$(grep -E '^file_count=' "$MANIFEST" | cut -d= -f2 || echo "")
  if [ -n "$newest" ] && [ "$zmt" -ge "$newest" ] && [ "$cv" = "$VERSION" ] && [ "$cfc" = "$WANT_FC" ]; then
    echo "[cgo-pack] up to date: $ZIP_REL (version=$VERSION file_count=$cfc)"
    exit 0
  fi
fi

echo "[cgo-pack] assembling arm64 CGO pack for $GAME (symlink farm)…"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# 1. arm64 code files at zip root.
for f in "${CODE_FILES[@]}"; do
  ln -s "$ROOT/$ARM64_CODE/$f" "$STAGE/$f"
done

# 2. ALL rebuilt TXT banks at zip root (desktop set), then the android
#    *COMMON.TXT overrides overlaid over their same-named desktop banks.
for f in "${DESKTOP_TXT[@]}"; do
  ln -s "$ROOT/$ISO_BUILD/$f" "$STAGE/$f"
done
for f in "${TEXT_FILES[@]}"; do
  [ -e "$STAGE/$f" ] || fail "android text override $f has no desktop bank counterpart in $ISO_BUILD"
  ln -sf "$ROOT/$ANDROID_TEXT/$f" "$STAGE/$f"
done
echo "[cgo-pack] text banks: $N_DTXT (android overrides: $N_TEXT)"

# --- HARD completeness + consistency gates ---
got=$(find -L "$STAGE" -type f | wc -l | tr -d ' ')
[ "$got" -eq "$WANT_FC" ] || fail "staged $got files != expected $WANT_FC"

# arm64 consistency: KERNEL.CGO must be the arm64 build, NOT the x86 oracle.
k_stg=$(md5sum "$STAGE/KERNEL.CGO" | cut -d' ' -f1)
k_arm=$(md5sum "$ARM64_CODE/KERNEL.CGO" | cut -d' ' -f1)
[ "$k_stg" = "$k_arm" ] || fail "staged KERNEL.CGO != arm64 build (mixed/stale code)"
if [ -f "$ISO_BUILD/KERNEL.CGO" ]; then
  k_x86=$(md5sum "$ISO_BUILD/KERNEL.CGO" | cut -d' ' -f1)
  [ "$k_stg" != "$k_x86" ] || fail "staged KERNEL.CGO == x86 oracle (would SIGILL on the arm64 device)"
fi
echo "[cgo-pack] completeness OK: code=$N_CODE text=$N_TEXT; arm64 KERNEL.CGO verified."

RAW_BYTES=$(find -L "$STAGE" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')
FILE_COUNT=$(find -L "$STAGE" -type f | wc -l | tr -d ' ')
[ "$FILE_COUNT" -eq "$WANT_FC" ] || fail "assembled $FILE_COUNT files, expected $WANT_FC"

echo "[cgo-pack] packing $FILE_COUNT files → $ZIP_REL (DEFLATE)…"
rm -f "$ZIP_ABS"
# -6 balanced DEFLATE (CGOs compress well); -X drop extra metadata; -q quiet.
# zip dereferences the farm symlinks and stores real content at the flat entry name.
(
  cd "$STAGE"
  zip -6 -X -q "$ZIP_ABS" ./*
)

ZIP_BYTES=$(stat -c %s "$ZIP_ABS")

# Grecharged-buildsys-flags: record the flag-set marker compiled into the CGOs
# (GAME.CGO carries "ogflags:<flag-hash>:<target>"); release_verify pairs it with
# the libgk.so marker so a mixed flag-set APK is refused (risk R1).
FLAG_MARKER=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$ARM64_CODE/GAME.CGO" 2>/dev/null | head -1 || true)

cat > "$MANIFEST" <<EOF
# Generated by android/build_cgo_pack.sh — do not edit.
version=${VERSION}
game=${GAME}
file_count=${FILE_COUNT}
raw_bytes=${RAW_BYTES}
zip_bytes=${ZIP_BYTES}
flags=${FLAG_MARKER}
EOF

rm -rf "$STAGE"   # the symlink farm is transient; the zip + manifest are the artifacts

echo "[cgo-pack] done: ${ZIP_REL}"
echo "[cgo-pack]   files=${FILE_COUNT} (code=${N_CODE} txt=${N_DTXT} android-overrides=${N_TEXT})  raw=${RAW_BYTES}B  zip=${ZIP_BYTES}B  version=${VERSION}"

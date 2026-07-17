#!/usr/bin/env bash
# release_jak_builds.sh — publish the new-layout artifacts to the owner's release
# repo (moukrea/jak-builds). Phase Grecharged-buildsys-cidocs (P4): the release
# layout switches from the legacy {app-jak1-debug.apk, jak1_assets.zip} pair to
# the P2 packaging outputs, uploaded UNDER THEIR CANONICAL NAMES:
#   app-<game>-android-arm64.apk        (+ .manifest.txt)
#   app-<game>-linux-x86_64.tar.gz      (+ .manifest.txt)
#   app-<game>-windows-x86_64.zip       (+ .manifest.txt)   [if built]
#   <game>_assets.zip                   (+ manifest/properties) [--with-assets]
#
# Usage:
#   scripts/release_jak_builds.sh <tag> <title> <notes-file> [--game jak1]
#                                 [--with-assets] [--draft]
#
# Gates (refuse to publish anything unverified):
#   - release_verify.sh must PASS on the APK (cgo/custom pack content hashes,
#     R1 flag-set pairing, zero vanilla data in the APK, archive contract).
#   - every uploaded package must have its sidecar manifest.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TAG="${1:-}"; TITLE="${2:-}"; NOTES="${3:-}"
[ -n "$TAG" ] && [ -n "$TITLE" ] && [ -n "$NOTES" ] || {
  echo "usage: $0 <tag> <title> <notes-file> [--game jak1] [--with-assets] [--draft]" >&2; exit 1; }
shift 3
GAME="jak1"; WITH_ASSETS=0; DRAFT=()
while [ $# -gt 0 ]; do
  case "$1" in
    --game) GAME="$2"; shift;;
    --with-assets) WITH_ASSETS=1;;
    --draft) DRAFT=(--draft);;
    *) echo "unknown option '$1'" >&2; exit 1;;
  esac
  shift
done
[ -f "$NOTES" ] || { echo "[release FAIL] notes file '$NOTES' missing" >&2; exit 1; }

A="out/artifacts"
APK="$A/app-${GAME}-android-arm64.apk"
LIN="$A/app-${GAME}-linux-x86_64.tar.gz"
WIN="$A/app-${GAME}-windows-x86_64.zip"

need() { [ -f "$1" ] || { echo "[release FAIL] missing $1" >&2; exit 1; }; }
need "$APK"; need "${APK%.apk}.manifest.txt"
need "$LIN"; need "${LIN%.tar.gz}.manifest.txt"

FILES=("$APK" "${APK%.apk}.manifest.txt" "$LIN" "${LIN%.tar.gz}.manifest.txt")
if [ -f "$WIN" ]; then
  need "${WIN%.zip}.manifest.txt"
  FILES+=("$WIN" "${WIN%.zip}.manifest.txt")
else
  echo "[release] note: no windows package at $WIN — releasing without it"
fi
if [ "$WITH_ASSETS" -eq 1 ]; then
  need "$A/${GAME}_assets.zip"; need "$A/${GAME}_assets.manifest.txt"; need "$A/${GAME}_assets.properties"
  FILES+=("$A/${GAME}_assets.zip" "$A/${GAME}_assets.manifest.txt" "$A/${GAME}_assets.properties")
fi

echo "[release] gate: release_verify.sh $APK $GAME"
bash .autoport/lib/release_verify.sh "$APK" "$GAME"

echo "[release] creating $TAG on moukrea/jak-builds with ${#FILES[@]} assets"
gh release create "$TAG" -R moukrea/jak-builds --title "$TITLE" --notes-file "$NOTES" \
  "${DRAFT[@]}" "${FILES[@]}"
echo "[release] done: https://github.com/moukrea/jak-builds/releases/tag/$TAG"

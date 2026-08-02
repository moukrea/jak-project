#!/usr/bin/env bash
# deploy_verify.sh — PROVE the device is running the freshly-built libgk.so that
# reflects the current HEAD. Prevents the "fix committed/built but doesn't land
# on the device" class of silent progress loss.
#
# Checks (all must pass):
#   1. FRESHNESS: build-android libgk.so is NEWER than the newest C++/shader
#      source mtime (so the .so reflects recent edits — catches "didn't rebuild").
#   2. NOT-STALE-vs-HEAD: build-android libgk.so is NEWER than the HEAD commit
#      time (so the build happened after the latest committed change).
#   3. CHAIN: sha256(build libgk.so) == sha256(APK-bundled libgk.so) ==
#      sha256(device-installed libgk.so). So the device provably runs that .so.
#
# Usage: deploy_verify.sh [SERIAL] [GAME]   (defaults: eae4df44 jak1)
# Exit 0 = device provably runs the fresh HEAD-reflecting libgk.so; nonzero = NOT.
# Records a fingerprint to .autoport/reports/deploy-fingerprint.txt for audit.
#
# NOTE on the incremental-build hazard: cmake/ninja header-dep tracking *should*
# recompile dependents, but to be safe a phase that changes libgk.so C++/shaders
# MUST do a clean/forced rebuild (touch the changed TU or `ninja -t clean`) so the
# .so truly reflects HEAD. This script proves the RESULT reached the device; the
# clean-rebuild discipline guarantees the .so CONTENT matches the source.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
SERIAL="${1:-eae4df44}"
GAME="${2:-jak1}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.${GAME}"
SO_REL="lib/arm64-v8a/libgk.so"
BUILT="build-android/$SO_REL"
die() { echo "DEPLOY-VERIFY FAIL: $*" >&2; exit 1; }

# 0. The phone must actually BE here. Without this, an absent/unplugged device
# falls through to "package not installed on device <serial>", which reads as a
# stale or broken build and sends the next attempt hunting a phantom regression
# (Grecharged-loader-packfix 2026-07-29: the gate probed the unplugged Redmi
# while the work was verified on the owner's Honor). Never auto-substitute the
# connected device — the serial is configuration, and silently verifying a
# DIFFERENT phone than the phase targets is worse than failing.
if ! "$ADB" devices 2>/dev/null | grep -qE "^${SERIAL}[[:space:]]+device$"; then
  ATTACHED=$("$ADB" devices 2>/dev/null | tail -n +2 | grep -v '^$' | awk '{print $1"("$2")"}' | tr '\n' ' ')
  die "device $SERIAL is NOT connected (adb sees: ${ATTACHED:-none}) — this is a DEVICE-PRESENCE failure, not a stale build. Plug it in, clear an adb wedge (kill-server/start-server), or fix device_serial in milestones.yaml."
fi

[ -f "$BUILT" ] || die "no built libgk.so at $BUILT"
SO_MTIME=$(stat -c %Y "$BUILT")

# 1. Freshness vs source.
NEWEST_SRC=$(find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
if [ -n "$NEWEST_SRC" ] && [ "$SO_MTIME" -lt "$NEWEST_SRC" ]; then die "libgk.so ($(date -d @$SO_MTIME +%H:%M)) is OLDER than newest source ($(date -d @$NEWEST_SRC +%H:%M)) — STALE build, rebuild before deploy"; fi
echo "  ok: libgk.so newer than newest source"

# 2. (removed) "newer than HEAD commit time" — FALSE-POSITIVES on the normal
# build-then-commit flow (the .so is built before the commit that packages it).
# Freshness-vs-source (check 1) + the build==APK==device chain (check 3) are the
# real guarantees that the device runs a .so reflecting the current source.

# 3. Chain: build == APK == device.
# Repo-local temp: /tmp can be size-limited or sandbox-isolated (a 220MB APK
# pull died at ~79% under a sandboxed tmpfs), which false-FAILs the chain.
mkdir -p .autoport/tmp
TMP=$(mktemp -d .autoport/tmp/dv.XXXXXX); trap "rm -rf $TMP" EXIT
B=$(sha256sum "$BUILT" | cut -d' ' -f1)
APK=$(find android -name "app-${GAME}-debug.apk" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
[ -n "$APK" ] || die "no app-${GAME}-debug.apk"
unzip -p "$APK" "$SO_REL" > "$TMP/apk.so" 2>/dev/null || die "APK has no $SO_REL"
A=$(sha256sum "$TMP/apk.so" | cut -d' ' -f1)
[ "$B" = "$A" ] || die "build libgk.so != APK-bundled libgk.so — APK bundled a STALE .so (reassemble the APK after building)"
DP=$("$ADB" -s "$SERIAL" shell pm path "$PKG" 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
[ -n "$DP" ] || die "package not installed on device $SERIAL"
"$ADB" -s "$SERIAL" pull "$DP" "$TMP/dev.apk" >/dev/null 2>&1 || die "could not pull device APK"
unzip -p "$TMP/dev.apk" "$SO_REL" > "$TMP/dev.so" 2>/dev/null || die "device APK has no $SO_REL"
D=$(sha256sum "$TMP/dev.so" | cut -d' ' -f1)
[ "$A" = "$D" ] || die "APK libgk.so != DEVICE libgk.so — device is running a STALE install (reinstall the APK)"
echo "  ok: chain build==APK==device ($(echo $B|cut -c1-16))"

# 4. FLAG-SET pairing (Grecharged-buildsys-flags, risk R1): the libgk.so on the
# device must have been built from the SAME flag set as the CGOs it will load
# (both carry "ogflags:<flag-hash>:<target>"). A mixed pair is the flag-era
# variant of the frame-180 mixed-build class — refuse it.
MARK_SO=$(strings "$TMP/dev.so" | grep -m1 '^ogflags:' || true)
if [ -n "$MARK_SO" ]; then
  MARK_CGO=$("$ADB" -s "$SERIAL" exec-out run-as "$PKG" cat "files/cgo/${GAME}/GAME.CGO" 2>/dev/null | grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' | head -1 || true)
  if [ -n "$MARK_CGO" ]; then
    [ "$MARK_SO" = "$MARK_CGO" ] || die "FLAG-SET MISMATCH: libgk '$MARK_SO' vs device CGO '$MARK_CGO' — mixed flag-set deploy (R1), push the matching CGO set or APK"
    echo "  ok: flag-set pairing $MARK_SO (device libgk == device CGO)"
  else
    echo "  warn: device CGOs carry no ogflags marker (pre-flag-era set) — pairing not enforced"
  fi
fi

# 4b. FEATURE PARITY (Grecharged-hd-models boot-crash, 2026-08-02). The R1 pairing
# above only matches the ogflags HASH string. A libgk built with the OG_FEAT_*
# compile define OFF but stamped with the right OG_FLAG_SET_ID is marker-fresh yet
# FEATURE-stale: it carries the correct marker (so pairing passes) but LACKS the
# pc-* C binding. Its FLAG_HD_MODELS CGOs still emit (pc-set-recharged-enhanced-models! ...)
# every frame from boot -> the symbol value slot is 0 -> BLR ee_base -> sig=4 SIGILL;
# our handler eats the signal (no tombstone) and the process is reaped as exit-info
# reason=2 / subreason=3 (TOO MANY EMPTY PROCS). This is exactly how a d98928 libgk
# without the hd binding died on the Redmi. Tie the two sides by the shared GOAL
# symbol NAME: if the device GAME.CGO references the hd toggle setter (hd GOAL code
# shipped), the device libgk MUST provide that binding. grep -c (not -q) reads all
# input so the pipe never closes early -> no SIGPIPE under pipefail.
CGO_HAS_HD=$("$ADB" -s "$SERIAL" exec-out run-as "$PKG" cat "files/cgo/${GAME}/GAME.CGO" 2>/dev/null | grep -a -c 'pc-set-recharged-enhanced-models!' || true)
if [ "${CGO_HAS_HD:-0}" -ge 1 ]; then
  SO_HAS_HD=$(strings "$TMP/dev.so" | grep -c 'pc-set-recharged-enhanced-models!' || true)
  [ "${SO_HAS_HD:-0}" -ge 1 ] || die "FEATURE-STALE libgk: device GAME.CGO emits (pc-set-recharged-enhanced-models! ...) (FLAG_HD_MODELS on) but the device libgk has NO such binding — marker-fresh / OG_FEAT_HD_MODELS-OFF build. Its boot per-frame call hits an unbound symbol -> fn-ptr=0 SIGILL (reaped reason=2/TOO_MANY_EMPTY). Rebuild libgk with --hd-models (OG_FEAT_HD_MODELS=ON) and reinstall."
  echo "  ok: hd-models feature parity (device CGO hd call has its device libgk binding)"
fi

# 5. CUSTOM PACK landing (Grecharged-buildsys-packaging): the port-custom asset
# set the APK ships (grassbake / enhanced fr3 / recharged PNGs) must be unpacked
# on device at the version the build produced — a stale custom set is the asset
# variant of the mixed-build class. Member-level md5 compare (packs are tiny).
CUS_MAN="android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.manifest.properties"
CUS_ZIP="android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.zip"
if [ -f "$CUS_MAN" ] && [ -f "$CUS_ZIP" ]; then
  CUS_VER=$(grep -E '^version=' "$CUS_MAN" | cut -d= -f2)
  CUS_FC=$(grep -E '^file_count=' "$CUS_MAN" | cut -d= -f2)
  DEV_STAMP=$("$ADB" -s "$SERIAL" exec-out run-as "$PKG" cat "files/.custom_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n' || true)
  if [ "$CUS_FC" -gt 0 ]; then
    [ "$DEV_STAMP" = "$CUS_VER" ] || die "custom pack STALE on device: stamp '$DEV_STAMP' != built version '$CUS_VER' (relaunch the app so LoaderActivity re-unpacks, or reinstall)"
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      M_LOCAL=$(unzip -p "$CUS_ZIP" "$m" | md5sum | cut -d' ' -f1)
      M_DEV=$("$ADB" -s "$SERIAL" exec-out run-as "$PKG" md5sum "files/custom/${GAME}/${m}" 2>/dev/null | cut -d' ' -f1 | tr -d '\r' || true)
      [ "$M_LOCAL" = "$M_DEV" ] || die "custom pack member $m: device md5 '$M_DEV' != pack '$M_LOCAL'"
    done < <(python3 -c "
import zipfile
for n in zipfile.ZipFile('$CUS_ZIP').namelist():
    if not n.endswith('/'): print(n)")
    echo "  ok: custom pack on device == built pack (version $CUS_VER, $CUS_FC member(s))"
  else
    echo "  ok: custom pack empty for this flag set (nothing to verify on device)"
  fi
else
  echo "  warn: no built custom pack ($CUS_MAN) — pre-packaging-era build, custom-set check skipped"
fi

# Record fingerprint.
mkdir -p .autoport/reports
printf 'deploy-verify PASS %s  commit=%s  libgk_sha=%s  so_mtime=%s\n' "$(date -Is)" "$(git rev-parse --short HEAD)" "$(echo $B|cut -c1-16)" "$(date -d @$SO_MTIME -Is)" >> .autoport/reports/deploy-fingerprint.txt

echo "DEPLOY-VERIFY PASS: device $SERIAL provably runs the fresh HEAD ($(git rev-parse --short HEAD)) libgk.so."

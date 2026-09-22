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
# LE COMPARATEUR DE FRAICHEUR, RESOLU AVANT LE `cd` : ce script change de repertoire, et un
# chemin relatif a `$0` ne survivrait pas au changement.
FR_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/freshness.sh
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=freshness.sh
. "$FR_LIB" || { echo "DEPLOY-VERIFY FAIL: lib/freshness.sh introuvable ($FR_LIB) — ce script ne compare plus aucun horodatage lui-meme et refuse de deviner." >&2; exit 1; }
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

# 1. Freshness vs source.
# A LA NANOSECONDE, DES DEUX COTES (harness-subsecond-freshness-is-blind, 2026-09-12).
# Cette comparaison lisait `stat -c %Y` d'un cote et `find -printf %T@ | cut -d. -f1` de
# l'autre : DEUX troncatures a la seconde entiere, puis un `-lt` qui declarait l'egalite
# fraiche. Un libgk.so lie a 14:32:03,1 et une source reecrite a 14:32:03,9 passaient donc
# pour frais, et le `echo` ci-dessous imprimait un vert IMMERITE. Le depot est en btrfs et
# stocke bien la nanoseconde : la perte etait entierement dans la lecture.
# L'EGALITE NE VAUT PLUS FRAICHEUR : a horodatage egal, rien ne dit lequel a ete ecrit en
# premier, et cette porte se trompe toujours du cote PERMISSIF quand elle devine.
FR_SITE=deploy_verify/libgk-vs-source
SO_NS=$(fr_mtime_ns "$BUILT"); SO_MTIME=$(( SO_NS / 1000000000 ))
NEWEST_SRC_NS=$(find game/graphics game/kernel android -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.vert' -o -name '*.frag' \) -printf '%T@\n' 2>/dev/null | fr_plus_recent_ns)
NEWEST_SRC=$(( NEWEST_SRC_NS / 1000000000 ))
if [ "$NEWEST_SRC_NS" != 0 ]; then
  case "$(fr_verdict "$SO_NS" "$NEWEST_SRC_NS")" in
    perime)  die "libgk.so ($(date -d @$SO_MTIME +%H:%M:%S), ${SO_NS}ns) is OLDER than newest source ($(date -d @$NEWEST_SRC +%H:%M:%S), ${NEWEST_SRC_NS}ns) — STALE build, rebuild before deploy" ;;
    douteux) die "libgk.so et la source la plus recente portent le MEME horodatage a la nanoseconde ($SO_NS) : DOUTEUX, pas frais — rien ne dit lequel a ete ecrit en premier. Rebatis avant de deployer." ;;
  esac
fi
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
# 2026-09-11 — RACCOURCI PROUVE. Tirer 671 Mo a chaque fermeture pour lire l'empreinte d'un
# seul fichier coutait 17 a 60 s. L'installeur enregistre ce qu'il a installe ET l'identite du
# fichier pose sur le telephone (chemin, taille, date). Si le telephone porte TOUJOURS ce
# fichier-la — meme chemin, meme taille, meme date — alors son libgk.so est celui enregistre,
# et la chaine se ferme sans rien transferer. Toute divergence, y compris un APK pose a la main
# par l'owner depuis jak-builds, fait retomber sur le tirage complet. Jamais l'inverse.
CHAIN=".autoport/.installed_chain"
D=""
if [ -s "$CHAIN" ]; then
  IFS='|' read -r c_ser c_pkg c_path c_size c_mtime c_sha < "$CHAIN"
  if [ "$c_ser" = "$SERIAL" ] && [ "$c_pkg" = "$PKG" ] && [ "$c_path" = "$DP" ] && [ -n "$c_sha" ]; then
    # NB : le shell du telephone decoupe le format sur l'espace et prend « %Y » pour un
    # chemin. Separateur sans espace, obligatoire.
    now=$("$ADB" -s "$SERIAL" shell stat -c '%s:%Y' "$DP" 2>/dev/null | tr -d '\r')
    if [ "$now" = "$c_size:$c_mtime" ]; then
      D="$c_sha"
      echo "  (chaine lue sur l'empreinte d'installation — APK non tire)"
    fi
  fi
fi
if [ -z "$D" ]; then
  "$ADB" -s "$SERIAL" pull "$DP" "$TMP/dev.apk" >/dev/null 2>&1 || die "could not pull device APK"
fi
if [ -z "$D" ]; then
  unzip -p "$TMP/dev.apk" "$SO_REL" > "$TMP/dev.so" 2>/dev/null || die "device APK has no $SO_REL"
  D=$(sha256sum "$TMP/dev.so" | cut -d' ' -f1)
fi
[ "$A" = "$D" ] || die "APK libgk.so != DEVICE libgk.so — device is running a STALE install (reinstall the APK)"
echo "  ok: chain build==APK==device ($(echo $B|cut -c1-16))"

# 3b. LE PACK DE CODE GOAL (harness-device-deploy-gate-must-compare-the-asset-pack, 22/09).
# La chaine ci-dessus ne lit que libgk.so : un essai 100 % GOAL passait cette fermeture avec le
# pack d'AVANT sur le telephone. On lit les OCTETS de `assets/bundle/<game>_cgo.zip`, local et
# installe, par la MEME porte que la course (`deploy_verify_assets.sh --gate`), sans rien
# installer ici. Puis le tampon deballe : le jeu lit `files/cgo/<game>/`, pas l'APK.
AG=$(bash "$(dirname "$FR_LIB")/deploy_verify_assets.sh" --gate --no-deploy --item deploy_verify \
       --arm cloture --serial "$SERIAL" --game "$GAME" --binary "$BUILT" 2>/dev/null)
agv(){ printf '%s\n' "$AG" | sed -n "s/^$1=//p" | tail -1; }
case "$(agv asset_pack_decision)/$(agv asset_pack_reason)" in
  identique/*)
    [ "$(agv asset_pack_device_stamp)" = "$(agv asset_pack_local_version)" ] \
      || die "cgo pack UNPACKED on device is STALE: stamp '$(agv asset_pack_device_stamp)' != built version '$(agv asset_pack_local_version)' (launch the app once so LoaderActivity re-unpacks)"
    echo "  ok: cgo pack on device == built pack ($(agv asset_pack_local_md5 | cut -c1-16), version $(agv asset_pack_local_version))" ;;
  inconnu/pack-local-absent)
    echo "  warn: no built cgo pack — pre-packaging-era build, cgo pack check skipped" ;;
  *)
    die "cgo pack: decision=$(agv asset_pack_decision) reason=$(agv asset_pack_reason) local=$(agv asset_pack_local_md5) device=$(agv asset_pack_device_md5) — the device does NOT run the built GOAL code (install the APK the builder produced)" ;;
esac

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

# 4c. FEATURE PARITY, physics flag (same class as 4b). --physics compiles the
# secondary-motion sim into libgk AND emits (pc-set-physics! ...) from the flagged GOAL
# code. A marker-fresh / OG_FEAT_PHYSICS-OFF libgk would leave that call unbound ->
# fn-ptr=0 SIGILL at the first toggle. Same shared-symbol-name tie, same grep -c (never
# -q) so the pipe is fully consumed under pipefail.
CGO_HAS_PHYS=$("$ADB" -s "$SERIAL" exec-out run-as "$PKG" cat "files/cgo/${GAME}/GAME.CGO" 2>/dev/null | grep -a -c 'pc-set-physics!' || true)
if [ "${CGO_HAS_PHYS:-0}" -ge 1 ]; then
  SO_HAS_PHYS=$(strings "$TMP/dev.so" | grep -c 'pc-set-physics!' || true)
  [ "${SO_HAS_PHYS:-0}" -ge 1 ] || die "FEATURE-STALE libgk: device GAME.CGO emits (pc-set-physics! ...) (FLAG_PHYSICS on) but the device libgk has NO such binding — marker-fresh / OG_FEAT_PHYSICS-OFF build. The call hits an unbound symbol -> fn-ptr=0 SIGILL. Rebuild libgk with --hd-models --physics (OG_FEAT_PHYSICS=ON) and reinstall."
  echo "  ok: physics feature parity (device CGO physics call has its device libgk binding)"
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

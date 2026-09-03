#!/usr/bin/env bash
# gpdb_deploy.sh — Gprecompute-deterministic-bake, CLOSE-GATE deploy.
#
# WHY THIS EXISTS. Attempt 1 shipped the whole phase (tangents baked into the fr3, subdivision
# demoted to a setting) and never built it for ANDROID. The close gate caught the consequence
# ("libgk.so (01:14) is OLDER than newest source (04:28)"), but the deeper fact only came out at the
# link: the phase moved the tangent derivation into a NEW TU, common/custom_data/TangentDerive.cpp,
# and android/CMakeLists.txt carries an EXPLICIT source list (it links no `common` library). So the
# arm64 libgk did not merely lag — it could not link at all:
#     ld.lld: error: undefined symbol: tfrag3::retangent_level_from_final_normals(tfrag3::Level&)
#     ld.lld: error: undefined symbol: tfrag3::tangent_derive_diag()
# The desktop build was green the whole time because common/CMakeLists.txt globs the new file in.
#
# ORDER IS IMPOSED, AND EACH STEP PROVES THE PREVIOUS ONE LANDED:
#   libgk -> HD external pack -> CGO pack -> custom pack -> APK -> install -> boot -> deploy_verify.
# The HD pack is NOT optional this cycle: TFRAG3_VERSION went 43 -> 44 and Level::serialize()
# ASSERTs on a mismatch, so the 2026-07-14/2026-08-11 fr3/enhanced/*.fr3 sitting on the phone would
# HARD-CRASH the first level load with the ENHANCED MODELS toggle on. They ship EXTERNAL (ND IP,
# never in the APK), so nothing in the APK chain can refresh them — this script must.
#
# Never `rm -rf` on code, never kill by pattern, PIDs only.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gprecompute-deterministic-bake; mkdir -p "$OUT"
LOG="$OUT/deploy.log"; : > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[deploy FAIL] $*"; exit 1; }

MARKER_EXPECT="ogflags:435df2141670:android-arm64"   # hd-models,pbr,physics
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
[ -f "$APK" ] || die "no APK at $APK"
say "APK: $APK ($(stat -c%s "$APK") bytes, $(date -d @$(stat -c%Y "$APK") +%H:%M:%S))"

# ---- ARTIFACT GATES (before touching the phone) ---------------------------------------------
unzip -p "$APK" lib/arm64-v8a/libgk.so > "$OUT/.apk_libgk.so" || die "APK has no libgk.so"
MARK=$(strings "$OUT/.apk_libgk.so" | grep -m1 '^ogflags:' || true)
[ "$MARK" = "$MARKER_EXPECT" ] || die "APK libgk marker '$MARK' != '$MARKER_EXPECT'"
say "APK libgk marker: $MARK"
# grep -c, never -q: pipefail + early close = SIGPIPE-141 false failure.
for sym in 'pc-set-physics!' 'pc-set-recharged-enhanced-models!' 'pc-set-mesh-subdiv-rounds!'; do
  n=$(strings "$OUT/.apk_libgk.so" | grep -c -- "$sym" || true)
  [ "${n:-0}" -ge 1 ] || die "APK libgk lacks the $sym binding"
  say "APK libgk exposes $sym"
done
rm -f "$OUT/.apk_libgk.so"
B=$(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -d' ' -f1)
A=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | sha256sum | cut -d' ' -f1)
[ "$B" = "$A" ] || die "APK libgk != build libgk (gradle bundled a cached .so)"
say "APK libgk == build libgk ($(echo $B | cut -c1-16))"
for p in custom cgo; do
  WANT=$(grep -E '^version=' "android/app/src/jak1/assets-slim/bundle/jak1_${p}.manifest.properties" | cut -d= -f2)
  GOT=$(unzip -p "$APK" "assets/bundle/jak1_${p}.manifest.properties" | grep -E '^version=' | cut -d= -f2)
  [ "$WANT" = "$GOT" ] || die "APK embeds ${p} pack '$GOT' but the tree built '$WANT'"
  say "APK embeds jak1_${p} pack version $GOT (== built)"
done

# ---- DEVICE ---------------------------------------------------------------------------------
$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not connected"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
# feedback_asleep_device_looks_like_dead_engine: TOP_SLEEPING blocks `am start` with no signal.
WAKE=$($ADB -s "$S" shell dumpsys power 2>/dev/null | grep -ao 'mWakefulness=[A-Za-z]*' | head -1)
say "device wakefulness: ${WAKE:-unknown}"
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then
  die "device PIN-LOCKED — cannot drive it"
fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
say "installing $(stat -c%s "$APK") bytes (this takes minutes)..."
timeout 3600 $ADB -s "$S" install -r -d "$APK" >> "$LOG" 2>&1 || die "adb install failed (see $LOG)"
say "install ok"

# ---- EXTERNAL HD PACK: the fr3 the APK is FORBIDDEN to carry -------------------------------
ZIP=out/artifacts/jak1_hd_assets.zip
[ -f "$ZIP" ] || die "no $ZIP — run scripts/package_hd_assets.sh jak1"
NAGZ=$(unzip -l "$ZIP" | grep -c 'hd/.*-ag\.go' || true)
say "HD pack: $ZIP ($(stat -c%s "$ZIP") bytes, $NAGZ ag.go — need 11)"
[ "${NAGZ:-0}" -ge 11 ] || die "HD pack has only $NAGZ ag.go"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
unzip -q "$ZIP" -d "$TMPD" || die "unzip of the HD pack failed"
# Every enhanced fr3 we are about to push must BE version 44, or we would push the very crash we
# are here to prevent. u16 at the head of the zstd payload, after the 8-byte raw-size prefix.
for f in "$TMPD"/fr3/enhanced/*.fr3; do
  V=$(tail -c +9 "$f" | zstd -dcq 2>/dev/null | head -c 2 | od -A n -t u2 | tr -d ' \n')
  [ "$V" = "44" ] || die "$(basename "$f") in the HD pack is TFRAG3_VERSION $V, not 44 — pushing it would ASSERT at load"
  say "HD pack $(basename "$f"): TFRAG3_VERSION $V"
done
DEVBASE=/storage/emulated/0/OpenGOAL/jak1/assets
$ADB -s "$S" shell mkdir -p "$DEVBASE/hd" "$DEVBASE/fr3/enhanced" >/dev/null 2>&1
$ADB -s "$S" push "$TMPD"/hd/. "$DEVBASE/hd/" >> "$LOG" 2>&1 || die "push hd/ failed"
$ADB -s "$S" push "$TMPD"/fr3/enhanced/. "$DEVBASE/fr3/enhanced/" >> "$LOG" 2>&1 || die "push fr3/enhanced failed"
PUSHFAIL=0
while IFS= read -r f; do
  rel=${f#"$TMPD"/}
  LM=$(md5sum "$f" | cut -d' ' -f1)
  DM=$($ADB -s "$S" shell md5sum "$DEVBASE/$rel" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
  [ "$LM" = "$DM" ] || { say "MD5 MISMATCH: $rel local=$LM device=$DM"; PUSHFAIL=1; }
done < <(find "$TMPD/hd" "$TMPD/fr3/enhanced" -type f)
[ "$PUSHFAIL" = 0 ] || die "HD pack push verification failed"
say "HD pack pushed + md5-verified (all files device == pack)"

# ---- LoaderActivity boot (MainActivity bypasses pack extraction) ----------------------------
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LC="$OUT/deploy.logcat.log"; : > "$LC"
# NOT in a subshell: `( adb logcat ) &` makes $! the subshell and orphans the reader.
$ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I '*:S' >> "$LC" 2>/dev/null &
LCP=$!
trap 'kill $LCP 2>/dev/null || true; wait $LCP 2>/dev/null || true; rm -rf "$TMPD"' EXIT
$ADB -s "$S" shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
T0=$(date +%s); RF=0
# 1200s, not 600: this cycle re-unpacks a 514 MB custom pack (+44 MB of baked tangents) on a phone.
while [ $(( $(date +%s)-T0 )) -lt 1200 ]; do
  RF=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LC" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); RF=${RF:-0}
  [ "$RF" -gt 600 ] && break; sleep 8
done
[ "${RF:-0}" -gt 600 ] || die "title never reached (render-frame=$RF at t+$(( $(date +%s)-T0 ))s) — see $LC"
say "boot ok: render-frame=$RF at t+$(( $(date +%s)-T0 ))s"

# ---- THE PHASE'S OWN CODE PATH, ON THE PHONE ------------------------------------------------
# PROOF ECONOMY: no new harness. These lines already exist in the load path; all that is asked of
# this run is that they show up on arm64 with the numbers the x86 run predicted.
NTAN=$(grep -ac 'A55-TANGENT' "$LC" || true)
[ "${NTAN:-0}" -ge 1 ] || die "no A55-TANGENT line on device — the baked-tangent expansion never ran"
say "A55-TANGENT lines on device: $NTAN"
grep -a 'A55-TANGENT' "$LC" | sed 's/^/  /' | tail -8 | tee -a "$LOG"
NPRE=$(grep -ac 'predates the tangent bake' "$LC" || true)
[ "${NPRE:-0}" -eq 0 ] || die "$NPRE tree(s) fell back to Duff/Frisvad — an fr3 on this phone has NO baked tangents"
say "trees falling back for want of a bake: 0"
NVER=$(grep -ac 'did you forget to re-decompile' "$LC" || true)
[ "${NVER:-0}" -eq 0 ] || die "$NVER TFRAG3_VERSION mismatch(es) on device — a stale fr3 is still being opened"
say "TFRAG3_VERSION mismatches: 0"
NSUB=$(grep -ac 'mesh-subdiv' "$LC" || true)
say "mesh-subdiv lines on device: $NSUB"
grep -a 'mesh-subdiv' "$LC" | sed 's/^/  /' | tail -4 | tee -a "$LOG"

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2

# ---- CGO landing proof (byte-level, marker-immune) -----------------------------------------
LOCAL_CGO=$(md5sum out/jak1-arm64-full/iso/GAME.CGO | cut -d' ' -f1)
DEV_CGO=$($ADB -s "$S" shell run-as $PKG md5sum files/cgo/jak1/GAME.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
say "GAME.CGO md5: built=$LOCAL_CGO device=$DEV_CGO"
[ "$LOCAL_CGO" = "$DEV_CGO" ] || die "device GAME.CGO is STALE (extraction did not refresh it)"

# ---- physics_chains.txt: the external copy WINS, so it is refreshed and proven --------------
LP=$(md5sum recharged_assets/physics_chains.txt | cut -d' ' -f1)
DEV_PHYS=$($ADB -s "$S" shell run-as $PKG find files -name physics_chains.txt 2>/dev/null | tr -d '\r' | head -1)
[ -n "$DEV_PHYS" ] || die "physics_chains.txt not under files/ — custom pack extraction missed it"
DP=$($ADB -s "$S" shell run-as $PKG md5sum "$DEV_PHYS" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
[ "$LP" = "$DP" ] || die "packaged physics_chains.txt on device ($DP) != built ($LP)"
EXT_DIR=$DEVBASE/recharged_assets
$ADB -s "$S" shell mkdir -p "$EXT_DIR" >/dev/null 2>&1
$ADB -s "$S" push recharged_assets/physics_chains.txt "$EXT_DIR/physics_chains.txt" >> "$LOG" 2>&1 \
  || die "cannot push the external physics_chains.txt override"
DE=$($ADB -s "$S" shell md5sum "$EXT_DIR/physics_chains.txt" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
[ "$LP" = "$DE" ] || die "external physics_chains.txt override is STALE — it would beat the fresh APK copy"
say "physics_chains.txt md5 $LP: packaged==built AND external override==built"

# ---- the close gate's own instrument, unmodified --------------------------------------------
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tee -a "$LOG" | tail -12
[ "${PIPESTATUS[0]}" -eq 0 ] || die "deploy_verify FAILED (see $LOG)"
say "[deploy PASS] device $S provably runs the fresh HEAD build (libgk + CGO + 514 MB custom pack + external HD fr3 v44)"

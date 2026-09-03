#!/usr/bin/env bash
# hd5_deploy_fresh.sh — M3: install the fresh jak1 APK on the Redmi, LoaderActivity boot
# (MainActivity bypasses pack extraction), byte-prove the new GAME.CGO landed, push the NEW
# 9-model HD pack to the external assets dir and md5-verify device==pack, then deploy_verify.
#
# Same-flag-set trap (hd-models,pbr unchanged): deploy_verify's ogflags marker CANNOT catch a
# stale device CGO from a same-flags rebuild — the md5 landing proof below is the real gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-hd-models5; mkdir -p "$OUT"
LOG="$OUT/deploy_fresh.log"; : > "$LOG"
say(){ echo "$*" | tee -a "$LOG"; }
die(){ say "[deploy FAIL] $*"; exit 1; }

APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
[ -n "$APK" ] || die "no APK"
say "APK: $APK ($(stat -c%s "$APK") bytes, $(date -d @$(stat -c%Y "$APK") +%H:%M:%S))"
MARK=$(unzip -p "$APK" lib/arm64-v8a/libgk.so | strings | grep -m1 '^ogflags:' || true)
say "APK libgk marker: $MARK (expect ogflags:009eadd8b50c:android-arm64 = hd-models,pbr)"
[ "$MARK" = "ogflags:009eadd8b50c:android-arm64" ] || die "APK marker mismatch — wrong flag set"

$ADB devices | grep -qE "^${S}[[:space:]]+device$" || die "device $S not connected"
$ADB -s "$S" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if $ADB -s "$S" shell dumpsys trust 2>/dev/null | grep -a '(current)' | grep -q 'deviceLocked=1'; then die "device PIN-LOCKED — wait for owner"; fi

$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true
say "installing (this can take ~2min)..."
$ADB -s "$S" install -r -d "$APK" >> "$LOG" 2>&1 || die "adb install failed (see $LOG)"
say "install ok"

# ---- push the NEW HD pack BEFORE the extraction boot (Loader stages ag.go at boot) ---------
ZIP=out/artifacts/jak1_hd_assets.zip
[ -f "$ZIP" ] || die "no $ZIP — run the bake+package first"
NAGZ=$(unzip -l "$ZIP" | grep -c 'hd/.*-ag\.go' || true)
say "HD pack: $ZIP ($(stat -c%s "$ZIP") bytes, $NAGZ ag.go — need 9)"
[ "$NAGZ" -ge 9 ] || die "pack has only $NAGZ ag.go"
TMPD=$(mktemp -d)
unzip -q "$ZIP" -d "$TMPD" || die "unzip failed"
DEVBASE=/storage/emulated/0/OpenGOAL/jak1/assets
$ADB -s "$S" shell mkdir -p "$DEVBASE/hd" "$DEVBASE/fr3/enhanced" >/dev/null 2>&1
$ADB -s "$S" push "$TMPD"/hd/. "$DEVBASE/hd/" >> "$LOG" 2>&1 || die "push hd/ failed"
$ADB -s "$S" push "$TMPD"/fr3/enhanced/. "$DEVBASE/fr3/enhanced/" >> "$LOG" 2>&1 || die "push fr3/enhanced failed"
# md5 verify device == pack, every file we pushed
PUSHFAIL=0
while IFS= read -r f; do
  rel=${f#"$TMPD"/}
  LM=$(md5sum "$f" | cut -d' ' -f1)
  DM=$($ADB -s "$S" shell md5sum "$DEVBASE/$rel" 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
  if [ "$LM" != "$DM" ]; then say "MD5 MISMATCH: $rel local=$LM device=$DM"; PUSHFAIL=1; fi
done < <(find "$TMPD/hd" "$TMPD/fr3/enhanced" -type f)
rm -rf "$TMPD"
[ "$PUSHFAIL" = 0 ] || die "HD pack push verification failed"
say "HD pack pushed + md5-verified (all files device==pack)"

# ---- LoaderActivity boot -> extraction -> title --------------------------------------------
$ADB -s "$S" logcat -c >/dev/null 2>&1 || true
LC="$OUT/deploy_fresh.logcat.log"; : > "$LC"
( $ADB -s "$S" logcat -v threadtime opengoal-gk:V GK_STDOUT:I GK_STDERR:I '*:S' >> "$LC" ) 2>/dev/null &
LCP=$!
trap 'kill $LCP 2>/dev/null || true' EXIT
$ADB -s "$S" shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
T0=$(date +%s); RF=0
while [ $(( $(date +%s)-T0 )) -lt 600 ]; do
  RF=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LC" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1); RF=${RF:-0}
  [ "$RF" -gt 600 ] && break; sleep 8
done
[ "$RF" -gt 600 ] || die "title never reached after install (render-frame=$RF at t+$(( $(date +%s)-T0 ))s) — extraction stuck?"
say "post-install boot ok: render-frame=$RF at t+$(( $(date +%s)-T0 ))s"
$ADB -s "$S" shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2

# ---- CGO landing proof (byte-level, marker-immune) ------------------------------------------
LOCAL_CGO=$(md5sum out/jak1-arm64-full/iso/GAME.CGO | cut -d' ' -f1)
DEV_CGO=$($ADB -s "$S" shell run-as $PKG md5sum files/cgo/jak1/GAME.CGO 2>/dev/null | cut -d' ' -f1 | tr -d '\r')
say "GAME.CGO md5: built=$LOCAL_CGO device=$DEV_CGO"
[ "$LOCAL_CGO" = "$DEV_CGO" ] || die "device GAME.CGO is STALE (extraction did not refresh it)"

bash .autoport/lib/deploy_verify.sh "$S" jak1 >> "$LOG" 2>&1 || { tail -4 "$LOG"; die "deploy_verify FAILED"; }
say "$(tail -1 "$LOG")"
say "[deploy PASS] device runs the fresh build incl. the new GAME.CGO + 9-model HD pack"

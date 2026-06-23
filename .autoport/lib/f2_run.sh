#!/usr/bin/env bash
# Phase F2 (autoport) — audio device driver.
#
# Builds the current-HEAD libgk (now with the REAL 989snd synth wired into
# the SDL3 AAudio sink — android_sound_stubs.cpp dropped, sndshim/sdshim +
# 989snd compiled in, Player::Tick pumped by audio_get_callback), deploys it
# via a SLIM APK (libgk-only change; F2 touches no goal_src/CGOs so there is
# no mixed-build risk), then boots jak1 to the interactive title and idles so
# the audio path runs: the boot DGO/sound-bank loads fire the overlord
# `LoadSingle @ #x..` queue markers, the title music streams a VAG (the
# `PlayVag @ #x..` marker + a non-silent PCM peak), and the SDL3 AAudio
# callback pumps continuously.
#
# Produces the artefacts the F2 validator inspects:
#   .autoport/reports/F2-boot.log           — opengoal-gk + GK_STDOUT logcat
#                                             (AAudio open marker, audio
#                                              triggers, throttled callback
#                                              lines w/ pcm peak)
#   .autoport/reports/F2-audio-triggers.txt — extracted trigger multiset
#   .autoport/reports/F2-status.txt / F2-launch.md
#
# The validator (.autoport/validators/phase-F2-gameplay-audio.sh) re-parses
# F2-boot.log itself; this script's job is to produce an honest capture in
# which audio genuinely opened (AAudio), genuinely triggered (>=5 events),
# genuinely pumped (>=100 callbacks), and — beyond the validator — genuinely
# produced non-silent PCM (pcm peak > 0).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"

REPORT_DIR=".autoport/reports"
BOOT_LOG="$REPORT_DIR/F2-boot.log"
TRIGGERS="$REPORT_DIR/F2-audio-triggers.txt"
STATUS_TXT="$REPORT_DIR/F2-status.txt"
REPORT_MD="$REPORT_DIR/F2-launch.md"
mkdir -p "$REPORT_DIR"

A() { "$ADB" -s "$SERIAL" "$@"; }

# Guard against a leftover prior runner's trailing force-stop murdering this run.
pkill -f 'logcat.*opengoal-gk' 2>/dev/null || true

echo "== F2 step 1/5: build current-HEAD libgk.so (real 989snd -> SDL AAudio sink) =="
bash .autoport/lib/d3_build.sh

echo "== F2 step 2/5: build SLIM jak1 debug APK (libgk-only; DGOs already on device) =="
( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 40 ) \
    || { echo "FAIL: gradle slim build failed"; exit 1; }
[ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }

echo "== F2 step 3/5: install + verify the device runs the fresh HEAD libgk =="
device_require_attached
device_stayon_on
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked

device_miui_unblock_install
STAGE="/data/local/tmp/$(basename "$APK")"
A push "$APK" "$STAGE" >/tmp/f2-push.out 2>&1 || { cat /tmp/f2-push.out; echo "FAIL: push"; exit 1; }
A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/f2-pm.out 2>&1 || { cat /tmp/f2-pm.out; echo "FAIL: pm install"; exit 1; }
grep -q "Success" /tmp/f2-pm.out || { cat /tmp/f2-pm.out; echo "FAIL: pm install no Success"; exit 1; }
A shell rm -f "$STAGE" >/dev/null 2>&1 || true

# Deploy-landing guard: PROVE the device runs the freshly built HEAD libgk.so.
bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify (device not running fresh HEAD libgk)"; exit 1; }

echo "== F2 step 4/5: launch, boot to title, idle so audio streams =="
# Arm verbose audio-callback logging so the SDL audio callback emits a
# "callback fired" line every callback (the F2 validator wants >=100 in the
# window). Default cadence (1-per-1024) is untouched for every other phase.
A shell setprop debug.opengoal.audio.verbose 1 >/dev/null 2>&1 || true
echo "  prop debug.opengoal.audio.verbose = $(A shell getprop debug.opengoal.audio.verbose | tr -d '\r')"

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c   >/dev/null 2>&1 || true
: > "$BOOT_LOG"

# Capture the GOAL-runtime tags: opengoal-gk carries the SDL audio markers +
# the link sequence; GK_STDOUT carries the overlord printf audio triggers
# (PlayVag/StopVag/PauseStream) + the DisplayQueue LoadSingle lines; libc/DEBUG
# catch native crashes.
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$BOOT_LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
    kill "$LOGCAT_PID" 2>/dev/null || true
    A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
    A shell setprop debug.opengoal.audio.verbose 0 >/dev/null 2>&1 || true
    device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/f2-am.out 2>&1 || true
grep -q 'Error' /tmp/f2-am.out && { cat /tmp/f2-am.out; echo "FAIL: am start"; exit 1; }

crash_seen() {
    grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$BOOT_LOG" \
        && grep -qaE '>>> org.opengoal.gk.jak1' "$BOOT_LOG"
}

# Warm up to the interactive title (the title music streams there), up to 150s.
echo "  warming up to title (link finish: logo, up to 150s)..."
TITLE_OK=0
for i in $(seq 1 150); do
    if grep -qa "link finish: logo" "$BOOT_LOG"; then echo "  title linked ~${i}s"; TITLE_OK=1; break; fi
    if crash_seen; then echo "  native crash before title"; break; fi
    sleep 1
done

# Idle ~40s at/around the title so the audio callback pumps and the title
# music streams a VAG (PlayVag + non-silent peak). No input needed: jak1's
# title/attract plays its theme on its own.
echo "  idle ~40s capturing the audio path..."
for i in $(seq 1 40); do
    if crash_seen; then echo "  native crash during audio idle"; break; fi
    if (( i % 10 == 0 )); then
        CBp=$(grep -ca "SDL_audio: callback fired" "$BOOT_LOG" 2>/dev/null || echo 0)
        TRp=$(grep -acE "PlayVag @ #x[0-9a-fA-F]+|LoadSingle @ #x[0-9a-fA-F]+|PauseStream|StopVag" "$BOOT_LOG" 2>/dev/null || echo 0)
        echo "   [idle ${i}/40] callbacks=$CBp triggers~=$TRp"
    fi
    sleep 1
done

echo "== F2 step 5/5: parse audio triggers + peak =="
# Extract the trigger multiset exactly as the validator does, for the report.
grep -oE "PlayVag @ #x[0-9a-fA-F]+|LoadSingle @ #x[0-9a-fA-F]+|PauseStream|StopVag" "$BOOT_LOG" \
    > "$TRIGGERS" 2>/dev/null || true

TRIG_COUNT=$(wc -l < "$TRIGGERS" 2>/dev/null || echo 0)
CB_COUNT=$(grep -ca "SDL_audio: callback fired" "$BOOT_LOG" 2>/dev/null || echo 0)
AAUDIO_OK=$(grep -caE "SDL_audio: opened.*aaudio|aaudio.*opened" "$BOOT_LOG" 2>/dev/null || echo 0)
# Loudest pcm peak the audio callback logged — objective "audio actually
# plays" evidence (0 => synth produced only silence in the window).
PEAK=$(grep -oaE "pcm peak=[0-9]+" "$BOOT_LOG" 2>/dev/null | grep -oE "[0-9]+" | sort -n | tail -1)
PEAK=${PEAK:-0}

# Per-type breakdown for the report.
N_PLAYVAG=$(grep -c "PlayVag @ #x" "$TRIGGERS" 2>/dev/null || echo 0)
N_LOADSINGLE=$(grep -c "LoadSingle @ #x" "$TRIGGERS" 2>/dev/null || echo 0)
N_PAUSE=$(grep -c "PauseStream" "$TRIGGERS" 2>/dev/null || echo 0)
N_STOP=$(grep -c "StopVag" "$TRIGGERS" 2>/dev/null || echo 0)

DET="fail"; NOTES=""
if [ "$AAUDIO_OK" -ge 1 ] && [ "$TRIG_COUNT" -ge 5 ] && [ "$CB_COUNT" -ge 100 ]; then
    DET="pass"
    NOTES="AAudio open; $TRIG_COUNT triggers; $CB_COUNT callbacks; pcm peak=$PEAK"
    [ "$PEAK" -gt 0 ] || NOTES="$NOTES (WARN: peak=0 — markers fired but synth silent in window)"
else
    NOTES="AAudio=$AAUDIO_OK triggers=$TRIG_COUNT callbacks=$CB_COUNT peak=$PEAK (need AAudio>=1, triggers>=5, callbacks>=100)"
fi
echo "$DET: $NOTES" > "$STATUS_TXT"

{
    echo "# Phase F2 — Android audio launch report"
    echo; echo "_Generated: $(date -Iseconds)_"; echo
    echo "## Determination"; echo; echo "**$DET** — $NOTES"; echo
    echo "## Artefacts"; echo
    echo "- boot log:  \`$BOOT_LOG\` ($(wc -l < "$BOOT_LOG" 2>/dev/null || echo 0) lines)"
    echo "- triggers:  \`$TRIGGERS\` ($TRIG_COUNT events)"
    echo; echo "## Audio scoreboard"; echo; echo '```'
    printf "  %-34s %s\n" "AAudio open marker"        "$AAUDIO_OK"
    printf "  %-34s %s\n" "SDL audio callbacks logged" "$CB_COUNT"
    printf "  %-34s %s\n" "pcm peak (0=silent)"        "$PEAK"
    printf "  %-34s %s\n" "triggers total"             "$TRIG_COUNT"
    printf "  %-34s %s\n" "  PlayVag @ #x"             "$N_PLAYVAG"
    printf "  %-34s %s\n" "  LoadSingle @ #x"          "$N_LOADSINGLE"
    printf "  %-34s %s\n" "  PauseStream"              "$N_PAUSE"
    printf "  %-34s %s\n" "  StopVag"                  "$N_STOP"
    echo '```'
} > "$REPORT_MD"

kill "$LOGCAT_PID" 2>/dev/null || true
trap - EXIT
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
A shell setprop debug.opengoal.audio.verbose 0 >/dev/null 2>&1 || true
device_stayon_restore 2>/dev/null || true

echo
echo "F2 device run: $DET — $NOTES"
exit 0

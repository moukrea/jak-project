#!/usr/bin/env bash
# Gjak2-render JAK1-ON-JAK2 enumerator run helper (instrumentation-only).
# Usage: j1onj2_run.sh <run_number>
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
N="$1"
OUT=/home/emeric/code/jak-project/.autoport/reports/Gjak2-render/jak2-j1onj2-run${N}.log

echo "=== RUN ${N} start $(date) ==="
"$ADB" -s eae4df44 shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
"$ADB" -s eae4df44 shell svc power stayon true >/dev/null 2>&1
"$ADB" -s eae4df44 shell am force-stop "$PKG"
sleep 2
"$ADB" -s eae4df44 logcat -c >/dev/null 2>&1
# background logcat
"$ADB" -s eae4df44 logcat -v time GK_STDOUT:V GK_STDERR:V opengoal-gk:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$OUT" 2>&1 &
LOGPID=$!
sleep 1
"$ADB" -s eae4df44 shell am start -n "${PKG}/${ACT}"
# wait ~150s
sleep 150
kill "$LOGPID" >/dev/null 2>&1
wait "$LOGPID" 2>/dev/null
echo "=== RUN ${N} done $(date); log lines: $(wc -l < "$OUT") ==="

#!/usr/bin/env bash
# harness_smoke.sh — Grecharged-buildsys-firstboot gate: prove the LIVE .autoport
# device harness has been migrated to the new on-device layout, and (optionally)
# that the device tree matches the new contract.
#
#   STATIC half (always): fail if any LIVE harness script still carries a stale
#     layout literal (old game-dir spelling, old settings filename/location, or the
#     retired engine-overlay path). Scope excludes reports/, validators/, gold/, the
#     migrator's own dir, and this script.
#   DEVICE half (skipped with SKIP_DEVICE=1 or when adb can't reach the device):
#     assert the new per-game external tree + settings.ini exist and are well-formed.
#
# Exit 0 only if every check that RAN passed.
#
# NOTE: uses [[ $var == *pat* ]] membership tests, never `echo | grep -q`, to dodge
# the pipefail+SIGPIPE false-fail class on large variables.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/device_env.sh
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
adb(){ "$ADB" "$@"; }

FAIL=0
note(){ echo "  $*"; }
bad(){ echo "FAIL: $*" >&2; FAIL=1; }

# ---- STATIC half -----------------------------------------------------------
echo "== harness_smoke STATIC: scan live harness for stale layout literals =="

# The LIVE harness = .autoport/lib/*.sh + .autoport/*.sh (root), MINUS this script.
# reports/, validators/, gold/, tools/ (except intentionally) are history/tooling.
mapfile -t LIVE < <(ls .autoport/lib/*.sh .autoport/*.sh 2>/dev/null | grep -v '/harness_smoke.sh$')

# Stale literals that MUST be gone from the live harness. Note: the ANDROID-INTERNAL
# config form `files/.config/OpenGOAL` is stale (internal mode deleted); the DESKTOP
# `~/.config/OpenGOAL/...` dir is UNCHANGED per contract, so we only flag the internal form.
STALE_LITERALS=(
  'jak_1'
  'pc-settings.gc'
  'files/.config/OpenGOAL'
  'files/iso_data'
)

for lit in "${STALE_LITERALS[@]}"; do
  hits=""
  for f in "${LIVE[@]}"; do
    # grep -F: literal match; -l: filename only. Guard each file individually.
    if grep -Fl -- "$lit" "$f" >/dev/null 2>&1; then
      hits+="    $f"$'\n'
    fi
  done
  if [ -n "$hits" ]; then
    bad "stale literal '$lit' still present in the live harness:"
    printf '%s' "$hits" >&2
  else
    note "ok: no '$lit' in live harness"
  fi
done

# ---- DEVICE half -----------------------------------------------------------
if [ "${SKIP_DEVICE:-0}" = 1 ]; then
  echo "== harness_smoke DEVICE: SKIPPED (SKIP_DEVICE=1) =="
elif ! adb -s "$S" get-state >/dev/null 2>&1; then
  echo "== harness_smoke DEVICE: SKIPPED (device $S not reachable) =="
else
  echo "== harness_smoke DEVICE: assert new on-device layout ($DEVICE_GAME_ROOT) =="
  for d in "$DEVICE_ASSETS" "$DEVICE_SAVES" "$DEVICE_CUSTOM_ASSETS"; do
    if adb -s "$S" shell "test -d '$d'" >/dev/null 2>&1; then
      note "ok: dir exists $d"
    else
      bad "missing device dir: $d"
    fi
  done
  if adb -s "$S" shell "test -f '$DEVICE_SETTINGS_INI'" >/dev/null 2>&1; then
    note "ok: settings file exists $DEVICE_SETTINGS_INI"
    FIRST=$(adb -s "$S" shell "head -1 '$DEVICE_SETTINGS_INI'" 2>/dev/null | tr -d '\r')
    if [[ $FIRST == '[settings]' ]]; then
      note "ok: settings.ini first line is [settings]"
    else
      bad "settings.ini first line is '$FIRST', expected [settings]"
    fi
  else
    bad "missing device settings file: $DEVICE_SETTINGS_INI"
  fi
fi

# ---- verdict ---------------------------------------------------------------
if [ "$FAIL" = 0 ]; then
  echo "HARNESS-SMOKE PASS"
  exit 0
else
  echo "HARNESS-SMOKE FAIL"
  exit 1
fi

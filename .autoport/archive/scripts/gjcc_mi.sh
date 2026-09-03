#!/usr/bin/env bash
# Reconstruction x86 de out/jak1/iso, verrou de livraison tenu par CE processus vivant.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOCK=".autoport/.deploy-in-progress"
_stale(){ [ -f "$1" ] || return 0
          local p; p=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$1" | head -1)
          [ -n "$p" ] || return 0
          kill -0 "$p" 2>/dev/null && return 1 || return 0; }
_own=0
for i in $(seq 1 60); do
  if _stale "$LOCK"; then printf 'gjcc_mi pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"; _own=1; break; fi
  sleep 5
done
[ "$_own" = 1 ] || { echo "FAIL: verrou tenu"; exit 1; }
trap '[ "$_own" = 1 ] && rm -f "$LOCK"' EXIT
for i in $(seq 1 60); do pgrep -x goalc >/dev/null 2>&1 || break; sleep 5; done
./build-x86/goalc/goalc --user-auto --game jak1 -c '(mi)' > .autoport/reports/Gjak1-crate-collision/runs/mi.log 2>&1
rc=$?
sed 's/\x1b\[[0-9;]*m//g' .autoport/reports/Gjak1-crate-collision/runs/mi.log | tail -25
exit $rc

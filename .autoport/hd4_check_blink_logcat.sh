#!/usr/bin/env bash
# hd4_check_blink_logcat.sh <logcat-file> <leg-name> <slot> [slot...]
# CYCLE-4 device-side blink assertions over a banked logcat (renderer counters, never captures):
#   per slot: [hd-blink] heartbeats present, donor_paints>0 in some window, stock_covered always 0,
#   lid excursion observed (some window lid_min<=0.5 = a blink closed, some window lid_max>=0.9 =
#   eyes open). Plus carried flicker BLACKOUT/GAP=0 over the same log.
set -uo pipefail
LC="$1"; LEG="$2"; shift 2
[ -f "$LC" ] || { echo "[$LEG FAIL] no logcat $LC"; exit 1; }
ok=1
stocklid=$(grep -ac '\[hd-blink\] STOCKLID' "$LC" || true)
echo "[$LEG] STOCKLID events: $stocklid (must be 0)"
[ "$stocklid" = 0 ] || ok=0
for s in "$@"; do
  hb=$(grep -a "\[hd-blink\] slot=$s " "$LC" | tr -d '\r')
  n=$(echo "$hb" | grep -c 'donor_paints' || true)
  if [ "$n" = 0 ]; then echo "[$LEG] FAIL slot=$s: no [hd-blink] heartbeat"; ok=0; continue; fi
  donor=$(echo "$hb" | grep -oE 'donor_paints=[0-9]+' | grep -cv 'donor_paints=0$' || true)
  stock=$(echo "$hb" | grep -oE 'stock_covered=[0-9]+' | grep -cv 'stock_covered=0$' || true)
  closed=$(echo "$hb" | awk 'match($0,/lid_min=([0-9.]+)/,m){ if (m[1]+0<=0.5) c++ } END{print c+0}')
  open=$(echo "$hb" | awk 'match($0,/lid_max=([0-9.]+)/,m){ if (m[1]+0>=0.9) c++ } END{print c+0}')
  echo "[$LEG] slot=$s heartbeats=$n donor-active-windows=$donor stock-nonzero-windows=$stock closed-windows(lid_min<=0.5)=$closed open-windows(lid_max>=0.9)=$open"
  [ "$donor" -ge 1 ] || { echo "[$LEG] FAIL slot=$s: no donor lid paints"; ok=0; }
  [ "$stock" = 0 ] || { echo "[$LEG] FAIL slot=$s: stock lid painted while covered"; ok=0; }
  [ "$closed" -ge 1 ] || { echo "[$LEG] FAIL slot=$s: lid never dipped <=0.5 — no visible blink"; ok=0; }
  [ "$open" -ge 1 ] || { echo "[$LEG] FAIL slot=$s: lid never opened >=0.9"; ok=0; }
done
evb=$(grep -ac '\[hd-flicker\] BLACKOUT' "$LC" || true)
evg=$(grep -ac '\[hd-flicker\] GAP' "$LC" || true)
echo "[$LEG] flicker BLACKOUT=$evb GAP=$evg (carried, must be 0/0)"
[ "$evb" = 0 ] && [ "$evg" = 0 ] || ok=0
if [ "$ok" = 1 ]; then echo "[$LEG blink-check PASS]"; exit 0; else echo "[$LEG blink-check FAIL]"; exit 1; fi

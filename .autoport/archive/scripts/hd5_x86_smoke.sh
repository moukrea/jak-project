#!/usr/bin/env bash
# hd5_x86_smoke.sh — M3 bonus looks x86-FIRST smoke (state-dumps-x86-first rule).
#
# Three legs against the same fresh build, driven ONLY by the per-character look settings
# (the new hd-look-* ints in settings.ini — the exact mechanism the menu carousells write):
#   LEG A "bonus":    jak=2 dax=2 keira=2 samos=2 -> jak2-hd/daxp-hd/keira3-hd/ysamos-hd
#                     ALL FOUR bonus models SUBMITTED found=1; the M1/M2 models must NOT submit
#                     (one companion per driver — the look REPLACES, never stacks).
#   LEG B "hd+jak3":  jak=3 dax=1 keira=1 samos=1 -> jak3-hd submits, and the look=1 path still
#                     drives the M2 primaries (dax-hd/keira-hd/samos-hd) through the NEW code.
#   LEG C "original": all 0 -> ZERO companions spawn, zero suppression: OriginaL look = pure stock
#                     even with enhanced fr3 selected.
# PASS bar per leg: boot OK, fr3-select GAME: ENHANCED, the leg's expected submit set (and
# forbidden set empty), no blerc-slot exhaustion, no crash markers, gk alive WATCH seconds.
# Visual quality stays the owner's call (code-level proof only).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models5; mkdir -p "$OUT"
R="$OUT/x86_smoke_bonus.txt"; : > "$R"
WATCH="${WATCH:-150}"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
say(){ echo "$*" | tee -a "$R"; }

# ---- staleness gates (never smoke a stale artifact) -------------------------------------------
[ -f "$ISO/GAME.CGO" ] || { say "FAIL: no $ISO/GAME.CGO"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd.gc"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/pckernel-impl.gc ] || { say "FAIL: GAME.CGO stale vs pckernel-impl.gc"; exit 1; }
ENH=out/jak1/fr3/enhanced/GAME.fr3
[ -f "$ENH" ] || { say "FAIL: no enhanced GAME.fr3 — bake first"; exit 1; }
for m in jak2-hd daxp-hd keira3-hd ysamos-hd jak3-hd; do
  # the bake log gate is upstream; here we just require the models to be IN the shipped fr3.
  # NB: audit exits 0 even for a missing model — gate on the OUTPUT naming the model (verified:
  # present model -> its name appears in the dump; missing -> zero mentions).
  # NB2: NO `| grep -q` here — with pipefail, grep -q's early exit SIGPIPEs the audit tool and
  # the pipeline reports 141 for models with large dumps (feedback_validator_pipefail_grep_q;
  # bit this exact script on 2026-08-05, deterministic on jak2-hd/jak3-hd). Capture + [[ == * ]].
  AUD=$(build/tools/hd_merc_swap/hd_merc_swap audit "$ENH" "$m-lod0" 2>&1 || true)
  [[ "$AUD" == *"$m-lod0"* ]] || { say "FAIL: $m-lod0 not in enhanced GAME.fr3"; exit 1; }
done
say "enhanced GAME.fr3 contains all 5 bonus models (audit probe)"

# ---- stage the 9 HD art-groups where -fakeiso loado finds them --------------------------------
mkdir -p out/jak1/obj
for c in jak-hd dax-hd keira-hd samos-hd jak2-hd jak3-hd daxp-hd keira3-hd ysamos-hd; do
  cp -f "recharged_assets/hd_anim/$c-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-ag.go"; exit 1; }
done
say "staged 9 HD art-groups into out/jak1/obj"

# ---- settings.ini manipulation (the same file the menu persists to) ---------------------------
[ -f "$INI" ] || { say "FAIL: no $INI (run gk once to create it)"; exit 1; }
cp "$INI" "$OUT/.settings.ini.pre-smoke"
set_ini(){ # set_ini <key> <value>
  # NEVER append at EOF: the file ends inside the [music] section and its sub-parser leaves an
  # extra key's value unconsumed -> "pc settings read error" -> the WHOLE tail of the file is
  # dropped and the looks silently run on defaults (bit this script 2026-08-05). Insert new keys
  # at TOP LEVEL, right after the recharged-enhanced-models? line.
  if grep -q "^$1 " "$INI"; then sed -i "s|^$1 .*|$1 = $2|" "$INI"
  else sed -i "/^recharged-enhanced-models? = /a $1 = $2" "$INI"
       grep -q "^$1 = $2$" "$INI" || { say "FAIL: could not insert $1 (no recharged-enhanced-models? anchor?)"; exit 1; }
  fi
}
restore_ini(){ [ -f "$OUT/.settings.ini.pre-smoke" ] && cp "$OUT/.settings.ini.pre-smoke" "$INI" || true; }
grep -q '^version = #x' "$INI" || { say "FAIL: settings.ini has no version stamp"; exit 1; }
if grep -q '^recharged-master? = #f' "$INI"; then say "FAIL: recharged-master? #f would force STOCK"; exit 1; fi
set_ini 'recharged-enhanced-models?' '#t'

GKPID=0
cleanup(){ [ "${GKPID:-0}" -gt 0 ] && kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; restore_ini; }
trap cleanup EXIT

run_leg(){ # run_leg <tag> <jak> <dax> <keira> <samos> <expect-csv> <forbid-csv>
  local TAG="$1" LJ="$2" LD="$3" LK="$4" LS="$5" EXPECT="$6" FORBID="$7"
  local GKLOG="$OUT/.smoke_gk_$TAG.log"; : > "$GKLOG"
  set_ini 'hd-look-jak' "$LJ"; set_ini 'hd-look-daxter' "$LD"
  set_ini 'hd-look-keira' "$LK"; set_ini 'hd-look-samos' "$LS"
  say ""
  say "=== LEG $TAG: hd-look jak=$LJ dax=$LD keira=$LK samos=$LS ==="
  "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
  GKPID=$!
  local booted=0 i
  for i in $(seq 1 150); do
    kill -0 "$GKPID" 2>/dev/null || { say "FAIL($TAG): gk exited during boot"; tail -25 "$GKLOG" >> "$R"; return 1; }
    grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { say "FAIL($TAG): boot timeout"; tail -25 "$GKLOG" >> "$R"; return 1; }
  say "booted — watching ${WATCH}s"
  sleep "$WATCH"
  local ALIVE=no; kill -0 "$GKPID" 2>/dev/null && ALIVE=yes
  local OK=1
  grep -aq 'HD-MODELS fr3-select GAME: ENHANCED' "$GKLOG" || { say "FAIL($TAG): GAME not ENHANCED"; OK=0; }
  local m
  if [ -n "$EXPECT" ]; then for m in ${EXPECT//,/ }; do
    if grep -aq "SUBMITTED name='$m-lod0' found=1" "$GKLOG"; then
      say "OK($TAG): $m-lod0 SUBMITTED found=1"
    else say "FAIL($TAG): $m-lod0 never submitted"; OK=0; fi
  done; fi
  if [ -n "$FORBID" ]; then for m in ${FORBID//,/ }; do
    if grep -aq "SUBMITTED name='$m-lod0' found=1" "$GKLOG"; then
      say "FAIL($TAG): forbidden $m-lod0 submitted (look did not replace)"; OK=0
    fi
  done; fi
  local NCOMP NOSLOT CRASH
  NCOMP=$(grep -ac '\[HD-COMP\] spawned' "$GKLOG" || true)
  NOSLOT=$(grep -ac 'no free blerc override slot' "$GKLOG" || true)
  CRASH=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$GKLOG" || true)
  say "leg $TAG: alive=$ALIVE spawn-lines=$NCOMP blerc-exhaustion=$NOSLOT crash-markers=$CRASH"
  [ "$ALIVE" = yes ] || OK=0
  [ "$NOSLOT" = 0 ] || OK=0
  [ "$CRASH" = 0 ] || OK=0
  if [ "$TAG" = "C-original" ]; then
    [ "$NCOMP" = 0 ] || { say "FAIL($TAG): companions spawned with all looks=0"; OK=0; }
    local NSUP; NSUP=$(grep -ac 'hd-render.*suppress pid=' "$GKLOG" || true)
    [ "$NSUP" = 0 ] || { say "FAIL($TAG): suppression active with all looks=0"; OK=0; }
    say "leg C: suppress-lines=$NSUP (must be 0)"
  fi
  kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; GKPID=0; sleep 2
  [ "$OK" = 1 ]
}

FAILED=0
run_leg "A-bonus"    2 2 2 2 "jak2-hd,daxp-hd,keira3-hd,ysamos-hd" "jak-hd,dax-hd,keira-hd,samos-hd,jak3-hd" || FAILED=1
run_leg "B-hd-jak3"  3 1 1 1 "jak3-hd,dax-hd,keira-hd,samos-hd"    "jak-hd,jak2-hd,daxp-hd,keira3-hd,ysamos-hd" || FAILED=1
run_leg "C-original" 0 0 0 0 ""                                     "jak-hd,dax-hd,keira-hd,samos-hd,jak2-hd,jak3-hd,daxp-hd,keira3-hd,ysamos-hd" || FAILED=1

say ""
if [ "$FAILED" = 0 ]; then say "[hd5 x86 smoke PASS] all three look-matrix legs green"; else say "[hd5 x86 smoke FAIL] see legs above"; fi
exit "$FAILED"

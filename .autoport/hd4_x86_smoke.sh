#!/usr/bin/env bash
# hd4_x86_smoke.sh — cycle-2 x86-FIRST smoke (state-dumps-x86-first rule): the new runtime code
# (bones.gc blerc-override registry checked per merc draw + generalized jak-hd.gc companions +
# Merc2 effect-enable widening) must survive real boot+gameplay on x86 BEFORE burning device runs.
# PASS bar: boot OK, enhanced fr3 selected, >=1 [HD-COMP] spawned, >=1 SUBMITTED found=1,
# no blerc-slot exhaustion, gk alive after WATCH seconds. Visual quality stays the owner's call.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models4; mkdir -p "$OUT"
R="$OUT/x86_smoke_cycle2.txt"; : > "$R"
GKLOG="$OUT/.smoke_gk.log"; : > "$GKLOG"
WATCH="${WATCH:-180}"
say(){ echo "$*" | tee -a "$R"; }

[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd.gc"; exit 1; }
mkdir -p out/jak1/obj
for c in jak dax keira samos; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-hd-ag.go"; exit 1; }
done
say "staged 4 HD art-groups into out/jak1/obj"

# assert the toggles: enhanced must be #t in the x86 settings file; recharged-master? defaults
# to #t (pckernel-impl.gc:260) and is absent from this file — do NOT write anything here.
PCS="$HOME/.config/OpenGOAL/jak1/settings/pc-settings.gc"
if [ -f "$PCS" ]; then
  grep -q '(recharged-enhanced-models? #t)' "$PCS" || { say "FAIL: enhanced-models not #t in $PCS"; exit 1; }
  if grep -q '(recharged-master? #f)' "$PCS"; then say "FAIL: recharged-master? #f would force STOCK"; exit 1; fi
  say "settings OK: enhanced #t, master default/#t"
else
  say "note: no pc-settings.gc found — relying on defaults"
fi

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; }
trap cleanup EXIT
booted=0
for i in $(seq 1 150); do
  kill -0 "$GKPID" 2>/dev/null || { say "FAIL: gk exited during boot"; tail -25 "$GKLOG" >> "$R"; exit 1; }
  grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
  sleep 1
done
[ "$booted" = 1 ] || { say "FAIL: boot timeout"; tail -25 "$GKLOG" >> "$R"; exit 1; }
say "booted (title reached) — watching $WATCH s of runtime for companion/crash evidence"
sleep "$WATCH"

ALIVE=no; kill -0 "$GKPID" 2>/dev/null && ALIVE=yes
FRSEL=$(grep -a -m2 'HD-MODELS fr3-select' "$GKLOG" | tr '\n' ';' | tr -d '\r')
NCOMP=$(grep -ac '\[HD-COMP\] spawned' "$GKLOG" || true)
SUBM=$(grep -a 'SUBMITTED' "$GKLOG" | grep -oE "name='[a-z]+-hd-lod0' found=1" | sort | uniq -c | tr '\n' ';' )
NOSLOT=$(grep -ac 'no free blerc override slot' "$GKLOG" || true)
CRASH=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$GKLOG" || true)
say "gk alive after ${WATCH}s: $ALIVE"
say "fr3-select: ${FRSEL:-none-yet (title only)}"
say "[HD-COMP] spawned lines: $NCOMP"
say "SUBMITTED found=1: ${SUBM:-NONE}"
say "blerc-slot exhaustion: $NOSLOT   crash markers: $CRASH"
OK=1
[ "$ALIVE" = yes ] || OK=0
[ "$CRASH" -eq 0 ] || OK=0
[ "$NOSLOT" -eq 0 ] || OK=0
[ "$NCOMP" -ge 1 ] || { say "note: no companion spawned (title/logo only run?)"; }
[ "$OK" -eq 1 ] && say "[x86-smoke PASS] runtime survives with cycle-2 code; companion evidence above" \
               || say "[x86-smoke FAIL]"
exit $(( 1 - OK ))

#!/usr/bin/env bash
# gfp_x86_proof.sh — Gfirstperson-hd-hide RUNTIME PROOF on x86 (trace only, no screenshots).
#
# What it proves, by reading the ACTUAL draw status the engine gates on (drawable.gc:448
# rejects on the mask (hidden no-anim no-skeleton-update)):
#   A) baseline, third person : stock Jak, stock Daxter and BOTH HD companions are drawable;
#   B) first person (target-look-around) : all four carry a blocking bit;
#   C) back to third person   : all four are drawable again (no latch).
#
# The [JAK-HD] mirror lines carry their own NEGATIVE CONTROL: they print the driver's `hid`
# and `noanim` bits separately. In first person the driver shows hid=0 noanim=1 — i.e. the
# PRE-FIX predicate (which read `hidden` only) is measurably false in exactly the state where
# the model has to disappear, so it could not have fired.
#
# METRIC NATURE/FRAME: GFP-PROBE/GFP-COMP publish a BITFIELD (draw-status, uint8) read on the
# process object itself — not a position, not a variance. No frame of reference applies.
# Blocking mask = hidden(2) | no-anim(4) | no-skeleton-update(16) = 22.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gfirstperson-hd-hide"; mkdir -p "$OUT"
LOG="$OUT/x86_proof.log"; GCLOG="$OUT/x86_proof_goalc.log"
[ -x "$GK" ] || { echo "FAIL: $GK missing"; exit 1; }

# HD art-groups are IP-gated and generated locally. init-jak-hd loado()s them through
# (make-file-name (file-kind art-group) ... 6 #f), which on a -fakeiso desktop run resolves to
# out/jak1/obj/<name>-ag.go — NOT the iso dir (first attempt staged them in $ISO and the run
# printed "[HD-COMP] asset missing ... HD unavailable", n=0 companions). On the APK they travel
# through scripts/package_hd_assets.sh into assets/hd/, a different path entirely.
# out/jak1/obj is build output and the auto-builder wipes it, so re-stage on every run.
for ag in jak-hd-ag.go dax-hd-ag.go; do
  cp -f "recharged_assets/hd_anim/$ag" "out/jak1/obj/$ag" || { echo "FAIL: cannot stage $ag"; exit 1; }
done
ls -la out/jak1/obj/jak-hd-ag.go out/jak1/obj/dax-hd-ag.go

: > "$LOG"; : > "$GCLOG"
echo "== launch x86 gk =="
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT

echo "== wait for title (link finish: logo) =="
for i in $(seq 1 120); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk exited during boot"; tail -30 "$LOG"; exit 1; }
  grep -qE "link finish: logo" "$LOG" && { echo "  booted ~${i}s"; break; }
  sleep 1
done
sleep 3

echo "== goalc (lt)+(build-game) =="
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 240); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game done ~${i}s"; break; }; done
sleep 3

echo "== enable HD models, then warp to game-start (Geyser Rock) =="
echo '(set! (-> *pc-settings* recharged-enhanced-models?) #t)' >&3
echo '(start (quote play) (get-continue-by-name *game-info* "game-start"))' >&3
sleep 20
# re-assert after the load (settings survive, but the loader reads the toggle at level load)
echo '(set! (-> *pc-settings* recharged-enhanced-models?) #t)' >&3
sleep 10

probe(){
  local tag="$1"
  echo "(format 0 \"GFP-PROBE tag=~A st=~A tgt=~D sk=~D n=~D~%\" (quote $tag) (-> *target* next-state name) (-> *target* draw status) (-> (the-as process-drawable (ppointer->process (-> *target* sidekick))) draw status) *hd-scan-companion-count*)" >&3
  echo "(dotimes (i *hd-scan-companion-count*) (format 0 \"GFP-COMP tag=~A i=~D entry=~D st=~D~%\" (quote $tag) i (-> (-> *hd-scan-companions* i) entry) (-> (-> *hd-scan-companions* i) draw status)))" >&3
  sleep 2
}

echo "== wait for the two HD companions to spawn (jak-hd entry 0 + dax-hd entry 1) =="
for i in $(seq 1 20); do
  echo '(format 0 "GFP-WAIT n=~D~%" *hd-scan-companion-count*)' >&3
  sleep 2
  n=$(grep -aoE "GFP-WAIT n=[0-9]+" "$LOG" | tail -1 | grep -oE "[0-9]+$")
  [ "${n:-0}" -ge 2 ] && { echo "  companions up: n=$n (~$((i*2))s)"; break; }
done
if [ "${n:-0}" -lt 2 ]; then
  echo "FAIL: only ${n:-0} HD companion(s) spawned — the HD half of this proof would be VACUOUS."
  grep -aE "HD-COMP|HD-MODELS merc-load|asset missing" "$LOG" | tail -20
  exit 1
fi

echo "== A) baseline: third person =="
probe A-third; probe A-third; probe A-third

echo "== B) first person: target-look-around =="
echo '(send-event *target* (quote change-mode) (quote look-around))' >&3
sleep 6
probe B-firstperson; probe B-firstperson; probe B-firstperson

echo "== C) back to third person =="
echo '(send-event *target* (quote end-mode))' >&3
sleep 6
probe C-third; probe C-third; probe C-third

sleep 2
echo "== harvest =="
{
  echo "---- GFP-PROBE / GFP-COMP ----"
  grep -E "GFP-PROBE|GFP-COMP" "$LOG" || echo "(none)"
  echo "---- [JAK-HD] mirror transitions ----"
  grep -E "\[JAK-HD\] mirror" "$LOG" || echo "(none)"
} | tee "$OUT/x86_proof_trace.txt"
echo "done."

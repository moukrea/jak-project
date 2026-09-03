#!/usr/bin/env bash
# gd3_x86_probe.sh — x86-FIRST reference dump for Gd3-jak-cinematic.
# Drives our-x86 gk into the NEW-GAME intro cinematic (same initialize! path the
# progress-menu NEW GAME runs: continue "intro-start"), then polls Jak's
# joint-control / draw-control / process-state every 1s. The key signal:
#   - is *target* (Jak) spawned?
#   - is its process state == process-drawable-art-error (= invisible art-error)?
#   - is each active joint channel's frame-group a valid art-joint-anim?
# Reads go to the TARGET stdout via (format 0 ...) -> captured from the gk log.
# Non-invasive: build-game hot-loads into the running target; out/ is gitignored;
# no source edits.  Env: REPO GK GOALC ISO OUTLOG (abs) POLLS (def 150)
set -uo pipefail
REPO="${REPO:-/home/emeric/code/jak-project}"
GK="${GK:-build-x86/game/gk}"
GOALC="${GOALC:-build-x86/goalc/goalc}"
ISO="${ISO:-out/jak1/iso}"
OUTLOG="${OUTLOG:-/home/emeric/code/jak-project/.autoport/reports/Gd3-jak/x86-probe.txt}"
POLLS="${POLLS:-150}"
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
cd "$REPO"
mkdir -p "$(dirname "$OUTLOG")"
GKLOG="$(mktemp)"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"
echo "[gd3] repo=$REPO gk=$GK polls=$POLLS log=$GKLOG"
[ -x "$GK" ] || { echo "[gd3] FAIL: $GK missing"; exit 1; }
env OG_GD3_CENSUS=1 "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 90); do kill -0 "$GKPID" 2>/dev/null || { echo "[gd3] gk exited during boot"; tail -20 "$GKLOG"; exit 1; }
  grep -qE "link finish: (default-menu|logo)($|-)" "$GKLOG" && { echo "[gd3] title up ~${i}s"; break; }; sleep 1; done
sleep 3
timeout $((POLLS+260)) "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --auto-lt < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
echo "[gd3] build-game sent; waiting up to 140s for symbol intern..."
for i in $(seq 1 140); do sleep 1; grep -qiE "Successfully built all|Build Successful|\] OK" "$GCLOG" 2>/dev/null && { echo "[gd3] build-game done ~${i}s"; break; }; done
sleep 4
echo "[gd3] triggering NEW-GAME intro cinematic (continue intro-start)"
echo "(begin (set! (-> *game-info* mode) (quote play)) (initialize! *game-info* (quote game) (the-as game-save #f) \"intro-start\") (set-master-mode (quote game)))" >&3
# Jak/draw/joint introspection (<=8 format args each; (format 0 ...) -> target stdout)
JAKFORM='(if *target* (let ((sk (-> *target* skel))) (format 0 "GD3JAK st=~A ac=~D ch0fg=~A ch0t=~A ch0ok=~A~%" (-> *target* state name) (-> sk active-channels) (-> sk channel 0 frame-group) (if (-> sk channel 0 frame-group) (-> sk channel 0 frame-group type) (quote nofg)) (if (-> sk channel 0 frame-group) (type-type? (-> sk channel 0 frame-group type) art-joint-anim) (quote no)))) (format 0 "GD3JAK no-target~%"))'
CH1FORM='(if (and *target* (>= (-> *target* skel active-channels) 2)) (let ((sk (-> *target* skel))) (format 0 "GD3JAK2 ch1fg=~A ch1t=~A ch1ok=~A drawstat=~A~%" (-> sk channel 1 frame-group) (if (-> sk channel 1 frame-group) (-> sk channel 1 frame-group type) (quote nofg)) (if (-> sk channel 1 frame-group) (type-type? (-> sk channel 1 frame-group type) art-joint-anim) (quote no)) (-> *target* draw status))))'
echo "[gd3] polling ${POLLS}x @1s for Jak joint/state"
for i in $(seq 1 "$POLLS"); do echo "$JAKFORM" >&3; echo "$CH1FORM" >&3; sleep 1; done
exec 3>&-
sleep 3
echo "[gd3] === GD3JAK samples ==="
grep -aE "GD3JAK" "$GKLOG" > "$OUTLOG" 2>/dev/null || true
tail -40 "$OUTLOG" || true
N=$(grep -ac 'GD3JAK ' "$GKLOG" 2>/dev/null || echo 0)
echo "[gd3] GD3JAK lines=$N -> $OUTLOG"
echo "[gd3] art-error / master-slot / dummy-19 signals in gk log:"
grep -aiE "art error for|could not find a master slot|dummy-19 bad|process-drawable-art-error" "$GKLOG" 2>/dev/null | sort | uniq -c | head -20 || true
echo "[gd3] === GD3-CENSUS (merc tris per bucket; jakdax = jak/daxter/sidekick model tris) ==="
grep -aE "GD3-CENSUS" "$GKLOG" 2>/dev/null | grep -aE "jakdax=[1-9]" | sort | uniq -c | sort -rn | head -15 || true
echo "[gd3] --- max jakdax tris seen per bucket ---"
grep -aoE "GD3-CENSUS bucket=[a-z0-9-]+ tris=[0-9]+ jakdax=[0-9]+" "$GKLOG" 2>/dev/null | awk '{b=$2; sub("bucket=","",b); j=$4; sub("jakdax=","",j); if(j+0>m[b]) m[b]=j+0} END{for(k in m) print k, "maxjakdax="m[k]}' | sort || true
grep -aE "GD3-CENSUS" "$GKLOG" 2>/dev/null > "${OUTLOG%.txt}.census.log" || true
echo "[gd3] census lines -> ${OUTLOG%.txt}.census.log ($(grep -ac GD3-CENSUS "$GKLOG" 2>/dev/null || echo 0) lines)"
echo "[gd3] === GD3-MERC (eichar visibility: enable_mask / VISIBLE tris / bones repaired) ==="
echo "[gd3] GD3-MERC lines: $(grep -ac 'GD3-MERC' "$GKLOG" 2>/dev/null || echo 0)"
echo "[gd3] max VISIBLE tris: $(grep -aoE 'visible=[0-9]+' "$GKLOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1)"
echo "[gd3] max repaired_total (should be 0 on x86): $(grep -aoE 'repaired_total=[0-9]+' "$GKLOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1)"
grep -aE 'GD3-MERC' "$GKLOG" 2>/dev/null | sed -E 's/.*(GD3-MERC model=[a-z0-9-]+ neff=[0-9]+ enable=0x[0-9a-f]+ ialpha=0x[0-9a-f]+ visible=[0-9]+ repaired_now=[0-9]+).*/\1/' | sort | uniq -c | sort -rn | head -10 || true
grep -aE 'GD3-MERC' "$GKLOG" 2>/dev/null > "${OUTLOG%.txt}.jakdraw.log" || true
echo "[gd3] level markers:"; grep -aE "link finish: (intro|misty|village1|training)|GAMEPLAY: enter" "$GKLOG" 2>/dev/null | tail -12 || true
cp -f "$GKLOG" "${OUTLOG%.txt}.gk.log" 2>/dev/null || true
cp -f "$GCLOG" "${OUTLOG%.txt}.goalc.log" 2>/dev/null || true
echo "[gd3] done."

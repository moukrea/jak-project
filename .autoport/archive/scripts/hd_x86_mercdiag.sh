#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; GOALC=build/goalc/goalc; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
OUT=.autoport/reports/hd-models3; mkdir -p "$OUT"; R="$OUT/mercdiag.txt"; : > "$R"
GKLOG="$OUT/.md_gk.log"; GCLOG="$OUT/.md_gc.log"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cp -f recharged_assets/hd_anim/jak-hd-ag.go "$ISO/jak-hd-ag.go" 2>/dev/null
"$GK" --game jak1 --portable -fakeiso --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 45); do kill -0 "$GKPID" 2>/dev/null || { echo "gk died"|tee -a "$R"; tail -12 "$GKLOG">>"$R"; exit 1; }; sleep 1; done
timeout 400 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!; exec 3>"$FIFO"
echo '(lt)' >&3; sleep 3; echo '(build-game)' >&3
for i in $(seq 1 160); do sleep 1; grep -qiE "Successfully built all" "$GCLOG" 2>/dev/null && break; done
sleep 3
echo '(set! (-> *pc-settings* recharged-enhanced-models?) #t)' >&3
echo '(start (quote play) (get-continue-by-name *game-info* "game-start"))' >&3
for i in $(seq 1 45); do echo '(when *target* (format 0 "TGT-READY~%"))' >&3; sleep 2; grep -qa TGT-READY "$GKLOG" 2>/dev/null && break; done
sleep 12
echo "=== [jak-hd-render] SUBMIT log (fires if the companion draws jak-hd-lod0) ===" | tee -a "$R"
grep -ha "jak-hd-render" "$GKLOG" 2>/dev/null | tee -a "$R"
echo "=== jak-hd merc-loaded by renderer? ===" | tee -a "$R"
grep -hai "merc-load.*jak-hd\|jak-hd-lod0" "$GKLOG" 2>/dev/null | tail -3 | tee -a "$R"
echo "=== companion [JAK-HD] + spawned? ===" | tee -a "$R"
grep -ha "\[JAK-HD\]\|TGT-READY" "$GKLOG" 2>/dev/null | tail -4 | tee -a "$R"
grep -q "jak-hd-render" "$R" && echo "RESULT: companion SUBMITS the merc" >>"$R" || echo "RESULT: companion does NOT submit the merc (draw-path bug)" >>"$R"

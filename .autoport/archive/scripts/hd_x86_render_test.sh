#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; GOALC=build/goalc/goalc; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
OUT=.autoport/reports/hd-models3; mkdir -p "$OUT"; R="$OUT/render-test.txt"; : > "$R"
GKLOG="$OUT/.rt_gk.log"; GCLOG="$(mktemp)"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cp -f recharged_assets/hd_anim/jak-hd-ag.go "$ISO/jak-hd-ag.go" 2>/dev/null
"$GK" --game jak1 --portable -fakeiso --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 200); do kill -0 "$GKPID" 2>/dev/null || { echo "gk died"|tee -a "$R"; tail -15 "$GKLOG">>"$R"; exit 1; }; grep -qE "link finish: logo-loop" "$GKLOG" && break; sleep 1; done
sleep 6
timeout 400 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!; exec 3>"$FIFO"
echo '(lt)' >&3; echo '(build-game)' >&3
for i in $(seq 1 160); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
sleep 3
echo '(set! (-> *pc-settings* recharged-enhanced-models?) #t)' >&3
echo '(start (quote play) (get-continue-by-name *game-info* "game-start"))' >&3
for i in $(seq 1 40); do echo '(when *target* (format 0 "TGT-READY~%"))' >&3; sleep 2; grep -qa TGT-READY "$GKLOG" 2>/dev/null && break; done
sleep 10   # let the companion spawn + its f60/f150 bone-dump fire from its OWN :post
echo "=== companion spawn + its OWN bone read ([JAK-HD]) ===" | tee -a "$R"
grep -ha "\[JAK-HD\]" "$GKLOG" 2>/dev/null | tail -6 | tee -a "$R"
echo "=== merc-load: is jak-hd-lod0 loaded by the renderer? ===" | tee -a "$R"
grep -haiE "merc-load.*jak-hd|jak-hd-lod0|HD-MODELS merc" "$GKLOG" 2>/dev/null | tail -5 | tee -a "$R"
echo "=== crash? ===" | tee -a "$R"
grep -haiE "crash|signal|SIGSEGV|art-error|could not" "$GKLOG" 2>/dev/null | tail -3 | tee -a "$R"

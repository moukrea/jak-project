#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; GOALC=build/goalc/goalc; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
OUT=.autoport/reports/hd-models3; mkdir -p "$OUT"; R="$OUT/render-inspect.txt"; : > "$R"
GKLOG="$OUT/.ri_gk.log"; GCLOG="$OUT/.ri_gc.log"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cp -f recharged_assets/hd_anim/jak-hd-ag.go "$ISO/jak-hd-ag.go" 2>/dev/null
"$GK" --game jak1 --portable -fakeiso --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
# robust: wait until gk has been up 40s (past IOP/kernel init) regardless of the logo-loop marker
for i in $(seq 1 60); do kill -0 "$GKPID" 2>/dev/null || { echo "gk died at boot"|tee -a "$R"; tail -15 "$GKLOG">>"$R"; exit 1; }; sleep 1; done
timeout 400 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!; exec 3>"$FIFO"
echo '(lt)' >&3; sleep 3
echo '(build-game)' >&3
for i in $(seq 1 160); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
sleep 3
echo '(set! (-> *pc-settings* recharged-enhanced-models?) #t)' >&3
echo '(start (quote play) (get-continue-by-name *game-info* "game-start"))' >&3
for i in $(seq 1 45); do echo '(when *target* (format 0 "TGT-READY~%"))' >&3; sleep 2; grep -qa TGT-READY "$GKLOG" "$GCLOG" 2>/dev/null && break; done
sleep 10
# INSPECT the render path of the companion
P='(begin
  (if (and *jak-hd-process* (nonzero? (-> *jak-hd-process* 0)))
    (let ((h (-> *jak-hd-process* 0)))
      (format 0 "RI hd-alive skel=~D drawstat=~D~%" (if (nonzero? (-> h draw skeleton)) (-> h draw skeleton length) -1) (-> h draw status))
      (format 0 "RI hd-mgeo=~D lod-count=~D~%" (-> h draw mgeo) (-> h draw lod-count))
      (format 0 "RI hd-bone4=(~f ~f ~f) tgt-bone4=(~f ~f ~f)~%"
        (-> h draw skeleton bones 4 transform vector 3 x) (-> h draw skeleton bones 4 transform vector 3 y) (-> h draw skeleton bones 4 transform vector 3 z)
        (-> *target* draw skeleton bones 4 transform vector 3 x) (-> *target* draw skeleton bones 4 transform vector 3 y) (-> *target* draw skeleton bones 4 transform vector 3 z))
      (format 0 "RI tgt-drawstat=~D (skip-bones bit5)~%" (-> *target* draw status)))
    (format 0 "RI hd-NONE (companion not spawned)~%")))'
for t in 1 2 3; do echo "$P" >&3; sleep 4; grep -qa "RI " "$GKLOG" "$GCLOG" && break; done
echo "=== companion [JAK-HD] logs ===" | tee -a "$R"; grep -ha "\[JAK-HD\]" "$GKLOG" 2>/dev/null | tail -5 | tee -a "$R"
echo "=== render inspect ===" | tee -a "$R"; grep -ha "RI " "$GKLOG" "$GCLOG" 2>/dev/null | grep -v "format 0" | sort -u | tee -a "$R"
echo "=== is jak-hd-lod0 merc-loaded by the renderer? ===" | tee -a "$R"; grep -hai "jak-hd-lod0\|merc-load.*jak-hd" "$GKLOG" 2>/dev/null | tail -3 | tee -a "$R"

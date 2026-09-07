#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
notes=.autoport/reports/lighting-census/notes
data="$notes/essai17-rpc"
mkdir -p "$data"
# Refuse a live build before pausing the verified idle builder; restore it on exit.
python3 - <<'PYCHECK'
from pathlib import Path
import subprocess
p=2541075
assert Path(f'/proc/{p}/cmdline').read_bytes().split(b'\0')[:2] == [b'bash', b'.autoport/auto_build_apk.sh']
assert subprocess.check_output(['ps', '--ppid', str(p), '-o', 'comm='], text=True).split() == ['sleep']
assert not Path('.autoport/.deploy-in-progress').exists()
PYCHECK
builder=2541075
trap 'kill -CONT "$builder"' EXIT
kill -STOP "$builder"
sha256sum -c "$notes/refs-before-essai12.sha256" > "$data/historical-before.log"
git rev-parse HEAD > "$data/fork-head.txt"
git diff --binary HEAD -- game common goal_src goalc android > "$data/fork-source.patch"
sha256sum build/game/gk out/jak1/iso/GAME.CGO out/jak1/iso/ENGINE.CGO \
  out/jak1/iso/KERNEL.CGO .autoport/refset/neutral.inputs > "$data/fork-inputs.sha256"
export DISPLAY="${DISPLAY:-:0}" SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
if [ -z "${XAUTHORITY:-}" ]; then
  for x in /run/user/"$(id -u)"/.mutter-Xwaylandauth.*; do
    [ ! -e "$x" ] || export XAUTHORITY="$x"
  done
fi
export OG_BOOT_REPLAY_BOUNDARY=actors-sweep
export OG_BOOT_REPLAY_CONTINUE=village1-hut
export OG_REFSET=replay OG_REFSET_DIR=.autoport/refset
export OG_REFSET_VANTAGES=legacy OG_REFSET_PHASES=1 OG_REFSET_HOURS=0
export OG_RECHARGED=0 OG_LIGHTING=0 OG_RT_LIGHT=0
export OG_LEVEL_WARP=village1-hut OG_LEVEL_WARP_POS='-116 14 40'
export OG_WANT_LEVELS=village1,beach OG_WANT_DISPLAY=beach,display
export OG_PAD_REPLAY_REPLAY=.autoport/refset/neutral.inputs
export OG_PACE_MEASURE=1 AUTOPORT_FEATURE=lighting-census AUTOPORT_FEATURE_ARMED=1
# One short bootstrap recording, followed by the single official replay proof.
# No reference image is captured, replaced or qualified by this stream.
set +e
OG_BOOT_REPLAY_CAPTURE="$data/fork-bootstrap.bin" \
  stdbuf -oL -eL timeout -k 5 20 build/game/gk --game jak1 --portable \
  -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem \
  > "$data/fork-bootstrap-capture.log" 2>&1
capture_rc=$?
set -e
printf 'bootstrap_capture_rc=%s\n' "$capture_rc"
grep -aE 'BOOTREPLAY (finish|error|actors-sweep|invalid)' "$data/fork-bootstrap-capture.log" || true
export OG_BOOT_REPLAY_REPLAY="$data/fork-bootstrap.bin"
set +e
AUTOPORT_PROOF_WAIT_MAX=300 bash .autoport/lib/proof_run.sh lighting-census x86 --timeout 60 \
  > "$notes/proof-run-rpc-essai17.log" 2>&1
proof_rc=$?
set -e
printf 'proof_run_rc=%s\n' "$proof_rc"
sha256sum -c "$notes/refs-before-essai12.sha256" > "$data/historical-after.log"
sha256sum -c "$data/fork-inputs.sha256" > "$data/fork-inputs-after.log"
grep -aE '^BOOTREPLAY (finish|error|actors-sweep|invalid)|^REFSET done' .autoport/reports/lighting-census/proof-engine.log

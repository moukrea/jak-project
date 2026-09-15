#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
N="$PWD/.autoport/reports/perf-codegen-arm64-calls/notes/a2-final"
LOCK="$PWD/.autoport/.deploy-in-progress"
exec 8> .autoport/.delivery-artifacts.lock
flock -n -x 8 || exit 3
if [ -e "$LOCK" ]; then
  p=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
    echo "construction concurrente pid=$p" >&2; exit 3
  fi
  unlink "$LOCK"
fi
(set -o noclobber; printf '%s pid=%s\n' "$0" "$$" > "$LOCK")
OBJ_MOVED=0
restore() {
  local rc=$?
  if [ "$OBJ_MOVED" = 1 ]; then
    mv out/jak1/obj "$N/obj-arm64-generated"
    mv "$N/obj-original" out/jak1/obj
  fi
  if [ -d "$N/iso-original" ]; then
    cp -p "$N/iso-original/"*.CGO "$N/iso-original/"*.DGO out/jak1/iso/
  fi
  unlink "$LOCK"
  exit "$rc"
}
trap restore EXIT
mkdir "$N/iso-original" "$N/iso-arm64-generated"
cp -p out/jak1/iso/*.CGO out/jak1/iso/*.DGO "$N/iso-original/"
sha256sum out/jak1/iso/*.CGO out/jak1/iso/*.DGO > "$N/x86-cgos-before.sha256"
mv out/jak1/obj "$N/obj-original"
OBJ_MOVED=1
mkdir out/jak1/obj
mkdir -p "$N/tmp"
export TMPDIR="$N/tmp"
export LC_ALL=C
build-arm64/goalc/goalc --version
build-arm64/goalc/goalc --user-auto --game jak1 --disable-ansi \
  -c '(make-group "iso" :force #t)' > "$N/regen-arm64.log" 2>&1
grep -aE 'Successfully built all [0-9]+ targets' "$N/regen-arm64.log"
cp -p out/jak1/iso/*.CGO out/jak1/iso/*.DGO "$N/iso-arm64-generated/"
test "$(find "$N/iso-arm64-generated" -maxdepth 1 -type f | wc -l)" = 28
# The new normal-function prologue banks X3/X5 after FP/LR.
# Check actual emitted bytes in both delivered archives.
for archive in GAME.CGO ENGINE.CGO; do
  grep -aobP '\xfd\x7b\xbf\xa9\xfd\x03\x00\x91\xe3\x17\xbf\xa9' "$N/iso-arm64-generated/$archive" > "$N/$archive-call-markers.log"
  printf '%s callee_save_prologues=%s\n' "$archive" "$(wc -l < "$N/$archive-call-markers.log")"
done
mv out/jak1-arm64-full/iso "$N/iso-arm64-before"
mv "$N/iso-arm64-generated" out/jak1-arm64-full/iso
sha256sum out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO > "$N/arm64-cgos-after.sha256"

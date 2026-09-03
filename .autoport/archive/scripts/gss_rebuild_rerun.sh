#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gsubtitle-style
GOALC=build-x86/goalc/goalc; ISO=out/jak1/iso; SNAP=/home/emeric/.autoport-scratch/gss-iso
LOCK=.autoport/.deploy-in-progress
printf 'gss_rebuild pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" --disable-ansi --cmd '(mi)' > "$OUT/x86-mi.log" 2>&1
grep -q "Successfully built all" "$OUT/x86-mi.log" || { echo "(mi) KO"; rm -f "$LOCK"; exit 1; }
rm -rf "$SNAP"; cp -a --reflink=auto "$ISO" "$SNAP"
echo "snapshot refait : $(md5sum "$SNAP/GAME.CGO" | cut -c1-12)"
rm -f "$LOCK"
exec bash .autoport/gss_run3.sh

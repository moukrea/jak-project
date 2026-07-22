#!/usr/bin/env bash
# gbt_evidence.sh — Grecharged-bundled-textures device evidence, staged (clone of gmt_evidence.sh).
# Stages:
#   abset texon|texoff|masteroff|texon_pbr|prec   configure settings.ini (app force-stopped first)
#     texon      master ON,  recharged-textures ON,  everything else stock  -> owner textures
#     texoff     master ON,  recharged-textures OFF, everything else stock  -> stock (toggle gate)
#     masteroff  master OFF, recharged-textures ON                          -> stock (master gate)
#     texon_pbr  texon + pbr-materials ON                                   -> bundled PBR maps
#     prec       texon + load-custom-assets ON (user override pushed by 'precpush')
#   cap <tag>    boot at the pinned vantage (village1-hut, TOD noon, native render scale),
#                screenrecord, settled frame -> device/<tag>.png + logcat-<tag>.log
#   compare      texon vs texoff MUST MISMATCH (owner textures land);
#                texoff vs masteroff MUST MATCH (toggle-OFF == stock == master-OFF ⇒ OFF==stock
#                and the master contract in one gate)
#   pbrcheck     logcat-texon_pbr must show 'custom pbr map (bundled)' _normal/_roughness/_height
#                loads + 'custom pbr material registered' for the owner texture names
#   precpush     build a garish magenta user override PNG and push it to the USER drop dir
#   preccheck    logcat-prec must show 'custom texture replacement (user)' for the overridden name
#                AND '(bundled)' for the others; frame prec.png MUST MISMATCH texon.png (roof went
#                magenta => user custom_assets WINS over bundled); then REMOVES the user file
#   menu <stage> boot|nav|texflip|greych|texflipback — the user flow on the new row
#   cleanup      clear props, remove user override, force-stop
#
# Vantage/beat: village1-hut pos '-112.0 42.0 205.0' (owner vantage — hut roof tiles + straw +
# plaster all in frame, the exact surfaces the owner retextured), TOD pinned noon, native scale.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-bundled-textures/device; mkdir -p "$OUT"
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
USER_DROP="/storage/emulated/0/OpenGOAL/jak1/custom_assets"
INJECT="/data/data/$PKG/files/cpad_inject"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gbt-ev FAIL] $*" >&2; exit 1; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
fg_require(){ local f; f=$(fg); echo "  focus: $f"; case "$f" in *org.opengoal.gk.jak1*) : ;; *) die "jak1 not foreground: $f";; esac }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1 ($(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0)B)"; }
disk_key(){ adb shell cat "$PCS" 2>/dev/null | grep -aE "^$1" | tr -d '\r'; }

set_kv(){ # set_kv <file> <key-regex-escaped> <value-line>  (ERE on both sides — see gmt fix)
  local f="$1" k="$2" v="$3"
  if grep -qE "^$k = " "$f"; then sed -i -E "s/^$k = .*/$v/" "$f"; else sed -i "/^\[secrets\]/i $v" "$f"; fi
}

settings_config(){ # texon | texoff | masteroff | texon_pbr | prec
  adb shell am force-stop $PKG; sleep 2
  adb shell cat "$PCS" > /tmp/gbt_pcs.ini 2>/dev/null || die "cannot read $PCS"
  tr -d '\r' < /tmp/gbt_pcs.ini > /tmp/gbt_pcs2.ini && mv /tmp/gbt_pcs2.ini /tmp/gbt_pcs.ini
  # Pin the version line to THIS build's GOAL pckernel version (stale minor => GOAL discards
  # the whole file and every A/B config silently runs defaults — bit the gmt phase).
  grep -q 'static-pckernel-version 1 11 0 0' goal_src/jak1/pc/pckernel-impl.gc \
    || die "GOAL pckernel version no longer 1 11 0 0 — update the pinned hex below"
  set_kv /tmp/gbt_pcs.ini 'version' 'version = #x1000b00000000'
  # Common baseline: every OTHER recharged feature at stock so the ONLY frame diff source is
  # the texture path under test. AO stays 0 (safe-boot sentinel, see gmt notes).
  set_kv /tmp/gbt_pcs.ini 'recharged-grass\?' 'recharged-grass? = #f'
  set_kv /tmp/gbt_pcs.ini 'pbr-materials\?' 'pbr-materials? = #f'
  set_kv /tmp/gbt_pcs.ini 'realtime-lighting\?' 'realtime-lighting? = #f'
  set_kv /tmp/gbt_pcs.ini 'recharged-foliage-wind\?' 'recharged-foliage-wind? = #f'
  set_kv /tmp/gbt_pcs.ini 'ambient-occlusion' 'ambient-occlusion = 0'
  set_kv /tmp/gbt_pcs.ini 'recharged-enhanced-models\?' 'recharged-enhanced-models? = #f'
  set_kv /tmp/gbt_pcs.ini 'load-custom-assets\?' 'load-custom-assets? = #f'
  case "$1" in
    texon)
      set_kv /tmp/gbt_pcs.ini 'recharged-master\?' 'recharged-master? = #t'
      set_kv /tmp/gbt_pcs.ini 'recharged-textures\?' 'recharged-textures? = #t'
      ;;
    texoff)
      set_kv /tmp/gbt_pcs.ini 'recharged-master\?' 'recharged-master? = #t'
      set_kv /tmp/gbt_pcs.ini 'recharged-textures\?' 'recharged-textures? = #f'
      ;;
    masteroff) # master OFF must force stock even with the texture toggle ON
      set_kv /tmp/gbt_pcs.ini 'recharged-master\?' 'recharged-master? = #f'
      set_kv /tmp/gbt_pcs.ini 'recharged-textures\?' 'recharged-textures? = #t'
      ;;
    texon_pbr) # bundled PBR maps path: textures ON + PBR ON
      set_kv /tmp/gbt_pcs.ini 'recharged-master\?' 'recharged-master? = #t'
      set_kv /tmp/gbt_pcs.ini 'recharged-textures\?' 'recharged-textures? = #t'
      set_kv /tmp/gbt_pcs.ini 'pbr-materials\?' 'pbr-materials? = #t'
      ;;
    prec) # precedence: user drop dir override (pushed by precpush) + bundled both active
      set_kv /tmp/gbt_pcs.ini 'recharged-master\?' 'recharged-master? = #t'
      set_kv /tmp/gbt_pcs.ini 'recharged-textures\?' 'recharged-textures? = #t'
      set_kv /tmp/gbt_pcs.ini 'load-custom-assets\?' 'load-custom-assets? = #t'
      ;;
    *) die "unknown config $1";;
  esac
  adb push /tmp/gbt_pcs.ini /data/local/tmp/gbt_pcs.ini >/dev/null 2>&1 || die "push failed"
  adb shell cp /data/local/tmp/gbt_pcs.ini "$PCS" || die "cp to settings failed"
  adb shell cat "$PCS" | tr -d '\r' | grep -q '^version = #x1000b00000000$' || die "version pin did not land on device"
  echo "  config '$1' applied:"; adb shell cat "$PCS" | grep -aE '^(version|recharged-master|recharged-textures|load-custom-assets|pbr-materials|recharged-grass|realtime-lighting|recharged-foliage-wind|ambient-occlusion)' | sed 's/^/    /'
}

warp_props(){
  adb shell setprop debug.opengoal.level.warp village1-hut
  adb shell "setprop debug.opengoal.level.warp.pos '-112.0 42.0 205.0'"
  adb shell setprop debug.opengoal.tod.hour 1200
  adb shell setprop debug.opengoal.renderscale.native 1
}
clear_props(){
  adb shell setprop debug.opengoal.level.warp '""'
  adb shell setprop debug.opengoal.level.warp.pos '""'
  adb shell setprop debug.opengoal.tod.hour '""'
  adb shell setprop debug.opengoal.renderscale.native '""'
}

boot_to_vantage(){ # <tag> — waits for LEVEL-WARP-SPAWN + settle; logs scanner/pbr lines
  adb shell am force-stop $PKG; sleep 2
  pkill -f "$ADB -s $S logcat" 2>/dev/null; sleep 1   # cross-session log bleed guard (gmt)
  adb logcat -c 2>/dev/null || true
  warp_props
  LOG="$OUT/logcat-$1.log"; : > "$LOG"
  ( adb logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|custom texture replacement|custom pbr|recharged-master|PC [Kk]ernel version|Fatal signal|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
    grep -aq 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && break; sleep 5
  done
  grep -aq 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" || die "no LEVEL-WARP-SPAWN in 300s (log $LOG)"
  echo "  spawned; settling 20s (static camera, pinned TOD)"; sleep 20
  fg_require
}

grab_frame(){ # <tag> — screenrecord (GL surface; screencap is black on it), last frame
  adb shell screenrecord --time-limit 6 --bit-rate 8000000 /sdcard/gbt_$1.mp4
  adb pull /sdcard/gbt_$1.mp4 /tmp/gbt_$1.mp4 >/dev/null 2>&1 || die "pull rec failed"
  adb shell rm -f /sdcard/gbt_$1.mp4
  rm -rf /tmp/gbt_frames_$1; mkdir -p /tmp/gbt_frames_$1
  ffmpeg -y -loglevel error -i /tmp/gbt_$1.mp4 -vf fps=2 /tmp/gbt_frames_$1/f_%03d.png
  local last; last=$(ls /tmp/gbt_frames_$1/f_*.png | tail -1)
  [ -n "$last" ] || die "no frames extracted for $1"
  cp "$last" "$OUT/$1.png"; echo "  frame -> $OUT/$1.png"
  rm -rf /tmp/gbt_frames_$1 /tmp/gbt_$1.mp4   # don't hoard capture intermediates (owner rule)
}

case "${1:?stage}" in
abset) settings_config "${2:?texon|texoff|masteroff|texon_pbr|prec}";;
cap)
  TAG=${2:?tag}
  boot_to_vantage "$TAG"
  grab_frame "$TAG"
  adb shell am force-stop $PKG
  ;;
compare)
  echo "== discrimination: texon vs texoff MUST MISMATCH (owner textures visibly land) =="
  python3 .autoport/lib/frame_compare.py "$OUT/texoff.png" "$OUT/texon.png" --threshold 24 --tolerance 0.02 \
    --diff "$OUT/diff_texon_vs_texoff.png" | tee "$OUT/compare_texon_texoff.txt" || true
  echo "== OFF==stock + master contract: texoff vs masteroff MUST MATCH =="
  python3 .autoport/lib/frame_compare.py "$OUT/texoff.png" "$OUT/masteroff.png" --threshold 24 --tolerance 0.02 \
    --diff "$OUT/diff_texoff_vs_masteroff.png" | tee "$OUT/compare_off_stock.txt"
  grep -q '^MISMATCH ' "$OUT/compare_texon_texoff.txt" || die "texon vs texoff did not MISMATCH (textures not landing)"
  grep -q '^MATCH ' "$OUT/compare_off_stock.txt" || die "texoff vs masteroff did not MATCH (OFF != stock)"
  echo "  bundled scanner lines (texon boot):"; grep -a 'custom texture replacement (bundled)' "$OUT/logcat-texon.log" | head -8
  grep -aq 'custom texture replacement (bundled): village1-vis-tfrag' "$OUT/logcat-texon.log" \
    || die "texon logcat has no bundled village1-vis-tfrag replacement lines"
  grep -a 'custom texture replacement (bundled)' "$OUT/logcat-texoff.log" | grep -q . \
    && die "texoff logcat still shows bundled replacements (toggle not gating!)"
  grep -a 'custom texture replacement' "$OUT/logcat-masteroff.log" | grep -q . \
    && die "masteroff logcat still shows replacements (master not gating!)"
  echo "[gbt-ev compare] PASS"
  ;;
pbrcheck)
  L="$OUT/logcat-texon_pbr.log"
  [ -f "$L" ] || die "no $L — run: abset texon_pbr && cap texon_pbr first"
  echo "== bundled PBR maps consumed under PBR ON =="
  for sfx in _normal _roughness _height; do
    grep -aq "custom pbr map (bundled): village1-vis-tfrag/.*$sfx" "$L" \
      || die "no bundled $sfx map load in $L"
    echo "  $sfx: $(grep -ac "custom pbr map (bundled): village1-vis-tfrag/.*$sfx" "$L") loads"
  done
  grep -aq 'custom pbr material registered: vil' "$L" || die "no pbr material registered for vil* textures"
  echo "  registered:"; grep -a 'custom pbr material registered: vil' "$L" | head -8
  echo "[gbt-ev pbrcheck] PASS"
  ;;
precpush)
  # a garish 64x64 solid-magenta override for ONE owner texture, in the USER drop dir —
  # bare-name key, exactly how a user would drop a file. Removed by preccheck/cleanup.
  python3 - "$OUT" <<'EOF'
import sys, struct, zlib, os
out = sys.argv[1]
w = h = 64
raw = b''.join(b'\x00' + b'\xff\x00\xff\xff' * w for _ in range(h))  # magenta RGBA rows
def chunk(t, d):
    c = struct.pack('>I', len(d)) + t + d
    return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw))
       + chunk(b'IEND', b''))
p = os.path.join(out, 'user-override-vil-hut-roof-tile-01.png')
open(p, 'wb').write(png)
print('  wrote', p, len(png), 'bytes')
EOF
  adb shell mkdir -p "$USER_DROP"
  adb push "$OUT/user-override-vil-hut-roof-tile-01.png" "$USER_DROP/vil-hut-roof-tile-01.png" || die "push user override failed"
  adb shell ls -la "$USER_DROP/vil-hut-roof-tile-01.png"
  echo "[gbt-ev precpush] user override in place ($USER_DROP/vil-hut-roof-tile-01.png)"
  ;;
preccheck)
  L="$OUT/logcat-prec.log"
  [ -f "$L" ] || die "no $L — run: precpush && abset prec && cap prec first"
  echo "== precedence: user custom_assets WINS over bundled =="
  grep -aq 'custom texture replacement (user): village1-vis-tfrag/vil-hut-roof-tile-01' "$L" \
    || die "overridden texture did not come from the USER dir"
  grep -a 'custom texture replacement (bundled)' "$L" | grep -q 'village1-vis-tfrag' \
    || die "non-overridden textures no longer bundled (expected user WINS only for the one file)"
  grep -a 'custom texture replacement (bundled): village1-vis-tfrag/vil-hut-roof-tile-01$' "$L" | grep -q . \
    && die "overridden texture ALSO loaded from bundle (precedence broken)"
  echo "  user line:";    grep -a 'custom texture replacement (user)' "$L" | head -2
  echo "  bundled lines:"; grep -a 'custom texture replacement (bundled)' "$L" | head -4
  echo "== frame: prec vs texon MUST MISMATCH (magenta roof) =="
  python3 .autoport/lib/frame_compare.py "$OUT/texon.png" "$OUT/prec.png" --threshold 24 --tolerance 0.02 \
    --diff "$OUT/diff_prec_vs_texon.png" | tee "$OUT/compare_prec_texon.txt" || true
  grep -q '^MISMATCH ' "$OUT/compare_prec_texon.txt" || die "prec vs texon did not MISMATCH (user override invisible)"
  adb shell rm -f "$USER_DROP/vil-hut-roof-tile-01.png"
  echo "  user override removed from device"
  echo "[gbt-ev preccheck] PASS"
  ;;
menu)
  ST=${2:?boot|nav|texflip|greych|texflipback}
  case "$ST" in
  boot)
    settings_config texon
    clear_props
    adb logcat -c 2>/dev/null || true
    adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    echo "  waiting 75s for title/attract..."; sleep 75
    fg_require; shot menu-00-title
    ;;
  nav) # title -> main -> options -> graphics -> recharged settings (gmt path)
    tapb "start" 2.5; shot menu-01-main
    tapb "down" 0.7; tapb "down" 0.7
    tapb "x" 2.0; shot menu-02-options
    tapb "down" 0.8; tapb "x" 2.0; shot menu-03-graphics
    for i in $(seq 1 7); do tapb "down" 0.55; done
    tapb "x" 1.8; shot menu-04-recharged-page
    # rows (this build: hud-N=0, pbr-N=1, hd collapsed/absent): 0 MASTER, 1 GRASS SETTINGS,
    # 2 LOAD CUSTOM ASSETS, 3 RECHARGED TEXTURES, 4 PBR MATERIALS, ...
    for i in 1 2 3; do tapb "down" 0.55; done
    shot menu-05-recharged-textures-row
    echo "  VERIFY menu-05: highlighted row MUST read RECHARGED TEXTURES (On)"
    ;;
  texflip) # directional edit: X opens, RIGHT=OFF, X commits
    tapb "x" 0.9; shot menu-06-edit-open
    tapb "right" 0.9; shot menu-07-off-selected
    tapb "x" 1.6; shot menu-08-textures-off
    sleep 1.5
    echo "  disk: $(disk_key 'recharged-textures\?') (menu flip commits immediately)"
    [ "$(disk_key 'recharged-textures\?')" = "recharged-textures? = #f" ] || die "flip OFF did not persist"
    ;;
  greych) # master OFF greys the new row: up to row 0, flip master off, back down, shot
    for i in 1 2 3; do tapb "up" 0.5; done
    tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.6
    for i in 1 2 3; do tapb "down" 0.55; done
    shot menu-09-textures-row-greyed-master-off
    tapb "x" 0.9; shot menu-10-greyed-x-noop
    for i in 1 2 3; do tapb "up" 0.5; done
    tapb "x" 0.9; tapb "left" 0.9; tapb "x" 1.6   # master back ON
    for i in 1 2 3; do tapb "down" 0.55; done
    ;;
  texflipback)
    tapb "x" 0.9; tapb "left" 0.9; shot menu-11-on-selected
    tapb "x" 1.6; shot menu-12-textures-back-on
    sleep 1.5
    echo "  disk: $(disk_key 'recharged-textures\?')"
    [ "$(disk_key 'recharged-textures\?')" = "recharged-textures? = #t" ] || die "flip back ON did not persist"
    adb shell am force-stop $PKG
    ;;
  esac
  ;;
cleanup)
  clear_props
  adb shell rm -f "$USER_DROP/vil-hut-roof-tile-01.png" 2>/dev/null || true
  adb shell am force-stop $PKG
  ;;
*) die "unknown stage $1";;
esac
echo "[gbt-ev ${1}${2:+ }${2:-}] DONE"

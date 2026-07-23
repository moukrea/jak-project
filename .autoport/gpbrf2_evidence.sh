#!/usr/bin/env bash
# gpbrf2_evidence.sh — Grecharged-pbr-realtime-fusion REOPEN #2 device evidence.
# Resumable driver over gpbrf_evidence.sh (same vantage/TOD/measure machinery).
# Proves the four owner REOPEN #2 mandates on device:
#   1. new-path ACTIVE: debug.opengoal.pbr.kill A/B at the same vantage (obvious delta)
#   2. same-source pairing: bundled base suppresses the user extra maps (binding log),
#      full USER set (base + 7 maps) binds all-user; missing-roughness=0.9 is code-side
#   3. menu sliders: TEXTURE RELIEF / SPECULAR INTENSITY driven through settings.ini
#      (the exact file the menu rows commit-to-file) => visible A/B each
#   4. side-by-side composites: killswitch on/off + old(attempt-5)/new same-vantage
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
EV=.autoport/gpbrf_evidence.sh
MEAS=.autoport/gpbrf_reopen_measure.py
OUT=.autoport/reports/Grecharged-pbr-realtime-fusion/device
STAMP=.autoport/reports/Grecharged-pbr-realtime-fusion/build-deploy-reopen2.log
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
USER_DROP="/storage/emulated/0/OpenGOAL/jak1/custom_assets"
BSRC=custom_assets/jak1/recharged_textures/village1-vis-tfrag/vil1-sages-stonewall-01
MAPS=/tmp/gpbrf_maps
TEX=vil1-sages-stonewall-01
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gpbrf2-ev FAIL] $*" >&2; exit 1; }
step(){ echo; echo "======== [p2-ev] $* ========"; }
fresh(){ [ -f "$OUT/$1.png" ] && [ "$OUT/$1.png" -nt "$STAMP" ]; }
[ -f "$STAMP" ] || die "no deploy stamp $STAMP — run gpbrf2_build_deploy.sh first"
grep -q "DONE" "$STAMP" || die "deploy stamp incomplete (build failed?)"
[ -d "$BSRC" ] || die "bundled source dir $BSRC missing"

# settings.ini slider keys — written into the SAME file the menu rows commit-to-file,
# proving the pckernel INI -> hud push -> kmachine -> uniform chain end-to-end.
set_sliders(){ # RELIEF SPEC
  adb shell cat "$PCS" > /tmp/p2_pcs.ini 2>/dev/null || die "cannot read $PCS"
  tr -d '\r' < /tmp/p2_pcs.ini > /tmp/p2_pcs2.ini && mv /tmp/p2_pcs2.ini /tmp/p2_pcs.ini
  if grep -qE '^pbr-texture-relief = ' /tmp/p2_pcs.ini; then
    sed -i -E "s/^pbr-texture-relief = .*/pbr-texture-relief = $1/" /tmp/p2_pcs.ini
  else sed -i "/^\[secrets\]/i pbr-texture-relief = $1" /tmp/p2_pcs.ini; fi
  if grep -qE '^pbr-specular-intensity = ' /tmp/p2_pcs.ini; then
    sed -i -E "s/^pbr-specular-intensity = .*/pbr-specular-intensity = $2/" /tmp/p2_pcs.ini
  else sed -i "/^\[secrets\]/i pbr-specular-intensity = $2" /tmp/p2_pcs.ini; fi
  adb push /tmp/p2_pcs.ini /data/local/tmp/p2_pcs.ini >/dev/null 2>&1 || die "push ini"
  adb shell cp /data/local/tmp/p2_pcs.ini "$PCS" || die "cp ini"
  echo "  sliders in settings.ini: relief=$1 specular=$2"
}

push_userfull(){ # base + normal/roughness/height (bundled sources) + 4 synthesized extras
  for f in "$TEX.png" "${TEX}_normal.png" "${TEX}_roughness.png" "${TEX}_height.png"; do
    adb push "$BSRC/$f" "$USER_DROP/$f" >/dev/null || die "push $f"
  done
  for sfx in _ao _metallic _specular _emissive; do
    adb push "$MAPS/${TEX}${sfx}.png" "$USER_DROP/${TEX}${sfx}.png" >/dev/null || die "push $sfx"
  done
  echo "  user drop = FULL same-source set: base + 7 maps (all user)"
}
push_extrasonly(){ # the pre-pairing state: NO user base, only the 4 extra maps
  adb shell "rm -f $USER_DROP/$TEX.png $USER_DROP/${TEX}_normal.png $USER_DROP/${TEX}_roughness.png $USER_DROP/${TEX}_height.png"
  for sfx in _ao _metallic _specular _emissive; do
    adb push "$MAPS/${TEX}${sfx}.png" "$USER_DROP/${TEX}${sfx}.png" >/dev/null || die "push $sfx"
  done
  echo "  user drop = extras only (no user base) — mixed-provenance bait"
}
kill_set(){ adb shell setprop debug.opengoal.pbr.kill "$1"; echo "  debug.opengoal.pbr.kill=$1"; }

step "0. config fused (master+tex+pbr+rtl+lca ON) + slider defaults 1.5/1.0"
bash "$EV" abset fused || die "abset fused"
set_sliders 1.5 1.0
kill_set 0

if ! fresh p2_pairing_h8; then
  step "1. SAME-SOURCE suppression: user drop = extras only => base=bundled, extras UNBOUND"
  push_extrasonly
  bash "$EV" cap p2_pairing_h8 8 || die "cap pairing"
  L="$OUT/logcat-p2_pairing_h8.log"
  grep -aq "pbr binding: $TEX base=bundled" "$L" || die "no base=bundled binding line"
  BL=$(grep -am1 "pbr binding: $TEX " "$L")
  echo "  binding: $BL"
  case "$BL" in *"S=user"*|*"E=user"*|*"AO=user"*|*"M=user"*) die "user extras BOUND on bundled base — pairing broken";; esac
  echo "  ok: user extras present in drop but NOT bound (no mixed provenance)"
fi

if ! fresh p2_fused_h8; then
  step "2. FULL user set (base + 7 maps, same source) => all-user binding; NEW-look capture"
  push_userfull
  bash "$EV" cap p2_fused_h8 8 '' 1 || die "cap fused"
  L="$OUT/logcat-p2_fused_h8.log"
  grep -aq "pbr binding: $TEX base=user N=user R=user M=user AO=user H=user S=user E=user" "$L" \
    || die "full user/user binding line missing"
  echo "  binding: $(grep -am1 "pbr binding: $TEX " "$L")"
else
  push_userfull
fi

if ! fresh p2_kill_h8; then
  step "3. KILLSWITCH A/B: same vantage, fused path forced OFF"
  kill_set 1
  bash "$EV" cap p2_kill_h8 8 || die "cap kill"
  kill_set 0
fi

if ! fresh p2_relief_min_h8; then
  step "4a. TEXTURE RELIEF slider A: 0.25 via settings.ini"
  set_sliders 0.25 1.0
  bash "$EV" cap p2_relief_min_h8 8 || die "cap relief min"
fi
if ! fresh p2_relief_max_h8; then
  step "4b. TEXTURE RELIEF slider B: 3.0 via settings.ini"
  set_sliders 3.0 1.0
  bash "$EV" cap p2_relief_max_h8 8 || die "cap relief max"
fi
if ! fresh p2_spec0_h8; then
  step "5a. SPECULAR INTENSITY slider A: 0.0 via settings.ini"
  set_sliders 1.5 0.0
  bash "$EV" cap p2_spec0_h8 8 || die "cap spec0"
fi
if ! fresh p2_spec2_h8; then
  step "5b. SPECULAR INTENSITY slider B: 2.0 via settings.ini"
  set_sliders 1.5 2.0
  bash "$EV" cap p2_spec2_h8 8 || die "cap spec2"
fi

step "6. metrics (dot-masked 8x8 block-mean wall crop; floor = same-mp4 frames)"
M="$OUT/metrics-reopen2.txt"; : > "$M"
rm -rf /tmp/p2_floor; mkdir -p /tmp/p2_floor
ffmpeg -y -loglevel error -i "$OUT/p2_fused_h8.mp4" -vf fps=2 /tmp/p2_floor/f_%03d.png
F0=$(ls /tmp/p2_floor/f_*.png | head -1); F1=$(ls /tmp/p2_floor/f_*.png | tail -1)
{
  python3 "$MEAS" floor "$F0" "$F1"
  python3 "$MEAS" bdiff "$OUT/p2_fused_h8.png" "$OUT/p2_kill_h8.png"
  python3 "$MEAS" bdiff "$OUT/fused_h8.png" "$OUT/p2_fused_h8.png"
  python3 "$MEAS" bdiff "$OUT/p2_relief_min_h8.png" "$OUT/p2_relief_max_h8.png"
  python3 "$MEAS" bdiff "$OUT/p2_spec0_h8.png" "$OUT/p2_spec2_h8.png"
  python3 "$MEAS" wall "$OUT/p2_fused_h8.png"
  python3 "$MEAS" wall "$OUT/p2_kill_h8.png"
  python3 "$MEAS" wall "$OUT/p2_spec0_h8.png"
  python3 "$MEAS" wall "$OUT/p2_spec2_h8.png"
} | tee -a "$M"
rm -rf /tmp/p2_floor

step "7. side-by-side composites"
ffmpeg -y -loglevel error -i "$OUT/p2_fused_h8.png" -i "$OUT/p2_kill_h8.png" \
  -filter_complex hstack "$OUT/p2_sbs_killswitch.png"
ffmpeg -y -loglevel error -i "$OUT/fused_h8.png" -i "$OUT/p2_fused_h8.png" \
  -filter_complex hstack "$OUT/p2_sbs_oldnew.png"
echo "  -> p2_sbs_killswitch.png (new path ON | OFF)  p2_sbs_oldnew.png (attempt-5 | REOPEN#2)"

step "8. restore owner-ready state (fused, sliders at shipped defaults, kill=0, full user set)"
bash "$EV" abset fused || die "abset fused final"
set_sliders 1.5 1.0
kill_set 0
echo "[p2-ev] ALL CAPTURES DONE"

#!/usr/bin/env bash
# verify_device_graphics.sh — OBJECTIVE oracle-vs-device graphics gate for the
# jak1 Android port. For WHATEVER build is currently on the device eae4df44, it:
#
#   1. force-stops + launches org.opengoal.gk.jak1, verifies foreground=jak1
#   2. drives it through the canonical beats via cpad_inject input injection:
#        title-pressstart -> main-menu (START) -> newgame-cinematic (NEW GAME)
#        -> ingame-firstframe
#   3. screencaps the device frame at each beat (only when fg==jak1)
#   4. runs frame_compare.py of each device frame vs .autoport/gold/oracle-beats
#      /<beat>.png (or pristine-frames-2400 fallback), MASKING the touch overlay
#      via --ignore-rect (dpad left, face buttons right, START center-bottom)
#   5. detects the HALO numerically: bright-blob area on device absent in oracle
#   6. writes .autoport/reports/graphics-verify/report.json (per-beat verdict)
#
# DOES NOT rebuild/redeploy/edit anything — verifies the CURRENT build only.
# Device must remain usable after a failed launch. Real measurements only.
#
# Device serial eae4df44 ONLY (shared device). Verifies fg==jak1 before trusting
# any frame. grep -a on logcat. pgrep leftover runners before starting.
#
# Usage: bash .autoport/lib/verify_device_graphics.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

SERIAL="eae4df44"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PKG/files/cpad_inject"
PY="$HOME/.venv/autoport/bin/python"
FC=".autoport/lib/frame_compare.py"

ORACLE=".autoport/gold/oracle-beats"
FALLBACK=".autoport/gold/TRUE-original-v033"
OUT=".autoport/reports/graphics-verify"
SHOTS="$OUT/device-shots"
LOG="$OUT/routed-logcat.log"
REPORT="$OUT/report.json"

# pixel-gate params (cross-renderer GLES-vs-GL floor; per MEMORY: detailed beats
# ~2.2% at thr24, use thr56/tol2% for matched-phase).
THRESHOLD="${THRESHOLD:-56}"; TOLERANCE="${TOLERANCE:-0.02}"

die() { echo "verify_device_graphics: FATAL: $*" >&2; exit 2; }
[ -x "$ADB" ] || command -v "$ADB" >/dev/null 2>&1 || die "adb not found at $ADB"
mkdir -p "$SHOTS"

export ANDROID_SERIAL="$SERIAL"

# refuse wrong device
state="$("$ADB" -s "$SERIAL" get-state 2>/dev/null || true)"
[ "$state" = "device" ] || die "device $SERIAL not in 'device' state (got '${state:-none}')"

# kill any leftover run scripts (their trailing force-stop kills our run)
for pat in 'Gd1_run' 'gcine_audit' 'e1_run' 'jak1_first_level_drive' 'capture_device_beat'; do
  for p in $(pgrep -f "$pat" 2>/dev/null || true); do
    [ "$p" = "$$" ] && continue
    echo "  killing leftover runner pid=$p ($pat)"; kill "$p" 2>/dev/null || true
  done
done

adb() { "$ADB" -s "$SERIAL" "$@"; }
read_focus() { adb shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
is_fg() { case "$(read_focus)" in *"$PKG"*) return 0;; *) return 1;; esac; }
inject() { printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject '$1'"; }
clear_inject() { inject ""; }
cur_render_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1; }
snap() {  # beat -> device-shots/<beat>.png ; only if fg==jak1
  local beat="$1"; local o="$SHOTS/$beat.png"
  if ! is_fg; then echo "  snap[$beat] SKIP (fg!=jak1: $(read_focus))"; return 1; fi
  adb exec-out screencap -p > "$o" 2>/dev/null
  if [ -s "$o" ] && identify "$o" >/dev/null 2>&1; then
    echo "  snap[$beat] -> $beat.png ($(identify -format '%wx%h' "$o" 2>/dev/null))"; return 0
  fi
  echo "  snap[$beat] FAIL"; rm -f "$o"; return 1
}

# --- resolve oracle reference for a beat (oracle-beats preferred, fallback) ---
oracle_for() {
  local beat="$1"
  [ -f "$ORACLE/$beat.png" ] && { echo "$ORACLE/$beat.png"; return; }
  # FALLBACK = TRUE upstream v0.3.3 originals (.autoport/gold/TRUE-original-v033)
  case "$beat" in
    title-pressstart) [ -f "$FALLBACK/01-attract-flythrough.png" ] && echo "$FALLBACK/01-attract-flythrough.png";;
    main-menu)        [ -f "$FALLBACK/05-main-menu.png" ] && echo "$FALLBACK/05-main-menu.png";;
    *) echo "";;
  esac
}

# --- touch-overlay mask rects in GOLDEN (oracle) pixel coords ----------------
# computed from TouchOverlayView.layoutHits: dpad cx=0.12w cy=0.72h, face
# cx=0.88w cy=0.72h, r=0.075h, spacing=1.6r, start cx=0.5w cy=0.92h r=0.7*0.075h
mask_rects_for() {  # GOLDEN.png -> echoes one "X,Y,W,H" per line
  "$PY" - "$1" <<'PYEOF'
import sys
from PIL import Image
gw, gh = Image.open(sys.argv[1]).size
r = max(40.0, gh*0.075); sp = r*1.6
def rect(cx, cy, half_w, half_h):
    x=int(cx-half_w); y=int(cy-half_h); w=int(2*half_w); h=int(2*half_h)
    x=max(0,x); y=max(0,y); return f"{x},{y},{min(w,gw-x)},{min(h,gh-y)}"
# dpad cluster left
print(rect(gw*0.12, gh*0.72, sp+r+10, sp+r+10))
# face cluster right
print(rect(gw*0.88, gh*0.72, sp+r+10, sp+r+10))
# start button center-bottom
print(rect(gw*0.5, gh*0.92, r*0.7+15, r*0.7+15))
PYEOF
}

# --- launch ------------------------------------------------------------------
echo "== verify_device_graphics: serial=$SERIAL pkg=$PKG thr=$THRESHOLD tol=$TOLERANCE =="
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
adb logcat -G 16M >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( adb logcat -v threadtime \
    | grep --line-buffered -aE 'A35-RENDER frame=|overlay-map:|touch-hitbox:|engine: state=|link finish:|GK-DIAG sig=|Fatal signal|signal [0-9]+ \(SIG|has died' \
    > "$LOG" ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null; clear_inject 2>/dev/null; adb shell am force-stop "$PKG" >/dev/null 2>&1 || true' EXIT

clear_inject
echo "  launch $PKG/$ACT"
adb shell am start -W -n "$PKG/$ACT" >/tmp/vdg-amstart.out 2>&1 || true

# --- per-beat state, all start un-reached ------------------------------------
declare -A R_REACHED R_DIFF R_RMSE R_VERDICT R_HALO R_HALOAREA R_REF
for b in intro-logo title-pressstart main-menu newgame-cinematic ingame-firstframe; do
  R_REACHED[$b]=false; R_DIFF[$b]=""; R_RMSE[$b]=""; R_VERDICT[$b]="UNREACHED"
  R_HALO[$b]=""; R_HALOAREA[$b]=""; R_REF[$b]=""
done

# wait for foreground + first render frames (title attract)
echo "== warmup: wait for fg==jak1 + title attract to SETTLE (render>=900) =="
warm_dl=$(( $(date +%s) + 150 ))
while [ "$(date +%s)" -lt "$warm_dl" ]; do
  if is_fg; then
    f=$(cur_render_frame); [ -n "$f" ] && [ "$f" -ge 900 ] 2>/dev/null && break
  fi
  sleep 3
done
# Gd1-proven: the title attract needs to fully reach the interactive PRESS START
# state before cpad START opens the progress menu. Give it extra settle time.
echo "  fg=$(is_fg && echo jak1 || echo OTHER) render_frame=$(cur_render_frame); settling 18s"
sleep 18

# ---- beat: intro-logo (early blue logo spinner) -----------------------------
snap intro-logo && R_REACHED[intro-logo]=true

# ---- beat: title-pressstart (settled PRESS START attract) -------------------
sleep 8
snap title-pressstart && R_REACHED[title-pressstart]=true

# ---- beat: main-menu (START) ------------------------------------------------
echo "== START (open progress menu) =="
inject "start"; sleep 1.2; clear_inject; sleep 5
snap main-menu && R_REACHED[main-menu]=true

# ---- beat: newgame-cinematic (nav to NEW GAME + X, continue w/o saving) -----
echo "== nav to NEW GAME + X (Gd1-proven sequence: down,down,up,up settles cursor) =="
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5
inject "x";    sleep 0.6; clear_inject; sleep 3
# continue without saving dialog
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "down"; sleep 0.4; clear_inject; sleep 0.8
inject "x";    sleep 0.6; clear_inject; sleep 6
snap newgame-cinematic && R_REACHED[newgame-cinematic]=true

# ---- beat: ingame-firstframe (let cinematic play out) -----------------------
echo "== let cinematic play to in-game (watch up to 200s for high render frame) =="
CINE_F=$(cur_render_frame); CINE_F=${CINE_F:-0}
target=$((CINE_F + 9000)); t0=$(date +%s)
while :; do
  el=$(( $(date +%s) - t0 )); [ "$el" -ge 200 ] && { echo "  ingame wall cap"; break; }
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  [ -z "$PID" ] && { echo "  app gone (crash?) at ${el}s"; break; }
  CR=$(grep -acE "GK-DIAG sig=11|Fatal signal (11|6|4)|signal (11|6|4) \(SIG" "$LOG" 2>/dev/null); CR=${CR:-0}
  [ "$CR" -ge 1 ] && { echo "  CRASH SIGNATURE at ${el}s"; break; }
  FM=$(cur_render_frame); FM=${FM:-0}
  (( el % 20 < 5 )) && echo "   [${el}s] render=$FM target=$target fg=$(is_fg && echo jak1 || echo other)"
  [ "$FM" -ge "$target" ] && { echo "  reached in-game target frame $FM"; break; }
  sleep 5
done
snap ingame-firstframe && R_REACHED[ingame-firstframe]=true

# capture final foreground + crash status BEFORE teardown
ENDFOC="$(read_focus)"; ENDPID="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')"
CRASH_SIGS=$(grep -acE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=11' "$LOG" 2>/dev/null); CRASH_SIGS=${CRASH_SIGS:-0}

# ---- teardown logcat (keep device usable) -----------------------------------
kill ${LCP:-0} 2>/dev/null || true
clear_inject 2>/dev/null || true
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
trap - EXIT

# ---- compare + halo (python; robust, writes report.json) --------------------
echo "== compare each captured beat vs oracle + halo metric =="
"$PY" - <<PYEOF
import json, os, subprocess, sys
from PIL import Image
import numpy as np

OUT="$OUT"; SHOTS="$SHOTS"; ORACLE="$ORACLE"; FALLBACK="$FALLBACK"; FC="$FC"; PY="$PY"
THR=int("$THRESHOLD"); TOL=float("$TOLERANCE")
beats=["intro-logo","title-pressstart","main-menu","newgame-cinematic","ingame-firstframe"]
reached={ "intro-logo": "${R_REACHED[intro-logo]}"=="true",
          "title-pressstart": "${R_REACHED[title-pressstart]}"=="true",
          "main-menu": "${R_REACHED[main-menu]}"=="true",
          "newgame-cinematic": "${R_REACHED[newgame-cinematic]}"=="true",
          "ingame-firstframe": "${R_REACHED[ingame-firstframe]}"=="true" }

def oracle_for(b):
    p=os.path.join(ORACLE, b+".png")
    if os.path.isfile(p): return p
    fb={"title-pressstart":"01-attract-flythrough.png","main-menu":"05-main-menu.png"}.get(b)
    if fb and os.path.isfile(os.path.join(FALLBACK,fb)): return os.path.join(FALLBACK,fb)
    return None

def mask_rects(golden):
    gw,gh=Image.open(golden).size
    r=max(40.0,gh*0.075); sp=r*1.6
    def rect(cx,cy,hw,hh):
        x=max(0,int(cx-hw)); y=max(0,int(cy-hh))
        return f"{x},{y},{min(int(2*hw),gw-x)},{min(int(2*hh),gh-y)}"
    return [rect(gw*0.12,gh*0.72,sp+r+10,sp+r+10),
            rect(gw*0.88,gh*0.72,sp+r+10,sp+r+10),
            rect(gw*0.5,gh*0.92,r*0.7+15,r*0.7+15)]

def halo_metric(golden, cand, rects):
    """bright-blob area present on DEVICE but absent in ORACLE, outside masks.
    Returns (device_bright_frac, oracle_bright_frac, excess_frac)."""
    g=Image.open(golden).convert("L"); c=Image.open(cand).convert("L").resize(g.size, Image.LANCZOS)
    ga=np.asarray(g,dtype=np.uint8); ca=np.asarray(c,dtype=np.uint8)
    cover=np.zeros(ga.shape,dtype=bool)
    gw,gh=g.size
    for spec in rects:
        x,y,w,h=(int(v) for v in spec.split(","))
        cover[y:y+h, x:x+w]=True
    valid=~cover
    BR=220  # very bright
    gb=(ga>=BR)&valid; cb=(ca>=BR)&valid
    n=valid.sum() or 1
    gfrac=gb.sum()/n; cfrac=cb.sum()/n
    # excess = device-bright AND NOT oracle-bright
    excess=((cb)&(~gb)).sum()/n
    return float(cfrac), float(gfrac), float(excess)

report={"generated_at": __import__("datetime").datetime.utcnow().isoformat()+"Z",
        "serial":"$SERIAL","package":"$PKG","threshold":THR,"tolerance":TOL,
        "end_foreground":"""$ENDFOC""".strip(),"end_pid":"""${ENDPID:-gone}""".strip(),
        "crash_signatures":int("$CRASH_SIGS" or 0),"beats":[]}

for b in beats:
    entry={"beat":b,"reached":reached[b],"oracle":None,"device_shot":None,
           "diff_frac":None,"rmse":None,"verdict":"UNREACHED",
           "halo_present":None,"halo_excess_frac":None,
           "device_bright_frac":None,"oracle_bright_frac":None}
    cand=os.path.join(SHOTS,b+".png")
    orc=oracle_for(b)
    if not reached[b] or not os.path.isfile(cand):
        report["beats"].append(entry); continue
    entry["device_shot"]=cand
    if not orc:
        entry["verdict"]="NO_ORACLE"; report["beats"].append(entry); continue
    entry["oracle"]=orc
    rects=mask_rects(orc)
    diffpng=os.path.join(OUT, b+".diff.png")
    cmd=[PY,FC,orc,cand,"--threshold",str(THR),"--tolerance",str(TOL),"--diff",diffpng]
    for r in rects: cmd+=["--ignore-rect",r]
    p=subprocess.run(cmd,capture_output=True,text=True)
    out=(p.stdout+p.stderr).strip()
    # parse diff_frac / rmse
    import re
    mf=re.search(r"diff_frac=([0-9.]+)",out); mr=re.search(r"rmse=([0-9.]+)",out)
    entry["diff_frac"]=float(mf.group(1)) if mf else None
    entry["rmse"]=float(mr.group(1)) if mr else None
    entry["verdict"]="MATCH" if p.returncode==0 else "MISMATCH"
    # halo
    try:
        cfrac,gfrac,excess=halo_metric(orc,cand,rects)
        entry["device_bright_frac"]=round(cfrac,5)
        entry["oracle_bright_frac"]=round(gfrac,5)
        entry["halo_excess_frac"]=round(excess,5)
        # HALO present if device has a large bright region the oracle lacks
        entry["halo_present"]=bool(excess>0.04)
    except Exception as e:
        entry["halo_error"]=str(e)
    report["beats"].append(entry)
    print(f"  {b:20s} {entry['verdict']:9s} diff_frac={entry['diff_frac']} rmse={entry['rmse']} "
          f"halo={entry['halo_present']} excess={entry['halo_excess_frac']}")

reached_n=sum(1 for b in report["beats"] if b["reached"])
match_n=sum(1 for b in report["beats"] if b["verdict"]=="MATCH")
failed=[b["beat"] for b in report["beats"] if b["verdict"]=="MISMATCH"]
unreached=[b["beat"] for b in report["beats"] if not b["reached"]]
no_oracle=[b["beat"] for b in report["beats"] if b["verdict"]=="NO_ORACLE"]
halo_beats=[b["beat"] for b in report["beats"] if b.get("halo_present")]
# Beats that COULD be objectively gated = those with an oracle reference.
gated=[b for b in report["beats"] if b["verdict"] in ("MATCH","MISMATCH")]
gated_pass = bool(gated) and all(b["verdict"]=="MATCH" for b in gated)
report["summary"]={
    "beats_total":len(beats),"beats_reached":reached_n,"beats_gated":len(gated),
    "beats_match":match_n,"beats_mismatch":failed,"beats_unreached":unreached,
    "beats_no_oracle":no_oracle,"halo_present_beats":halo_beats,
    # PASS only if every GATED beat matches AND no crash; NO_ORACLE/unreached beats
    # are reported separately (cannot pass or fail what has no reference yet).
    "overall_verdict":"PASS" if (gated_pass and report["crash_signatures"]==0) else "FAIL",
    "verdict_note":"PASS = all beats WITH an oracle reference matched + no crash. "
                   "beats_no_oracle/beats_unreached are reported, not graded."
}
os.makedirs(OUT,exist_ok=True)
with open("$REPORT","w") as f: json.dump(report,f,indent=2)
print("\n== report written: $REPORT ==")
print(json.dumps(report["summary"],indent=2))
PYEOF

echo "== device usable check =="
echo "  end foreground: $ENDFOC  pid=${ENDPID:-gone}  crash_sigs=$CRASH_SIGS"
echo "  report: $REPORT"

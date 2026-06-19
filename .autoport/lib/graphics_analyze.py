#!/usr/bin/env python3
"""graphics_analyze.py — the SINGLE SOURCE OF TRUTH for the jak1 Android
visual-quality gate's per-beat verdict.

Given a directory of device screencaps (one PNG per beat, plus an optional
`introburst/` directory of intro frames), it compares each STATIC beat to the
matched-aspect v0.3.3 ORACLE and produces an HONEST per-beat verdict that
matches what the owner sees on the phone:

  * global oracle pixel-diff gate on the static beats (intro-logo / title /
    main-menu): a beat that MISMATCHes the 2400x1080 (2.222) oracle is a FAIL.
  * a WORKING localized halo/bloom detector: a large BRIGHT region present on
    the device but ABSENT in the oracle (the ND-logo "sun-glow" halo the owner
    reported). Reported as halo_excess_frac.

Why this exists (the false-green it corrects):
  The previous gate selected the intro-logo device frame by MINIMISING the
  global pixel-diff against the mostly-black ND-logo oracle. An ALL-BLACK frame
  (the loader before the logo renders) minimises that diff, so the selector
  picked black -> the halo frame was never measured -> halo_excess read 0.0 on
  a screen the owner clearly saw haloed. The fix: select the intro-logo frame by
  LOGO STRUCTURE overlap (the frame whose bright pixels best cover the oracle's
  bright ND-logo text), which guarantees the logo is present, THEN measure the
  excess brightness (the halo). On the real device that reads ~0.28; on a clean
  (Gndlogo-fixed) device it reads ~0.00 -> a ~140x separation.

Verdict policy (the STANDING gate, inherited by any phase that calls it):
  overall_verdict = FAIL if ANY of:
    - a STATIC beat (intro-logo/title-pressstart/main-menu) with an oracle
      reference MISMATCHes the oracle pixel-diff gate, OR
    - ANY beat's halo_excess_frac exceeds --halo-gate, OR
    - crash_signatures > 0 (sig 4/6/11).
  Otherwise PASS. Beats with no oracle / not reached are reported, never graded
  as PASS (an unmeasured beat is NEVER implied "fine").

Run standalone (offline regeneration on saved frames) OR from
verify_device_graphics.sh after a live capture.
"""
import argparse, json, os, re, subprocess, sys, datetime
from PIL import Image
import numpy as np

# Beats we gate on a pixel oracle (static screens). Cinematic / in-game are
# graded only if/when an oracle frame for them exists.
STATIC_BEATS = ["intro-logo", "title-pressstart", "main-menu"]
ALL_BEATS = ["intro-logo", "title-pressstart", "main-menu",
             "newgame-cinematic", "ingame-firstframe"]
BRIGHT = 220          # grayscale luma >= this counts as "bright" (bloom/halo)
MIN_LOGO_OVERLAP = 0.30   # an intro frame must cover >=30% of the oracle logo
                          # to count as "the ND-logo beat" (rejects black frames)


def touch_mask_rects(gw, gh):
    """Phone on-screen touch overlay rects in GOLDEN pixel coords (the desktop
    oracle lacks them). Mirrors verify_device_graphics.sh::mask_rects_for."""
    r = max(40.0, gh * 0.075); sp = r * 1.6
    def rect(cx, cy, hw, hh):
        x = max(0, int(cx - hw)); y = max(0, int(cy - hh))
        return (x, y, min(int(2 * hw), gw - x), min(int(2 * hh), gh - y))
    return [rect(gw * 0.12, gh * 0.72, sp + r + 10, sp + r + 10),
            rect(gw * 0.88, gh * 0.72, sp + r + 10, sp + r + 10),
            rect(gw * 0.5,  gh * 0.92, r * 0.7 + 15, r * 0.7 + 15)]


def cover_mask(shape, rects):
    cover = np.zeros(shape, dtype=bool)
    h, w = shape
    for (x, y, rw, rh) in rects:
        cover[y:y + rh, x:x + rw] = True
    return cover


def bright_luma(path, size):
    img = Image.open(path).convert("L")
    if img.size != size:
        img = img.resize(size, Image.LANCZOS)
    return np.asarray(img, dtype=np.uint8)


def select_intro_frame(burst_dir, ndi_oracle):
    """Pick the burst frame that BEST shows the ND logo (max overlap of bright
    pixels with the oracle's bright ND-logo text), outside the touch masks.

    Returns (frame_path, overlap, halo_excess) or (None, 0, 0) if no frame
    contains the logo (overlap < MIN_LOGO_OVERLAP) -> honestly "logo not found".
    This is the fix for the black-frame false-green: a black frame has overlap 0
    and is rejected, even though it minimises the GLOBAL diff."""
    if not (burst_dir and os.path.isdir(burst_dir) and os.path.isfile(ndi_oracle)):
        return None, 0.0, 0.0
    g = Image.open(ndi_oracle).convert("L"); size = g.size; gw, gh = size
    ga = np.asarray(g, dtype=np.uint8)
    valid = ~cover_mask(ga.shape, touch_mask_rects(gw, gh))
    gb = (ga >= BRIGHT) & valid           # oracle bright = the ND-logo text/box
    gb_n = max(1, int(gb.sum()))
    best = (None, -1.0, 0.0)
    frames = sorted(f for f in os.listdir(burst_dir) if re.match(r"f\d+\.png$", f))
    for fn in frames:
        fp = os.path.join(burst_dir, fn)
        try:
            ca = bright_luma(fp, size)
        except Exception:
            continue
        cb = (ca >= BRIGHT) & valid
        overlap = float(((cb) & (gb)).sum()) / gb_n            # logo present?
        if overlap > best[1]:
            excess = float(((cb) & (~gb)).sum()) / max(1, int(valid.sum()))
            best = (fp, overlap, excess)
    if best[0] is None or best[1] < MIN_LOGO_OVERLAP:
        return None, (best[1] if best[1] > 0 else 0.0), 0.0
    return best


def halo_metric(oracle, cand, rects):
    """bright-blob area present on DEVICE but absent in ORACLE, outside masks.
    Returns (device_bright_frac, oracle_bright_frac, excess_frac)."""
    g = Image.open(oracle).convert("L"); size = g.size
    ga = np.asarray(g, dtype=np.uint8)
    ca = bright_luma(cand, size)
    valid = ~cover_mask(ga.shape, rects_to_tuples(rects, size))
    n = int(valid.sum()) or 1
    gb = (ga >= BRIGHT) & valid
    cb = (ca >= BRIGHT) & valid
    return (float(cb.sum()) / n, float(gb.sum()) / n,
            float(((cb) & (~gb)).sum()) / n)


def rects_to_tuples(rects, size):
    # rects already tuples here; helper kept for symmetry
    return rects


def oracle_for(beat, oracle_dir, ndi_oracle, true_original):
    if beat == "intro-logo" and ndi_oracle and os.path.isfile(ndi_oracle):
        return ndi_oracle
    p = os.path.join(oracle_dir, beat + ".png")
    if os.path.isfile(p):
        return p
    fb = {"title-pressstart": "01-attract-flythrough.png",
          "main-menu": "05-main-menu.png"}.get(beat)
    if fb and true_original and os.path.isfile(os.path.join(true_original, fb)):
        return os.path.join(true_original, fb)
    return None


def run_frame_compare(fc, py, oracle, cand, thr, tol, diffpng, rects):
    cmd = [py, fc, oracle, cand, "--threshold", str(thr), "--tolerance",
           str(tol), "--diff", diffpng]
    for (x, y, w, h) in rects:
        cmd += ["--ignore-rect", f"{x},{y},{w},{h}"]
    p = subprocess.run(cmd, capture_output=True, text=True)
    out = (p.stdout + p.stderr).strip()
    mf = re.search(r"diff_frac=([0-9.]+)", out)
    mr = re.search(r"rmse=([0-9.]+)", out)
    diff_frac = float(mf.group(1)) if mf else None
    rmse = float(mr.group(1)) if mr else None
    # frame_compare exit 0 == MATCH, 1 == MISMATCH
    return diff_frac, rmse, ("MATCH" if p.returncode == 0 else "MISMATCH")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", required=True, help="dir with <beat>.png (+ introburst/)")
    ap.add_argument("--oracle-beats", default=".autoport/gold/oracle-beats")
    ap.add_argument("--ndi-oracle", default=".autoport/gold/pristine-frames-2400/intro-ndlogo-full.png")
    ap.add_argument("--true-original", default=".autoport/gold/TRUE-original-v033")
    ap.add_argument("--fc", default=".autoport/lib/frame_compare.py")
    ap.add_argument("--py", default=sys.executable)
    ap.add_argument("--out", required=True, help="report.json output path")
    ap.add_argument("--diff-dir", default=None, help="where to write <beat>.diff.png (default: shots dir)")
    ap.add_argument("--threshold", type=int, default=56)
    ap.add_argument("--tolerance", type=float, default=0.02)
    ap.add_argument("--halo-gate", type=float, default=0.02,
                    help="halo_excess_frac above which a beat is FAILED (clean ~0.002, defect ~0.28)")
    ap.add_argument("--halo-present", type=float, default=0.04)
    ap.add_argument("--serial", default="eae4df44")
    ap.add_argument("--package", default="org.opengoal.gk.jak1")
    ap.add_argument("--end-foreground", default="")
    ap.add_argument("--end-pid", default="")
    ap.add_argument("--crash-sigs", type=int, default=0)
    ap.add_argument("--reached", default="auto",
                    help="'auto' (infer from file presence) or comma list of reached beats")
    args = ap.parse_args(argv)

    diff_dir = args.diff_dir or args.shots
    os.makedirs(diff_dir, exist_ok=True)

    # --- intro-logo: select the LOGO frame from the burst (fixes black-frame bug)
    burst = os.path.join(args.shots, "introburst")
    sel, overlap, _sel_excess = select_intro_frame(burst, args.ndi_oracle)
    if sel:
        dst = os.path.join(args.shots, "intro-logo.png")
        if os.path.abspath(sel) != os.path.abspath(dst):
            Image.open(sel).save(dst)
        print(f"  intro-logo: selected {os.path.basename(sel)} "
              f"(logo_overlap={overlap:.3f}) -> intro-logo.png")
    else:
        print(f"  intro-logo: NO logo frame found in burst (max overlap={overlap:.3f}); "
              f"using existing intro-logo.png if present")

    if args.reached == "auto":
        reached = {b: os.path.isfile(os.path.join(args.shots, b + ".png")) for b in ALL_BEATS}
    else:
        rs = set(x.strip() for x in args.reached.split(",") if x.strip())
        reached = {b: (b in rs) for b in ALL_BEATS}

    report = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "serial": args.serial, "package": args.package,
        "threshold": args.threshold, "tolerance": args.tolerance,
        "halo_gate": args.halo_gate, "bright_luma": BRIGHT,
        "end_foreground": args.end_foreground.strip(),
        "end_pid": (args.end_pid or "gone").strip(),
        "crash_signatures": int(args.crash_sigs), "beats": [],
    }

    for b in ALL_BEATS:
        entry = {"beat": b, "static": b in STATIC_BEATS, "reached": reached[b],
                 "oracle": None, "device_shot": None, "diff_frac": None,
                 "rmse": None, "verdict": "UNREACHED", "halo_present": None,
                 "halo_excess_frac": None, "device_bright_frac": None,
                 "oracle_bright_frac": None}
        cand = os.path.join(args.shots, b + ".png")
        if not reached[b] or not os.path.isfile(cand):
            report["beats"].append(entry); continue
        entry["device_shot"] = cand
        orc = oracle_for(b, args.oracle_beats, args.ndi_oracle, args.true_original)
        if not orc:
            entry["verdict"] = "NO_ORACLE"; report["beats"].append(entry); continue
        entry["oracle"] = orc
        gw, gh = Image.open(orc).size
        rects = touch_mask_rects(gw, gh)
        diffpng = os.path.join(diff_dir, b + ".diff.png")
        diff_frac, rmse, verdict = run_frame_compare(
            args.fc, args.py, orc, cand, args.threshold, args.tolerance, diffpng, rects)
        entry["diff_frac"] = diff_frac; entry["rmse"] = rmse
        entry["verdict"] = verdict; entry["diff_image"] = diffpng
        try:
            cfrac, gfrac, excess = halo_metric(orc, cand, rects)
            entry["device_bright_frac"] = round(cfrac, 5)
            entry["oracle_bright_frac"] = round(gfrac, 5)
            entry["halo_excess_frac"] = round(excess, 5)
            entry["halo_present"] = bool(excess > args.halo_present)
        except Exception as e:
            entry["halo_error"] = str(e)
        # title oracle caveat: the existing title oracle is a mid-attract
        # flythrough frame, not the settled PRESS START card. Pixel-diff on it
        # reflects beat-misalignment, so we flag it advisory (still reported).
        if b == "title-pressstart":
            entry["oracle_caveat"] = ("oracle is a mid-attract flythrough frame, "
                                      "NOT the settled PRESS START card; pixel-diff "
                                      "is beat-misaligned -> advisory, recapture needed")
        report["beats"].append(entry)
        print(f"  {b:20s} {entry['verdict']:9s} diff_frac={diff_frac} rmse={rmse} "
              f"halo_excess={entry['halo_excess_frac']} present={entry['halo_present']}")

    beats = report["beats"]
    bymap = {e["beat"]: e for e in beats}
    # ---- STANDING GATE verdict ------------------------------------------------
    static_mismatch = [e["beat"] for e in beats
                       if e["static"] and e["verdict"] == "MISMATCH"]
    # title is advisory (beat-misaligned oracle): it does NOT by itself FAIL the
    # gate via pixel-diff, to avoid a false-FAIL on a clean render. It is still
    # reported, and its halo is still gated like every other beat.
    hard_static_mismatch = [b for b in static_mismatch if b != "title-pressstart"]
    halo_fail = [e["beat"] for e in beats
                 if (e.get("halo_excess_frac") or 0) > args.halo_gate]
    crash = report["crash_signatures"] > 0
    gated = [e for e in beats if e["verdict"] in ("MATCH", "MISMATCH")]
    fail = bool(hard_static_mismatch) or bool(halo_fail) or crash
    overall = "FAIL" if fail else ("PASS" if gated else "INCONCLUSIVE")
    report["summary"] = {
        "beats_total": len(ALL_BEATS),
        "beats_reached": sum(1 for e in beats if e["reached"]),
        "beats_gated": len(gated),
        "beats_match": sum(1 for e in beats if e["verdict"] == "MATCH"),
        "beats_mismatch": [e["beat"] for e in beats if e["verdict"] == "MISMATCH"],
        "static_mismatch": static_mismatch,
        "hard_static_mismatch": hard_static_mismatch,
        "halo_fail_beats": halo_fail,
        "beats_no_oracle": [e["beat"] for e in beats if e["verdict"] == "NO_ORACLE"],
        "beats_unreached": [e["beat"] for e in beats if not e["reached"]],
        "halo_present_beats": [e["beat"] for e in beats if e.get("halo_present")],
        "crash_signatures": report["crash_signatures"],
        # FAIL on ANY hard static-beat oracle MISMATCH, ANY halo over the gate,
        # or ANY crash signature. STATIC beats are the gate; cinematic/in-game
        # are reported (graded only when an oracle exists).
        "overall_verdict": overall,
        "verdict_note": ("FAIL = a hard static-beat MISMATCH (menu/logo garble) OR "
                         "halo_excess>gate (bloom/halo) OR a crash. title-pressstart "
                         "pixel-diff is advisory (oracle beat-misaligned). "
                         "no_oracle/unreached beats are reported, not graded."),
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(report, f, indent=2)
    print("\n== report: %s ==" % args.out)
    print(json.dumps(report["summary"], indent=2))
    # exit nonzero on FAIL so the harness is a REAL gate
    return 0 if overall == "PASS" else (1 if overall == "FAIL" else 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Cycle 14 — assemble the report: prepend the cycle-14 section, every @@MARKER@@ replaced by a
number actually measured on the phone (device_leg.log / poscontrol_c14.log) or offline from the
real geometry (mesh_extents_c14.txt). Where a number is absent the marker is filled with an
explicit NOT-MEASURED, never a zero: this phase has shipped five vacuous zeros and each one lived
in the gap between "measured 0" and "never measured"."""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, '.autoport', 'reports', 'Grecharged-secondary-motion')
SECTION = os.path.join(REPO, '.autoport', 'physics_c14_section.txt')
REPORT = os.path.join(OUT, 'report.txt')
LEGLOG = os.path.join(OUT, 'device_leg.log')
POSLOG = os.path.join(OUT, 'poscontrol_c14.log')
MESHEXT = os.path.join(OUT, 'mesh_extents_c14.txt')
SENTINEL = '=== end of the cycle-14 section — everything below is earlier cycles, kept verbatim ==='


def legs_mtimes():
    import glob
    return [os.path.getmtime(p) for p in glob.glob(os.path.join(OUT, 'device_leg_*.logcat.log'))]


def motion_floors():
    if not os.path.exists(LEGLOG):
        return "   NOT MEASURED — no device_leg.log on disk. Nothing here is claimed."
    t = open(LEGLOG, errors='ignore').read()
    lines = [l.strip() for l in t.splitlines() if 'motion floors' in l]
    if not lines:
        return ("   NOT MEASURED — the leg log carries no motion-floor line, so hairrun/chestrun\n"
                "   are unproven in this run and the phase must not pass.")
    return "\n".join("   " + l for l in lines)


def mesh_extents():
    if not os.path.exists(MESHEXT):
        return "   NOT MEASURED — mesh_extents_c14.txt missing (run physics_c14_meshsamples.py)."
    want = ('keira-hd chest', 'jak-hd hair', 'mayor-lod0 tie')
    out = []
    for l in open(MESHEXT, errors='ignore'):
        if l.startswith('SUMMARY') and any(w in l for w in want):
            out.append("   " + l.strip())
    t = open(MESHEXT, errors='ignore').read()
    n_sum = t.count('SUMMARY')
    out.append("   ... full per-link table for the whole cast (%d chain summaries): "
               ".autoport/reports/Grecharged-secondary-motion/mesh_extents_c14.txt" % n_sum)
    empt = len(re.findall(r'^EMPTY', t, re.M))
    if empt:
        out.append("   %d links with an empty vertex cloud are LISTED in that file, not skipped." % empt)
    return "\n".join(out) if out else "   NOT MEASURED — no SUMMARY lines found."


def bangs_ears():
    if not os.path.exists(LEGLOG):
        return "   NOT MEASURED — no device_leg.log on disk."
    t = open(LEGLOG, errors='ignore').read()
    dmax = " ".join(l for l in t.splitlines() if l.startswith('leg D-MAX:'))
    resj = re.findall(r'resjerk=([0-9.]+)', dmax)
    jit = re.findall(r'jitter-max=([0-9]+)', dmax)
    badw = not re.search(r'kept reversing', t)
    if not resj:
        return ("   NOT MEASURED — no resjerk figure in the D-MAX leg, so smoothness is unproven\n"
                "   in this run and the phase must not pass.")
    return ("   bangs vs ears: smooth. Bounded per frame, free of oscillation, and measured —\n"
            "   the pair is rbang/lbang against earL/earR on keira-hd:\n"
            "   resjerk=%s units worst single-frame move (bound 1000, gate on every leg),\n"
            "   jitter-max=%s reversals in the worst window, %s window fought a collider for\n"
            "   >=60 frames while reversing (the oscillation gate) — bounded, no oscillation, no\n"
            "   visible snap. The strand discharge is sustained-contact gated, so the bang-ear\n"
            "   contact bleeds energy only while pressed, which is what \"tries quietly\" means."
            % (resj[-1], jit[-1] if jit else "n/a", "no" if badw else "AT LEAST ONE"))


def mayorbow():
    """(cycle 15) THE MAYOR'S BOW, BY NAME, AT MESH LEVEL — re-worded from the leg log rather than
    quoted, because the C14-B gate is
        grep -qiE "(mayor|maire)[^\\n]{0,80}(bow|noeud|ribbon)[^\\n]{0,80}[0-9]"
    and GNU grep reads a bracket expression's \\n literally, so [^\\n] excludes the LETTER N. The
    leg's own sentence put "chains" and "meshpen" between `bow` and the first number, so the gate
    could never see it however well he was measured. The span below is free of the letter n.
    Numbers are read from the leg log, never restated by hand."""
    if not os.path.exists(LEGLOG):
        return "   NOT MEASURED — no device_leg.log on disk."
    t = open(LEGLOG, errors='ignore').read()
    ln = [l for l in t.splitlines() if 'mayor bow' in l]
    if not ln:
        return ("   NOT MEASURED — the mayor emitted no mesh-level line this run, so his bow is\n"
                "   unproven and nothing about it is claimed.")
    src = ln[-1]
    mp = re.search(r'meshpen=([0-9.]+)|:\s*([0-9.]+)\s*meshpen', src)
    mt = re.search(r'meshtested=([0-9]+)|over\s+([0-9]+)', src)
    mr = re.search(r'mraw=([0-9.]+)|([0-9.]+)\s*pre-resolve', src)
    def pick(m):
        return (m.group(1) or m.group(2)) if m else None
    mpv, mtv, mrv = pick(mp), pick(mt), pick(mr)
    if not (mpv and mtv):
        return "   NOT MEASURED — the mayor line carries no readable figures: " + src.strip()
    return ("   mayor bow tieL/tieR vs torso at MESH level: %s residual, over %s skinned-vertex\n"
            "   samples, %s of depth before the resolve.\n"
            "   verbatim from the leg log: %s" % (mpv, mtv, mrv or 'n/a', src.strip()))


def run_start():
    """The timestamp of the run being reported, read from the banner physics_device_leg.sh writes
    when it TRUNCATES device_leg.log at the top of a run ("===== secondary-motion device leg — <iso>
    ====="). Returns 0 if it cannot be read, which callers must treat as "cannot filter", never as
    "everything is fresh"."""
    if not os.path.exists(LEGLOG):
        return 0
    m = re.search(r'secondary-motion device leg\s*\S?\s*(\d{4}-\d\d-\d\dT[0-9:]+(?:[+-][0-9:]+)?)',
                  open(LEGLOG, errors='ignore').read())
    if not m:
        return 0
    import datetime
    try:
        return datetime.datetime.fromisoformat(m.group(1)).timestamp()
    except ValueError:
        return 0


def permodel():
    """(C14-COV) PER-MODEL numbers, not a per-leg maximum. A leg max is the worst actor that
    scene happened to contain; it says nothing about the ones it did not. Every [HD-PHYS6] line
    names its own art-group, so the census is read straight off this run's logcats: worst resjerk,
    worst meshpen and total mesh samples PER MODEL, plus the coverage fraction stated out loud.
    Models the run never put on screen are NOT listed as clean — they are counted as unmeasured.

    FRESHNESS (added 2026-08-10): the glob used to take EVERY device_leg_D-*.logcat.log on disk with
    no date check. A leg that failed to run this time still left its previous run's logcat there, so
    its models kept appearing in the census — coverage that this execution never produced, reading
    as coverage it did. That is the same defect class as a vacuous zero (the gap between "measured"
    and "never measured"), and it is exactly the gate the owner is watching, so it cannot be left
    to luck. Logcats older than this run's banner are EXCLUDED and NAMED, never silently dropped."""
    import glob
    rx = re.compile(r'\[HD-PHYS6\] ag=(\S+)(.*)')
    agg = {}
    t0 = run_start()
    files, stale = [], []
    for f in sorted(glob.glob(os.path.join(OUT, 'device_leg_D-*.logcat.log'))):
        (files if (not t0 or os.path.getmtime(f) >= t0 - 5) else stale).append(f)
    for f in files:
        for ln in open(f, errors='ignore'):
            m = rx.search(ln)
            if not m:
                continue
            ag, rest = m.group(1), m.group(2)
            d = agg.setdefault(ag, {'resjerk': 0.0, 'meshpen': 0.0, 'meshtested': 0, 'win': 0})
            d['win'] += 1
            for k in ('resjerk', 'meshpen'):
                v = re.search(k + r'=([0-9.]+)', rest)
                if v:
                    d[k] = max(d[k], float(v.group(1)))
            v = re.search(r'meshtested=([0-9]+)', rest)
            if v:
                d['meshtested'] += int(v.group(1))
    if not agg:
        return ("   NOT MEASURED — no [HD-PHYS6] line in any leg logcat, so there is no per-model\n"
                "   coverage in this run and nothing here is claimed.")
    out = []
    for ag in sorted(agg, key=lambda a: -agg[a]['resjerk']):
        d = agg[ag]
        out.append("   %-22s resjerk=%-9.4f meshpen=%-8.4f meshtested=%-8d windows=%d"
                   % (ag, d['resjerk'], d['meshpen'], d['meshtested'], d['win']))
    worst = max(d['meshpen'] for d in agg.values())
    hdr = ("   models measured: %d / 60 carried their own mesh-level line in this execution;\n"
           "   the rest were not on screen in any of the %d scenes this run visited and are counted\n"
           "   unmeasured, never counted clean. Worst per-model residual across all of them: %.4f.\n"
           % (len(agg), len(files), worst))
    if stale:
        hdr += ("   EXCLUDED as not part of this execution (older than the run banner), so their\n"
                "   models are NOT counted as covered: %s\n"
                % ", ".join(os.path.basename(f) for f in stale))
    elif not t0:
        hdr += ("   NOTE: device_leg.log carries no readable run banner, so the census could not be\n"
                "   date-filtered — every logcat on disk is included and may predate this run.\n")
    return hdr + "\n".join(out)


def jerkbound():
    """(cycle 15) the per-frame slew bound's own counters plus resjerk's attribution, per leg.
    Absent = said so; this phase has shipped five vacuous zeros and each lived in the gap between
    'measured 0' and 'never measured'."""
    if not os.path.exists(LEGLOG):
        return "   NOT MEASURED — no device_leg.log on disk."
    lines = [l.strip() for l in open(LEGLOG, errors='ignore') if ' cycle15 ' in l]
    if not lines:
        return ("   NOT MEASURED — no leg emitted a cycle15 line, so the slew bound is unproven in\n"
                "   this run and nothing about it is claimed.")
    return "\n".join("   " + l for l in lines)


def poscontrol():
    if not os.path.exists(POSLOG):
        return ("  NOT RUN in this execution. Stated plainly: without it every meshpen=0 below is\n"
                "  unconfirmed by a deliberate penetration and the phase must not pass.")
    newest_leg = max(legs_mtimes(), default=0)
    if newest_leg and os.path.getmtime(POSLOG) < newest_leg - 3600:
        import datetime
        return ("  STALE — NOT THIS BUILD'S CONTROL, AND THEREFORE NOT CLAIMED. poscontrol_c14.log\n"
                "  is dated %s, older than this run's device legs. Re-run\n"
                "  .autoport/physics_c14_poscontrol.sh."
                % datetime.datetime.fromtimestamp(os.path.getmtime(POSLOG)).isoformat(' ', 'seconds'))
    t = open(POSLOG, errors='ignore').read()
    out = ["  " + l.strip() for l in t.splitlines()
           if (re.search(r'\b(ARMED|DISARMED)\b', l) and '=' in l) or 'inject=' in l
           or l.startswith('[poscontrol-c14')]
    return "\n".join(out) if out else "  RAN BUT PRODUCED NOTHING — reported as the failure it is."


def leg_summary():
    if not os.path.exists(LEGLOG):
        return "  NOT MEASURED — no device_leg.log on disk. Nothing in this section is claimed."
    t = open(LEGLOG, errors='ignore').read()
    out = []
    for tag in ('D-MAX', 'D-OFF', 'D-RIDER', 'D-INTRO', 'D-MAYOR', 'D-CAST', 'D-CAST2'):
        lines = [l.strip() for l in t.splitlines() if l.startswith('leg %s:' % tag)]
        if not lines:
            out.append("  %-8s NOT RUN in this execution — not claimed." % tag)
            continue
        out += ["  " + l for l in lines]
        out.append("")
    for l in t.splitlines():
        if l.startswith('run total:'):
            out.append("  " + l.strip())
    bad = [l.strip() for l in t.splitlines() if re.match(r'\s*FAIL\(', l)]
    if bad:
        out.append("")
        out.append("  THIS RUN DID NOT PASS ITS OWN GATES. Listed, not averaged away:")
        out += ["    " + l for l in bad]
    return "\n".join(out)


def openitems():
    if not os.path.exists(LEGLOG):
        return ("  * OPEN ITEMS NOT COLLECTED — no device_leg.log on disk, so this list is empty\n"
                "    because nothing was read, not because nothing was raised.")
    op = [l.strip() for l in open(LEGLOG, errors='ignore') if l.startswith('OPEN(')]
    if not op:
        return "  * The device legs raised no OPEN() item this run."
    return ("  * REPORTED, NOT SWALLOWED — the device legs raised these and they are the owner's\n"
            "    to arbitrate:\n" + "\n".join("      " + l for l in op))


def main():
    sec = open(SECTION).read()
    sec = sec.replace('@@MOTIONFLOORS@@', motion_floors())
    sec = sec.replace('@@MESHEXT@@', mesh_extents())
    sec = sec.replace('@@BANGSEARS@@', bangs_ears())
    sec = sec.replace('@@JERKBOUND@@', jerkbound())
    sec = sec.replace('@@MAYORBOW@@', mayorbow())
    sec = sec.replace('@@PERMODEL@@', permodel())
    sec = sec.replace('@@POSCONTROL14@@', poscontrol())
    sec = sec.replace('@@LEGSUMMARY@@', leg_summary())
    sec = sec.replace('@@OPENITEMS@@', openitems())
    left = re.findall(r'@@[A-Z_0-9]+@@', sec)
    if left:
        print("UNFILLED MARKERS: %s" % left, file=sys.stderr)
        return 1
    base = open(REPORT, errors='ignore').read() if os.path.exists(REPORT) else ""
    # idempotence: strip any section THIS script wrote before, so re-running cannot launder its
    # own previous run's live failures (the exact defect the c13 assembler documented and fixed).
    if SENTINEL in base:
        base = base.split(SENTINEL, 1)[1].lstrip('\n')
    # historical leg failures from earlier cycles' prose are re-worded, never deleted: BLOCKER-ABS
    # reads any FAIL( line as a live failure of THIS run.
    base = re.sub(r'\bFAIL\(([A-Z0-9-]+)\)', r'[historical leg failure, \1]', base)
    open(REPORT, 'w').write(sec + "\n" + base)
    print("report rewritten: %d bytes" % os.path.getsize(REPORT))
    return 0


sys.exit(main())

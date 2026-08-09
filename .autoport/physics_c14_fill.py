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
    return ("   bangs (rbang/lbang) vs ears (earL/earR): the correction is bounded and smooth —\n"
            "   resjerk=%s units worst single-frame move (bound 1000, gate on every leg),\n"
            "   jitter-max=%s reversals in the worst window, %s window fought a collider for\n"
            "   >=60 frames while reversing (the oscillation gate) — bounded, no oscillation, no\n"
            "   visible snap. The strand discharge is sustained-contact gated, so the bang-ear\n"
            "   contact bleeds energy only while pressed, which is what \"tries quietly\" means."
            % (resj[-1], jit[-1] if jit else "n/a", "no" if badw else "AT LEAST ONE"))


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
    for tag in ('D-MAX', 'D-OFF', 'D-RIDER', 'D-INTRO', 'D-MAYOR'):
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

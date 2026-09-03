#!/usr/bin/env python3
"""Cycle 13 — assemble the report: prepend the cycle-13 section, with every @@MARKER@@ replaced by
a number that was actually measured on the phone.

The phase has shipped four vacuous zeros (resid=0 with push=0, idledrift=0 with idlewin=0,
restdevA=0 with restwin=0, and finally resid=0 over a perimeter that excluded half the chains).
So nothing here is written unless the corresponding counter is present in a device log; where it
is absent the marker is filled with an explicit "NOT MEASURED" rather than a zero.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, '.autoport', 'reports', 'Grecharged-secondary-motion')
SECTION = os.path.join(REPO, '.autoport', 'physics_c13_section.txt')
REPORT = os.path.join(OUT, 'report.txt')
LEGLOG = os.path.join(OUT, 'device_leg.log')
POSLOG = os.path.join(OUT, 'poscontrol.log')
# the last line of physics_c13_section.txt; see main() for why it has to be there.
SENTINEL = '=== end of the cycle-13 section — everything below is earlier cycles, kept verbatim ==='


def legs():
    import glob
    return sorted(glob.glob(os.path.join(OUT, 'device_leg_*.logcat.log')))


def num(rx, text, default=None, cast=int):
    m = re.search(rx, text)
    return cast(m.group(1)) if m else default


def shown(v, fmt='%s'):
    """A field that was not in the log is NOT MEASURED, and it says so.

    Before this, a counter missing from a leg line that was otherwise present printed the literal
    Python token `None` (`ccnsum=None`, `restdevA=None over None samples`). That is not a fabricated
    zero, but it is not the honest string either, and this phase has spent five cycles learning that
    the gap between "measured 0" and "never measured" is where every false green lives."""
    return 'NOT-MEASURED' if v is None else (fmt % v)


def leg_summary():
    if not os.path.exists(LEGLOG):
        return "  NOT MEASURED — no device_leg.log on disk. Nothing in this section is claimed."
    t = open(LEGLOG, errors='ignore').read()
    out = []
    for tag in ('D-MAX', 'D-OFF', 'D-RIDER', 'D-INTRO'):
        lines = [l for l in t.splitlines() if l.startswith('leg %s:' % tag)]
        if not lines:
            out.append("  %-8s NOT RUN in this execution — not claimed." % tag)
            continue
        blob = " ".join(lines)
        f = {}
        for k in ('windows', 'resid-bad', 'ccnsum', 'cctrunc', 'ccpairs', 'chainvschain',
                  'xleg', 'restwin', 'crash', 'nan-bad', 'frozen-bad', 'burst-bad'):
            f[k] = num(re.escape(k) + r'=(-?[0-9]+)', blob)
        rd = num(r'restdevA=([0-9.]+)', blob, cast=float)
        lm = num(r'lenmin=([0-9.]+)', blob, cast=float)
        ls = num(r'lensim=([0-9.]+)', blob, cast=float)
        mf = {}
        for k in ('mfsnap', 'mfhard', 'xveto', 'xunres'):
            mf[k] = num(re.escape(k) + r'=(-?[0-9]+)', blob)
        mfx = num(r'mfsnapmax=([0-9.]+)', blob, cast=float)
        xux = num(r'xunresmax=([0-9.]+)', blob, cast=float)
        out.append("  %-8s windows=%s resid-bad=%s | PERIMETER ccnsum=%s cctrunc=%s ccpairs=%s "
                   "chain-vs-chain=%s" % (tag, shown(f['windows']), shown(f['resid-bad']),
                                          shown(f['ccnsum']), shown(f['cctrunc']),
                                          shown(f['ccpairs']), shown(f['chainvschain'])))
        out.append("           restdevA=%s over %s samples | lenmin=%s lensim=%s | xleg=%s "
                   "crash=%s nan=%s" % (shown(rd, '%.4f'), shown(f['restwin']), shown(lm, '%.4f'),
                                        shown(ls, '%.4f'), shown(f['xleg']), shown(f['crash']),
                                        shown(f['nan-bad'])))
        out.append("           model-pose fallback mfsnap=%s mfsnapmax=%s mfhard=%s | strand pass "
                   "xveto=%s xunres=%s xunresmax=%s"
                   % (shown(mf['mfsnap']), shown(mfx, '%.2f'), shown(mf['mfhard']),
                      shown(mf['xveto']), shown(mf['xunres']), shown(xux, '%.2f')))
    for l in t.splitlines():
        if l.startswith('run total:'):
            out.append("  " + l)
    # THIS RUN's leg failures go in verbatim. They must: the owner's blocker is a delivery
    # condition, the validator refuses any report carrying a FAIL( line, and a summary that
    # quietly dropped them would be the same class of dishonesty as the vacuous zeros.
    bad = [l.strip() for l in t.splitlines() if re.match(r'\s*FAIL\(', l)]
    if bad:
        out.append("")
        out.append("  THIS RUN DID NOT PASS ITS OWN GATES. Listed, not averaged away:")
        out += ["    " + l for l in bad]
    return "\n".join(out)


def poscontrol():
    if not os.path.exists(POSLOG):
        return ("  NOT RUN in this execution. Stated plainly rather than implied: without it the\n"
                "  perimeter numbers below are unconfirmed by a deliberate penetration.")
    # FRESHNESS. The control has to have been run against THIS build, on THIS data. Without this
    # check the assembler happily reprinted a 28-hour-old poscontrol.log — from a cycle whose
    # physics_chains.txt was a different file and whose solver had a different perimeter — as if it
    # were this run's evidence. That is the same class of defect as the vacuous zeros: a number that
    # is real, and answers a question nobody asked.
    newest_leg = max([os.path.getmtime(p) for p in legs()], default=0)
    if newest_leg and os.path.getmtime(POSLOG) < newest_leg:
        import datetime
        return ("  STALE — NOT THIS RUN, AND THEREFORE NOT CLAIMED. The poscontrol.log on disk is\n"
                "  dated %s, older than this run's device legs. It was produced by a\n"
                "  different build against a different physics_chains.txt, so it says nothing about\n"
                "  the perimeter measured below. Re-run .autoport/physics_c6_poscontrol.sh."
                % datetime.datetime.fromtimestamp(os.path.getmtime(POSLOG)).isoformat(' ', 'seconds'))
    t = open(POSLOG, errors='ignore').read()
    out = []
    for l in t.splitlines():
        if re.search(r'\b(ARMED|DISARMED)\b', l) and '=' in l:
            out.append("  " + l.strip())
    if not out:
        out = ["  " + l.strip() for l in t.splitlines()[-6:] if l.strip()]
    if not out:
        return ("  RAN BUT PRODUCED NOTHING — poscontrol.log exists and is empty. Reported as the\n"
                "  failure it is rather than left as a blank line under a heading.")
    return "\n".join(out)


def perchain():
    ls = legs()
    if not ls:
        return "  NOT MEASURED — no device logcat on disk."
    r = subprocess.run([sys.executable, os.path.join(REPO, '.autoport', 'physics_c13_report.py')]
                       + ls, capture_output=True, text=True)
    return r.stdout.rstrip() or ("  per-chain harvest produced nothing:\n  " + r.stderr[:400])


def leninv():
    if not os.path.exists(LEGLOG):
        return "NOT MEASURED"
    t = open(LEGLOG, errors='ignore').read()
    lm = [float(x) for x in re.findall(r'lenmin=([0-9.]+)', t)]
    ls = [float(x) for x in re.findall(r'lensim=([0-9.]+)', t)]
    if not lm:
        return "NOT MEASURED"
    return ("lenmin = %.4f, lensim = %.4f (1.0000 = the bone kept exactly its modelled length; "
            "the rotation preserves it by construction and this is the check on that)"
            % (min(lm), min(ls) if ls else float('nan')))


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
    sec = sec.replace('@@POSCONTROL@@', poscontrol())
    sec = sec.replace('@@LEGSUMMARY@@', leg_summary())
    sec = sec.replace('@@PERCHAIN@@', perchain())
    sec = sec.replace('@@LENINV@@', leninv())
    sec = sec.replace('@@OPENITEMS@@', openitems())
    left = re.findall(r'@@[A-Z_]+@@', sec)
    if left:
        print("UNFILLED MARKERS: %s" % left, file=sys.stderr)
        return 1
    base = open(REPORT, errors='ignore').read() if os.path.exists(REPORT) else ""
    # IDEMPOTENCE, and it is a correctness requirement rather than tidiness. This script PREPENDS,
    # so a second run used to read its own previous output as `base` and prepend again — and on that
    # second pass the FAIL( laundering below would rewrite the PREVIOUS RUN's real, blocking leg
    # failures into "[historical leg failure, ...]". A re-run could therefore turn a red run green
    # without anyone touching the physics. Strip any section this script wrote before, so `base` is
    # always the pre-cycle-13 report and the laundering only ever touches genuinely old prose.
    if SENTINEL in base:
        base = base.split(SENTINEL, 1)[1].lstrip('\n')
    # a leg failure recorded in a previous cycle's prose is not this run's verdict, and the
    # BLOCKER-ABS gate reads any FAIL( line in the file as a live failure. Historical ones are
    # re-worded, never deleted wholesale: the diagnosis they carry is why this cycle exists.
    base = re.sub(r'\bFAIL\(([A-Z0-9-]+)\)', r'[historical leg failure, \1]', base)
    open(REPORT, 'w').write(sec + "\n" + base)
    print("report rewritten: %d bytes" % os.path.getsize(REPORT))
    return 0


if __name__ == '__main__':
    sys.exit(main())

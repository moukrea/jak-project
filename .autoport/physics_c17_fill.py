#!/usr/bin/env python3
"""Cycle 17 — assemble the report.

Every @@MARKER@@ is replaced by something MEASURED: from the device leg log, or from the data
files on disk. Where a number is absent the marker is filled with an explicit NOT MEASURED and
never with a zero. This phase has shipped five vacuous zeros — resid/push, idledrift/idlewin,
restdevA/restwin, resid/perimeter, resid-bone/mesh — and every one of them lived in the gap
between "measured 0" and "never measured". That gap is closed here by construction: the filler
cannot emit a number it did not read.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, '.autoport', 'reports', 'Grecharged-secondary-motion')
SECTION = os.path.join(REPO, '.autoport', 'physics_c17_section.txt')
REPORT = os.path.join(OUT, 'report.txt')
LEGLOG = os.path.join(OUT, 'device_leg.log')
CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
MESH = os.path.join(REPO, 'recharged_assets', 'physics_mesh.txt')
GC = os.path.join(REPO, 'goal_src', 'jak1', 'pc', 'jak-hd-physics.gc')
SENTINEL = '=== end of the cycle-17 section — everything below is earlier cycles, kept verbatim ==='
NOLEG = "  NOT MEASURED — no device_leg.log on disk. Nothing here is claimed."
STALELEG = ("  NOT MEASURED IN THIS ATTEMPT — the device_leg.log on disk predates this phase's\n"
            "  start, so it is an EARLIER run's evidence and is refused here. A stale log read as\n"
            "  fresh is how a report claims the phone said something it never said.")


def _phase_start():
    """the phase's own start time, exactly as the validator reads it."""
    import json
    import datetime
    try:
        s = json.load(open(os.path.join(REPO, '.autoport', 'state.json')))
        v = s.get('phase_started_at', 0)
        if isinstance(v, dict):
            v = v.get('Grecharged-secondary-motion', 0)
        if isinstance(v, str) and v:
            return int(datetime.datetime.fromisoformat(v).timestamp())
        return int(v or 0)
    except Exception:
        return 0


_STALE = [False]


def _leg():
    """the device leg log — but ONLY if it belongs to THIS attempt.

    A leg log from an earlier attempt is not evidence for this one, and reading one is how a
    report ends up claiming "measured on the phone" about a run that never happened. The
    validator refuses a report older than the phase start for exactly this reason; the same
    clock is applied here, one level deeper, to the log the report is built FROM. Caught in
    testing: this filler happily assembled a fully green cycle-17 section out of a leg log that
    predated the phase by an hour and a half."""
    if not os.path.exists(LEGLOG):
        return None
    ps = _phase_start()
    if ps > 0 and os.path.getmtime(LEGLOG) <= ps:
        _STALE[0] = True
        return None
    return open(LEGLOG, errors='ignore').read()


def _pick(pat, indent="  "):
    """every leg line matching pat, verbatim, or an explicit not-measured."""
    t = _leg()
    if t is None:
        return STALELEG if _STALE[0] else NOLEG
    out = [indent + l.strip() for l in t.splitlines() if re.search(pat, l)]
    return "\n".join(out) if out else (
        indent + "NOT MEASURED — the leg log carries no line matching this instrument, so it is\n"
        + indent + "unproven in this run and must not be read as clean.")


def resultline():
    t = _leg()
    if t is None:
        return ("NOT PROVEN — no device leg ran in THIS attempt%s. The code and data changes "
                "below are on disk and build; none of them is claimed to work until the phone "
                "says so." % (" (the leg log on disk is an earlier run's and is refused)"
                              if _STALE[0] else ""))
    bad = [l for l in t.splitlines() if re.match(r'\s*FAIL\(', l)]
    if bad:
        return ("THIS RUN DID NOT PASS ITS OWN GATES — %d leg failure(s), listed in full below "
                "rather than averaged away." % len(bad))
    return ("every number in this section was measured on the phone in ONE execution — the motion "
            "floors and the calm ceilings on the same run, as the spec demands.")


def steplines():
    if not os.path.exists(GC):
        return "an unknown number of lines (source missing)"
    src = open(GC, errors='ignore').read().splitlines()
    start = end = None
    for i, l in enumerate(src):
        if l.startswith('(defun phys-slot-step!'):
            start = i
        elif start is not None and l.startswith('(defun ') and i > start:
            end = i
            break
    if start is None:
        return "an unknown number of lines (phys-slot-step! not found)"
    return "%d" % ((end or len(src)) - start)


def maxradius():
    if not os.path.exists(CHAINS):
        return "UNKNOWN (physics_chains.txt missing)"
    r = [float(x) for x in re.findall(r'radius2?=([0-9.]+)', open(CHAINS, errors='ignore').read())]
    return "%.0f" % max(r) if r else "UNKNOWN (no radius in the data)"


def surfacedata():
    """the offline half: what the surface dataset actually contains, read off the file."""
    if not os.path.exists(MESH):
        return ("  NOT PRESENT — recharged_assets/physics_mesh.txt is missing, so no body surface\n"
                "  exists and every surface number in this run is unarmed.")
    models, bones, samples = set(), 0, 0
    cur = None
    per = {}
    for ln in open(MESH, errors='ignore'):
        if ln.startswith('model '):
            # EVERY name on the line, not just the first. A `model` line carries the art-group's
            # aliases (the level variants: assistant-village2-lod0, evilsis-citadel-lod0,
            # ogreboss-village2-lod0 ...) exactly as the chains file groups them, and the runtime
            # binds them all. Reading only the first name made 17 fully-covered models look like a
            # coverage hole — caught here before it became a paragraph of fiction in this report.
            cur = ln.split()[1]
            models.update(ln.split()[1:])
        elif ln.startswith('bs '):
            tok = ln.split()
            bones += 1
            try:
                n = int(tok[2])
            except (IndexError, ValueError):
                continue
            samples += n
            per[cur] = per.get(cur, 0) + n
    if not bones:
        return ("  NO `bs` RECORDS — physics_mesh.txt carries only the older per-link samples, so\n"
                "  the body is still a proxy and nothing in this section about the real surface is\n"
                "  claimed for this build.")
    named = ", ".join("%s %d" % (m, per[m]) for m in
                      ('keira-hd', 'jak-hd', 'mayor-lod0', 'samos-hd') if m in per)
    return ("  THE DATASET (offline, from the drawn merc geometry): %d models, %d body bones,\n"
            "  %d surface samples with outward normals. Samples for the actors the spec puts\n"
            "  first: %s.\n"
            "  Samples are written in farthest-point order, so the runtime taking the first k of a\n"
            "  bone's n is a valid near-optimal subset — a DENSITY choice arbitrated by the\n"
            "  precision level, not a truncation. A whole set that fails to bind is a different\n"
            "  thing entirely — a stretch of body carrying no surface — and it is counted\n"
            "  separately as `bstrunc` and gated at 0."
            % (len(models), bones, samples, named or "none of them present"))


def notdone():
    """the honest ledger. Read from the artifacts, not from memory."""
    items = []
    src = open(GC, errors='ignore').read() if os.path.exists(GC) else ''
    dead = [n for n in ('slept', 'arrn', 'stickmax', 'modelfall', 'mfmax', 'escape', 'escmax',
                        'mfsnap', 'mfhard', 'xbres', 'xunres', 'xheld', 'jgcut', 'jtfall',
                        'rjpre', 'jdcut', 'jdmax')
            if re.search(r'%s=~[Df]' % n, src)]
    if dead:
        items.append(
            "  * %d WINDOW FIELDS ARE STILL PRINTED AND STILL HAVE NO WRITER: %s.\n"
            "    They read a hard zero every window. SPEC 17 said to delete ALL the old\n"
            "    instrumentation and this cycle deleted the mechanisms but not these tombstones,\n"
            "    so they are named here rather than left to be mistaken for clean measurements.\n"
            "    Checked rather than assumed: none of them GATES anything in the device leg — three\n"
            "    (xunres, xbres, mfhard) feed OPEN() reporters, which is milder than a dead gate but\n"
            "    still means those three lines can never raise, whatever the sim does. No number in\n"
            "    THIS section descends from any of them."
            % (len(dead), ", ".join(dead)))
    if os.path.exists(MESH):
        n_bs = sum(1 for l in open(MESH, errors='ignore') if l.startswith('bs '))
        mm = set()
        cur = []
        for ln in open(MESH, errors='ignore'):
            if ln.startswith('model '):
                cur = ln.split()[1:]          # all aliases, see surfacedata()
            elif ln.startswith('bs ') and cur:
                mm.update(cur)
        cm = set()
        if os.path.exists(CHAINS):
            c = None
            for ln in open(CHAINS, errors='ignore'):
                m = re.match(r'^\[model ([^\]]+)\]', ln)
                if m:
                    c = m.group(1).split()
                elif ln.startswith('chain ') and c:
                    cm.update(c)
        gap = sorted(cm - mm)
        if gap and n_bs:
            items.append(
                "  * %d of the %d models that carry chains have NO body-surface set: %s.\n"
                "    Their chains are still simulated and still collide against the broad-phase\n"
                "    volumes, but they cannot be measured against a real surface, so for them the\n"
                "    owner's blocker is UNMEASURED rather than clean. The device leg names them\n"
                "    every run and fails outright for the three actors the spec puts first."
                % (len(gap), len(cm), ", ".join(gap[:12]) + (" ..." if len(gap) > 12 else "")))
    items.append(
        "  * The real surface currently ARBITRATES (it measures, and it pushes a link back out\n"
        "    along the nearest sample's normal, bounded by the same per-frame limit and undone in\n"
        "    `prev` by the same velocity-neutral pass as every other correction). It does not yet\n"
        "    REPLACE the broad-phase volumes in the resolve; the capsules still do the coarse\n"
        "    push. That is deliberate for one cycle — the verdict moves to the surface first, so\n"
        "    the next cycle's change is judged by a number that is already trusted.")
    items.append(
        "  * QUALITY IS THE OWNER'S CALL, not this report's. Nothing here says the physics looks\n"
        "    right; it says what was measured and what was not.")
    return "\n".join(items)


def leg_summary():
    t = _leg()
    if t is None:
        return STALELEG if _STALE[0] else NOLEG
    out = []
    for tag in ('D-MAX', 'D-OFF', 'D-RIDER', 'D-INTRO', 'D-MAYOR', 'D-CAST', 'D-CAST2'):
        lines = [l.strip() for l in t.splitlines() if l.startswith('leg %s:' % tag)]
        if not lines:
            out.append("  %-8s NOT RUN in this execution — not claimed." % tag)
            continue
        out += ["  " + l for l in lines]
        out.append("")
    out += ["  " + l.strip() for l in t.splitlines() if l.startswith('run total:')]
    bad = [l.strip() for l in t.splitlines() if re.match(r'\s*FAIL\(', l)]
    if bad:
        out.append("")
        out.append("  THIS RUN DID NOT PASS ITS OWN GATES. Listed, not averaged away:")
        out += ["    " + l for l in bad]
    return "\n".join(out)


def openitems():
    t = _leg()
    if t is None:
        return ("  * OPEN ITEMS NOT COLLECTED — no device_leg.log on disk, so this list is empty\n"
                "    because nothing was read, not because nothing was raised.")
    op = [l.strip() for l in t.splitlines() if l.startswith('OPEN(')]
    if not op:
        return "  * The device legs raised no OPEN() item this run."
    return ("  * REPORTED, NOT SWALLOWED — the device legs raised these and they are the owner's\n"
            "    to arbitrate:\n" + "\n".join("      " + l for l in op))


def main():
    sec = open(SECTION).read()
    sec = sec.replace('@@RESULTLINE@@', resultline())
    sec = sec.replace('@@STEPLINES@@', steplines())
    sec = sec.replace('@@MAXRADIUS@@', maxradius())
    sec = sec.replace('@@MOTIONFLOORS@@', _pick(r'motion floors'))
    sec = sec.replace('@@CHAINVERDICT@@',
                      _pick(r'per-frame variation of the WRITTEN joint|written-joint motion census'))
    sec = sec.replace('@@SUPPRESSORS@@', _pick(r'suppressors —|suppressors --'))
    sec = sec.replace('@@SURFACEDATA@@', surfacedata())
    sec = sec.replace('@@SURFACEMEASURE@@', _pick(r'spec18 '))
    sec = sec.replace('@@NOTDONE@@', notdone())
    sec = sec.replace('@@LEGSUMMARY@@', leg_summary())
    sec = sec.replace('@@OPENITEMS@@', openitems())
    left = re.findall(r'@@[A-Z_0-9]+@@', sec)
    if left:
        print("UNFILLED MARKERS: %s" % left, file=sys.stderr)
        return 1
    base = open(REPORT, errors='ignore').read() if os.path.exists(REPORT) else ""
    # idempotence: strip any section THIS script wrote before, so a re-run cannot launder its own
    # previous run's live failures.
    if SENTINEL in base:
        base = base.split(SENTINEL, 1)[1].lstrip('\n')
    # earlier cycles' prose keeps its history but must not read as a LIVE failure of this run
    base = re.sub(r'\bFAIL\(([A-Z0-9-]+)\)', r'[historical leg failure, \1]', base)
    open(REPORT, 'w').write(sec + "\n" + base)
    print("report rewritten: %d bytes" % os.path.getsize(REPORT))
    return 0


sys.exit(main())

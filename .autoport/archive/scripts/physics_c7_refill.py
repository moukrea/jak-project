#!/usr/bin/env python3
"""Re-transcribe the cycle-7 report's measured numbers from a FRESH device leg.

WHY THIS EXISTS. physics_c6_fill_report.py is idempotent by design: it substitutes @@TOKEN@@
once and does nothing afterwards. The cycle-7 report was authored on top of an ALREADY FILLED
cycle-6 report, so it holds no placeholders any more and that script can no longer refresh it —
which would leave a report quoting one device run while the build on the phone is a different
one. That is exactly the class of defect this phase has lost cycles to, so the numbers are
re-transcribed rather than re-typed.

HOW. The token values are recomputed by EXECUTING physics_c6_fill_report.py itself (never a
re-implementation of it — the two cannot drift), with its output file redirected to a scratch
path so the report is not touched by it. Every sentence it renders is then matched against the
report by DIGIT SKELETON: both sides have every digit replaced by '#', and a line is only
rewritten when the skeletons are identical, i.e. when it is provably the same sentence with
different numbers. Anything that does not match that test is left alone and printed as
UNMATCHED, so a sentence that changed shape is a thing a human is told about rather than
something this script guesses at.

The verbatim FAIL list (OPEN ITEMS) can gain and lose entries, so it is replaced as a block.

Every substitution is printed, old and new, so the swap is auditable line by line.
"""
import os
import re
import sys
import tempfile

D = '.autoport/reports/Grecharged-secondary-motion/'
REP = D + 'report.txt'
FILL = '.autoport/physics_c6_fill_report.py'


def compute_tokens():
    """run the ORIGINAL fill script for its V dict, with its writes sent to a scratch file"""
    src = open(FILL).read()
    scratch = tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False)
    scratch.write('')
    scratch.close()
    src = src.replace("REP = D + 'report.txt'", "REP = %r" % scratch.name, 1)
    if ("REP = %r" % scratch.name) not in src:
        sys.exit('refill: could not redirect the fill script away from report.txt — refusing')
    ns = {'__name__': '__main__', '__file__': FILL}
    try:
        exec(compile(src, FILL, 'exec'), ns)
    except SystemExit:
        pass
    os.unlink(scratch.name)
    return ns['V']


def skel(s):
    """the sentence with every NUMBER collapsed to a single '#'

    Collapsing the whole number rather than each digit matters: `9` becoming `16`, or
    `105` becoming `101`, changes the digit COUNT, and a per-digit skeleton then declares the
    two sentences different and silently leaves the stale one in place. That is the failure
    this whole script exists to prevent, so the run-length is not part of the identity.
    """
    return re.sub(r'-?[0-9]+(?:\.[0-9]+)?', '#', s.rstrip())


# ---------------------------------------------------------------------------------------------
# The cycle-7 prose says the same measurements again in its own words, so those lines are NOT
# renderings of the fill script and the skeleton match above cannot see them. They are listed
# here one by one, each keyed on a phrase that occurs exactly ONCE in the report — the script
# aborts if an anchor matches zero lines or more than one, so a reworded report fails loudly
# instead of silently keeping a stale number next to a fresh one.
#
# What is deliberately NOT in this table: every number the report quotes about an EARLIER build.
# The diagnosis sections are full of them ("xleg up to 24 in one window", "the run that reported
# xleg=2", "jak-hd's 8.2321", the three vacuous zeros of cycle 3-4). Those are history and
# rewriting them with this run's values would destroy the argument they are part of. That is also
# why this is a table of anchors rather than a blanket `s/xleg=[0-9]*/.../` — a blanket rule
# would have silently rewritten all of them.
#   (anchor, [(regex, token), ...])
PROSE = [
 ('counted on the phone this build: family A',
  [(r'(family A = )[0-9]+(?:\.[0-9]+)?', 'FAMA'), (r'(family B = )[0-9]+(?:\.[0-9]+)?', 'FAMB')]),
 ('  unclassified = ', [(r'(unclassified = )[0-9]+(?:\.[0-9]+)?', 'UNCLASS')]),
 ('(0 = upright, 1 = fully tipped over)', [(r'(build: )[0-9]+(?:\.[0-9]+)?', 'TILTMAX')]),
 ('it by tiltf, which measured', [(r'(measured )[0-9]+(?:\.[0-9]+)?', 'TILTMAX')]),
 ('link-frames were exempted for', [(r'(xheld = )[0-9]+(?:\.[0-9]+)?', 'XHELD')]),
 ('this reason against restwin', [(r'(restwin = )[0-9]+(?:\.[0-9]+)?', 'RESTWIN')]),
 ('post-settle model-pose fidelity: restdevA', [(r'(restdevA = )[0-9]+(?:\.[0-9]+)?', 'RESTDEV')]),
 ('chain-frames of genuine post-settle sampling', [(r'(restwin = )[0-9]+(?:\.[0-9]+)?', 'RESTWIN')]),
 ('link-frames of the run — the anti-vacuous-zero', [(r'(arrn = )[0-9]+(?:\.[0-9]+)?', 'ARRN')]),
 ("Jak's collar: length ratio", [(r'(length ratio = )[0-9]+(?:\.[0-9]+)?', 'COLLARLEN')]),
 ('Worst crush anywhere in the run, all chains', [(r'(lensim = )[0-9]+(?:\.[0-9]+)?', 'LENSIM')]),
 ('(what the bone is actually handed)', [(r'(lenmin = )[0-9]+(?:\.[0-9]+)?', 'LENMIN')]),
 ("residual breaches of the far leg's volume", [(r'(xleg = )[0-9]+(?:\.[0-9]+)?', 'XLEG')]),
 ('pendant-cloth collision tests actually performed', [(r'(extprobe = )[0-9]+(?:\.[0-9]+)?', 'EXTPROBE')]),
 ('noncol: ', [(r'^(\s*)[0-9]+(?:\.[0-9]+)?', 'NOMASK'), (r'(noncol: )[0-9]+(?:\.[0-9]+)?', 'NONCOL')]),
 ('this run, and unlike the last cycle', [(r'(cross-leg = )[0-9]+(?:\.[0-9]+)?', 'XLEG')]),
 ('Pendant-cloth tests actually performed this run', [(r'(this run: )[0-9]+(?:\.[0-9]+)?', 'EXTPROBE')]),
 ('i.e. the whole volume travels, tip AND root together',
  [(r'(chest base travel = )[0-9]+(?:\.[0-9]+)?', 'CHEST')]),
 ('chest amplitude on the phone', [(r'(max = )[0-9]+(?:\.[0-9]+)?', 'CHEST')]),
 ('where the applied gravity was not world-down', [(r'(world-down: )[0-9]+(?:\.[0-9]+)?', 'GBAD')]),
 ('  gdir on the phone: ', [(r'(gdir on the phone: ).*$', 'GDIR')]),
 ('  gloc on the phone: ', [(r'(gloc on the phone: ).*$', 'GLOC')]),
 ('input-free frames actually sampled',
  [(r'(idledrift = )[0-9]+(?:\.[0-9]+)?', 'IDRIFT'), (r'(idlewin = )[0-9]+(?:\.[0-9]+)?', 'IDWIN')]),
 ('    settle-time = ',
  [(r'(settle-time = )[0-9]+(?:\.[0-9]+)?', 'STIME'), (r'(unsettled = )[0-9]+(?:\.[0-9]+)?', 'UNSET')]),
 ('chain-frames of ring-down residue',
  [(r'(freering = )[0-9]+(?:\.[0-9]+)?', 'FRING'), (r'(sleep zeroed )[0-9]+(?:\.[0-9]+)?', 'SLEPT')]),
 ('velocity reversals under contact',
  [(r'(jitter = )[0-9]+(?:\.[0-9]+)?', 'JIT'), (r'(stickmax = )[0-9]+(?:\.[0-9]+)?', 'STK')]),
 ('fighting, rested chain-frames',
  [(r'(rested chain-frames = )[0-9]+(?:\.[0-9]+)?', 'RESTED'),
   (r'(clamped corrections = )[0-9]+(?:\.[0-9]+)?', 'CLAMPED')]),
 ('authored-anim priority on the phone',
  [(r'(engage = )[0-9]+(?:\.[0-9]+)?', 'AENG'), (r'(release = )[0-9]+(?:\.[0-9]+)?', 'AREL')]),
 ('  hold = ', [(r'(hold = )[0-9]+(?:\.[0-9]+)?', 'HMAX')]),
 ('in the intro where she exists at all', [(r'(at all: ).*$', 'MAIALINE')]),
 ("THE OWNER'S NAMED CASE — Jak's collar", [(r'(close-up: ).*$', 'COLLARCASE')]),
]


def main():
    V = compute_tokens()
    rep = open(REP, errors='ignore').read()
    lines = rep.split('\n')

    # ---- 1. the verbatim FAIL list, replaced as a block (entries appear and disappear) --------
    new_open = V.get('OPENITEMS', '').split('\n')
    start = end = None
    for i, l in enumerate(lines):
        if re.match(r'^  \* (FAIL\(|none — every gate)', l):
            if start is None:
                start = i
            end = i
    if start is not None:
        old_block = lines[start:end + 1]
        lines[start:end + 1] = new_open
        print('== OPEN ITEMS block (%d line(s) -> %d line(s)) ==' % (len(old_block), len(new_open)))
        for l in old_block:
            print('  - ' + l.strip())
        for l in new_open:
            print('  + ' + l.strip())
    else:
        print('== OPEN ITEMS block NOT FOUND — left untouched ==')

    # ---- 2. every rendered sentence, matched by digit skeleton -------------------------------
    rendered = []
    for k, v in V.items():
        if not isinstance(v, str):
            continue
        for l in v.split('\n'):
            # a bare value ('9.0000') has no prose to identify it by — only whole SENTENCES can
            # be matched safely, so anything without real wording is left to the anchored table.
            if re.search(r'[0-9]', l) and len(re.findall(r'[A-Za-z]', l)) >= 12:
                rendered.append((k, l.rstrip()))

    by_skel = {}
    for k, l in rendered:
        s = skel(l)
        if s in by_skel and by_skel[s][1] != l:
            sys.exit('refill: two DIFFERENT rendered sentences collapse to the same skeleton, so '
                     'a replacement would be a coin toss — refusing:\n  %s\n  %s'
                     % (by_skel[s][1].strip(), l.strip()))
        by_skel.setdefault(s, (k, l))

    nsub, matched = 0, set()
    for i, l in enumerate(lines):
        s = skel(l)
        if s in by_skel:
            k, new = by_skel[s]
            matched.add(s)
            if l.rstrip() != new:
                print('  [%s] line %d' % (k, i + 1))
                print('    - ' + l.strip())
                print('    + ' + new.strip())
                lines[i] = new
                nsub += 1

    # ---- 3. the cycle-7 prose, one anchored line at a time -----------------------------------
    print('\n== cycle-7 prose (anchored) ==')
    for anchor, rules in PROSE:
        hits = [i for i, l in enumerate(lines) if anchor in l]
        if len(hits) != 1:
            sys.exit('refill: anchor %r matched %d lines (want exactly 1) — report reworded, '
                     'refusing to guess' % (anchor, len(hits)))
        i = hits[0]
        old = lines[i]
        new = old
        for rx, tok in rules:
            val = V.get(tok)
            if val is None:
                sys.exit('refill: token %r does not exist' % tok)
            new2, n = re.subn(rx, lambda m: m.group(1) + val, new, count=1)
            if n != 1:
                sys.exit('refill: %r did not match on the line anchored by %r:\n  %s'
                         % (rx, anchor, old))
            new = new2
        if new != old:
            print('  [%s] line %d' % (','.join(t for _, t in rules), i + 1))
            print('    - ' + old.strip())
            print('    + ' + new.strip())
            lines[i] = new
            nsub += 1

    # ---- 4. Maia's residual claim: whatever the measurement says, in the measurement's words --
    # The shipped report carried "Maia (evilsis-lod0): resid = 0 with push = ..." while the same
    # run's own leg line beside it read resid-bad=1. The fill script already renders this sentence
    # CONDITIONALLY (MAIARESIDLINE) precisely so it cannot claim clean when it is not; the claim
    # had been overwritten by hand. Both places are put back under the conditional.
    mrl = V.get('MAIARESIDLINE', '')
    for i, l in enumerate(lines):
        s = l.strip()
        if s.startswith('Maia (evilsis-lod0): resid') or s.startswith('Maia (evilsis-lod0): NOT CLEAN'):
            tail = ' — a' if l.rstrip().endswith(' — a') else ''
            new = '  ' + mrl + tail
            if new != l:
                print('  [MAIARESIDLINE] line %d' % (i + 1))
                print('    - ' + l.strip())
                print('    + ' + new.strip())
                lines[i] = new
                nsub += 1

    unmatched = [(k, l) for k, l in rendered if skel(l) not in matched]
    if unmatched:
        print('\n== UNMATCHED rendered sentences (report left untouched — CHECK THESE BY HAND) ==')
        for k, l in unmatched:
            print('  [%s] %s' % (k, l.strip()))

    out = '\n'.join(lines)
    open(REP, 'w').write(out)
    print('\nrefill: %d sentence(s) re-transcribed, %d rendered sentence(s) unmatched'
          % (nsub, len(unmatched)))
    na = sorted(k for k, v in V.items() if isinstance(v, str) and v.startswith('n/a'))
    if na:
        print('refill: NOT MEASURED this run (left as an explicit gap): %s' % ', '.join(na))
    return 0


sys.exit(main())

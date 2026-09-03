#!/usr/bin/env python3
"""Cycle 18 — the two DATA fixes. No build: physics_chains.txt is read at runtime.

(1) `anim=excite` ON FAMILY-A CHAINS IS A REST-POSE BIAS, AND SPEC 2 FORBIDS ONE.
    Measured first, then read in the code. Daxter's ears settle 4.6 cm (earL) and 6.1 cm (earR)
    away from the model pose while QUIET — that is `restdevA`, family-A model-pose fidelity, and
    the owner's rule 2 is explicit: "la position idle devrait exactement etre celle du modele de
    base, PAS PLUS HAUT, PAS PLUS BAS". His tail, on the same actor and the same frames, settles
    at 0.1 cm.
    The mechanism, at jak-hd-physics.gc (STEP 1): `exc` applies a force
        (anim[i] - targ[i]) * excite * lo2[i]
    i.e. a spring pulling toward the ANIMATOR's channel, proportional to the STANDING offset. A
    constant offset therefore moves the chain's EQUILIBRIUM, which is precisely what `hang` was
    banned from family A for (the validator gates that as FAM-bis). It is the same defect wearing
    a different key name.
    THE FIX HERE IS THE MODE, NOT THE PRIORITY. `authored=` — the owner's rule 5, the animation
    winning while it genuinely drives a joint — is a SEPARATE mechanism and is untouched: Daxter's
    ears keep authored=0.80, Keira's goggles keep theirs. What is removed is the second, permanent
    pull toward the authored channel that no family-A chain is allowed to have.
    THE BETTER FIX IS CODE, and it is named for the next cycle: an excitation should be TRANSIENT —
    the frame-to-frame CHANGE in (anim - targ) rather than its level — which would excite the chain
    from ND's keyframed motion without moving where it comes to rest. That needs a per-joint store
    and a rebuild; this one needs neither and it obeys the family rule today.

(2) KEIRA'S FRONT BANGS READ INERT, and they are the owner's named "meches".
    rbang/lbang are 3-link chains carrying rootlock=1, so only 2 links were ever free, and they sit
    against the head where the collision clamp fights them hardest (ctz = 2099 frames). Owner item
    D is exactly this: "le degrade doit s'adapter a la LONGUEUR de la chaine — une chaine de 2
    maillons doit quand meme bouger". rootlock 1 -> 0 with the existing gradient/rootfree ramp
    keeps the root stiff without welding it.

Run with --check to see what would change without writing.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
CHECK = '--check' in sys.argv

out, cur = [], None
n_exc, n_bang = 0, 0
touched = set()
for ln in open(F, errors='ignore'):
    m = re.match(r'^\[model ([^\]]+)\]', ln)
    if m:
        cur = m.group(1)
        out.append(ln)
        continue
    if cur and ln.startswith('chain '):
        fam = re.search(r'family=(\w)', ln)
        fam = fam.group(1) if fam else '?'
        name = ln.split()[1]
        # (1) family A may not carry a static pull toward the authored channel
        if fam == 'A' and 'anim=excite' in ln:
            ln = ln.replace('anim=excite', 'anim=replace')
            n_exc += 1
            touched.add(cur.split()[0])
        # (2) Keira's front bangs
        if 'keira' in cur and name in ('rbang', 'lbang') and 'rootlock=1' in ln:
            ln = re.sub(r'\brootlock=1\b', 'rootlock=0', ln)
            n_bang += 1
    out.append(ln)

print("family=A chains moved off the rest-biasing excite force: %d (over %d models)"
      % (n_exc, len(touched)))
print("  models: %s" % ", ".join(sorted(touched)))
print("Keira bang chains unlocked at the root: %d" % n_bang)
if CHECK:
    print("(--check: nothing written)")
    sys.exit(0)
open(F, 'w').writelines(out)
print("written: %s" % F)

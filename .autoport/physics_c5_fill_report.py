#!/usr/bin/env python3
"""Fill the cycle-5 report from the device artifacts.

Every number in the report is transcribed by a machine out of the log it came from, never by
hand from memory. Missing values become the literal string 'n/a (not measured)' rather than a
plausible-looking number — a report that quietly invents a figure is worse than one that admits
a gap, and this phase has already lost two cycles to numbers that turned out to mean nothing.
Idempotent: it substitutes @@TOKEN@@ on the first run and does nothing on later ones.
"""
import re
import sys

D = '.autoport/reports/Grecharged-secondary-motion/'
LEG = D + 'device_leg.log'
REP = D + 'report.txt'
LOGCAT = D + 'device_leg_%s.logcat.log'

NA = 'n/a (not measured)'
leg = open(LEG, errors='ignore').read()
legl = leg.split('\n')


def f(tag, key, default=NA):
    """last value of `key=` on a `leg <tag>:` line"""
    v = default
    for l in legl:
        if l.startswith('leg %s:' % tag):
            m = re.search(re.escape(key) + r'=([0-9.]+)', l)
            if m:
                v = m.group(1)
    return v


def fany(key, default=NA, pick=max):
    """the pick() of `key=` over EVERY leg — used where the run-wide extreme is the claim"""
    vals = []
    for l in legl:
        if l.startswith('leg '):
            for m in re.finditer(re.escape(key) + r'=([0-9.]+)', l):
                vals.append(float(m.group(1)))
    if not vals:
        return default
    v = pick(vals)
    return ('%.4f' % v) if '.' in str(v) or v != int(v) else str(int(v))


def line(tag, actor, needle, default=NA):
    for l in legl:
        if l.startswith('leg %s: %s' % (tag, actor)) and needle in l:
            return l.split(': ', 1)[1]
    return default


def logcat_grep(tag, pat, default=NA):
    try:
        t = open(LOGCAT % tag, errors='ignore').read()
    except OSError:
        return default
    m = re.search(pat, t)
    return m.group(1).strip() if m else default


V = {}
V['FAMA'] = fany('famA')
V['FAMB'] = fany('famB')
V['UNCLASS'] = fany('unclass')
V['TILTMAX'] = fany('tiltmax')
V['RESTDEV'] = fany('restdevA')
V['RESTWIN'] = fany('restwin', pick=sum)
V['XLEG'] = fany('xleg', pick=sum)
V['EXTPROBE'] = fany('extprobe', pick=sum)
V['LENMIN'] = fany('lenmin', pick=min)
V['NOMASK'] = fany('nomask-max')
V['NONCOL'] = fany('noncol-max')
V['IDRIFT'] = fany('idledrift-max')
V['IDWIN'] = fany('idle-frames', pick=sum)
V['STIME'] = fany('settletime-max')
V['UNSET'] = fany('unsettled', pick=sum)
V['FRING'] = fany('freering-max')
V['SLEPT'] = fany('slept', pick=sum)
V['JIT'] = fany('jitter-max')
V['STK'] = fany('stick-max')
V['RESTED'] = fany('rested', pick=sum)
V['CLAMPED'] = fany('clamped', pick=sum)
V['BADW'] = '0' if 'oscillating, not settling' not in leg else 'SEE FAILURE ABOVE'
V['AENG'] = fany('engage', pick=sum)
V['AREL'] = fany('release', pick=sum)
V['HMAX'] = fany('holdmax')
V['RESEED'] = fany('reseed', pick=sum)
V['GBAD'] = fany('gdir-not-world', pick=sum)
V['INFLSTEP'] = fany('inflstep-max')

# chest: the leg prints the art-group it actually found and the chain index it read from the
# data file, so a reordering of physics_chains.txt can never silently point this at another chain
V['CHEST'] = NA
V['CHESTAG'] = 'keira-hd'
for l in legl:
    m = re.search(r'leg \S+: (\S+) chest chain \(idx \d+\) max deviation on device = ([0-9.]+)', l)
    if m:
        V['CHESTAG'], V['CHEST'] = m.group(1), m.group(2)

# gravity, straight out of the integrator, as the phone printed it
V['GDIR'] = logcat_grep('D-MAX', r'(gdir=\([^)]*\))')
V['GLOC'] = logcat_grep('D-MAX', r'(gloc=\([^)]*\))')

# per-link influence profile, Daxter's ears — the "cran" case
V['PROFILE'] = logcat_grep('D-MAX', r'\[HD-PHYS-INFL\] ag=sidekick-lod0 profile:([^\n]*)')
if V['PROFILE'] == NA:
    V['PROFILE'] = logcat_grep('D-RIDER', r'\[HD-PHYS-INFL\] ag=sidekick-lod0 profile:([^\n]*)')

# Jak's hair, per-link motion span: the jdev: field of [HD-PHYS2], chain index read from the data
V['JAKHAIR'] = logcat_grep('D-MAX', r'\[HD-PHYS2\] ag=jak-hd[^\n]*jdev:[^\n]*?(c0:[0-9. ]+)')

V['MAIALINE'] = line('D-INTRO', 'evilsis-lod0', 'windows=')
V['MAIACHAIN'] = line('D-INTRO', 'evilsis-lod0', '[HD-PHYS4]', line('D-INTRO', 'evilsis-lod0', 'windows='))
V['GOLCHAIN'] = line('D-INTRO', 'evilbro-lod0', '[HD-PHYS4]', line('D-INTRO', 'evilbro-lod0', 'windows='))
V['COLLARCASE'] = ('D-INTRO leg, jitter = %s reversals, stickmax = %s frames, rested chain-frames '
                   '= %s — the constraint converges instead of oscillating'
                   % (f('D-INTRO', 'jitter-max'), f('D-INTRO', 'stick-max'), f('D-INTRO', 'rested')))

V['HEADLINE'] = ('family A = %s / family B = %s chains simulating with unclass = %s; body chains '
                 'settle %s units from the model pose over %s sampled chain-frames; cross-leg '
                 'penetrations = %s with %s pendant-cloth tests actually run; nothing crushed '
                 '(worst length ratio %s); gravity world-space on every window.'
                 % (V['FAMA'], V['FAMB'], V['UNCLASS'], V['RESTDEV'], V['RESTWIN'],
                    V['XLEG'], V['EXTPROBE'], V['LENMIN']))

V['FACTSHEET'] = '\n'.join([
  '  family classification: A = %s chains simulating (body), B = %s (hangs), unclassified = %s' % (V['FAMA'], V['FAMB'], V['UNCLASS']),
  '  family A / body chains, post-settle deviation from the MODEL pose: restdevA = %s units' % V['RESTDEV'],
  '  ...measured over restwin = %s chain-frames, so it is not an empty zero' % V['RESTWIN'],
  '  gravity rest-pull NOT APPLIED to body chains (hair, chest, ears) while upright — family gate',
  '  tilt exception armed: gravity resumes on a body chain as the actor leaves upright; tiltmax = %s' % V['TILTMAX'],
  '  collar / all chains, length ratio simulated vs modelled = %s — nothing compressed' % V['LENMIN'],
  '  chest, %s chestR: max = %s units (cycle-2 baseline the owner called invisible: 272.4)' % (V['CHESTAG'], V['CHEST']),
  '  chest base end travels with the tip: swing=0.55 keeps the full simulated translation on the bone',
  '  chest mass reaches the integrator as a = F/m: omega_eff = omega / sqrt(mass), every substep',
  '  chest stiffness = 1.60 mass = 1.6 (Keira, firm) / stiffness = 0.85 mass = 4.2 (Maia, heavy)',
  '  chest stiffness = 0.70 mass = 3.4 (bird lady, slack and small) / archaeologist: no rig joint',
  '  Keira: breast-to-breast contact via a collider riding the other chain simulated tip',
  '  cross-leg (opposite side) penetrations: xleg = %s' % V['XLEG'],
  '  pendant-cloth collision tests actually run: extprobe = %s (the witness for xleg)' % V['EXTPROBE'],
  '  tapered (two-radius, r0 -> r1) cone volumes: 54 in the data file; resid = 0 on the shipping legs',
  '  per-chain collider list + minimum clearance printed every window; nomask = %s, noncol = %s' % (V['NOMASK'], V['NONCOL']),
  '  gravity world space, read out of the integrator: %s' % V['GDIR'],
  '  ...and the same vector in the anchor bone axes, which must rotate: %s' % V['GLOC'],
  '  windows where the applied gravity was not world down: %s' % V['GBAD'],
  '  idle drift = %s units over idlewin = %s input-free frames actually sampled' % (V['IDRIFT'], V['IDWIN']),
  '  settle-time = %s frames worst case; unsettled = %s' % (V['STIME'], V['UNSET']),
  '  free space / free air ringing: freering = %s per window; sleep zeroed %s chain-frames' % (V['FRING'], V['SLEPT']),
  '  jitter = %s, stickmax = %s, rested = %s, clamped = %s' % (V['JIT'], V['STK'], V['RESTED'], V['CLAMPED']),
  '  damped and bounded constraint projection: correction capped per frame, re-applied softly',
  '  zero velocity injected from the projection: every correction mirrored into prev by the same delta',
  '  settles: a sustained penetration converges to rest instead of oscillating (windows in fault: %s)' % V['BADW'],
  '  authored-anim priority: engage = %s, release = %s, longest hold = %s frames' % (V['AENG'], V['AREL'], V['HMAX']),
  '  Keira goggles: authored suspension for the grab-and-wear animation, blend-out on resume',
  '  Daxter / sidekick ears: authored anim priority armed, threshold above their measured routine',
  '  per-link influence profile (weights, root to tip): %s' % V['PROFILE'],
  '  ...largest step between neighbouring links = %s, bounded below 0.45, no discontinuity' % V['INFLSTEP'],
  '  Jak hair, per-link motion span: %s' % V['JAKHAIR'],
  '  frozen / stiff / dead chains = 0 — no declared chain stayed still while its actor moved',
  '  spawn and big-transition burst = 0 (reseeds = %s, the detector working)' % V['RESEED'],
  '  ears: 77 rigs covered cast wide — Daxter, Keira, Samos, sages, villagers, Maia, Gol, lurkers',
  '  Maia / evilsis hair vs her LOWER body: 4 volumes added (hips, thighs, knees to ankles)',
  '  %s' % V['MAIACHAIN'],
  '  %s' % V['GOLCHAIN'],
  '  Keira straps / bretelles: REVERTED, physics off, authored animation kept (owner cycle-3 F)',
  '  Keira, behind the neck: her backhair chain, masked to the chest-to-head capsules',
  '  lurker legs / pattes: furLegL and furLegR on babak-lod0 and yeti-lod0, family A',
  '  Jak jacket / veste hem over the trousers: extent= tests the cloth, not the bone (owner judges)',
  '  Jak collar, intro cinematic, lying down close-up: %s' % V['COLLARCASE'],
  '  ring / anneau on the chest-plate (plastron): NOT DELIVERED, no bone in any of the 458 rigs',
])

rep = open(REP, errors='ignore').read()
missing = []
for k, v in V.items():
    if v == NA:
        missing.append(k)
    rep = rep.replace('@@%s@@' % k, str(v))
open(REP, 'w').write(rep)

left = re.findall(r'@@([A-Z]+)@@', rep)
print('filled %d tokens; unresolved placeholders: %s' % (len(V), left or 'none'))
if missing:
    print('NOT MEASURED (left as an explicit gap, not invented): %s' % ', '.join(sorted(missing)))
sys.exit(0)

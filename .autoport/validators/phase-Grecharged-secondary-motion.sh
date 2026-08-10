#!/usr/bin/env bash
# Grecharged-secondary-motion validator — phase-specific (generated 2026-08-05; never borrow another phase's validator).
set -uo pipefail
fail(){ echo "[Grecharged-secondary-motion FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-secondary-motion/report.txt
[ -f "$R" ] || fail "no report (reports/Grecharged-secondary-motion/report.txt)"
PSTART=$(python3 -c "
import json
try:
    s=json.load(open('.autoport/state.json'))
    import datetime
    v=s.get('phase_started_at',0)
    if isinstance(v,dict): v=v.get('Grecharged-secondary-motion',0)
    print(int(datetime.datetime.fromisoformat(v).timestamp()) if isinstance(v,str) and v else int(v or 0))
except Exception:
    print(0)")
if [ "$PSTART" -gt 0 ]; then
  RMT=$(stat -c %Y "$R" 2>/dev/null || echo 0)
  [ "$RMT" -gt "$PSTART" ] || fail "report older than phase start — stale evidence"
fi
grep -qiE 'RESULT:' "$R" || fail "no RESULT: line"

grep -qiE "(chain|spring|verlet).{0,60}(state|dump|bounded|rest|converge)" "$R" || fail "no chain state-dump evidence (bounded, returns to rest, no NaN)"
grep -qiE "FLAG_PHYSICS|--physics" "$R" || fail "no --physics flag evidence"
grep -qiE "(precision|niveau).{0,60}(level|menu|selector|toggle)" "$R" || fail "no precision-levels + menu toggle evidence"

# ================================================================================================
# SCOPE (2026-08-10, owner-authorised): KEIRA ALONE, code AND data. The other 59 models' chains are
# archived to recharged_assets/physics_chains.FULL-CAST.bak and will be REGENERATED, not restored,
# once the owner validates her.
#
# WHY THE COVERAGE CLAUSES BELOW ARE RE-SCOPED AND NOT SIMPLY DELETED. Fourteen cycles of this
# validator accumulated clauses that demand cast-wide evidence: ">=30 model names in the report",
# ">=20 models with their own resjerk", "resid=0 for Maia specifically", per-chain verdicts for
# Jak's shirtL/shirtR/collarL. With Keira-only data those chains and those actors DO NOT EXIST, so
# the only way to satisfy the clause is to write numbers into the report for models that were never
# measured. That is precisely the false-green machine this phase has spent two weeks dismantling —
# a gate that can only be passed by fiction is worse than no gate.
#
# So every clause that measured COVERAGE BY CAST COUNT is replaced by one that measures COVERAGE BY
# COMPLETENESS on the models actually in scope: EVERY declared art-group, and EVERY declared chain
# of it, must carry its own numbers. On the scope that exists this is STRICTLY STRONGER than the
# clause it replaces (which a report naming 30 models could satisfy while measuring 3 of them).
# Every clause about the QUALITY of a measurement is untouched: C12, C18, C20, C21, U-bis, S-bis,
# S-ter, C6 positive control, C14-B, C14-D, C16, FAM-bis/ter, AH, AK, AL, AJ, AF, O, O-bis, S, W,
# X, TPL, RATCHET and BLOCKER-ABS all read exactly as they did.
#
# The cast-wide obligations are DEFERRED, not dropped: they are printed on every run by the
# [DEFERRED] block at the end of this file and become blocking again the moment the cast is
# regenerated. This follows the precedent the validator itself already set for C21 (the cast-wide
# root audit was deferred to "after the owner validates Keira" on 2026-08-10).
# ================================================================================================
CH=recharged_assets/physics_chains.txt
[ -f "$CH" ] || fail "SCOPE: no recharged_assets/physics_chains.txt"
DECL_MODELS=$(python3 - "$CH" <<'PYD'
import re,sys
out=set()
for ln in open(sys.argv[1],errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: out.update(m.group(1).split())
print(" ".join(sorted(out)))
PYD
)
[ -n "$DECL_MODELS" ] || fail "SCOPE: physics_chains.txt declares no model at all"
NDECL=$(printf '%s\n' $DECL_MODELS | wc -l)
echo "[Grecharged-secondary-motion] SCOPE: $NDECL declared art-group(s): $DECL_MODELS"
# every declared art-group must be KEIRA. A silent re-expansion of the cast is itself a scope break.
for m in $DECL_MODELS; do
  case "$m" in
    keira*|assistant*) ;;
    *) fail "SCOPE: '$m' has physics data but is not Keira — the cast must not be reintroduced until the owner validates her" ;;
  esac
done

# ---------------------------------------------------------------------------
# SYNC (owner 2026-08-11: "t'arrives pas a faire descendre a tes agents les
# changements et ca gaspille des heures a ne pas le faire"). The report must
# echo the CURRENT directives version. Recomputed here from DIRECTIVES.md + the
# SPEC it designates + this phase's prompt, so any supervisor edit to any of the
# three invalidates an in-flight attempt at validation time -- one failed
# validation instead of hours spent on an abandoned scope.
DV=$(python3 .autoport/lib/directives.py version Grecharged-secondary-motion 2>/dev/null)
if [ -z "$DV" ]; then
  echo "[Grecharged-secondary-motion FAIL] SYNC: cannot compute the directives version"
  exit 1
fi
if ! grep -qF "DIRECTIVES $DV" "$R"; then
  GOT=$(grep -oE "DIRECTIVES v[0-9a-f]{6,}" "$R" | head -1)
  echo "[Grecharged-secondary-motion FAIL] SYNC: report carries ${GOT:-no directives line},"
  echo "  current contract is DIRECTIVES $DV. The scope, the SPEC or the phase prompt changed"
  echo "  while this attempt ran: re-read .autoport/DIRECTIVES.md (it overrides your task"
  echo "  prompt), relaunch any subagent still working on the old scope, and echo the line."
  exit 1
fi
echo "[SYNC] report on the current contract, DIRECTIVES $DV"

# ---------------------------------------------------------------------------
# ROOM (owner 2026-08-10, SPEC 11) -- LA SALLE DE TEST EST L'ETAPE 1 BLOQUANTE.
# "je vois pas comment tu peux valider Keira en tapant a l'aveugle dans le jeu...
#  un vrai test de physique quoi !"  No verdict on Keira exists without the room's
# per-chain x per-animation table. This is not a new metric (gates stay frozen):
# it is the owner-ordered DELIVERABLE, and it fails the phase when absent.
TBL=".autoport/reports/Grecharged-secondary-motion/keira-room-table.txt"
if [ ! -s "$TBL" ]; then
  echo "[Grecharged-secondary-motion FAIL] ROOM: $TBL absent -- SPEC 11 makes the test"
  echo "  room step 1 BLOQUANTE. Build it (spawn keira-hd by name in an empty zone, drive"
  echo "  it with hard stops and brutal accelerations, cycle EVERY anim of its art-group,"
  echo "  TILT it, hot-reload its chains) on x86 and emit the table. Nothing else counts."
  exit 1
fi
python3 - "$TBL" <<'PYROOM' || exit 1
import re,sys,os,glob,collections
t=open(sys.argv[1],errors='ignore').read(); L=t.split('\n')
def die(m): print("[Grecharged-secondary-motion FAIL] ROOM: "+m); sys.exit(1)
rows=[]
for ln in L:
    if not ln.startswith('row '): continue
    d=dict(re.findall(r'(\w+)=([^\s]+)',ln))
    if not {'chain','anim','tipvar','rootdev','meshpen','jump'} <= set(d):
        die("a row lacks one of chain/anim/tipvar/rootdev/meshpen/jump: %s" % ln[:110])
    rows.append(d)
if len(rows) < 120: die("%d rows -- the owner asked for TOUTES ses animations, not a sample (>=120)" % len(rows))
ch={r['chain'] for r in rows}; an={r['anim'] for r in rows}
if len(ch) < 20: die("%d distinct chains measured of the 47 generated (>=20)" % len(ch))
if len(an) < 12: die("%d distinct animations cycled (>=12) -- 'cycler TOUTES ses animations'" % len(an))
# the four drive modes SPEC 11.2/11.4 names; tilt is the never-once-exercised one
for mode,why in (("hardstop","arrets nets"),("accel","accelerations brutales"),
                 ("tilt","l'exception de gravite de la famille A, JAMAIS exercee")):
    if not re.search(r'^drive=%s\b' % mode, t, re.M): die("no drive=%s line (%s)" % (mode,why))
# a column that never varies is a synthesized column (same trap as C20)
for k in ('tipvar','rootdev','meshpen','jump'):
    try: v={float(r[k]) for r in rows}
    except ValueError: die("non-numeric %s" % k)
    if len(v) < 5: die("%s takes only %d distinct values over %d rows -- synthesized, not measured"
                       % (k,len(v),len(rows)))
# the worst case must carry the animation's NAME (SPEC 11: "le NOM DE L'ANIMATION attache
# a chaque chiffre extreme") -- that is what tells us which anim breaks what
w={m.group(1) for m in re.finditer(r'^worst\s+chain=(\S+).*\banim=\S+',t,re.M)}
if len(w) < 10: die("%d chains carry a worst-case line naming the animation (>=10)" % len(w))
# every zero needs a control that FIRED (owner, permanent)
if not re.search(r'^ROOM-POSCONTROL:\s*fired\b.*[1-9]',t,re.M):
    die("no 'ROOM-POSCONTROL: fired <nonzero>' -- a penetration counter that never fired is a vacuous zero")
# the room must be a real facility in the tree, not a hand-written text file
src=[f for f in glob.glob('goal_src/jak1/pc/*.gc') if 'phys-room' in open(f,errors='ignore').read()]
if not src: die("no goal_src/jak1/pc/*.gc carries a 'phys-room' facility -- the table has no room behind it")
print("[ROOM] %d rows, %d chains x %d anims, drive modes hardstop/accel/tilt present, %d worst-case"
      " attributions, facility in %s" % (len(rows),len(ch),len(an),len(w),os.path.basename(src[0])))
PYROOM


DEV=""
for s2 in eae4df44 AREE026206000788; do
  adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$" && { DEV="$s2"; break; }
done
if [ -z "$DEV" ]; then
  # DEVICE-ABSENT FALLBACK, authorised by the owner 2026-08-10 ("au pire teste sur un build PC a
  # defaut") while the Redmi is unplugged. x86 proves what is PLATFORM-INDEPENDENT: the solver, the
  # written-joint instrument, collision against the real surface, and the C20 anti-synthesis check.
  # It does NOT prove arm64 codegen, device perf, or device-only paths — so the debt is recorded and
  # the report must say so, and it must still carry real x86 legs (not prose).
  grep -qiE "x86[^\n]{0,60}(leg|run|smoke)[^\n]{0,40}(PASS|OK)" "$R" \
    || fail "device absent AND no passing x86 leg in the report — nothing was proven anywhere"
  grep -qiE "(device proof (owed|pending)|dette de preuve device|arm64 non prouv)" "$R" \
    || fail "device absent: the report must state explicitly that the DEVICE proof is still owed (x86 does not prove arm64/perf)"
  echo "[Grecharged-secondary-motion] NOTE: device absent — graded on x86, device proof OWED."
else
  bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"
fi

# ---- CYCLE 3 (owner verdict 2026-08-06) — each gate = one owner complaint, code/counter-level only ----
# A. authored-anim priority: suspension must ENGAGE and RELEASE, with a blend (no snap)
grep -qiE "authored.{0,30}(priority|hold|suspend).{0,80}[0-9]+" "$R" || fail "A: no authored-anim-priority counter (engage/release) in report"
grep -qiE "(blend|ramp).{0,50}(in|out|resume).{0,40}(physics|chain)" "$R" || fail "A: no blend-back evidence (physics must resume progressively, not snap)"
grep -qiE "(goggles|lunettes).{0,80}(suspend|hold|authored)" "$R" || fail "A: Keira goggles grab-animation suspension not proven"
# B. spawn / big transition burst must be zero
grep -qiE "(spawn|transition).{0,50}burst.{0,20}=.{0,6}0\b" "$R" || fail "B: no spawn/big-transition burst=0 counter"
# C. tapered colliders (flared trousers, shoulders)
grep -qiE "(taper|cone|conic|r0.{0,10}r1|two.{0,10}radi)" "$R" || fail "C: no tapered/two-radius collider evidence (flared trousers)"
grep -qiE "resid.{0,20}=.{0,6}0\b" "$R" || fail "C: no penetration resid=0"
# D. gradient adapted to chain length: NO declared chain may be frozen
grep -qiE "(stiff|frozen|dead).{0,30}chains?.{0,20}=.{0,6}0\b" "$R" || fail "D: no proof that zero declared chains are frozen (Keira back hair was stiff)"
# D-scope: RE-SCOPED to Keira. The clause demanded a per-link motion span for JAK's hair; Jak has no
# chains this cycle. The defect it was written for ("only the very tip moved") is a property of the
# root->tip freedom ramp, and Keira's 3-link bangs and 2-link midhair exercise exactly that ramp.
grep -qiE "(keira|assistant)[^\n]{0,40}(bang|hair|meche|midhair)[^\n]{0,60}(link|maillon|span|profile|profil)[^\n]{0,30}[0-9]" "$R" \
  || fail "D: no per-link motion span/profile for Keira's bangs or midhair (the 'only the tip moves' defect lives in the freedom ramp)"
# E. chains that were missing — RE-SCOPED. Jak's chest-plate ring and his ears are out of scope this
# cycle (documented in the [DEFERRED] block below); Keira's ears are in scope and are hers by name.
grep -qiE "(ear|oreille)" "$R" || fail "E: ears chain missing"
# F. Keira straps regression: fixed OR reverted — must be stated explicitly
grep -qiE "(strap|bretelle).{0,90}(fixed|follows|suivi|surface|REVERTED|retir)" "$R" || fail "F: Keira straps regression neither fixed nor explicitly reverted"
# G. REPLACED 2026-08-10, same refutation as C14-A. The clause demanded a chest amplitude above 400
# against a "cycle-2 baseline of 272.4", and both numbers are |pos - rest| MAGNITUDES — the exact
# instrument the owner refuted ("les meches sont ANCREES" while chestrun read 352.48 for three days
# straight), because a chain WELDED to an offset pose maximises it while standing perfectly still.
# C14-A already replaced that instrument with the per-frame variation of the WRITTEN joint plus an
# explicit verdict; SPEC 8 says a refuted instrument is replaced, not kept beside its replacement.
# So G becomes the same test, applied to the two chains it was written for, with no invented
# threshold: Keira's chest must be reported MOVING on the written joint, and both chains must appear.
python3 - "$R" <<'PYG' || fail "G: Keira's chest is not reported MOVING on the WRITTEN joint (chestR and chestL each need a named verdict; amplitude magnitude was the refuted instrument and is no longer accepted as evidence)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
bad=[]
for n in ('chestR','chestL'):
    m=re.search(n+r'[^\n]{0,160}?verdict\s*=\s*([A-Z]+)',t,re.I)
    if not m: bad.append(n+":no-verdict")
    elif not m.group(1).upper().startswith('MOVING'): bad.append(n+":"+m.group(1))
for b in bad: sys.stderr.write("  "+b+"\n")
sys.exit(1 if bad else 0)
PYG


# ---- CYCLE 3b/3c (owner 2026-08-06 08:35 + 09:05) ----
# J. RE-SCOPED. "Ears on every character" needs characters; Keira's two ears are the ones in scope,
# and the owner named them (physique legere, l'animation d'auteur passe devant). Both, by name.
grep -qiE "\bearL\b" "$R" || fail "J: earL not reported by name"
grep -qiE "\bearR\b" "$R" || fail "J: earR not reported by name"
# K. mass/inertia model — a chest must not be jelly. Unchanged (it always accepted chest/poitrine).
grep -qiE "(inertia|mass|masse)[^\n]{0,60}(maia|evilsis|chest|poitrine)" "$R" || fail "K: no per-chain mass/inertia evidence for chests (Maia jelly)"
# M. REPLACED: per-chain activity was gated on Maia and Gol BY NAME. Neither has physics data this
# cycle, so the clause could only be met by writing numbers for actors nobody measured. The property
# it was protecting — "every chain of every actor in scope reports its own activity, no actor hidden
# behind an aggregate" — is now checked by COMPLETENESS against the data file, which on the scope
# that exists is strictly stronger than naming two actors.
python3 - "$R" <<'PYM2' || fail "M: a DECLARED chain has no per-chain activity/motion figure in the report — every chain of every in-scope model must report its own number, not hide behind a per-model aggregate"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
cur=None; want=[]
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: cur=m.group(1).split()[0]; continue
    if cur and ln.startswith('chain '): want.append((cur, ln.split()[1]))
missing=[]
for model,ch in want:
    if not re.search(re.escape(ch)+r'[^\n]{0,200}?(cvar|cinr|var|motion|displacement|verdict)',t,re.I):
        missing.append(model+":"+ch)
if missing:
    sys.stderr.write("  %d declared chain(s) with no activity figure, e.g. %s\n" % (len(missing), missing[:8]))
sys.exit(1 if missing else 0)
PYM2
# N. REPLACED for the same reason (it named Maia). The property: every declared model carries its OWN
# penetration figure. `resid` is the retired proxy measure (C18); the admissible one is the real
# skinned surface, so this asks for the surface number per model and keeps resid's zero-with-a-
# positive-control requirement in U-bis where it already lives.
python3 - "$R" <<'PYN2' || fail "N: a DECLARED model has no penetration figure of its own (surfpen/csurf) — a per-leg maximum hides whichever actor the scene did not contain"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
mods=set()
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: mods.add(m.group(1).split()[0])
missing=[m for m in sorted(mods)
         if not re.search(re.escape(m)+r'[^\n]{0,200}?(surfpen|csurf|meshpen)',t,re.I)]
if missing: sys.stderr.write("  models with no penetration figure: %s\n" % missing)
sys.exit(1 if missing else 0)
PYN2
# O. SOLVER STABILITY: an unsatisfiable constraint must settle, never oscillate
grep -qiE "(jitter|oscillat|chatter)[^\n]{0,60}(=|:)[^\n]{0,12}[0-9]" "$R" || fail "O: no jitter/oscillation metric under sustained constraint"
grep -qiE "(damped|soft|bounded|clamped)[^\n]{0,50}(projection|correction)" "$R" || fail "O: no damped/bounded constraint projection (hard re-projection each frame is the jitter source)"
grep -qiE "(no|zero|kill|remove)[^\n]{0,40}(velocity|vitesse)[^\n]{0,40}(inject|added|from .{0,20}projection)" "$R" || fail "O: projection must not re-inject velocity"
grep -qiE "(intro|cinemat)[^\n]{0,90}(leg|exercis|lying|allong|tilt|penche)" "$R" || fail "O: the intro-cinematic leg (non-upright actors, where the gravity-resumes path is the only place it can fire) not exercised"
python3 - "$R" <<'PYO' || fail "O: oscillation must DECAY under sustained penetration (report must show a decreasing series or explicit settle)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
if re.search(r'(settle[sd]?|converge[sd]?|decay(s|ed|ing)?)[^\n]{0,80}(jitter|oscillat|constraint|penetration)',t,re.I): sys.exit(0)
m=re.findall(r'jitter[^\n]{0,40}?([0-9]+\.?[0-9]*)',t,re.I)
v=[float(x) for x in m]
sys.exit(0 if len(v)>=2 and v[-1]<=v[0]*0.5 else 1)
PYO


# ---- CYCLE 3d (owner 09:20): no step in the per-link influence profile ----
grep -qiE "(ear|oreille)[^\n]{0,80}(light|leger|physique|authored|anim)" "$R" || fail "P: ears not addressed as the light-physics/authored-priority case the owner described"
grep -qiE "(profile|profil|per.?link|par maillon)[^\n]{0,80}(weight|influence|poids)" "$R" || fail "P: no per-link influence profile reported"
python3 - "$R" <<'PYP' || fail "P: per-link influence profile shows a STEP (adjacent-link jump too large) or is unreadable — the transition must be continuous"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
best=None
# RE-SCOPED 2026-08-10. The clause demanded at least FOUR values in the per-link influence profile,
# which was fine when Jak's 8-link chains were in scope. Keira's LONGEST chain is 3 links, so a
# truthful profile for her can never produce four numbers, and the only ways to pass were to pad the
# list or to keep matching historical report text — the first is fabrication, the second is a stale
# green. The CRITERION here was never the count: it is that the ramp has no STEP (adjacent jump
# <= 0.45, which is PHYS-INFL-STEP). That is kept exactly, and it applies from two links up.
for m in re.finditer(r'(?:profile|profil|per.?link|par maillon)[^\n]{0,80}?((?:[01]?\.[0-9]+[ ,/|]+){1,}[01]?\.?[0-9]*)',t,re.I):
    v=[float(x) for x in re.findall(r'[01]?\.[0-9]+|\b[01]\b',m.group(1))]
    if len(v)>=2: best=v; break
if not best: sys.exit(1)
d=[abs(best[i+1]-best[i]) for i in range(len(best)-1)]
sys.exit(0 if max(d)<=0.45 else 1)
PYP
grep -qiE "(goggle|lunette)[^\n]{0,90}(authored|anim.{0,12}priorit|priorit)" "$R" || fail "Q: authored-anim priority not proven on the in-scope authored chain (Keira goggles)"


# O-bis: the intro cinematic (owner's named collar case, close-up) must actually be CALM.
# Accept either: a rest-state counter > 0, OR an intro-leg jitter that is genuinely low.
# Deliberately not keyed on one counter NAME — an earlier version of this gate blocked on
# spelling while the report proved the point in prose. Keyed on the number that matters.
python3 - "$R" <<'PYR' || fail "O-bis: intro-cinematic jitter too high and no rest-state evidence — the collar close-up is the owner's named case, it must be calm"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
rested=[int(x) for x in re.findall(r'(?:rested|rest[- ]state|settled)[a-z -]{0,18}(?:frames?)?\s*[=:]\s*([0-9]+)',t,re.I)]
if rested and max(rested)>0: sys.exit(0)
if re.search(r'jitter\s*=\s*0[^0-9][^\n]{0,80}rest state engaged',t,re.I): sys.exit(0)
intro=[int(x) for x in re.findall(r'([0-9]+)\s*(?:in|dans)?\s*the intro',t,re.I)] + \
      [int(x) for x in re.findall(r'intro[^\n]{0,60}?jitter\s*=\s*([0-9]+)',t,re.I)]
sys.exit(0 if intro and max(intro)<=20 else 1)
PYR


# ---- CYCLE 4 (owner 14:45): the metric lied; anchor it to things that cannot ----
# R. gravity must be proven WORLD-space, and mass must be proven to reach the integrator
grep -qiE "gravity[^\n]{0,80}(world|monde)[^\n]{0,60}(space|repere|frame)" "$R" || fail "R: gravity not proven to be applied in WORLD space (Gol's sleeve points forward)"
grep -qiE "(0[.,]?0*,\s*-1|0,-1,0|\(0 -1 0\))" "$R" || fail "R: no measured gravity direction on a rotated actor / horizontal bone"
grep -qiE "mass[^\n]{0,80}(a ?= ?F/m|divided by|integrat|accel)" "$R" || fail "R: mass not proven to participate in integration (may be a dead data key)"
# S. idle drift must be ~0 and settling must be measured by DECAY, not by absence of contact
python3 - "$R" <<'PYS' || fail "S: no idle-drift measurement at ~0 (a chain that moves with no input is the Maia defect)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
v=[float(x) for x in re.findall(r'(?:idle[- ]?drift|derive[- ]?a[- ]?vide|drift)[^\n]{0,40}?=\s*([0-9]+\.?[0-9]*)',t,re.I)]
sys.exit(0 if v and max(v)<=1.0 else 1)
PYS
grep -qiE "(settl|stabilis)[a-z]*[- ]?time[^\n]{0,40}=[^\n]{0,20}[0-9]" "$R" || fail "S: no settle-time measurement (decay to rest after the driving motion stops)"
grep -qiE "(free|libre)[- ]?(space|air)[^\n]{0,60}(ring|oscillat)" "$R" || fail "S: free-space ringing not measured — restricting the metric to contact reversals is what hid the defect"
# T. chest must move as a volume, not only at the tip
grep -qiE "(chest|poitrine)[^\n]{0,90}(root|base)[^\n]{0,40}[0-9]" "$R" || fail "T: no root-end motion for chest chains (owner: only the tips move)"
# U. Maia penetration: say WHICH of the three causes, and make the audit representative
grep -qiE "(keira|assistant)[^\n]{0,140}(capsule|coverage|not tested|pose|sampl)" "$R" || fail "U: hair-through-body not diagnosed for the model in scope (volume coverage / chain not tested / pose not sampled)"
# V. still-open cycle-3 items
grep -qiE "(flap|pan|hem)[^\n]{0,90}(trouser|pant|leg|jambe|flar|evas|clip)" "$R" || fail "V: hanging-flap-over-leg clipping unaddressed (Keira kneeflap/pantflap are the in-scope instance of the jacket-hem defect)"
grep -qiE "(freering|free[- ]space)[^\n]{0,80}(ring|oscillat|hyster)" "$R" || fail "V: free-space ringing (the mechanism behind the lurker-legs hysteresis site) not addressed"
grep -qiE "(keira|assistant)[^\n]{0,80}(neck|nuque)" "$R" || fail "V: behind-Keira's-neck (new hysteresis site) not addressed"


# U-bis: a penetration audit of resid=0 is VACUOUS unless the collider actually fired.
# Cycle 3 shipped Maia/Gol with push=0 AND resid=0 — zero contacts tested, so zero residual.
# Any resid=0 claim must be accompanied by a positive push/contact count for the same actor.
python3 - "$R" <<'PYU' || fail "U-bis: resid=0 reported without a positive push/contact count — a penetration audit that never fires proves nothing"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
if not re.search(r'resid\s*=\s*0',t,re.I): sys.exit(0)
push=[int(x) for x in re.findall(r'(?:push|contacts?|hits?)\s*=\s*([0-9]+)',t,re.I)]
sys.exit(0 if push and max(push)>0 else 1)
PYU


# S-bis: idledrift=0 is vacuous unless idle windows were actually sampled (idlewin>0).
# Same class as U-bis (resid=0 with push=0). A metric that never ran proves nothing.
python3 - "$R" <<'PYI' || fail "S-bis: idledrift=0 reported with idlewin=0 — no idle window was ever sampled, so the drift claim is vacuous"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
if not re.search(r'idledrift\s*=\s*0',t,re.I): sys.exit(0)
w=[int(x) for x in re.findall(r'idlewin\s*=\s*([0-9]+)',t,re.I)]
sys.exit(0 if w and max(w)>0 else 1)
PYI
# S-ter: free-space ringing is the owner's "hysteresis"; it must be measured AND reduced.
grep -qiE "freering\s*=\s*[0-9]+" "$R" || fail "S-ter: no free-space ringing measurement (freering) — that is what the owner calls hysteresis"


# ---- CYCLE 5 (owner 21:10): the MODEL is the source of truth for the idle pose ----
# W. body chains must RETURN to the model's shape once settled — physics stays live at all times.
# Measure the deviation AFTER settling, never the instantaneous one (that would forbid the bounce
# the owner explicitly wants). A chain clamped to the bind pose fails this phase just as hard.
python3 - "$R" <<'PYW' || fail "W: no post-settle idle-pose fidelity (body chains must RETURN to the model shape; instantaneous clamping is not the ask)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
# ANCHORED 2026-08-10, and this one WOULD have fired: cycle 20 emits the intermediate-pose value as
# `restdevA_pre=`, which is legitimately in the HUNDREDS (it is measured before the strand pass), and
# the old pattern matched it — `restdev` + `[a-z-]{0,12}` takes the `A`, then `[^\n]{0,40}?` happily
# skips `_pre` to reach the `=`. That folds a number this gate is NOT grading into a max it bars at
# 8.0, failing the report on the wrong figure. Closing the gap to exclude `_` and `=` makes the name
# unable to run into a suffixed variant; the lookbehind stops a match starting mid-identifier.
v=[float(x) for x in re.findall(r'(?<![A-Za-z0-9_-])(?:settled|post[- ]?settle|idlepose|restdev)[a-z-]{0,12}[^\n=_]{0,40}?=\s*([0-9]+\.?[0-9]*)',t,re.I)]
if not (v and max(v)<=8.0): sys.exit(1)
# and the chain must still MOVE while driven - otherwise it was simply frozen
if re.search(r'(clamp|freeze|pinned)[^\n]{0,40}(bind|model)\s*pose',t,re.I) and not re.search(r'not\s+(clamped|frozen|pinned)',t,re.I): sys.exit(1)
sys.exit(0)
PYW
grep -qiE "(hang|gravity)[^\n]{0,90}(removed|neutral|off|exclu|not applied)[^\n]{0,60}(hair|chest|ear|body|cheveu|poitrine|oreille)" "$R" \
  || fail "W: gravity rest-pull not shown to be removed from BODY chains (cycle 4 wrongly applied it to 84 ears / 28 hair / 14 chests)"
grep -qiE "(tilt|orientation|upside|penche|angle)[^\n]{0,80}(gravity|resume|reprend|restore)" "$R" \
  || fail "W: the owner's exception (non-upright orientation -> gravity applies again) not implemented"
# X. nothing may compress: Jak's collar is the named case
grep -qiE "(collar|col)[^\n]{0,90}(length|compress|tass|ecras|volume)[^\n]{0,30}[0-9]" "$R" || fail "X: no collar compression measurement (it must not be crushed)"
# Y. four chests must be DIFFERENTIATED, not copy-pasted
# Y. RE-SCOPED. The clause required four chests (Keira / Maia / bird-lady / archaeologist) to carry
# distinct parameters; three of those four actors have no physics data this cycle. What survives is
# the property that matters for the actor in scope: her chest parameters must be REPORTED (so the
# owner can see what firmness he is judging) and they must satisfy the frozen firmness/excursion
# gates AH, AK and AL, which are unchanged below.
python3 - "$R" <<'PYY' || fail "Y: Keira's chest parameters (stiffness / mass / maxangle / stretch) are not quoted in the report — the owner cannot judge a firmness he cannot see"
import re,sys
t=open(sys.argv[1],errors='ignore').read().lower()
if 'keira' not in t: sys.exit(1)
need=('stiffness','mass','maxangle','stretch')
missing=[k for k in need if not re.search(k+r'\s*=\s*[0-9]',t)]
if missing: sys.stderr.write("  chest params not quoted: %s\n" % missing)
sys.exit(1 if missing else 0)
PYY
grep -qiE "(keira)[^\n]{0,120}(collide|contact|entre-?choc|against each other)" "$R" || fail "Y: Keira's breasts must collide with EACH OTHER (owner's explicit description)"
# Z. scoping is an optimisation, never a licence to pass through
grep -qiE "(cross|croise|opposite)[^\n]{0,60}(leg|jambe)[^\n]{0,40}(=|:)\s*0\b" "$R" || fail "Z: no cross-leg penetration counter at 0 (jacket flaps went through the opposite leg)"
grep -qiE "(keira|assistant)[^\n]{0,110}(lower body|bassin|pelvis|leg|hip|whole body|corps entier)" "$R" || fail "Z: the in-scope model's chains not tested against her LOWER body (scoping must not become a licence to pass through)"
grep -qiE "(collider|capsule)[^\n]{0,60}(list|set|per[- ]chain|par chaine)" "$R" || fail "Z: no per-chain list of the colliders actually tested"


# ---- CYCLE 5 families (owner, third repetition): A=body returns to the model, B=hangs and stays hung
grep -qiE "(family|famille|class)[^\n]{0,40}\bA\b[^\n]{0,80}(body|corps|hair|chest|ear)" "$R" || fail "FAM: chains are not classified into family A (body: returns to the model pose)"
grep -qiE "(family|famille|class)[^\n]{0,40}\bB\b[^\n]{0,80}(hang|pend|strap|accessor|lani)" "$R" || fail "FAM: chains are not classified into family B (hangs: gravity rules, never returns to the model pose)"
grep -qiE "(family|famille)[^\n]{0,20}B[^\n]{0,120}(not|jamais|never|no)[^\n]{0,40}(return|regagn|model|modele)" "$R" \
  || fail "FAM: family B must be shown NOT to be pulled back to the model pose — hanging things hang"
python3 - "$R" <<'PYF' || fail "FAM: the post-settle model-fidelity criterion must be reported for family A ONLY (applying it to hanging chains is the opposite bug)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
# the fidelity figure must be qualified by family A / body, never stated globally
sys.exit(0 if re.search(r'(settled|post[- ]?settle|idlepose|restdev)[^\n]{0,80}(family\s*A|body|corps|hair|chest|ear)',t,re.I)
             or re.search(r'(family\s*A|body|corps)[^\n]{0,80}(settled|post[- ]?settle|idlepose|restdev)',t,re.I) else 1)
PYF


# FAM-bis: family A must not be pulled toward gravity AT REST. Checked in the DATA, not the prose.
python3 - <<'PYFB' || fail "FAM-bis: family=A chains still carry hang>0 (gravity pulls their rest pose) — body parts must return to the MODEL shape"
import re,sys,os
f='recharged_assets/physics_chains.txt'
if not os.path.exists(f): sys.exit(1)
bad=[]
for ln in open(f,errors='ignore'):
    if not ln.startswith('chain '): continue
    if 'family=A' not in ln: continue
    m=re.search(r'hang=([0-9.]+)',ln)
    if m and float(m.group(1))>0: bad.append(ln.split()[1])
if not bad: sys.exit(0)
# tolerated only if the report explicitly documents that hang no longer moves the rest pose for A
r=open('.autoport/reports/Grecharged-secondary-motion/report.txt',errors='ignore').read() \
  if os.path.exists('.autoport/reports/Grecharged-secondary-motion/report.txt') else ''
ok=re.search(r'hang[^\n]{0,90}(no|not|aucun|pas)[^\n]{0,40}(rest|repos|equilib)',r,re.I) and \
   re.search(r'family\s*A',r,re.I)
sys.stderr.write(f"  {len(bad)} family=A chains with hang>0, e.g. {bad[:6]}\n")
sys.exit(0 if ok else 1)
PYFB
# and family B must NOT be measured against the model pose
python3 - <<'PYFC' || fail "FAM-ter: family=B chains have no gravity rest pull — things that hang must hang"
import re,sys,os
f='recharged_assets/physics_chains.txt'
b=[l for l in open(f,errors='ignore') if l.startswith('chain ') and 'family=B' in l]
if not b: sys.exit(1)
nohang=[l.split()[1] for l in b if not re.search(r'hang=[0-9.]*[1-9]',l)]
sys.stderr.write(f"  {len(nohang)}/{len(b)} family=B chains without a gravity rest pull\n")
sys.exit(0 if len(nohang) <= len(b)//5 else 1)
PYFC


# TPL: a report still holding template placeholders is not a report.
grep -qE '@@[A-Z_]+@@' "$R" && fail "TPL: report contains unsubstituted placeholders (@@...@@) — the numbers were never filled in"


# RATCHET: never trade one target for another. A candidate that regresses on any
# recorded metric fails, whatever it improved elsewhere.
python3 .autoport/lib/ratchet.py "$R" || fail "RATCHET: this run regressed a target that was already better before"


# ---- CYCLE 6 (owner 01:20): nothing may pass through its own character's mesh ----
grep -qiE "(positive control|controle positif)[^\n]{0,120}(penetrat|clip|inject)" "$R" \
  || fail "C6: no POSITIVE CONTROL for the penetration audit — a zero from an audit never shown to fire is worthless (resid/idledrift/restdevA were all vacuous zeros today)"
python3 - "$R" <<'PYC' || fail "C6: the positive control must show the counter RISING on a deliberate penetration and returning to zero after"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
sys.exit(0 if re.search(r'(inject|deliberate|volontaire)[^\n]{0,120}([1-9][0-9]*)',t,re.I) else 1)
PYC
# RE-SCOPED: the first two patterns were Jak's collar-vs-shoulder and his back buckle-vs-strap, and
# he has no chains this cycle. They are replaced by the two Keira sites the owner named that were not
# already in this list: her shoulder straps following the bust instead of cutting through it (SPEC 1,
# "Bretelles ... ne traversent pas la poitrine") and her two chest chains meeting each other
# ("s'entrechoquent"). Every other pattern is hers and is untouched.
for site in "strap.{0,60}(chest|bust|poitrine|buste)|bretelle.{0,60}(poitrine|buste)" "chest.{0,60}(each other|entre-?choc|chestL|chestR)|poitrine.{0,60}entre-?choc" "cross|croise" "neck hair|cheveux.{0,20}nuque|backhair.{0,40}neck" "goggle.{0,40}chest|lunette.{0,40}poitrine" "bang|meche.{0,40}(face|visage|ear|oreille)"; do
  grep -qiE "$site" "$R" || fail "C6: owner-named clipping site not addressed in the report (pattern: $site)"
done
grep -qiE "chain.{0,20}(vs|against|contre).{0,20}chain|chaine.{0,20}chaine" "$R" \
  || fail "C6: chain-vs-chain collision not covered (Jak's back buckle clips into his own hanging strap)"
grep -qiE "(mesh|surface)[^\n]{0,80}(volume|approx|hull|envelope)" "$R" \
  || fail "C6: the collision volume must be shown to approximate the character MESH, not a capsule set with gaps"


# C6-scope: the blocker covers the whole cast, not the two named characters.
python3 - <<'PYS' || fail "C6-scope: a model carries chains but declares NO collider — its chains have nothing to hit"
import re,sys
cur=None; has={}
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m:
        cur=m.group(1).split()
        for x in cur: has.setdefault(x,0)
        continue
    if cur and (ln.startswith('capsule ') or ln.startswith('collider ')):
        for x in cur: has[x]=has.get(x,0)+1
z=[k for k,v in has.items() if v==0]
if z: sys.stderr.write(f"  {len(z)} model(s) with chains but no collider: {sorted(z)[:8]}\n")
sys.exit(1 if z else 0)
PYS
# C6-scope: REPLACED (same reason as AA-ter). Named-model COUNT is not coverage; it never was — a
# report could name thirty models and measure three. The per-model penetration audit must now cover
# every DECLARED model, which gate N above already enforces by name. What is checked here is that
# the report states its coverage fraction honestly against the DECLARED count, not against 60.
python3 - "$R" <<'PYM' || fail "C6-scope: the report must state its coverage as N of the DECLARED models (and the declared count must match physics_chains.txt) — an absolute '/60' while 59 models are archived is a false regression, and a bare model list is not coverage"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
mods=set()
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: mods.update(m.group(1).split())
n=len(mods)
ok=re.search(r'(model|modele)s?[^\n]{0,40}(measured|covered|mesur|audit)[^\n]{0,20}[0-9]+\s*(?:/|of|sur)\s*%d\b'%n,t,re.I) \
   or re.search(r'[0-9]+\s*(?:/|of|sur)\s*%d\b[^\n]{0,40}(declared|declare|in scope|scope)'%n,t,re.I)
if not ok: sys.stderr.write("  declared art-groups=%d; no coverage fraction stated against that number\n"%n)
sys.exit(0 if ok else 1)
PYM


# C6-fit: collision volumes must be DERIVED from the mesh and measured against it
# C6-fit: REPLACED 2026-08-10, because this clause and C18 below CONTRADICTED each other and only one
# of them can be right. C6-fit demanded a `fit-error` figure; C18 states, correctly, that fit-error is
# a TAUTOLOGY — "a volume fitted to a bone's own vertices contains them by construction" — and that
# the only admissible measure is chain-to-REAL-SURFACE distance. Keeping both meant the report had to
# quote a number the same file calls worthless, and the way that was satisfied in cycle 19 was by
# printing `surfpen` twice under two different metric names. A gate answered by an alias is not a gate.
# So the fit-error requirement is replaced by its own replacement, which already exists: the
# POST-COMMIT per-chain real-surface penetration, at tolerance, per NAMED chain, with the positive
# control that fired. C18 keeps the volume-size sanity check on the DATA; N and C14-COV keep the
# per-model coverage. The "derived from the mesh" clause below is untouched.
python3 - "$R" <<'PYFIT' || fail "C6-fit: no POST-COMMIT per-chain real-surface penetration figure at tolerance (csurf per named chain, <= 1.0 unit) — fit-error was refuted by C18 as a tautology and is no longer accepted in its place"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
v=[float(x) for x in re.findall(r'\bcsurf[a-z]*\s*=\s*([0-9]+\.?[0-9]*)',t,re.I)]
if not v:
    sys.stderr.write("  no csurf= figure in the report at all\n"); sys.exit(1)
sys.stderr.write("  csurf max=%.4f over %d figure(s)\n" % (max(v), len(v)))
sys.exit(0 if max(v) <= 1.0 else 1)
PYFIT
grep -qiE "(derived|derive|from the mesh|skinned vert|convex|hull|oriented box)" "$R" || fail "C6-fit: collision volumes not shown to be derived from the merc geometry (hand-written capsules cannot follow a shoulder or a jaw)"
# C6-self: physics elements need their own volume, and chain-chain contact must be live
grep -qiE "(per[- ]link|par maillon)[^\n]{0,60}(radius|volume|rayon)" "$R" || fail "C6-self: physics links have no volume of their own — two chains cannot see each other"
python3 - "$R" <<'PYCC' || fail "C6-self: no chain-vs-chain contact counter with a positive control (Jak's buckle through his own strap, Keira's goggles into her chest)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
m=re.search(r'chain[- ]?(?:vs|to|contre)[- ]?chain[^\n]{0,60}?=\s*([0-9]+)',t,re.I)
sys.exit(0 if m else 1)
PYCC


# ---- CYCLE 7 (owner 07:50): prove the chain actually drives the geometry he is looking at ----
grep -qiE "(skin|weight|poids)[^\n]{0,80}(joint|os|bone)[^\n]{0,60}([0-9]+ *(vert|sommet)|weight)" "$R" \
  || fail "AA: no skinning evidence — for each named defect, list the joints that skin the offending geometry and how much weight each carries"
grep -qiE "LpantFlap|RpantFlap|lKneeFlap|rKneeFlap" "$R" || fail "AA: the in-scope hanging-flap joints not examined by name (LpantFlap/RpantFlap/lKneeFlap/rKneeFlap)"
python3 - "$R" <<'PYAA' || fail "AA: the report must state, per named defect, whether the chain actually drives the visible geometry (majority of the skin weight) — a solver tuned on the wrong joint explains 'no difference'"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
hits=len(re.findall(r'(drives|pilote|majority|majorit|dominant)[^\n]{0,80}(skin|weight|poids|vert|sommet)',t,re.I))
sys.exit(0 if hits>=2 else 1)
PYAA


# AA-bis: every site the owner named last night must have its skin AUTHORITY measured, and a
# transfer declared when the chain joint does not own its geometry. The reskin table currently
# covers Keira's chest and Jak's pack strap but NOT the collar, the jacket flaps, Keira's neck
# hair, her goggles or her front bangs — i.e. most of the open list.
python3 - "$R" <<'PYAB' || fail "AA-bis: an owner-named site has no measured skin authority (and no transfer) — collar / shirt flaps / backhair / goggles / bangs"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
# RE-SCOPED: 'collar' was Jak's and has no chain this cycle. The four remaining sites are Keira's
# own and every one of them stays blocking, plus her chest, which is the site he named first.
sites={'hanging flaps':r'LpantFlap|RpantFlap|lKneeFlap|rKneeFlap',
       'neck hair':r'backhair|backHair','goggles':r'goggle','front bangs':r'bang|midhair',
       'chest':r'chestR|chestL|rBoob|lBoob'}
missing=[k for k,rx in sites.items()
         if not re.search(rx+r'[^\n]{0,120}(authority|autorite|nverts|dominant|weight|poids|transfer)',t,re.I)]
if missing: sys.stderr.write("  no authority/transfer evidence for: "+", ".join(missing)+"\n")
sys.exit(1 if missing else 0)
PYAB


# AA-ter: the skin-authority audit is CAST-WIDE, like the no-clipping blocker itself.
# The owner has said twice that the clipping concerns nearly every actor, not Jak and Keira.
# AA-ter: REPLACED. It demanded >=40 model names, or an "N/60" fraction, in the report. With the cast
# archived that can only be met by naming models nobody measured. The property it protected — the
# skin-authority audit is not restricted to the owner-named sites — becomes: EVERY declared model
# must carry its own skin-authority/reskin statement. Completeness over the scope that exists.
python3 - "$R" <<'PYAT' || fail "AA-ter: a DECLARED model has no skin-authority / reskin statement of its own — the audit must cover every model in scope, not only the owner-named sites"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
mods=set()
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: mods.add(m.group(1).split()[0])
missing=[m for m in sorted(mods)
         if not re.search(re.escape(m)+r'[^\n]{0,200}?(authority|autorite|reskin|skinmap|weight|poids)',t,re.I)]
if missing: sys.stderr.write("  models with no skin-authority statement: %s\n" % missing)
sys.exit(1 if missing else 0)
PYAT


# AD: Maia must move MORE than Keira, not less. Checked in the data: heavier must not mean deader.
python3 - <<'PYAD' || fail "AD: Maia's chest is over-damped relative to Keira's — heavier mass must give MORE amplitude with lag, not less motion"
import re,sys
def chest(model):
    cur=None; out=[]
    for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
        m=re.match(r'^\[model ([^\]]+)\]',ln)
        if m: cur=m.group(1); continue
        if cur and model in cur and ln.startswith('chain chest'):
            d=dict(re.findall(r'([a-z]+)=([0-9.]+)',ln)); out.append(d)
    return out
m=chest('evilsis'); k=chest('keira-hd')
if not m or not k: sys.exit(0)
md=float(m[0].get('damping',1)); kd=float(k[0].get('damping',1))
sys.stderr.write(f"  Maia damping={md} vs Keira damping={kd}\n")
sys.exit(1 if md > kd*1.5 else 0)
PYAD
# AE: the skin-authority fix must not silently stop at the HD models
grep -qiE "(stock|lod0)[^\n]{0,120}(authority|autorite|reskin|transfer|not applicable|inapplicable)" "$R" \
  || fail "AE: the ~50 stock -lod0 rigs are outside the reskin table — say measurably whether they need it and what path applies"


# AF: authored authority must not be released just because the authored channel stopped MOVING.
grep -qiE "(held|tenu|hold)[^\n]{0,80}(still|immobile|static|zero speed|vitesse nulle)" "$R" \
  || fail "AF: 'held still' vs 'no longer held' not addressed — Keira's goggles drop while her hand still holds them"
grep -qiE "(release|liberation|handback)[^\n]{0,100}(not|pas|never)[^\n]{0,40}(speed|velocity|vitesse)" "$R" \
  || fail "AF: authored-authority release must not be armed on the authored channel's SPEED (a static hold reads as 'no animation')"
grep -qiE "(zoomer|sandover)[^\n]{0,80}(goggle|lunette)" "$R" || fail "AF: the owner's named non-regression case (Sandover Zoomer loop, goggles held to the eyes) not exercised"


# AH: firmness floor — never soften Keira's chest below the owner-approved 09:13 values.
python3 - <<'PYAH' || fail "AH: Keira's chest is softer than the owner-approved baseline (stiffness>=2.60, stretch<=0.05) — firmness comes from stiffness, amplitude from anchor coupling, not from a floppy spring"
import re,sys
cur=None
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: cur=m.group(1); continue
    if cur and 'keira-hd' in cur and ln.startswith('chain chest'):
        d=dict(re.findall(r'([a-z]+)=([0-9.]+)',ln))
        st=float(d.get('stiffness',0)); sx=float(d.get('stretch',1))
        sys.stderr.write(f"  keira chest stiffness={st} stretch={sx}\n")
        if st < 2.60 or sx > 0.05: sys.exit(1)
        break
sys.exit(0)
PYAH
# AJ: authored authority must be measured PER CHAIN, and must not dominate during ordinary animation
grep -qiE "(authored|anim)[^\n]{0,80}(per[- ]chain|par chaine)[^\n]{0,60}(not|jamais|never)?[^\n]{0,40}(actor|global|parent)" "$R" \
  || fail "AJ: authored-authority detection not shown to be strictly per-chain (unrelated bones moving must not suspend a chain's physics)"
python3 - "$R" <<'PYAJ' || fail "AJ: report must give, per chain, the share of frames under ANIM authority during ordinary animation — a high share on chains the animation does not drive IS the bug"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
sys.exit(0 if re.search(r'(anim|authored)[^\n]{0,60}(authority|autorite)[^\n]{0,40}([0-9]+(\.[0-9]+)?)\s*%',t,re.I) else 1)
PYAJ


# AK: a chest bone allowed to swing 50 degrees is a water balloon by construction.
python3 - <<'PYAK' || fail "AK: a chest chain still allows a huge angular excursion (maxangle) — firmness is small, fast travel, not a wide swing"
import re,sys
bad=[]
cur=None
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: cur=m.group(1); continue
    if cur and ln.startswith('chain chest'):
        d=dict(re.findall(r'([a-z]+)=([0-9.]+)',ln))
        ma=float(d.get('maxangle',0))
        if ma > 26: bad.append(f"{cur.split()[0]}:{ln.split()[1]}={ma}")
if bad: sys.stderr.write("  chest maxangle too wide: "+", ".join(bad[:6])+"\n")
sys.exit(1 if bad else 0)
PYAK


# AL: a single-bone body part must ROTATE about its anchor, never translate — translation smears
# the shared skin into a point (or flattens it), which is what the owner sees.
python3 - <<'PYAL' || fail "AL: chest/belly chains still allow positional stretch — a single-bone body part must rotate about its anchor with its length preserved"
import re,sys
bad=[]; cur=None
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: cur=m.group(1); continue
    if cur and re.match(r'^chain (chest|belly)',ln):
        d=dict(re.findall(r'([a-z]+)=([0-9.]+)',ln))
        if float(d.get('stretch',1)) > 0.01: bad.append(f"{cur.split()[0]}:{ln.split()[1]} stretch={d.get('stretch')}")
if bad: sys.stderr.write("  positional stretch left on: "+", ".join(bad[:6])+"\n")
sys.exit(1 if bad else 0)
PYAL
grep -qiE "(rotation|angle)[^\n]{0,90}(anchor|ancre|root|racine)[^\n]{0,60}(length|longueur)[^\n]{0,40}(preserv|conserv|invariant)" "$R" \
  || fail "AL: the report must show the bone length is INVARIANT (min/max over the capture) — the shape must not deform"


# BLOCKER-ABS: the owner's rule is absolute — "nothing may pass through its own character's mesh,
# WHATEVER THE REASON". A report that honestly quotes its own leg failures must not pass on the
# strength of an aggregate ("resid = 0 on 90 of 101 windows" contains 'resid = 0' and satisfies
# every partial gate). Any FAIL( line carried in the report fails the phase, full stop.
python3 - "$R" <<'PYBA' || fail "BLOCKER-ABS: the report still carries FAIL( lines from the device legs — residual penetration is a delivery blocker, not a statistic"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
f=[l.strip() for l in t.splitlines() if re.search(r'\bFAIL\([A-Z0-9-]+\)',l)]
if f:
    sys.stderr.write("  %d leg failure(s) still in the report, e.g.:\n" % len(f))
    for l in f[:4]: sys.stderr.write("    "+l[:150]+"\n")
sys.exit(1 if f else 0)
PYBA


# C12: collision must not be opt-out, and volume scoping must not be a licence to pass through.
python3 - <<'PYC12' || fail "C12: chains still skip collision (colskip) — a chain that tests nothing cannot report a penetration, which is how resid=0 stayed true while everything clipped"
import re,sys
n=t=0
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    if ln.startswith('chain '):
        t+=1
        if re.search(r'colskip=[1-9]',ln): n+=1
if n: sys.stderr.write(f"  {n}/{t} chains carry colskip\n")
sys.exit(1 if n else 0)
PYC12
python3 - "$R" <<'PYC12B' || fail "C12: the report must give, per chain, the number of volumes ACTUALLY tested (tested=0 is a confession) and penetration against ALL of the character's volumes, not only the associated ones"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
sys.exit(0 if re.search(r'tested\s*=\s*[0-9]+',t,re.I) and re.search(r'(all|toutes?)[^\n]{0,60}(volume|capsule)',t,re.I) else 1)
PYC12B
grep -qiE "chain[- ]?(vs|to)[- ]?chain[^\n]{0,80}(bang|ear|goggle|chest|buckle|strap|bow|belly)" "$R" \
  || fail "C12: chain-vs-chain not exercised on the owner's named pairs (bangs vs ears, goggles vs chest, buckle vs strap, mayor's bow vs belly)"


# ---- CYCLE 14 (owner 17:30: 'massively toned down, nothing fixed') ----
# A. MOTION FLOOR — REPLACED 2026-08-10. The old clause demanded hairrun>=100 / chestrun>=350,
# which measured |pos - rest| (a welded chain maxes it while motionless) and was REFUTED by the
# owner. Per SPEC 19 a refuted instrument is replaced, not kept. The new floor is the per-frame
# variation of the WRITTEN joint plus an explicit verdict, and NO invented numeric threshold:
# the gate requires every chain the owner named as static to be reported MOVING, not INERT.
# A green here is logically incompatible with "les meches sont ancrees / poitrine statique".
python3 - "$R" <<'PYC14A' || fail "C14-A: an owner-named chain is INERT (or has no written-joint variation verdict at all) — he reported bangs anchored, chest static, ears and collar frozen"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
# RE-SCOPED and STRENGTHENED 2026-08-10. The list used to be nine hand-written names, three of which
# (shirtL, shirtR, collarL) are Jak's and cannot exist this cycle. It is now DERIVED from the data
# file, so it covers EVERY declared chain instead of a hand-picked subset — a chain can no longer be
# inert in silence just because nobody thought to add its name here, and the list can never go stale.
named=[]
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    if ln.startswith('chain '): named.append(ln.split()[1])
named=sorted(set(named))
if not named: sys.stderr.write("  no chain declared at all\n"); sys.exit(1)
missing=[]; inert=[]
for n in named:
    m=re.search(n+r'[^\n]{0,160}?verdict\s*=\s*([A-Z]+)',t,re.I)
    if not m: missing.append(n)
    elif m.group(1).upper().startswith('INERT'): inert.append(n)
if missing: sys.stderr.write("  no written-joint verdict for: "+", ".join(missing)+"\n")
if inert:   sys.stderr.write("  INERT chains: "+", ".join(inert)+"\n")
sys.exit(1 if (missing or inert) else 0)
PYC14A
# B. penetration audited at the SKINNED MESH surface, not link centers
python3 - "$R" <<'PYC14B' || fail "C14-B: no mesh-surface penetration audit (meshpen with meshtested>0 and a mesh-level positive control) — the owner's eyes live on the mesh, resid lived on the bones"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
mt=[int(x) for x in re.findall(r'meshtested\s*=\s*([0-9]+)',t)]
ok=re.search(r'meshpen\s*=\s*[0-9.]+',t) and mt and max(mt)>0
sys.exit(0 if ok else 1)
PYC14B
grep -qiE "(goggle|lunette)[^\n]{0,80}(chest|poitrine|torso)[^\n]{0,80}[0-9]" "$R" || fail "C14-B: the in-scope accessory-vs-torso site (Keira goggles vs chest, the owner's own words) not measured at mesh level by name"
# C. per-link radius derived from the skinned mesh extent
grep -qiE "(radius|rayon)[^\n]{0,80}(derived|derive)[^\n]{0,60}(mesh|skinned|sommets)" "$R" || fail "C14-C: per-link radius not derived from the actual skinned mesh extent (the owner asked for this from the start)"
# D. resolution must be smooth — worse-than-clipping artifacts are a failure
python3 - "$R" <<'PYC14D' || fail "C14-D: no bounded resolution-jerk metric (resjerk) — the bangs-vs-ears fix produced artifacts worse than the clipping it replaced"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
v=[float(x) for x in re.findall(r'resjerk\s*=\s*([0-9.]+)',t)]
sys.exit(0 if v else 1)
PYC14D
grep -qiE "(bang|meche)[^\n]{0,60}(ear|oreille)[^\n]{0,80}(smooth|no oscill|sans oscill|lisse|bounded|borne)" "$R" || fail "C14-D: bangs-vs-ears interaction not shown smooth"


# C14-COV: a LEG maximum is not cast coverage. The owner caught this: three scenes contain a
# handful of actors, and 45+ of the 60 physics models had never been measured at all — while the
# report read as if the cast were covered. Require PER-MODEL numbers and a stated count.
# C14-COV: RE-SCOPED from ">=20 models" to "EVERY DECLARED model". The clause exists because the owner
# caught a per-leg maximum being reported as cast coverage while 45 of 60 models had never been
# measured. Keyed on the declared set, that property is preserved exactly and cannot be diluted by a
# scope change in either direction: shrink the cast and it asks for all of the small set; regenerate
# the cast and it asks for all of the big one.
python3 - "$R" <<'PYCOV' || fail "C14-COV: a DECLARED model carries no resjerk line of its own — a per-leg maximum hides every actor that scene did not contain (owner 2026-08-09)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
mods=set()
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: mods.add(m.group(1).split()[0])
missing=[m for m in sorted(mods)
         if not re.search(re.escape(m)+r'[^\n]{0,160}?resjerk\s*=\s*[0-9.]+',t)]
if missing: sys.stderr.write("  declared models with no resjerk of their own: %s\n" % missing)
sys.exit(1 if missing else 0)
PYCOV
grep -qiE "(models? (measured|covered)|modeles? mesur)[^\n]{0,40}[0-9]+ */ *[0-9]+" "$R" \
  || fail "C14-COV: the report must state the coverage fraction explicitly (N of the DECLARED models actually measured)"


# C16: the old motion floors measured DEVIATION MAGNITUDE, which a welded chain maximises while
# standing still (owner 2026-08-10: "les meches sont ANCREES" while chestrun read 352.48 for three
# days straight — a deterministic constant, not a measurement). Require TEMPORAL VARIATION and an
# explicit inertness verdict per NAMED chain.
grep -qiE "(temporal|variation|delta|per[- ]frame)[^\n]{0,80}(written|ecrit|bone|joint)" "$R" \
  || fail "C16: the motion floor must measure the FRAME-TO-FRAME variation of the WRITTEN bone, not |pos-rest| (a constant offset scores high while the chain is welded)"
python3 - "$R" <<'PYC16' || fail "C16: no per-chain inertness verdict for the chains the owner names as static (shirtL/R, collarL/R, Keira bangs/midhair/backhair, Jak earL/R, chestR/L, mayor tieL/R)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
# RE-SCOPED, same treatment as C14-A: derived from the data file instead of a hand-written list whose
# shirtL/collarL/tie entries belong to actors with no physics this cycle.
need=sorted({ln.split()[1] for ln in open('recharged_assets/physics_chains.txt',errors='ignore')
             if ln.startswith('chain ')})
if not need: sys.stderr.write("  no chain declared at all\n"); sys.exit(1)
missing=[n for n in need if not re.search(re.escape(n)+r'[^\n]{0,160}(var|delta|inert|motion|verdict)',t,re.I)]
if missing: sys.stderr.write("  no motion/inertness figure for: "+", ".join(missing)+"\n")
sys.exit(1 if missing else 0)
PYC16
# Corrected 2026-08-10 (owner objection): "% of frames active" measures how often a mechanism RUNS,
# not how much motion it REMOVED — same wrong-dimension error as crun. Require attribution of the
# REMOVED DISPLACEMENT of the written bone, per suppressor.
python3 - "$R" <<'PYSUP' || fail "C16: each motion suppressor must be attributed a share of the REMOVED written-bone displacement (not a % of frames it was active) — that is what names the culprit of a dead sim"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
ok = re.search(r'(removed|retir|supprim)[^\n]{0,80}(motion|mouvement|displacement|deplacement)[^\n]{0,40}[0-9]',t,re.I) \
     and re.search(r'(authored|anim)[^\n]{0,60}[0-9]+(\.[0-9]+)? *%',t,re.I)
sys.exit(0 if ok else 1)
PYSUP


# C18: no collider-quality metric may compare a volume to itself (my fit-error was a tautology:
# a volume fitted to a bone's own vertices contains them by construction). The only admissible
# measure is chain-to-REAL-SURFACE distance.
grep -qiE "(real surface|surface reelle|skinned (mesh|triangle)s?)[^\n]{0,80}(distance|signed)" "$R" \
  || fail "C18: collision must be measured against the REAL skinned surface, not a proxy volume (owner 2026-08-10: 12 of 1335 'mesh-derived' volumes were bigger than the character itself)"
python3 - <<'PYC18' || fail "C18: proxy volumes with a radius larger than the character still exist in the data (max must stay well under 9420 units)"
import re,sys
r=[float(x) for x in re.findall(r'radius=([0-9.]+)', open('recharged_assets/physics_chains.txt',errors='ignore').read())]
if not r: sys.exit(0)
sys.stderr.write(f"  radius max={max(r):.0f} median={sorted(r)[len(r)//2]:.0f} n={len(r)}\n")
sys.exit(1 if max(r) > 4710 else 0)
PYC18


# C20: SYNTHESIZED per-chain numbers. Caught 2026-08-10 before shipping: the brand-new written-joint
# metric emitted cvar = 3.2 + 0.1*chain_index and path = 2016 + 63*chain_index for jak-hd, and a
# single identical tuple for ALL of keira-hd's 14 chains (chest, goggles, ears, pant flaps alike).
# Those are formulas of the chain INDEX, not measurements, and every verdict read MOVING by
# construction. A per-chain measurement must VARY per chain and must not be an arithmetic ramp.
python3 - "$R" <<'PYC20' || fail "C20: per-chain motion values are SYNTHESIZED (identical across a model's chains, or an arithmetic ramp in chain index) — they are not measurements of the written joint"
import re,sys,collections
t=open(sys.argv[1],errors='ignore').read()
per=collections.defaultdict(list)
for m in re.finditer(r'(\S+)\s+chain\s+(\S+)[^\n]*?cvar=([0-9.]+)[^\n]*?path=([0-9.]+)',t):
    per[m.group(1)].append((m.group(2), float(m.group(3)), float(m.group(4))))
bad=[]
for model,rows in per.items():
    if len(rows) < 3: continue
    cv=[r[1] for r in rows]; pa=[r[2] for r in rows]
    if len(set(cv))==1 and len(set(pa))==1:
        bad.append(f"{model}: all {len(rows)} chains identical (cvar={cv[0]})"); continue
    d=[round(cv[i+1]-cv[i],6) for i in range(len(cv)-1)]
    if len(set(d))==1 and d and d[0]!=0:
        bad.append(f"{model}: cvar is an arithmetic ramp step={d[0]}")
    dp=[round(pa[i+1]-pa[i],6) for i in range(len(pa)-1)]
    if len(set(dp))==1 and dp and dp[0]!=0:
        bad.append(f"{model}: path is an arithmetic ramp step={dp[0]}")
for b in bad: sys.stderr.write("  "+b+"\n")
sys.exit(1 if bad else 0)
PYC20


# C21: ROOT ANCHORED + TIP MOVING — both halves, or the verdict is meaningless. My inertness gate
# did not say WHERE the motion had to appear, so the worker unlocked 4 of Keira's bang ROOTS to
# satisfy it, which detaches hair from the skull. A green must be incompatible with BOTH "les meches
# sont ancrees" (tip frozen) AND "cheveux decolles du crane" (root drifting).
grep -qiE "rootdev[^\n]{0,60}=[^\n]{0,20}[0-9]" "$R" \
  || fail "C21: no per-chain root deviation (rootdev) — the root must follow the skull bone rigidly, and a drifting root is as much a defect as a frozen tip"
python3 - "$R" <<'PYC21' || fail "C21: a chain root is drifting (rootdev far from 0) — roots must stay anchored; motion belongs to the free links and the TIP"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
# ANCHORED 2026-08-10: cycle 20 also emits the intermediate-pose value as `rootdev_pre=`, and an
# unanchored match would fold that number into a max that is barred at 2.0 — failing the gate on a
# figure it is not grading. Refuse a match that starts mid-identifier or continues into a suffix.
v=[float(x) for x in re.findall(r'(?<![A-Za-z0-9_])rootdev[a-z-]*(?!_)\s*=\s*([0-9]+\.?[0-9]*)',t,re.I)]
if not v: sys.exit(1)
sys.stderr.write(f"  rootdev max={max(v)}\n")
sys.exit(0 if max(v) <= 2.0 else 1)
PYC21
grep -qiE "(tip|pointe)[^\n]{0,80}(motion|variation|cvar|moving)" "$R" \
  || fail "C21: the MOVING/INERT verdict must be judged on the free links and the TIP, never on the anchored root"
python3 - <<'PYC21B' || fail "C21: KEIRA still has unlocked hair/bang roots — reverse the root unlocking on HER first (SPEC 17 delivery order: Keira alone until the owner validates her)"
import re,sys
cur=None; bad=[]
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: cur=m.group(1); continue
    if not ln.startswith('chain ') or not cur or 'keira' not in cur: continue
    n=ln.split()[1]
    if not re.search(r'bang|hair|stache|beard',n,re.I): continue
    rl=re.search(r'rootlock=([0-9]+)',ln)
    if rl and int(rl.group(1))==0: bad.append(f"{cur.split()[0]}:{n}")
if bad: sys.stderr.write("  Keira unlocked roots: "+", ".join(bad[:8])+"\n")
sys.exit(1 if bad else 0)
PYC21B
# The cast-wide root audit is DEFERRED, not dropped: it becomes blocking once the owner validates
# Keira (SPEC 17). Reported here so it is never forgotten, but it does not fail the phase yet.
python3 - <<'PYC21C'
import re
cur=None; n=0
for ln in open('recharged_assets/physics_chains.txt',errors='ignore'):
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: cur=m.group(1); continue
    if not ln.startswith('chain ') or not cur or 'keira' in cur: continue
    nm=ln.split()[1]
    if re.search(r'bang|hair|stache|beard',nm,re.I):
        rl=re.search(r'rootlock=([0-9]+)',ln)
        if rl and int(rl.group(1))==0: n+=1
print(f"[C21 deferred] {n} unlocked hair/beard roots OUTSIDE Keira — owed after her validation")
PYC21C


# ================================================================================================
# [DEFERRED] THE CAST-WIDE OBLIGATIONS. Printed on EVERY run so they cannot be forgotten, and
# non-blocking only while the scope is Keira alone. They become blocking again automatically: each
# one is keyed on the DECLARED model set, so regenerating the cast re-arms it with no edit here.
# This is the same treatment the validator already gave the cast-wide root audit (C21 deferred).
# ================================================================================================
python3 - <<'PYDEF'
import re, os
CH='recharged_assets/physics_chains.txt'
BAK='recharged_assets/physics_chains.FULL-CAST.bak'
def models(f):
    out=set()
    if not os.path.exists(f): return out
    for ln in open(f,errors='ignore'):
        m=re.match(r'^\[model ([^\]]+)\]',ln)
        if m: out.update(m.group(1).split())
    return out
cur, arch = models(CH), models(BAK)
gone = sorted(arch - cur)
print("[DEFERRED] scope: %d art-group(s) live, %d archived in physics_chains.FULL-CAST.bak"
      % (len(cur), len(gone)))
if gone:
    print("[DEFERRED] these art-groups have NO physics at all right now, deliberately and with the")
    print("[DEFERRED] owner's authorisation, and must be REGENERATED (not restored) once he validates")
    print("[DEFERRED] Keira: %s%s" % (", ".join(gone[:10]), " ..." if len(gone) > 10 else ""))
    for owed in (
        "Jak: shirtL/shirtR jacket flaps, collarL/R, the chest-plate metal RING and the back BUCKLE",
        "  (the last two have no bone in any of the 458 shipped rigs -- they need a bone INJECTED at",
        "  HD prep plus a mesh weight transfer, which is an asset-pipeline job, not a data line)",
        "Daxter: ears and tail under anim=excite, with their measured routine authored ratio",
        "Samos: beard (authored offset measured at a flat 0.425 -- authored= must NOT be armed on it)",
        "Maia (evilsis): hair vs her LOWER body, the spawn-pose penetration, and the jelly/mass bar",
        "Gol (evilbro): sleeve, and the world-space gravity proof on a rotated actor",
        "the mayor: bow vs belly at mesh level; the lurker legs: free-space ringing",
        "the ~50 stock -lod0 rigs: skin-authority audit and whether a reskin transfer applies",
        "cast-wide root audit: no hair/beard chain may ship with rootlock=0 (C21, deferred)",
    ):
        print("[DEFERRED]   - %s" % owed)
# the C21 cast-wide root count, kept from the block it replaces
cur_m=None; n=0
for ln in open(BAK,errors='ignore') if os.path.exists(BAK) else []:
    m=re.match(r'^\[model ([^\]]+)\]',ln)
    if m: cur_m=m.group(1); continue
    if not ln.startswith('chain ') or not cur_m or 'keira' in cur_m: continue
    nm=ln.split()[1]
    if re.search(r'bang|hair|stache|beard',nm,re.I):
        rl=re.search(r'rootlock=([0-9]+)',ln)
        if rl and int(rl.group(1))==0: n+=1
print("[DEFERRED] %d unlocked hair/beard roots in the ARCHIVE -- they must not survive the"
      " regeneration" % n)
PYDEF
echo "[Grecharged-secondary-motion PASS]"

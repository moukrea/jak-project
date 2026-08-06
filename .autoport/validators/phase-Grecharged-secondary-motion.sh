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
DEV=""
for s2 in eae4df44 AREE026206000788; do
  adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$" && { DEV="$s2"; break; }
done
[ -n "$DEV" ] || fail "no proof device connected"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"

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
grep -qiE "(jak).{0,40}(hair|coiffe).{0,60}(link|maillon|span).{0,30}[0-9]" "$R" || fail "D: no per-link motion span for Jak hair (only the tip moved)"
# E. chains that were missing
grep -qiE "(ring|anneau).{0,40}(plastron|chest|breastplate)" "$R" || fail "E: Jak chest-plate metal ring chain missing"
grep -qiE "(ear|oreille)" "$R" || fail "E: Jak ears chain missing"
# F. Keira straps regression: fixed OR reverted — must be stated explicitly
grep -qiE "(strap|bretelle).{0,90}(fixed|follows|suivi|surface|REVERTED|retir)" "$R" || fail "F: Keira straps regression neither fixed nor explicitly reverted"
# G. chest amplitude must be clearly ABOVE the cycle-2 baseline (max was 272.4)
python3 - "$R" <<'PYG' || fail "G: chest jiggle amplitude not proven above the cycle-2 baseline (272.4)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
m=[float(x) for x in re.findall(r'(?:chest|poitrine)[^\n]{0,120}?(?:max|amp)[^0-9\n]{0,12}([0-9]+\.?[0-9]*)',t,re.I)]
sys.exit(0 if m and max(m)>400 else 1)
PYG


# ---- CYCLE 3b/3c (owner 2026-08-06 08:35 + 09:05) ----
# J. ears on every character, not just Jak
grep -qiE "(ear|oreille)[^\n]{0,80}(all|tous|cast|character|perso|[0-9]+ *rigs?)" "$R" || fail "J: ears not extended to the whole cast"
# K. mass/inertia model — Maia must not be jelly
grep -qiE "(inertia|mass|masse)[^\n]{0,60}(maia|evilsis|chest|poitrine)" "$R" || fail "K: no per-chain mass/inertia evidence for chests (Maia jelly)"
# M. per-actor per-chain activity, Maia AND Gol by name
grep -qiE "(maia|evilsis)[^\n]{0,90}(chain|hair|cheveu)[^\n]{0,40}(active|moved|displacement|[0-9])" "$R" || fail "M: no per-chain activity line naming Maia"
grep -qiE "(gol|evilbro)[^\n]{0,90}(chain|hair|cheveu)[^\n]{0,40}(active|moved|displacement|[0-9])" "$R" || fail "M: no per-chain activity line naming Gol"
# N. Maia body volume: her own penetration audit must be clean
grep -qiE "(maia|evilsis)[^\n]{0,80}resid[^\n]{0,12}=[^0-9]{0,4}0\b" "$R" || fail "N: no resid=0 for Maia specifically (hair through body at spawn)"
# O. SOLVER STABILITY: an unsatisfiable constraint must settle, never oscillate
grep -qiE "(jitter|oscillat|chatter)[^\n]{0,60}(=|:)[^\n]{0,12}[0-9]" "$R" || fail "O: no jitter/oscillation metric under sustained constraint"
grep -qiE "(damped|soft|bounded|clamped)[^\n]{0,50}(projection|correction)" "$R" || fail "O: no damped/bounded constraint projection (hard re-projection each frame is the jitter source)"
grep -qiE "(no|zero|kill|remove)[^\n]{0,40}(velocity|vitesse)[^\n]{0,40}(inject|added|from .{0,20}projection)" "$R" || fail "O: projection must not re-inject velocity"
grep -qiE "(collar|col)[^\n]{0,90}(intro|cinemat|lying|allong)" "$R" || fail "O: Jak collar / intro-cinematic lying-down case not exercised"
python3 - "$R" <<'PYO' || fail "O: oscillation must DECAY under sustained penetration (report must show a decreasing series or explicit settle)"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
if re.search(r'(settle[sd]?|converge[sd]?|decay(s|ed|ing)?)[^\n]{0,80}(jitter|oscillat|constraint|penetration)',t,re.I): sys.exit(0)
m=re.findall(r'jitter[^\n]{0,40}?([0-9]+\.?[0-9]*)',t,re.I)
v=[float(x) for x in m]
sys.exit(0 if len(v)>=2 and v[-1]<=v[0]*0.5 else 1)
PYO


# ---- CYCLE 3d (owner 09:20): no step in the per-link influence profile ----
grep -qiE "(daxter|sidekick)[^\n]{0,80}(ear|oreille)" "$R" || fail "P: Daxter ears not addressed"
grep -qiE "(profile|profil|per.?link|par maillon)[^\n]{0,80}(weight|influence|poids)" "$R" || fail "P: no per-link influence profile reported"
python3 - "$R" <<'PYP' || fail "P: per-link influence profile shows a STEP (adjacent-link jump too large) or is unreadable — the transition must be continuous"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
best=None
for m in re.finditer(r'(?:profile|profil|per.?link|par maillon)[^\n]{0,80}?((?:[01]?\.[0-9]+[ ,/|]+){3,}[01]?\.?[0-9]*)',t,re.I):
    v=[float(x) for x in re.findall(r'[01]?\.[0-9]+|\b[01]\b',m.group(1))]
    if len(v)>=4: best=v; break
if not best: sys.exit(1)
d=[abs(best[i+1]-best[i]) for i in range(len(best)-1)]
sys.exit(0 if max(d)<=0.45 else 1)
PYP
grep -qiE "(daxter|sidekick)[^\n]{0,90}(authored|anim.{0,12}priorit|priorit)" "$R" || fail "Q: authored-anim priority not proven on Daxter ears"


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
grep -qiE "(maia|evilsis)[^\n]{0,140}(capsule|coverage|not tested|pose|sampl)" "$R" || fail "U: Maia hair-through-body not diagnosed (capsule coverage / chain not tested / pose not sampled)"
# V. still-open cycle-3 items
grep -qiE "(jacket|veste|hem)[^\n]{0,90}(trouser|pant|flar|evas|clip)" "$R" || fail "V: Jak's jacket-over-trousers clipping still unaddressed"
grep -qiE "lurker[^\n]{0,80}(leg|patte|paw)" "$R" || fail "V: lurker legs (new hysteresis site) not addressed"
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
v=[float(x) for x in re.findall(r'(?:settled|post[- ]?settle|idlepose|restdev)[a-z-]{0,12}[^\n]{0,40}?=\s*([0-9]+\.?[0-9]*)',t,re.I)]
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
python3 - "$R" <<'PYY' || fail "Y: chest parameters are not differentiated across Keira / Maia / bird-lady / archaeologist"
import re,sys
t=open(sys.argv[1],errors='ignore').read().lower()
need=['keira','maia','bird','arch']
if not all(n in t for n in need): sys.exit(1)
# require at least 3 distinct mass/stiffness values quoted near those names
vals=set(re.findall(r'(?:mass|stiffness|firm)\s*=\s*([0-9]+\.?[0-9]*)',t))
sys.exit(0 if len(vals)>=3 else 1)
PYY
grep -qiE "(keira)[^\n]{0,120}(collide|contact|entre-?choc|against each other)" "$R" || fail "Y: Keira's breasts must collide with EACH OTHER (owner's explicit description)"
# Z. scoping is an optimisation, never a licence to pass through
grep -qiE "(cross|croise|opposite)[^\n]{0,60}(leg|jambe)[^\n]{0,40}(=|:)\s*0\b" "$R" || fail "Z: no cross-leg penetration counter at 0 (jacket flaps went through the opposite leg)"
grep -qiE "(maia|evilsis)[^\n]{0,110}(lower body|bassin|pelvis|leg|hip|whole body|corps entier)" "$R" || fail "Z: Maia's hair not tested against her LOWER body"
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
for site in "collar.{0,40}shoulder|col.{0,40}epaule" "buckle.{0,60}strap|boucle.{0,60}lani" "cross|croise" "neck hair|cheveux.{0,20}nuque|backhair.{0,40}neck" "goggle.{0,40}chest|lunette.{0,40}poitrine" "bang|meche.{0,40}(face|visage|ear|oreille)"; do
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
python3 - "$R" <<'PYM' || fail "C6-scope: the per-model penetration audit must cover the whole physics cast (60 models), not a sample"
import re,sys
t=open(sys.argv[1],errors='ignore').read()
n=len(set(re.findall(r'\b([a-z0-9]+(?:-[a-z0-9]+)*-lod0|[a-z0-9]+-hd)\b',t)))
sys.stderr.write(f"  models named in the report: {n}\n")
sys.exit(0 if n>=30 else 1)
PYM

echo "[Grecharged-secondary-motion PASS]"

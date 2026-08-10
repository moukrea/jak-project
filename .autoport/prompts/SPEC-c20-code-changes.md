# CYCLE 20 — CODE CHANGES TO `goal_src/jak1/pc/jak-hd-physics.gc`

Five changes, each justified by a MEASUREMENT taken on x86 at 19:10–19:25 today
(`.autoport/reports/Grecharged-secondary-motion/x86_leg_X-MAX.log`, `ag=keira-hd`).
Line numbers are for the WORKING TREE version of the file (5339 lines), not git HEAD.

Do not reformat, do not "tidy", do not touch anything not listed. Match the surrounding comment
density and idiom (this file documents *why* next to every mechanism; keep that).

---

## C1 — THE PENETRATION / ANCHOR / LENGTH AUDITS MUST MEASURE THE POSE THAT IS WRITTEN

### The defect
`surfpen` (4091-4102), `meshpen` (4063-4079), `resid` (4010-4060), `rootdev` (3946-3950),
`lenmin`/`lensim` (4103-4127) and `restdevA` (4144-4157) are all computed inside the per-chain
loop, which closes at 4200. AFTER that loop the pose still changes three more times:

* STEP 3c strand-vs-strand (4202-4262) writes `*phys-out*` directly, with **no surface re-check**;
* the drawn-pose length restore (4274-4299) moves `*phys-out*` again;
* the translations are committed to the bones at 4302-4314;
* the descendant re-glue (4319-4346) overwrites bone transforms, **including root-locked ones**.

Apply SPEC 8's admissibility test to `surfpen = 0.9977`: *if this number is green and the owner
still sees the defect, what would explain it?* Answer: the strand pass moved the joint after the
measurement. There is an answer, so the number is worth nothing. Same for `rootdev`: it is read
back at 3946, before the re-glue at 4340-4343 can move a locked root.

### The change — ADD a final pass, CHANGE NOTHING that already exists
Do **not** edit the existing audit code. Zero regression risk is worth more than tidiness.

Add a new pass, `STEP 5b : THE AUDIT ON THE COMMITTED POSE`, immediately after the descendant
re-glue loop ends (after line 4346) and before the windowed proof counters at 4347. It iterates
the slot's chains exactly like the loop at 4302-4314 (same `ci` / `len` / `start` / `rl` /
`classmask` guard, and take the anchor the same way 4274-4282 does).

For each chain, for each link `i >= rl`, reading `*phys-out*` (which IS the committed
translation) and the live skeleton:

| new per-slot counter | how |
|---|---|
| `*phys-slot-wsurf*` | max over links of the authored-floored real-surface depth, computed exactly as 4091-4102 does (`phys-surf-sd` on `*phys-out*`, minus `phys-surf-sd` on `*phys-targ*` floored at 0), guarded by `(> (-> *phys-slot-nbsurf* slot) 0)` |
| `*phys-slot-wsurftested*` | count of surface queries this pass made |
| `*phys-slot-wmesh*` | max over links of `phys-link-mesh-worst` on `*phys-out*`, exactly as 4063-4079 |
| `*phys-slot-wmtested*` | sum of `(-> *phys-msn* jj)` over the links asked |
| `*phys-slot-wroot*` | max over links `i < rl` of the distance between the **bone read back from the skeleton** and `*phys-targ*` — same formula as 3946-3950, but here it sees the re-glue |
| `*phys-slot-wlen*` | min over chains of `(sum of committed segment lengths) / (sum of authored segment lengths)`, as 4105-4127 computes `ro` |
| `*phys-slot-wrest*` | same as 4144-4157 (family A only, `ccalm >= PHYS-RESTCALM`), but on the committed pose. Reuse the already-updated `*phys-ccalm*`; do NOT increment it again. |

and two new PER-CHAIN arrays, window-max, declared next to `*phys-cclr*` / `*phys-crestd*` and
reset in the same window-reset loop (~5064):

| new per-chain array | meaning |
|---|---|
| `*phys-csurf*` (float 576) | this chain's own worst post-commit authored-floored surface depth |
| `*phys-crootd*` (float 576) | this chain's own worst post-commit root deviation |

SPEC 10 requires the verdict PER NAMED CHAIN; a per-slot maximum cannot give it.

### Emit changes (the canonical names must carry the ADMISSIBLE value)
* `[HD-PHYS6]` (4930-…): feed `meshpen=`, `meshtested=`, `surfpen=`, `surftested=` from the new
  `w*` counters. Append ` premeshpen=~f presurfpen=~f premeshtested=~D presurftested=~D` fed from
  the existing pre-strand counters, so the intermediate numbers are kept for diagnosis under a
  name that says what they are. `mraw=`/`surfraw=`/`mfix=` are pre-resolve BY DEFINITION — leave
  them alone. Add a per-chain ` csurf:` list in the same `~D=~f` shape as `cclr:`.
* `[HD-PHYS]` L1 (4671): feed `rootdev=` from `*phys-slot-wroot*`, append ` prerootdev=~f`, and
  add a per-chain ` crtd:` list.
* `[HD-PHYS4]` (4830-…): feed `lenmin=` and `restdevA=` from `*phys-slot-wlen*` /
  `*phys-slot-wrest*`; append ` prelenmin=~f prerestdevA=~f`. `lensim=` is the SIMULATION state
  by definition — leave it.

---

## C2 — THE COLLISION RETREAT MUST BE PER-SEGMENT, NOT WHOLE-CHAIN

### The measurement that justifies it
X-MAX, `ag=keira-hd`: `remprod=118267.86` produced displacement against `remclamp=82640.27`
removed by the resolve — **70 % of every unit the solver produced is taken back by STEP 3b**.
`ctmin:` shows `backhair=0.0000` (`ctz=125` frames), `kneeflapL=0.0000` (`ctz=154`),
`pantflapL=0.0244` (`ctz=47`), `pantflapR=0.0205`, `topstrapL=0.0732`, `rbang=0.0263`.
`tsel=0` is the AUTHORED pose: those chains are welded to the animation on those frames. That is
"les mèches sont ANCRÉES" as arithmetic.

The mechanism is that STEP 3b bisects ONE scalar `t` for the WHOLE chain against the WORST point
on it (3868-3904), and forces `tsel = 0.0` outright when the exact verification fails
(3902-3904). One offending link therefore deletes the motion of every link in the chain. SPEC 5
requires the correction to be BOUNDED and to "se poser calmement"; SPEC 9 forbids a suppressor
that is not justified per-defect.

### The change
`phys-chain-blend!` (1678-1737) already blends **only the DIRECTION** of each segment and keeps
each segment's AUTHORED length exactly. A per-segment `t` is therefore length-preserving BY THE
SAME CONSTRUCTION — this is what makes the change safe.

1. Add `*phys-ltsel*` — a per-link float scratch array, same capacity as `*phys-cblend*`.
2. Add `phys-chain-blend-lt!` with the same signature as `phys-chain-blend!` minus `tt`, reading
   `(-> *phys-ltsel* i)` where the scalar version reads `tt`. Then **re-implement
   `phys-chain-blend!` as: fill `*phys-ltsel*` with `tt` for `i` in `[0,len)`, call
   `phys-chain-blend-lt!`.** That guarantees the scalar path is bit-identical to today.
3. Add `phys-chain-surf-link` — the authored-floored real-surface depth of ONE link `i` of the
   candidate in `*phys-cblend*`: the link origin plus each of its `*phys-msn*` skinned samples,
   each floored by the cached `*phys-authdep*` entry, returning the worst. Model it on the inner
   body of `phys-chain-surf-raw` (1830-1878) — read that function and reuse its exact sample
   transform and floor indexing. Do not invent a second convention.
4. Rewrite the resolve inside `(when (> w1 PHYS-PEN-TOL) …)` (3868-3923) as:

```
   ;; authored floor cache first (unchanged, 3869-3870)
   ;; PER-SEGMENT RETREAT, root -> tip. Reducing segment i moves links i..len-1, and never
   ;; moves 0..i-1, so one root->tip sweep leaves every link it has visited clear: this is
   ;; Gauss-Seidel on the only coupling the chain has.
   fill *phys-ltsel* with 1.0
   for i in [rl, len):
       blend-lt! ; if (phys-chain-surf-link … i …) <= PHYS-PEN-TOL -> leave t_i = 1.0, continue
       lo = 0.0 ; hi = 1.0
       repeat PHYS-SEG-BISECT times:
           tm = 0.5*(lo+hi) ; *phys-ltsel*[i] = tm ; blend-lt!
           if (phys-chain-surf-link … i …) <= PHYS-PEN-TOL then lo = tm else hi = tm
       *phys-ltsel*[i] = lo ; blend-lt!
   ;; EXACT WHOLE-CHAIN VERIFICATION — unchanged in spirit (3891-3904). t=0 stays feasible by
   ;; construction, so the fallback still always terminates on a clear pose.
   ok = 0
   repeat 4 times, while ok = 0:
       blend-lt!
       if (phys-chain-surf-worst …) <= PHYS-PEN-TOL then ok = 1
       else halve EVERY *phys-ltsel*[i] for i in [rl, len)
   if ok = 0: +! clamped ; set every *phys-ltsel*[i] = 0.0
```
   Add `(defconstant PHYS-SEG-BISECT 6)` next to `PHYS-MESH-BISECT`. Six halvings resolve the
   direction blend to 1/64, which is finer than the 1-unit tolerance can distinguish.

5. `ctmin` / `ctz` diagnostics: `tsel` no longer exists as a scalar. Use
   `tmn = min over i in [rl,len) of *phys-ltsel*[i]` for both — `ctz` still counts frames with
   `tmn < PHYS-TMIN-DIAG`, `ctmin` still keeps the window running MIN. Same names, same meaning
   ("was this chain fought by the resolve"), now measured on the worst segment instead of the
   only one. Keep `(set! tmn (fmax tmn PHYS-TMIN-FLOOR))` semantics: apply
   `PHYS-TMIN-FLOOR` to each `*phys-ltsel*[i]` after the search, exactly where 3919 applies it.

6. The commit at 3924-3932 becomes: if `collide?` and `tmn < 0.9999` (or any `t_i < 0.9999`) then
   `blend-lt!` and copy `*phys-cblend*` as 3927-3929 does; else copy `*phys-out0*` as 3930-3932.
   The non-collide path must stay bit-identical.

### Worst case is today's behaviour
Every `t_i = 0` reproduces the current whole-chain veto exactly, so this change can only ever
REDUCE clamping. That is the property that makes it shippable in the same cycle as C3.

---

## C3 — FAMILY A HAS NO DRIVING FORCE AT ALL WHEN THE ACTOR IS UPRIGHT

### The measurement that justifies it
Same window, same actor, same frames. `cinr` (mean written motion over frames the chain's own
anchor really moved), against the phase's own inert bar of 0.25:

```
  family A:  rbang .. lbang 0.144  rmidhair 0.132  lmidhair 0.0097  earL 0.0138
             earR 0.114  chestL 0.0397        -> INERT
  family B:  goggles 26.05  kneeflapL 1.29  kneeflapR 0.558  pantflapR 1.52
             topstrapL 6.26  topstrapR 4.64  -> MOVING
```
Family B moves, family A does not, in the same frames on the same skeleton. The only difference
in the integrator is line 3390-3391:

```
  (gacc (* (-> *phys-cgrav* ci) PHYS-GRAV-ACCEL (- 1.0 authw) sw
           (if (= 2 (-> *phys-cfam* ci)) 1.0 tiltf)))
```
`tiltf` is 0 for an upright actor (2833-2845), so **for family A upright, `gacc` is exactly
zero** and the chain's only remaining excitation is the anchor pseudo-force `cacc`, itself
clamped by `PHYS-COUPLE-MAX` (3378-3381). Keira standing and talking has almost no anchor
acceleration, so her hair, ears and chest have no driver. They are inert BY CONSTRUCTION, not by
tuning — which is why fourteen cycles of tuning did not move them.

SPEC 2 asks for the other thing: *"La gravité agit sur la **dynamique**, pas sur le point
d'équilibre : au repos, en position normale, ça regagne exactement la forme du modèle."*
Deleting gravity satisfies the equilibrium half and throws away the dynamics half.

### The change
Give family A the full world gravity, and cancel exactly the part of it that the ACTOR IS
CARRYING, so the equilibrium is untouched:

```
  g_world  = (0,-1,0) * (cgrav * PHYS-GRAV-ACCEL * (1-authw) * sw)      ;; today's magnitude
  carried  = R_anchor_now · gref                                        ;; unit vector
  g_eff    = g_world - (1 - tiltf) * |g_world| * carried                ;; family A
  g_eff    = g_world                                                    ;; family B, unchanged
```
where `gref` is a NEW per-chain unit vector, `*phys-cgref*`, captured ONCE per chain — the world
down direction expressed in the anchor bone's own axes at the moment of capture:

```
  gref = ( phys-axis-dot abm 0 down, phys-axis-dot abm 1 down, phys-axis-dot abm 2 down )
  with down = (0,-1,0) and abm = (-> skel bones (+ anchor-k 1) transform)
```
Read `phys-axis-dot` first and confirm whether it normalises the axis; if it does not, normalise.
Capture it on the first frame the chain is bound AND the anchor basis is non-degenerate — reuse
the same degenerate-row guard the tilt code uses at 2842 (`rl2 > 0.000001`). An un-posed frame
has every bone at the origin, so capturing there would poison the chain permanently: guard it,
and add a per-chain "captured" flag so it is taken exactly once. Reset the flag on rebind.

Then replace the scalar-y gravity at 3410 with the vector subtraction of `g_eff`. Keep the
family-B path arithmetically identical to today (`g_eff.y = -gacc`, `x = z = 0`).

### Why this cannot break owner rule W
At the reference orientation `carried` is the world down direction and `tiltf` is 0, so
`g_eff` is **identically zero** — bit-identical to today's behaviour, so `restdevA` /
"returns exactly to the model shape" is preserved BY CONSTRUCTION, not by tuning. It becomes
non-zero only as the anchor bone rotates away from where it was captured (she nods, leans, is
knocked over), which is exactly SPEC 2's stated exception, now continuous instead of a step.

### The gravity-direction diagnostic must not be broken by this
`gdir=` / `gloc=` (3402-3422) exist to prove gravity is applied in WORLD space, and
`physics_x86_grade.py:122` FAILS the leg if `gx²+gz² > 1e-4` or `gy > -0.999`. For family A the
applied vector is now deliberately a residual, so **gate the `gdir`/`gloc` capture on
`(or (= 2 cfam) (> tiltf 0.999))`** — i.e. sample it only where the applied vector IS the full
world gravity. Keira has seven family B chains, so the sample is never empty.

Add a new per-slot counter `*phys-slot-gresid*` = max over family A chains of
`|g_eff| / |g_world|` (0.0 when perfectly upright and aligned, 1.0 when gravity fully resumes),
printed on `[HD-PHYS3]` as ` gresid=~f`. This is the positive evidence that C3 fires at all: a
`gresid` of 0 everywhere would mean the new term is dead.

---

## C4 — DELETE `respath=`

`*phys-lresv*` is zeroed at 2570 and 2813 and **never accumulated anywhere** (no `vector+!` into
it exists). `*phys-slot-respath*` is fed only from it (4380-4383), so `respath=` on `[HD-PHYS6]`
(4940) prints a hard `0.0000` for ever. This file has already deleted twenty counters for exactly
this reason (see the note at 282-290). Delete the emit, the slot variable and the dead
`*phys-lresv*` plumbing. Do not replace it.

---

## C5 — SPLIT THE REMOVED-DISPLACEMENT LEDGER, AND ATTRIBUTE THE ONE-FRAME JUMP

### C5a — `remclamp` currently cannot separate STEP 3b from the strand pass
It is `Σ|out0 − out|` (4422-4424), and `out` is read after both. Add a snapshot array
`*phys-out1*` (same declaration shape as `*phys-out0*`), filled right after the STEP 4 bone
write completes (i.e. at the end of the per-chain body, ~4199) with the current `*phys-out*`.
Then:
* `remclamp` becomes `Σ|out0 − out1|` — the resolve alone;
* new `*phys-slot-remstrand*` = `Σ|out1 − out|` — the strand pass and the drawn-length restore.
Print ` remstrand=~f` next to `remclamp=` on `[HD-PHYS7]`. Without this split I cannot tell
whether C2 worked.

### C5b — a jump caused by the ANIMATION is not a resolution artifact
`resjerk=516.42` on X-MAX is numerically identical to `cvmx` of chain 9 = `goggles` = 516.4174,
and `goggles` carries `authored=1.00 authrise=10`. That is the authored takeover moving the
goggles to her eyes — which SPEC 6 says the animation is SUPPOSED to win. Reporting it as
resolution jerk names the wrong culprit.

Add a per-chain array `*phys-cvmxs*` (float 576): the max per-frame written displacement over
frames on which `authw < 0.5`, i.e. the SIM's own worst jump with authored takeover excluded.
Fold it in the same place `cvmx` is folded (4441-4459) and print it on `[HD-PHYS7]` as a
per-chain ` cvms:` list. Reset it in the same window-reset loop as `cvmx`.

---

## HOW TO VERIFY BEFORE HANDING BACK

1. `bash .autoport/build_x86_goal.sh` if such a script exists; otherwise find how the phase
   rebuilds GOAL only (grep `.autoport/physics_x86_leg.sh` for the freshness gate it enforces:
   `out/jak1/iso/GAME.CGO` must end up newer than this file) and run exactly that. Do NOT run a
   full cmake reconfigure — no C++ changed.
2. The compile must be clean. Report the exact command you used and its tail.
3. `strings out/jak1/iso/GAME.CGO` must contain every new literal: `csurf:`, `crtd:`, `cvms:`,
   `gresid=`, `remstrand=`, `presurfpen=`, `premeshpen=`, `prerootdev=`, `prelenmin=`,
   `prerestdevA=`, and must NOT contain `respath=`.
4. Do not run the legs. Report back; the manager runs the proof.

---

# C6 — ONE SURFACE AUTHORITY, NOT TWO FIGHTING (added after the L/R diagnosis)

## The measurement that justifies it — six predictions, six hits
Of Keira's three left/right head pairs, exactly one member of each is frozen, with IDENTICAL data
parameters and with `ctmin` 0.999-1.0 (so it is NOT the STEP 3b clamp). The dead ones hold a large
CONSTANT offset with one float ULP of per-frame movement: `cdev` 58.5 / 45.9 / 90.2 / 20.9 against
`cdsp` 0.0625 / 0.0312 / 0.0312 / 0.0156.

`phys-link-surf-push`, called from STEP 3a-bis (3558-3575), returns
`eff = depth(p) - max(0, depth(authored))` and pushes out when `eff > PHYS-PEN-TOL`. Because the
authored floor is subtracted, the wall sits EXACTLY at the authored pose and is ONE-SIDED: outward
motion is free, inward motion beyond 1 unit is deleted — and `PHYS-PROJFIX = 1.0` mirrors the
correction into `prev`, so the velocity is deleted with it. For a link whose authored pose the SDF
already reads as INSIDE, that is not a constraint, it is a ratchet: the chain walks outward until it
rests on the wall and then stops.

Whether a link's authored pose reads "inside" is a rig CONSTANT (STEP 0a re-glues every physics
joint to its bind-pose local every frame), and it is asymmetric because `phys-surf-sd` is a
POINT-CLOUD SDF whose `bs head` set ships 12 samples of which `PHYS-BSURF-MAX` keeps the first 8 in
file order — and those 8 contain no mirror pair. Replayed at each free link's authored pose:
Rbangb +66.7 INSIDE (dead) vs Lbangb -1.4 (alive); Lmidhairb +55.0 INSIDE (dead) vs Rmidhairb
-227.2 (alive); lEarb +242.7 INSIDE (dead) vs rEarb -188.1 (alive).

Two aggravations in the same call: the correction is applied to the link ORIGIN but sized by the
worst depth over `ms` samples sitting 250-1674 units away, bounded only by `maxcorr` — that is where
48-90 units of static offset come from; and `surfhit` is per-slot only, so no per-chain counter could
ever have shown this.

## The change
**Delete the STEP 3a-bis in-loop surface push.** STEP 3b already enforces the same objective — the
same `phys-surf-sd`, the same authored floor — but as a BOUNDED, CONTINUOUS retreat evaluated on the
pose that will actually be committed, with `t=0` feasible by construction so it always terminates on
a clear pose. With C2 that retreat is per-segment, so its cost is local. The in-loop push is
therefore redundant for correctness and is the only one of the two that can freeze a chain.

Note for the record why this is not the reverted experiment: the comment at 3608-3618 records that
removing the PROXY-CAPSULE push was tried and reverted because `surfpen` went to 217-733. That was
when STEP 3b bisected on CAPSULES. STEP 3b now bisects on the SURFACE, so the surface pre-conditioner
is redundant in a way the capsule one was not. **Leave the proxy-capsule push (3576-3652) exactly as
it is** — this change removes only the real-surface push at 3558-3575.

Concretely:
1. Remove the call site and its `when` wrapper at 3558-3575. Replace it with a comment carrying the
   measurement above and the reasoning, in this file's usual style, so nobody reinstates it blind.
2. If `phys-link-surf-push` becomes unreferenced, DELETE the function too (this file's own doctrine
   on dead code), and note in the comment where the call was that it went with it. If something else
   still calls it, say so in your report instead of deleting.
3. `snrm2`, declared at 2721 with the comment "so probing the AUTHORED pose's own depth cannot
   clobber the push direction", is never used anywhere — the fix its comment describes was never
   applied. If it becomes unreferenced too, delete it and say so.
4. `surfhit=` counted only that push. Keep the counter but feed it from the C1 post-commit audit
   (count of links whose post-commit authored-floored depth exceeded `PHYS-PEN-TOL`), so it keeps
   meaning "how often the surface actually had something to say" instead of silently becoming a
   structural zero. Say in your report which you did.

## C6b — the strand pass must respect the same authority
STEP 3c (4202-4262) vetoes a strand-vs-strand push using `phys-body-pen`, which is CAPSULE-based,
and then writes the bone with no surface re-check. C1's post-commit audit will now measure exactly
that hole. Change the veto to use the real surface (`phys-surf-sd`, authored-floored, same
convention as everywhere else) when the model has `bs` data (`(> (-> *phys-slot-nbsurf* slot) 0)`),
falling back to `phys-body-pen` when it does not — the same `sauth?` test STEP 3b already uses. The
veto's shape does not change: a push that would make the depth worse by more than `PHYS-PEN-TOL` is
refused and counted in `xveto`.

## Expected, measurable consequences — state these in your report as predictions, not as results
* `surfhit` changes meaning (see 4 above); the per-chain `csurf:` from C1 becomes the penetration
  authority.
* `rbang`, `lmidhair` and `earL` should stop holding a constant offset. Their `cdsp` should rise off
  the float-ULP floor. If they do not, C6 is refuted and must be reported as refuted.
* `remclamp` may rise (STEP 3b now has no pre-conditioner). `remstrand` from C5a and the per-segment
  `ctmin` say whether that trade is acceptable. Do not tune anything to make it look better.

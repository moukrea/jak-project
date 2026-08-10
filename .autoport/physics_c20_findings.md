# CYCLE 20 — WHAT WAS MEASURED, WHAT IT MEANS, WHAT WAS CHANGED

Everything below is read off the run of 19:07–19:25 today (the cycle-19 build, which had already
switched the collision objective to the real skinned surface). Sources:
`.autoport/reports/Grecharged-secondary-motion/x86_leg_X-{MAX,INTRO}.log` and `.x86_probe1.log`.
That run is the BASELINE this cycle is measured against. Note it graded the FULL-CAST data file,
but Keira's own section was byte-identical to the current one (same lines 175–300), so every
Keira number below is a like-for-like baseline.

Chain index -> name for `keira-hd` (declaration order IS the runtime index):
`0=rbang 1=lbang 2=rmidhair 3=lmidhair 4=backhair 5=earL 6=earR 7=chestR 8=chestL 9=goggles
10=kneeflapL 11=kneeflapR 12=pantflapL 13=pantflapR 14=topstrapL 15=topstrapR`

---

## FINDING 1 — family A is inert BY CONSTRUCTION, and the data says so in one number

`tiltmax=0.0000` on EVERY window of EVERY leg. `tiltf` is therefore 0 always, and the integrator
multiplies family A's gravity by exactly that:

    gacc = cgrav * PHYS-GRAV-ACCEL * (1-authw) * sw * (if (= 2 cfam) 1.0 tiltf)

So for all nine of her family-A chains, on 100 % of measured frames, the gravity term was
identically zero. Their only remaining excitation was the anchor pseudo-force, itself clamped by
`PHYS-COUPLE-MAX`. Standing and talking, she has almost no anchor acceleration.

`cinr` (mean written-joint motion over frames the chain's own anchor really moved), bar = 0.25:

| family A | cinr | verdict | family B | cinr | verdict |
|---|---|---|---|---|---|
| rbang    | 0.88–1.71 | MOVING | goggles   | 26.0–31.5 | MOVING |
| lbang    | 0.14 | **INERT** | kneeflapL | 1.29–4.26 | MOVING |
| rmidhair | 0.13 | **INERT** | kneeflapR | 0.56–1.20 | MOVING |
| lmidhair | 0.0097 | **INERT** | pantflapL | 0.030–0.17 | **INERT** |
| backhair | 0.39–0.70 | MOVING | pantflapR | 0.69–2.69 | MOVING |
| earL     | 0.0109–0.0138 | **INERT** | topstrapL | 5.89–8.52 | MOVING |
| earR     | 0.089–0.114 | **INERT** | topstrapR | 0.010–9.72 | MOVING |
| chestR   | 0.87–1.38 | MOVING | | | |
| chestL   | 0.0040–0.0495 | **INERT** | | | |

Six of the nine family-A chains are inert; six of seven family-B chains move. Same actor, same
frames, same skeleton. The run-total gate confirmed it by name:
`FAIL(RUN): ... keira-hd:chestL (cinr=0.0372) keira-hd:earL (0.0126) keira-hd:lbang (0.1674)
keira-hd:lmidhair (0.0098) keira-hd:rmidhair (0.2226)`.

This is the owner's oldest sentence — "les mèches de Keira sont ANCRÉES", "la poitrine
complètement statique" — and it is arithmetic, not tuning. Fourteen cycles of parameter changes
could not move a term that was being multiplied by zero.

=> **C3**: give family A the world gravity and cancel only the part the actor is CARRYING, so the
equilibrium stays exactly the model pose (identically, at the reference orientation) while a nod,
a lean or a knock-over restores a real force. New `gresid=` reports the residual; a `gresid` of 0
everywhere would mean the term is dead.

## FINDING 2 — the collision resolve removes 70 % of everything the solver produces

Ledger, X-MAX: `remprod=118267.86` produced vs `remclamp=82640.27` removed. `ctmin:` (per chain,
window minimum of the blend fraction; 0 = welded to the authored pose):

    backhair 0.0000 (ctz=125 frames)   kneeflapL 0.0000 (ctz=154)   pantflapL 0.0244 (ctz=47)
    pantflapR 0.0205                   topstrapL 0.0732             rbang 0.0263 (ctz=18)

STEP 3b bisected ONE scalar `t` for the WHOLE chain against its WORST point, and forced `t = 0`
outright when the exact verification failed. One offending link therefore deleted the motion of
every link in its chain.

=> **C2**: retreat PER SEGMENT, root to tip. `phys-chain-blend!` already blends only each
segment's DIRECTION and keeps its authored length, so a per-segment `t` is length-preserving by
the same construction. Every `t_i = 0` reproduces today's behaviour exactly, so the change can
only ever reduce clamping.

## FINDING 3 — the penetration and anchoring numbers did not measure the written pose

`surfpen=0.9977` looked like "at tolerance". It is computed at line 4091, inside the per-chain
loop. After that loop the pose is still changed three times: the strand-vs-strand pass writes
`*phys-out*` with **no surface re-check**, the drawn-pose length restore moves it again, the
translations are committed, and the descendant re-glue overwrites bone transforms including
root-locked ones.

SPEC 8's admissibility test: *if this number is green and the owner still sees the defect, what
would explain it?* — the strand pass moved the joint after the measurement. There is an answer, so
the number was worth nothing. Same for `rootdev` (read back before the re-glue) and for `lenmin`,
whose own fix (the drawn-pose restore) runs AFTER the number that grades it.

=> **C1**: a post-commit audit pass. The canonical names now carry the admissible values; the
intermediate ones are kept as `*_pre=` for diagnosis. New per-chain `csurf:` / `crtd:` because
SPEC 10 wants the verdict per NAMED chain and a per-slot maximum cannot give it.

## FINDING 4 — `restdevA` was a vacuous zero, and where it is not, it is over the bar

`restdevA=0.0000` with **`restwin=0`** in almost every window: no sample was ever taken. In the
few windows that did sample, `crestd: 1=15.8143` — that is `lbang`, 15.8 units off the model pose
at rest, against the W gate's bar of 8.0. So the metric was simultaneously empty and, when it
fired, red. Same class as the `resid=0 / push=0` and `idledrift=0 / idlewin=0` confessions this
phase already has gates for.

## FINDING 5 — `resjerk` was blaming the resolve for the animator's own motion

`resjerk=516.42` on X-MAX is numerically identical to `cvmx` of chain 9 = `goggles` = 516.4174,
and `goggles` carries `authored=1.00 authrise=10` — the animation grabbing them and putting them
over her eyes, which SPEC 6 says the animation is SUPPOSED to win.

=> **C5b**: per-chain `cvms:` = the worst one-frame written displacement on frames where the
authored weight is below 0.5, i.e. the sim's own jump with the authored takeover excluded.
=> **C5a**: `remclamp` split into `remclamp` (the resolve alone) and `remstrand` (the strand pass
plus the length restore), because the two were summed and neither could be attributed.

## FINDING 6 — `respath=` could never be anything but zero

`*phys-lresv*` is zeroed in two places and accumulated in none. `respath=` printed a hard
`0.0000` for ever. => **C4**: deleted, following the twenty counters this file has already deleted
for the same reason.

---

# HARNESS AND SCOPE FINDINGS (not physics — but they decided what got measured)

## H1 — three of the six proof legs measured nothing at all
Observed `ag=` sets: X-CAST and X-CAST2 contain only `jak-hd` + `dax-hd`; X-MAYOR contains
`keira-hd` but she emitted **zero** window lines there (7 lines, all init/bsurf/INFL). With the
cast archived, those three legs can only produce "no window state dump" — a failure for a
data-scope reason that says nothing about physics. Each leg now declares the art-groups it
contains and SKIPS, loudly, when none of them has declared data. The gate is derived from the
data file, so the legs re-arm themselves the moment the cast is regenerated.

## H2 — `keira3-hd` had never been measured, once, ever
`hd-look-keira` selects 0=ORIGINAL / 1=HD / 2=JAK 3, and look 2 is what maps to `keira3-hd`.
Nothing in the harness had ever set it: `keira3-hd` appears **zero times in every leg log on
record**, while its 16 chains sat in the data file as an unmeasured claim. Added leg `X-K3`.

## H3 — Keira's GAMEPLAY rig had no physics at all
In cutscenes she is `keira-hd`; in gameplay she is `assistant-lod0` (+5 level variants), which is
what X-RIDER instruments. Her stock section was archived with the cast, so walking into her hut
would have shown nothing moving. `assistant-*-lod0` IS Keira and is therefore in scope; it is
being GENERATED from the stock rig, not restored from the archive.

## H4 — the validator's coverage clauses could only be passed by fiction
Fourteen cycles had accumulated clauses demanding ">=30 model names in the report", ">=20 models
with their own resjerk", "resid=0 for Maia specifically", and per-chain verdicts for Jak's
`shirtL`/`shirtR`/`collarL`. Under the owner-authorised Keira-only scope those actors and chains
do not exist, so the only way to satisfy them was to write numbers for models nobody measured.
Every such clause was re-keyed from COVERAGE BY CAST COUNT to COVERAGE BY COMPLETENESS over the
DECLARED set — on the scope that exists this is strictly stronger, since a report naming thirty
models could satisfy the old form while measuring three. Every clause about the QUALITY of a
measurement is untouched. The cast-wide obligations are printed by a `[DEFERRED]` block on every
run and re-arm automatically.

Two hand-written name lists (C14-A, C16) were replaced by lists DERIVED from the data file, so a
chain can no longer be inert in silence because nobody thought to add its name.

## H5 — a field-name substring trap, caught before it fired
The intermediate metrics were first specified as `presurfpen=` / `prerootdev=` / …. A `pre`
PREFIX leaves the canonical name as a substring, and the consumers match `<name>\s*=` anywhere in
the line — the C21 gate's `rootdev[a-z-]*\s*=` would have read `prerootdev=743.2` as
`rootdev=743.2` and failed a 2.0-unit bar on a number it was not grading. Renamed to a `_pre`
SUFFIX, and the readers in `ratchet.py` and the C21 gate were anchored as well, because a guard
that depends on nobody coining an unlucky key is not a guard.

---

# THE RATCHET, STATED PLAINLY BECAUSE IT LOOKS LIKE A DODGE

`ratchet.py` currently reds on the cycle-19 report: `restdevA 525.8508` vs a stored best of
`5.0768`, and `lenmin 0.8944` vs `0.9605`. Both offending numbers belong to **out-of-scope models
in legs that are now skipped**: 525.85 is `explorer-lod0` in X-MAYOR; the other large readings are
`farmer-lod0` 360.72 and `jak-hd` 419.55, same leg.

So this cycle's run will not produce them — not because anything improved, but because the
population the metric ranges over SHRANK by an owner-authorised scope reduction. That cuts both
ways and must be said out loud: **shrinking the population makes the ratchet easier, and shrinking
a population to get past a red is exactly the move this phase must never make.** The numbers in
this cycle's report are Keira-only and are NOT comparable with the stored cast-wide bars. The cast
figures are owed, they are listed in the `[DEFERRED]` block, and they will be re-measured — not
re-seeded — when the cast is regenerated.

Also on record for the same reason: the stored `restdevA=5.0768` was itself produced by a build in
which the chains did not move (the file's own comment at 3793: "the clamp was writing the AUTHORED
pose, and a chain welded to the animation sits exactly on the model pose by construction"). It is
a phantom of the weld, and the W gate's independent 8.0-unit bar is what actually protects rule W.

---

# DECLARED SPEC DEVIATION (one, and it is deliberate)

SPEC 2 asks that gravity act on the dynamics of family A. C3 implements that. What C3 does NOT do
is give the equilibrium a gravity-derived sag term of any kind — the cancellation is exact at the
reference orientation, by construction, precisely so that owner rule W ("la position idle devrait
EXACTEMENT être celle du modèle de base") cannot be broken by this change. If the owner later wants
hair that hangs slightly lower at rest than the sculpt, that is a separate, deliberate decision
about the ART, not a physics fix, and it needs his word first.

---

# FINDING 7 — THE ONE THAT ACTUALLY EXPLAINS THE DEAD SET, 6 CASES OUT OF 6

FINDING 1 (family A has no gravity term) is true and is why nothing has any AMPLITUDE. It is not
why *specific* chains are frozen while their mirror images move. That has a different cause, and
it is exact.

## The mechanism
`phys-link-surf-push` is called once per free link per frame inside STEP 3a-bis
(jak-hd-physics.gc:3558-3575). It returns

    eff = depth(p) - max(0, depth(authored pose))

and pushes the link out whenever `eff > PHYS-PEN-TOL` (1.0). `PHYS-PROJFIX = 1.0` mirrors that
correction into the verlet `prev`, so the velocity is killed with it.

Subtract the authored floor and the wall sits EXACTLY AT THE AUTHORED POSE, one-sided: outward
motion is free, inward motion beyond 1 unit is deleted **and its velocity zeroed, every frame**.
For a link whose authored pose the SDF already calls "inside", that is not a constraint, it is a
ratchet. The chain drifts outward until it rests against the wall and then holds a large CONSTANT
offset with no variation — which is precisely the measured signature of the dead chains:
`cdev` 58.5 / 45.9 / 90.2 / 20.9 units of offset, with `cdsp` 0.0625 / 0.0312 / 0.0312 / 0.0156,
i.e. one float ULP of per-frame movement, and `ctmin` 0.999-1.0 (so NOT the STEP 3b clamp).

## Why one side of each pair and not the other
The signed distance is a POINT-CLOUD SDF: nearest of the bone's `bs` samples, signed by that
sample's own normal. `bs head` ships **12** samples and `PHYS-BSURF-MAX` keeps the **first 8 in
file order**. Those 8 contain **no mirror pair** — the two samples that would have restored
symmetry are the dropped #8 and #10. So the surface estimate is asymmetric even though the mesh
and the joints are exact mirrors (verified: mirror residual 0.0 on Rbangb/Lbangb,
Rmidhairb/Lmidhairb, rEarb/lEarb; all 95 bind matrices have det = +1.0, so nothing is reflected).

Replaying `phys-surf-sd` at each free link's authored pose:

| chain | free link | depth(authored) | wall armed | measured cvar |
|---|---|---|---|---|
| rbang    | Rbangb    | **+66.7 inside** | YES | 0.017 **DEAD** |
| lbang    | Lbangb/c  | −1.4 / −46.4 | no | 0.39–0.77 alive |
| rmidhair | Rmidhairb | −227.2 | no | 0.34–1.26 alive |
| lmidhair | Lmidhairb | **+55.0 inside** | YES | 0.011 **DEAD** |
| backhair | backHair2 | −20.1 | no | 0.82–2.01 alive |
| earL     | lEarb     | **+242.7 inside** | YES | 0.006 **DEAD** |
| earR     | rEarb     | −188.1 | no | 0.23–0.62 alive |

Three pairs, six chains, six correct predictions. And because STEP 0a re-glues every physics joint
to its bind-pose local under the animated parent, that depth is a RIG CONSTANT for the whole run —
which is why the pattern is identical across three windows and two different legs.

Two aggravating details in the same call: the correction is applied to the link ORIGIN but sized by
the worst depth over the link's `ms` samples, which sit 250–1674 units away — that is where 48–90
unit static offsets come from; and there is **no per-chain surface-push counter** (`surfhit` is
per-slot only), which is why nineteen cycles could not see any of this.

## REFUTED, each with a number, so none of them comes back
* ORDER / shared scratch (my own leading hypothesis): every per-chain scratch buffer is fully
  rewritten over `[0,len)` before any read — `lo2`/`lcos`/`lsin`, `lpush`, `*phys-psave*`,
  `*phys-ccap*`, `*phys-cclist*`, `*phys-cblend*`, `*phys-swl*`/`*phys-sws*`, `moved`. And the data
  kills it anyway: dead = indices 0, 3, 5, 12 and alive = 1, 2, 6, 13 — it alternates.
* ANCHOR selection: all seven head chains share anchor `head`, and the log prints
  `canch: 0..6 = 109.2307` — the same anchor acceleration to four decimals. Chest pair share `chest`.
* MIRRORED / negative-determinant bind poses: all 95 bind matrices det = +1.00000; `R_R^T R_L` is a
  PROPER 180° rotation. That flip is exactly why the `ms` samples are exact negations — a rotation,
  not a reflection. Nothing in the swing, the direction blend, the length invariant or the re-glue
  is orientation-sensitive.
* `radii=` feeding the cone or the freedom ramp: `*phys-lrad*` is read only by collision. The cone
  is `cmaxrad * infl`; the profile is a function of `len`, `rl`, `rootfree`, `grad` only.
* `side=`: set once, read once, only to increment `xleg` (which is 0 in every Keira window).

NOT explained by this: the chest pair and pantflapL-vs-R. Their nearest sets are `chest` and
`Lknee`/`Rknee`, and the knee sets ARE exact mirrors, so those two pairs still need a cause. Said
plainly rather than folded into a 6/6 claim.

=> **C6**: the surface constraint stops being a per-substep positional ratchet with a velocity kill
and becomes what STEP 3b already is — ONE bounded, continuous, per-segment retreat evaluated on the
pose that will actually be committed. Two authorities fighting over the same objective is what
produced a frozen chain that no tuning could reach.

## Two incidental live defects the same pass turned up
1. `snrm2` is declared at :2721 with the comment "so probing the AUTHORED pose's own depth cannot
   clobber the push direction" — and is **never used**. The floor probes still pass `nrm` itself, so
   a losing sample's floor probe leaves `nrm` holding the normal at a DIFFERENT sample's authored
   point while `worst` belongs to another. The push could go the wrong way. The stated fix was never
   applied in the function that needs it. (Moot if the call site goes; recorded either way.)
2. `PHYS-IDLE-ANCH = 2.0` is never satisfied on a leg that drives the actor, so `restdevA` is a
   STRUCTURAL zero on the locomotion route — `restwin=0`. It is only measurable in a cutscene leg,
   where it read 15.81 on `lbang` against the W gate's 8.0 bar. This is the mechanism behind
   FINDING 4, and it means the W verdict must be taken from X-INTRO, never from X-MAX.

## OPEN, DELIBERATELY NOT FIXED TONIGHT — the SDF truncation itself
C6 removes the mechanism that turns the surface misclassification into a frozen chain, but it does
not remove the misclassification. `PHYS-BSURF-MAX = 8` truncates each bone's `bs` set at LOAD time,
not per tier, so the asymmetry survives at every precision level: `bs head` ships 12 samples and the
two that would restore mirror symmetry are dropped. STEP 3b still bisects against that same
point-cloud, so one side of a pair will still retreat sooner than the other — smaller, bounded and
continuous now, but present.

The `bs` sets are written in farthest-point order precisely so a prefix is a near-optimal cover, and
that is sound for a COVER; it is not mirror-symmetric, and a coarse cover is exactly what
misclassifies a joint sitting a few units from the surface. Raising the cap is a capacity change
(72 sets x 8) with a per-query cost on the device, and the honest fix is probably not more samples
but a surface test that does not have to decide a binary inside/outside for a near-surface joint.
Recorded as open, with the mechanism named, rather than half-fixed in the same cycle as six other
changes.

---

# THE DATA, GENERATED (SPEC 7) — VERIFIED INDEPENDENTLY, NOT TAKEN ON TRUST

`recharged_assets/physics_chains.txt` now declares **3 sections / 8 art-groups**, all Keira:
`keira-hd` (48 volumes), `keira3-hd` (49), `assistant-lod0` + 5 aliases (56). 47 chains total.
Checked by reading the file myself, not from the generator's report:

* family A -> `hang=0.00` and family B -> `hang>0`: **0 violations**, and 0 unclassified chains.
* `colskip=` / `chains=` / `xchain=` / `rootfree=` / `rootlock=0` on any chain line: **NONE**.
* every chain of 2+ joints carries `rootlock>=1`: **no exceptions** — so C21's "no unlocked hair
  root" holds by construction and not by inspection.
* `radius` max 1958 against C18's 4710 bar; median 536 over 347 volumes.
* `[eyescale]` and `[levels]` **byte-identical to HEAD**.
* the generator is idempotent byte-for-byte on a second run.

## The stock rig: where the hierarchy came from, and one thing the spec got wrong
`joint-node-info.min.json` does NOT carry parents — every entry under `assistant-lod0-jg` is a
2-element `[index, name]` pair. So spec option (a) was not available as written. The hierarchy,
bind pose and skin weights all come from the stock GLB instead, i.e. one source for every number.
`joint-node-info` is still used for what it IS authoritative about — the runtime joint ORDER — as
the cross-check the HD path gets from its `k2e` sidecar: all 96 names agree joint-for-joint, and a
disagreement is fatal rather than a warning. The 6 aliases were verified too: village2 permutes 60
joint indices and firecanyon/lavatube have 94 joints (missing `torch`/`torchTIP`) — none of them a
joint we drive, which is exactly what makes one name-keyed block legal for all six.

## Three things flagged rather than fixed
1. **`LpantFlap`, `RpantFlap` and `belt` have NO measurable thickness on the stock rig** — zero
   vertices at weight >= 0.34, so their radius is the `LINK_RADIUS_MIN` fallback of 24 units, and
   the same three chains have no `ms` mesh samples either. On the HD rigs the identical defect is
   fixed by a reskin rule; a stock jak1 rig cannot be reskinned. A 24-unit radius means those
   flaps collide as a thin line. Flagged, not fixed, and NOT papered over by widening the radius by
   hand — that would be exactly the hand-tuning SPEC 7 forbids. Same story for `topstrapL/R` on
   both HD rigs.
2. **The chest `at=` radius changed from a hand-written 320 to a DERIVED 252 on the HD rigs**
   (`R = d - G - r`: tip separation, minus the closest distance between the two cups' own skinned
   vertices, minus the partner link's half-thickness). That is a real behaviour change: first
   contact now needs 100 units of approach per cup instead of 66, i.e. the two sides meet LATER
   than before. It is the price of deriving the number instead of choosing it, and it is
   geometrically reachable on both rigs (max lateral travel at `maxangle=26` is 428 HD / 488
   stock, against 100 / 242 needed). If the owner says they no longer touch, this is the number to
   look at first.
3. **`belt` has no HD counterpart to copy its style from**, so it keeps the values the archived
   stock line shipped with. Every other stock chain uses the HD kind's numbers verbatim, so the
   two rigs of the same character behave the same.

`physics_c14_meshsamples.py` was NOT run: it has no `--only` flag, is driven off
physics_chains.txt, and would have truncated `physics_mesh.txt` from 43 models / 1733 `bs` / 580
`ms` down to Keira alone, destroying the surface data for every other actor. Confirmed still
intact at 43 models.

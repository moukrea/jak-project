# Unified Unsupported Breast Soft-Body Physics Specification

> **Source : l'owner, 2026-08-13 23:30. Document AUTORITAIRE.**
> À appliquer **à la lettre** pour la poitrine (Keira, Maia) et à **transposer** pour le reste
> (cheveux, mèches, lanières, lunettes) : même architecture de solveur, valeurs propres à chaque
> organe. Aucune ligne de cette spec ne se paraphrase ni ne s'arrondit sans mesure à l'appui.

---

# KEIRA HAGAI — MEDIUM/LARGE BUST

## 1. Target

This specification defines unsupported breast soft-body physics for Keira Hagai, using the supplied
standing model as the anatomical and visual reference.

The intended simulation shall reproduce the behavior expected from a real adult woman with broadly
comparable torso and breast proportions, ignoring intentionally stylized non-torso proportions such
as the oversized head.

The target is deliberately biased toward the high-motion end of realistic unsupported movement,
while remaining physically coherent.

The simulation shall exhibit:

- visible inertial lag;
- gravity-dependent redistribution;
- clear but damped bounce;
- moderate-to-large shape deformation;
- independent left/right motion;
- broad anatomical attachment to the thorax;
- near-conservation of breast volume;
- realistic saturation under extreme gameplay accelerations.

The result shall avoid:

- rigid movement;
- spherical pendulum behavior;
- water-balloon behavior;
- rubber-like stretching;
- sustained gelatin oscillation;
- arbitrary sinusoidal jiggle unrelated to actual body acceleration.

The garment shall provide no meaningful support or compression. It shall follow the underlying
breast surface closely and shall not materially alter the breast dynamics.

## 2. Critical Neutral-Pose Definition

The supplied standing model is the exact "100%" reference state.

When Keira Hagai is upright, stationary, under normal Earth gravity, and not externally colliding
with anything, the final settled breast geometry shall reproduce the original authored standing
model.

    Projection = 100%
    Width      = 100%
    Height     = 100%
    COM Position = P0
    COM Velocity = 0
    Additional Procedural Sag = 0%

Any sag, lower-pole fullness, projection, spacing, cleavage, or asymmetry present in the original
model is considered already built into the reference geometry.

**No additional gravity sag shall be applied merely because the simulation is active.**

## 3. Gravity Calibration

The simulation operates relative to the authored upright "1 g" equilibrium.

Define:

- `g_world` = world gravity;
- `R` = torso orientation;
- `g_local` = gravity transformed into breast-local torso space;
- `g_ref` = local gravity vector in the authored upright standing pose;
- `a_torso` = linear acceleration of the breast root/chest;
- `ω` = torso angular velocity;
- `α` = torso angular acceleration.

A useful solver-space driving acceleration is conceptually:

    a_drive = (g_local - g_ref) - a_torso + a_angular

Standing still gives `g_local = g_ref` and `a_torso = 0`, therefore `a_drive = 0`, and the system
converges exactly to the authored mesh.

**The solver therefore responds to changes from the standing gravitational equilibrium, rather than
applying a second independent gravity sag.**

## 4. Reference Morphology

Keira Hagai presents: narrow-to-moderate ribcage; substantial but not extreme breast volume;
significant forward projection; fairly full upper and lower poles; fairly close medial positioning;
moderate distal soft-tissue mass; visibly soft unsupported morphology.

As a loose human sizing analogy only, the visual volume is consistent with approximately a large
C / D-ish breast volume on a relatively narrow ribcage, depending strongly on band measurement and
sizing system. **Bra cup designation shall not be used by the simulation.**

## 5. Estimated Physical Properties

**Per breast** — estimated volume 450–600 mL; nominal volume **525 mL**; effective soft-tissue
density ~0.93–0.98 g/mL, nominal **0.95 g/mL**; estimated mass 0.42–0.58 kg; nominal simulation
mass **0.50 kg**.

**Combined breasts** — nominal volume ~1.05 L; nominal mass ~1.00 kg; practical combined mass range
0.85–1.15 kg.

## 6. Normalized Geometry

Define `L0` neutral forward projection, `W0` neutral breast width, `H0` neutral vertical extent,
`B0` neutral characteristic root-to-apex length, `P0` neutral breast center-of-mass position.

Approximate human-scale equivalents:

    L0 ≈ 110–125 mm
    W0 ≈ 130–150 mm
    H0 ≈ 125–145 mm
    B0 ≈ 115–125 mm

Absolute values are sanity-checking references only. The game implementation shall derive
normalized dimensions directly from the character mesh. All global displacement limits below use
`B0` unless another axis is explicitly named.

## 7. Local Coordinate System

    +X = character's outward lateral direction
    +Y = upward along torso
    +Z = forward from chest

For the left and right breasts, outward `+X` should be mirrored so that the equations remain
symmetrical. All dynamic calculations shall occur relative to the torso/root transform rather than
directly in world space.

## 8. Volume Conservation

Breast tissue shall behave as a near-incompressible soft volume.

    Normal movement:          98–101% of neutral volume
    Strong transient events:  96–102%

Conceptually `Sx·Sy·Sz ≈ 1`, **but the whole breast shall not be represented by one affine scale
transformation.** Instead: root tissue moves little; intermediate tissue redistributes; distal
tissue deforms most; local thickness compensates for elongation; flattening redistributes material
laterally.

The volume constraint applies to the actual deformable volume, not merely to the bounding-box
dimensions quoted below.

## 9. Neutral Standing State

    Projection        = 1.00 L0
    Width             = 1.00 W0
    Height            = 1.00 H0
    COM Displacement  = 0.00 B0
    Apex Displacement = 0.00 B0
    AdditionalStandingSag = 0

Residual oscillations caused by preceding movement may temporarily cross the neutral shape. Once
settled, however, the original authored standing shape shall be restored exactly.

## 10. Supine — Lying Face-Up

    Forward projection:  −25 to −35%, nominal −30%   SupineProjectionScale = 0.70
    Width:               +18 to +28%, nominal +23%   SupineWidthScale      = 1.23
    Vertical envelope:   +5 to +12%,  nominal +9%    SupineHeightScale     = 1.09
    COM toward thorax:   18–28% B0,   nominal 23% B0
    Outward COM migration per breast: 4–10% W0, nominal 7% W0

Required visual behavior: reduced forward projection; wider footprint against the thorax; moderate
outward migration; increased separation; soft flattening; redistribution of distal tissue. The
breast root shall remain broadly attached. **The entire breast shall not simply scale uniformly
from its center.**

## 11. Prone / Torso Horizontal With Breasts Hanging Freely

    Static COM displacement: 20–28% B0, nominal 24% B0, upper static target 30% B0
    Root-to-apex length:     +18 to +26%, nominal +23%   HangingLengthScale = 1.23
    Transient settling peak: ~+30%                       HangingTransientLengthMax = 1.30
    Width:                   −7 to −13%, nominal −10%    HangingWidthScale = 0.90
    Thickness:               −6 to −12%, nominal −9%     HangingThicknessScale = 0.91

The root remains relatively stable while distal tissue becomes longer, somewhat narrower, lower,
more pendant. The change must occur progressively along the root-to-apex axis.

## 12. Sideways Gravity / Side-Lying Orientation

The breasts shall not behave identically. The gravity-side breast experiences stronger thoracic
compression, while the opposite breast migrates across the chest.

    Global lateral COM response:            15–24% B0, nominal 19%
    Upper/opposite breast medial migration: 10–18% W0, nominal 14%
    Gravity-side lateral flattening:        −15 to −25%, nominal −20%

Compensating enlargement occurs principally in the two perpendicular dimensions. External surface
collision, if the character is actually lying on a floor or bed, shall be solved separately rather
than baked into this orientation equilibrium.

## 13. Intermediate Gravity Orientations

Supine, prone, upright and lateral states **shall not exist as unrelated hard-coded morph targets.**
The equilibrium state shall vary continuously with the local gravity direction.

At a 45° forward lean, Keira should exhibit approximately: mild-to-moderate forward/downward COM
migration; modest root-to-apex elongation; slightly reduced width; redistribution toward the
lower/distal pole.

The system shall use the gravity vector to derive the target physical tendency. Static pose morphs
may assist deformation, but they shall be driven continuously by orientation.

## 14. Jump Take-Off

    COM lag:                 ordinary 15–25% B0, strong 25–32% B0
    Apex displacement:       ordinary 20–30% B0, strong 30–38% B0
    Directional elongation:  ordinary +7 to +13%, strong +13 to +18%
    Perpendicular contraction: ≈ −4 to −8%

**The majority of visible movement must come from global mass lag and rotation, not from stretching
the tissue by the complete displacement magnitude.**

## 15. Jump Apex and Falling Transition

At the apex of a jump, torso vertical velocity may temporarily become almost zero while breast
soft-body velocity remains non-zero. The breast simulation shall depend on acceleration, relative
velocity and current soft-body state, and **shall not use character speed alone.**

    upward torso acceleration → breast downward lag
    acceleration decreases    → breast catches torso
    jump apex                 → breast may cross neutral position
    fall begins               → inertia creates opposite relative displacement

This phase reversal should occur naturally through integration rather than through a scripted bounce
animation.

## 16. Landing / Abrupt Vertical Deceleration

    Strong landing COM:        25–35% B0
    Very hard landing COM:     35–40% B0
    Strong landing apex:       30–42% B0
    Very hard / exceptional:   42–50% B0
    Recommended soft ceiling:  MaxApexDisplacement ≈ 0.50 B0

    Directional tissue elongation: ordinary +10 to +16%, strong +16 to +21%,
                                   exceptional transient ~+25%

"25%" is a deformation ceiling, not a normal target.

## 17. Horizontal Acceleration and Braking

    COM lag:                moderate 10–18% B0, strong 18–27% B0, upper transient ~30% B0
    Apex displacement:      strong 25–35% B0, upper transient ~40% B0
    Directional elongation: moderate +5 to +10%, strong +10 to +15%, upper transient ~18%

Braking produces the corresponding opposite response and may create an overshoot through neutral.

## 18. Strong Yaw Rotation

Rapid torso yaw shall produce **angular lag rather than rigid breast rotation.**

    COM displacement:        moderate 10–17% B0, strong 17–24% B0, exceptional ~28% B0
    Apex displacement:       strong 20–30% B0, exceptional ~35% B0
    Directional deformation: stretch +5 to +12%, strong transient ~15%,
                             perpendicular compression −3 to −8%

Left and right trajectories shall differ because their offsets from the torso rotational axis
differ.

## 19. Strong Pitch Rotation

During a rapid forward bend: the torso rotates first; breast mass lags behind; gravity subsequently
pulls the breasts toward the new hanging equilibrium; the breasts may overshoot; damping returns
them toward equilibrium.

During rapid return to upright: breast mass remains forward/downward briefly; the authored standing
geometry is crossed; a smaller counter-motion occurs; the breast converges back to exactly "100%".

Strong pitch motion may generate **30–40% B0 apex displacement without requiring comparable local
stretch.**

## 20. Roll / Lateral Torso Motion

    Typical strong roll: COM 15–22% B0, apex 20–30% B0, local stretch +5 to +12%

The gravity-side and opposite-side breasts must not be mechanically mirrored after contact with the
torso begins.

## 21. Combined Translation and Rotation

Linear and rotational displacement contributions shall combine vectorially. **They shall not be
added without saturation.**

    D_combined = D_max · tanh( |D_linear + D_angular| / D_max )

This prevents combinations such as strong jump + fast rotation + abrupt animation acceleration from
creating implausibly large soft-body excursions.

## 22. Dynamic Soft Limits

    Breast COM:              normal ≤35% B0, hard transient ≤40% B0
    Distal/apex displacement: normal ≤42% B0, exceptional ≤50% B0
    Local tissue elongation: common 5–15%, large 15–21%, exceptional 21–25%
    Absolute stretch clamp:  25%

**Large apex displacement shall not imply equally large tissue extension.** Translation, rotation
and redistribution shall account for most of the excursion.

## 23. Primary Dynamic Model

A suitable global model is an anisotropic damped soft-body mass:

    M·ẍ + C·ẋ + K·x = M·a_drive + F_collision

where `x` = relative breast COM displacement; `M` = effective breast mass; `C` = damping;
`K` = anisotropic stiffness matrix; `a_drive` = gravity/orientation/inertial drive;
`F_collision` = breast/chest/breast/external contact forces.

The solver should then derive local deformation from COM displacement, angular lag, root
constraints, volume conservation, and local collision pressure.

**A single spring attached to the nipple/apex is insufficient.**

## 24. Primary Natural Frequencies

    Vertical    = 2.30 Hz     (range 2.1–2.5 Hz)
    Front/Back  = 2.50 Hz     (range 2.3–2.7 Hz)
    Lateral     = 2.65 Hz     (range 2.4–2.9 Hz)

**Vertical motion is intentionally the slowest.**

## 25. Damping

Recommended primary damping ratio **ζ = 0.35**, useful range 0.32–0.42. The nominal target
intentionally produces visible unsupported movement without long-lasting oscillation.

## 26. Rebound Magnitude

For ζ = 0.35 the theoretical opposite-side overshoot ratio is

    exp( −ζπ / √(1−ζ²) ) ≈ 0.31

Practical target ~30–31% of the previous major excursion.

    Primary displacement    50 mm
    First opposite rebound  ~15 mm
    Second return           ~4–6 mm

## 27. Settling Time

After one strong isolated impulse: dominant visible response 0.3–0.6 s; secondary movement
0.6–1.2 s; mostly settled ~1.0–1.5 s; essentially stationary ~1.3–1.7 s.

**Long-running obvious oscillation should not occur.**

## 28. Effective Spring Parameters

With m = 0.50 kg and f = 2.30 Hz: `k = m(2πf)² ≈ 104 N/m`.
With ζ = 0.35: `c = 2ζ√(km) ≈ 5.1 N·s/m`.

These values describe the effective whole-breast mode, not literal material properties of
biological tissue.

## 29. Anisotropy

    Vertical    1.00
    Front/back  0.90
    Lateral     0.82
    Torsional   0.72

The breast shall remain mobile in every direction because it is unsupported. The anisotropy merely
prevents an unrealistically isotropic blob response.

## 30. Root Attachment

Approximately **28–35% of the rear breast volume** should behave as strongly attached tissue,
nominal **30%**.

    Deep root           90–100%
    Rear/intermediate   55–85%
    Mid-volume          25–55%
    Distal volume        5–30%
    Apex                minimal direct anchoring

**There shall be no hard attachment boundary.**

## 31. Root-to-Apex Shape Gradient

With `r = 0` at chest attachment and `r = 1` at distal/apex region, a useful deformation weighting
is `w(r) = r^1.6…2.0` — little deformation at the root; progressively increasing mobility; largest
displacement in distal tissue.

## 32. Left/Right Independence

Each breast shall maintain independent state for translation, velocity, rotation, deformation and
collision history. Subtle parameter variation is recommended: mass ±2–4%, stiffness ±3–5%, damping
±3–5%. Symmetrical movement remains approximately symmetrical, but not mathematically identical.

## 33. Breast-Breast Interaction

Medial surfaces shall collide or repel before visible interpenetration. The interaction shall
support contact, local compression, tangential sliding, redirection of movement.

Recommended restitution 0.00–0.15, nominal **0.06**. Contact shall not create billiard-ball rebound.

## 34. Torso and External Collision

Breast tissue shall collide with chest wall, ribcage, relevant upper-abdominal regions, and
external surfaces where appropriate. Chest restitution 0.00–0.05, nominal **0.02**.

Collision energy should primarily become deformation, redistribution and damping — **not bounce.**

## 35. Garment Coupling

The visible tank top is a non-supportive conforming layer.

    Support contribution  ≈ 0
    Compression           ≈ 0
    Motion damping        ≈ 0
    Independent cloth lag ≈ 0

The garment follows the underlying breast surface essentially one-to-one. It may smooth tiny
high-frequency surface deformation for rendering stability, but shall not alter global motion.

## 36. Secondary Local Soft-Tissue Jiggle

A higher-frequency local mode may be layered over the global motion.

    Amplitude: normal 2–5% of local thickness, strong impulse 5–7%, hard ceiling ~7%
    Frequency: 4–7 Hz, nominal ~5.2 Hz
    Damping ratio: 0.55–0.75, nominal 0.65

This response should mainly appear after a change in direction of the global breast mass.

## 37. Numerical Stability, Resets and Discontinuities

The simulation shall be **timestep-independent**. Recommended effective soft-body update frequency
**≥120 Hz**; at 60 FPS, **2 substeps minimum**; hard impacts may use **3–4 adaptive substeps**.

Soft displacement clamps should be preferred to abrupt positional clamps.

The simulation state shall be rebased or reset on teleportation, instant cutscene placement,
animation root discontinuity, level transition, or implausibly large one-frame transform changes.

**Artificial transforms must not generate physical breast impulses.**

## 38. Recommended Complete Preset — Keira Hagai

```
# ==================================================
# KEIRA HAGAI — UNSUPPORTED MEDIUM/LARGE BUST
# ==================================================

# MORPHOLOGY
NominalVolumePerBreast       = 0.525 L
MassPerBreast                = 0.50 kg
NeutralProjection            = 1.00
NeutralWidth                 = 1.00
NeutralHeight                = 1.00
NeutralCOMOffset             = 0.00
AdditionalStandingSag        = 0.00

# PRIMARY DYNAMICS
GlobalFrequencyVertical      = 2.30 Hz
GlobalFrequencyAP            = 2.50 Hz
GlobalFrequencyLateral       = 2.65 Hz
GlobalDampingRatio           = 0.35
FirstBounceRatio             = 0.31

# SUPINE EQUILIBRIUM
SupineProjectionScale        = 0.70
SupineWidthScale             = 1.23
SupineHeightScale            = 1.09
SupineCOMDepth               = 0.23 B0
SupineCOMLateral             = 0.07 W0

# HANGING EQUILIBRIUM
HangingLengthScale           = 1.23
HangingWidthScale            = 0.90
HangingThicknessScale        = 0.91
HangingCOMDisplacement       = 0.24 B0
HangingTransientLengthMax    = 1.30

# SIDE-GRAVITY EQUILIBRIUM
SideGravityCOM               = 0.19 B0
UpperBreastMedialShift       = 0.14 W0
LowerBreastCompression       = 0.20

# DYNAMIC RESPONSE
StrongJumpCOMLag             = 0.25–0.32 B0
StrongJumpApexLag            = 0.30–0.38 B0
StrongLandingCOM             = 0.25–0.35 B0
HardLandingCOM               = 0.40 B0
StrongLandingApex            = 0.30–0.42 B0
HardLandingApex              = 0.50 B0
StrongLinearAccelCOM         = 0.18–0.27 B0
HardLinearAccelCOM           = 0.30 B0
StrongYawCOM                 = 0.17–0.24 B0
HardYawCOM                   = 0.28 B0
StrongYawApex                = 0.20–0.30 B0
HardYawApex                  = 0.35 B0

# SOFT LIMITS
NormalMaxCOMDisplacement     = 0.35 B0
HardMaxCOMDisplacement       = 0.40 B0
NormalMaxApexDisplacement    = 0.42 B0
HardMaxApexDisplacement      = 0.50 B0
NormalDynamicStretch         = 0.15
StrongDynamicStretch         = 0.21
AbsoluteStretchClamp         = 0.25
NormalVolumeRange            = 0.98–1.01
HardVolumeRange              = 0.96–1.02

# ANISOTROPY
VerticalCompliance           = 1.00
APCompliance                 = 0.90
LateralCompliance            = 0.82
TorsionalCompliance          = 0.72

# ATTACHMENT
StrongRootFraction           = 0.30
RootAnchor                   = 0.90–1.00
RearIntermediateAnchor       = 0.55–0.85
MidVolumeAnchor              = 0.25–0.55
DistalAnchor                 = 0.05–0.30
RootDeformationExponent      = 1.6–2.0

# COLLISION
BreastBreastRestitution      = 0.06
BreastChestRestitution       = 0.02
EnableBreastBreastCollision  = true
EnableChestCollision         = true
EnableExternalCollision      = true

# GARMENT
GarmentSupport               = 0.00
GarmentCompression           = 0.00
GarmentDynamicDamping        = 0.00

# SECONDARY TISSUE MODE
SecondaryJiggleAmplitude     = 0.02–0.05
SecondaryJiggleHardMax       = 0.07
SecondaryFrequency           = 5.2 Hz
SecondaryDampingRatio        = 0.65

# EFFECTIVE PRIMARY VERTICAL SPRING
VerticalEffectiveMass        = 0.50 kg
VerticalEffectiveStiffness   ≈ 104 N/m
VerticalEffectiveDamping     ≈ 5.1 N·s/m

# SOLVER
RecommendedEffectiveRate     >= 120 Hz
MinimumSubstepsAt60FPS       = 2
HardImpactSubsteps           = 3–4
```

## 39. Expected Visual Signature — Keira Hagai

Keira Hagai shall read as **full, soft, freely moving, moderately heavy, but still relatively
responsive.**

The defining behavior is: obvious vertical bounce; moderate lateral lag; meaningful but not enormous
supine spreading; moderate hanging elongation; one strong rebound followed by rapid decay;
noticeable but controlled deformation.

When motion ceases in the upright pose, the system shall recover **100% authored standing shape,
exactly.**

---

# MAIA ACHERON — VERY LARGE BUST

## 1. Target

This specification defines unsupported breast soft-body physics for Maia Acheron, using the supplied
standing model as the anatomical and visual reference.

Maia Acheron possesses roughly twice the breast volume and mass of Keira Hagai relative to a
similarly narrow torso. The simulation therefore targets: substantially greater inertia; larger
gravity-driven redistribution; lower-frequency movement; greater displacement; greater
orientation-dependent shape change; more breast-to-breast interaction; stronger thorax contact;
longer settling; greater distal deformation.

The tuning remains biased toward the high-motion end of plausible unsupported movement, rather than
toward conservative animation.

The result shall avoid rigid spherical motion; exaggerated elastic stretching; water-balloon
deformation; indefinite bouncing; arbitrary jiggle disconnected from acceleration.

The visible breast covering shall be treated as non-supportive for this physics model.

## 2. Critical Neutral-Pose Definition

The supplied standing model is the exact 100% reference state.

    Projection = 100%
    Width      = 100%
    Height     = 100%
    COM Position = P0
    COM Velocity = 0
    Additional Procedural Sag = 0%

The substantial visible projection and existing authored breast shape are already the neutral 1 g
state. **The solver shall not make the breasts hang lower simply because their estimated mass is
high.**

## 3. Gravity Calibration

Maia Acheron uses exactly the same equilibrium convention as Keira Hagai.

    a_drive = (g_local - g_ref) - a_torso + a_angular

In authored upright neutral, `g_local = g_ref` and `a_drive = 0`.

The high breast mass therefore affects inertia, natural frequency, collision momentum and transient
displacement — **without introducing additional static deformation in the reference standing pose.**

## 4. Reference Morphology

Very narrow torso; extremely large breast-to-ribcage volume ratio; much greater volume than Keira
Hagai; substantial forward projection; large distal mass; considerable medial volume; close-set
positioning; large superior/inferior envelope; strong potential for orientation-dependent
redistribution.

The breast volume reads approximately **2.0–2.2× Keira Hagai**. Cup size is not used by the physical
model.

## 5. Estimated Physical Properties

**Per breast** — estimated volume 950–1,250 mL; nominal **1,100 mL**; effective density
~0.93–0.98 g/mL, nominal 0.95 g/mL; estimated mass 0.90–1.20 kg; nominal simulation mass
**1.05 kg**.

**Combined** — nominal volume ~2.20 L; nominal mass ~2.10 kg; practical range 1.8–2.4 kg.

**Relative to Keira Hagai** — nominal volume ratio 1100/525 ≈ 2.10; nominal mass ratio
1.05/0.50 = 2.10.

## 6. Normalized Geometry

    L0 ≈ 140–165 mm
    W0 ≈ 160–185 mm
    H0 ≈ 165–195 mm
    B0 ≈ 145–160 mm

Illustrative only; normalized dimensions from the actual model remain authoritative.

## 7. Local Coordinate System

Same breast-local frame as Keira; left/right outward axes mirrored; dynamic state stored relative to
the torso/root, not directly in world coordinates.

## 8. Volume Conservation

    Normal movement:         98–101%
    Strong transient events: 96–102%

`Sx·Sy·Sz ≈ 1`, again **not a global scale operation.** The much greater breast volume means
deformation must involve substantial redistribution, especially against the chest when supine;
toward the distal pole when hanging; medially during inward acceleration; laterally during rotation.
The root remains much less deformable than the distal breast.

## 9. Neutral Standing State

    Projection        = 1.00 L0
    Width             = 1.00 W0
    Height            = 1.00 H0
    COM Displacement  = 0.00 B0
    Apex Displacement = 0.00 B0
    AdditionalStandingSag = 0

Despite the significantly larger estimated mass, the neutral standing mesh is not procedurally
altered. That mesh is the calibration equilibrium.

## 10. Supine — Lying Face-Up

    Forward projection:  −38 to −48%, nominal −43%   SupineProjectionScale = 0.57
    Width:               +32 to +46%, nominal +40%   SupineWidthScale      = 1.40
    Vertical envelope:   +12 to +22%, nominal +18%   SupineHeightScale     = 1.18
    COM toward thorax:   28–38% B0,   nominal 33% B0
    Outward COM migration per breast: 8–15% W0, nominal 11% W0

There shall be very obvious forward flattening; outward redistribution; increased separation; chest
contact; broadening of the breast footprint. **The authored standing roundness shall not survive
unchanged in the supine pose.**

## 11. Prone / Torso Horizontal With Breasts Hanging Freely

    Static COM displacement: 28–38% B0, nominal 33% B0, upper equilibrium ~40% B0
    Root-to-apex length:     +28 to +38%, nominal +33%   HangingLengthScale = 1.33
    Transient settling peak: +40 to +45%                 HangingTransientLengthMax = 1.45
    Width:                   −10 to −17%, nominal −13%   HangingWidthScale = 0.87
    Thickness:               −9 to −16%, nominal −13%    HangingThicknessScale = 0.87

Large distal mass produces pronounced elongation; stronger lower/distal fullness; reduced
root-region fullness; visible narrowing; substantially more pendant geometry than Keira Hagai.

## 12. Sideways Gravity / Side-Lying Orientation

    Overall lateral COM response:           22–32% B0, nominal 27% B0
    Upper/opposite breast medial migration: 16–26% W0, nominal 21% W0
    Gravity-side lateral flattening:        −22 to −35%, nominal −28%

Considerably more cross-chest migration, local compression, breast-to-breast contact and sideward
volume redistribution than Keira. External bed/floor compression remains a separate collision
phenomenon.

## 13. Intermediate Gravity Orientations

The equilibrium shall vary continuously with gravity direction. At a 45° forward lean, Maia shall
already demonstrate obvious forward/downward migration; lower-pole elongation; distal fullness; mild
narrowing; greater separation from the upper chest.

More pronounced than Keira because of the larger breast mass and distal volume. The final
deformation shall still arise dynamically rather than through an instantaneous pose switch.

## 14. Jump Take-Off

    COM lag:                ordinary 22–32% B0, strong 32–40% B0, upper transient ~42% B0
    Apex displacement:      ordinary 28–40% B0, strong 40–50% B0
    Directional elongation: ordinary +10 to +18%, strong +18 to +23%, upper transient ~26%
    Perpendicular contraction: ≈ −5 to −11%

**The effect should visually communicate weight, not simply increased jiggle amplitude.**

## 15. Jump Apex and Falling Transition

Maia retains substantially more soft-body momentum through the jump apex. Because primary frequency
is lower, the breast response remains more visibly out of phase with torso motion than for Keira.
The solver shall preserve this phase history.

## 16. Landing / Abrupt Vertical Deceleration

    Strong landing COM:      32–45% B0
    Very hard landing COM:   45–50% B0
    Strong landing apex:     45–58% B0
    Exceptional apex:        58–65% B0
    Recommended ceiling:     MaxApexDisplacement = 0.65 B0

For B0 ≈ 150 mm: 0.60 B0 ≈ 90 mm, 0.65 B0 ≈ 98 mm.

    Directional elongation: ordinary +14 to +20%, strong +20 to +26%, exceptional ~+30%

30% is a hard transient ceiling and shall not be routinely reached.

## 17. Horizontal Acceleration and Braking

    COM lag:                moderate 15–23% B0, strong 23–32% B0, extreme transient ~35% B0
    Apex displacement:      strong 30–42% B0, extreme transient ~48% B0
    Directional elongation: moderate +8 to +15%, strong +15 to +20%, extreme ~23%

Maia shall retain noticeably more lag after torso acceleration ends than Keira.

## 18. Strong Yaw Rotation

    COM displacement:  moderate 15–23% B0, strong 23–31% B0, upper transient ~35% B0
    Apex displacement: strong 30–42% B0, exceptional 45–50% B0
    Directional stretch: normal +7 to +13%, strong +13 to +19%, upper transient ~22%
    Perpendicular compression: −5 to −11%

During aggressive yaw, breast-to-breast contact may become important on the inward-moving side.

## 19. Strong Pitch Rotation

A strong pitch action can generate **40–50% B0 apex displacement without requiring equivalent
stretch.**

## 20. Roll / Lateral Torso Motion

    COM:   20–30% B0
    Apex:  28–40% B0, strong transient ~45% B0
    Local stretch: +8 to +17%

Pronounced asymmetry once one breast contacts the thorax, one contacts the other, and gravity begins
redistributing the volume.

## 21. Combined Translation and Rotation

    D_combined = D_max · tanh( |D_linear + D_angular| / D_max )

Even more important for Maia because individually plausible responses can otherwise add into an
implausibly enormous total displacement. A jump plus a spin shall produce a combined physical
response, **not the arithmetic sum of two independent maximum amplitudes.**

## 22. Dynamic Soft Limits

    Breast COM:    normal ≤45% B0, hard transient ≤50% B0
    Distal/apex:   normal high-amplitude ≤58–60% B0, exceptional ≤65% B0
    Solver recovery margin: ~70% B0 — never an intended visual target
    Local tissue elongation: common 8–18%, large 18–25%, exceptional 25–30%
    Absolute stretch clamp: 30%

A 60% apex excursion does not mean 60% tissue extension.

## 23. Primary Dynamic Model

Same architecture: `M·ẍ + C·ẋ + K·x = M·a_drive + F_collision`. Maia changes the values of M, K, C,
constraints and limits, **but not the fundamental solver design.**

**Maia Acheron shall not be implemented by multiplying Keira Hagai's jiggle amplitude by two.**

## 24. Primary Natural Frequencies

    Vertical    = 1.85 Hz    (range 1.7–2.0 Hz)
    Front/Back  = 2.00 Hz    (range 1.9–2.2 Hz)
    Lateral     = 2.10 Hz    (range 2.0–2.3 Hz)

The visibly slower response is one of the main cues distinguishing Maia's larger mass.

## 25. Damping

Recommended **ζ = 0.33**, useful range 0.30–0.37. The slightly lower damping ratio and substantially
lower natural frequency allow greater phase lag, larger first rebound, longer settling.

## 26. Rebound Magnitude

For ζ = 0.33 the overshoot ratio is ≈ **0.33**, roughly one third.

    Primary excursion       90 mm
    First opposite rebound  ~30 mm
    Second return           ~10 mm
    Third opposite rebound  ~3 mm

## 27. Settling Time

Dominant motion 0.4–0.8 s; secondary movement 0.8–1.5 s; mostly settled 1.3–1.8 s; essentially
stationary 1.6–2.2 s. Noticeably longer than Keira, but decaying continuously rather than
oscillating indefinitely.

## 28. Effective Spring Parameters

With m = 1.05 kg and f = 1.85 Hz: `k ≈ 142 N/m`. With ζ = 0.33: `c ≈ 8.1 N·s/m`.

Although absolute k is higher than Keira, Maia has much greater mass; its stiffness-to-mass ratio is
lower, producing the intended slower oscillation.

## 29. Anisotropy

    Vertical    1.00
    Front/back  0.95
    Lateral     0.88
    Torsional   0.80

Somewhat freer laterally and torsionally than Keira because the much larger distal volume permits
stronger redistribution.

## 30. Root Attachment

Strongly attached rear volume 22–30%, nominal **26%**.

    Deep root           90–100%
    Rear/intermediate   55–85%
    Mid-volume          25–55%
    Distal volume        5–25%
    Apex                minimal direct anchoring

The lower strong-root fraction relative to Keira reflects the much larger amount of tissue extending
beyond the attachment region. The anatomical root itself is not weaker; it represents a smaller
fraction of the total breast volume.

## 31. Root-to-Apex Shape Gradient

    w(r) = r^1.5…1.9

Compared with Keira, Maia permits slightly more mid-volume participation. This supports large distal
displacement; broad redistribution; stable root; **absence of hinge-like behavior.**

## 32. Left/Right Independence

Separate state per breast: translation, velocity, angular state, local deformation, collision
history. Variation: mass ±2–4%, stiffness ±3–5%, damping ±3–5%.

Especially important for Maia because the two breasts may contact each other during strong turns or
impacts and thereafter acquire different phases.

## 33. Breast-Breast Interaction

Medial surfaces must support collision, compression, sliding, displacement redirection, temporary
coupling. Recommended restitution 0.00–0.10, nominal **0.04**.

The solver shall prevent interpenetration, explosive separation, rigid-body sphere collision. Large
inward momentum should primarily generate compression and redirection.

## 34. Torso and External Collision

Chest restitution 0.00–0.04, nominal **0.02**. Because of the greater mass, torso contact should
produce substantial flattening, lateral redistribution and damping — **not a strong elastic bounce
directly away from the ribcage.**

## 35. Garment Coupling

    Support contribution  ≈ 0
    Compression           ≈ 0
    Motion damping        ≈ 0
    Independent cloth lag ≈ 0

The covering follows the simulated tissue surface. It does not reduce the amplitudes specified here.

## 36. Secondary Local Soft-Tissue Jiggle

    Normal amplitude: 3–7% of local thickness
    Strong impulse:   7–9%
    Hard ceiling:     ~10%
    Frequency:        3.5–5.5 Hz, nominal 4.4 Hz
    Damping:          0.50–0.70, nominal 0.60

Clearly subordinate to the slower primary global motion.

## 37. Numerical Stability, Resets and Discontinuities

Same numerical requirements; Maia benefits particularly from substepping because of its greater
excursion and more frequent collision. ≥120 Hz effective; 2 substeps minimum at 60 FPS; 3–4 adaptive
substeps during hard landing, breast-breast collision, chest collision, combined rotation and impact.

State reset/rebase for teleports, cutscene snaps, animation discontinuities, level streaming
repositioning, implausible root transform deltas. Soft saturation rather than abrupt positional
clipping whenever possible.

## 38. Recommended Complete Preset — Maia Acheron

```
# ==================================================
# MAIA ACHERON — UNSUPPORTED VERY LARGE BUST
# ==================================================

# MORPHOLOGY
NominalVolumePerBreast       = 1.10 L
MassPerBreast                = 1.05 kg
NeutralProjection            = 1.00
NeutralWidth                 = 1.00
NeutralHeight                = 1.00
NeutralCOMOffset             = 0.00
AdditionalStandingSag        = 0.00

# PRIMARY DYNAMICS
GlobalFrequencyVertical      = 1.85 Hz
GlobalFrequencyAP            = 2.00 Hz
GlobalFrequencyLateral       = 2.10 Hz
GlobalDampingRatio           = 0.33
FirstBounceRatio             = 0.33

# SUPINE EQUILIBRIUM
SupineProjectionScale        = 0.57
SupineWidthScale             = 1.40
SupineHeightScale            = 1.18
SupineCOMDepth               = 0.33 B0
SupineCOMLateral             = 0.11 W0

# HANGING EQUILIBRIUM
HangingLengthScale           = 1.33
HangingWidthScale            = 0.87
HangingThicknessScale        = 0.87
HangingCOMDisplacement       = 0.33 B0
HangingTransientLengthMax    = 1.45

# SIDE-GRAVITY EQUILIBRIUM
SideGravityCOM               = 0.27 B0
UpperBreastMedialShift       = 0.21 W0
LowerBreastCompression       = 0.28

# DYNAMIC RESPONSE
StrongJumpCOMLag             = 0.32–0.40 B0
StrongJumpApexLag            = 0.40–0.50 B0
StrongLandingCOM             = 0.32–0.45 B0
HardLandingCOM               = 0.50 B0
StrongLandingApex            = 0.45–0.58 B0
HardLandingApex              = 0.65 B0
StrongLinearAccelCOM         = 0.23–0.32 B0
HardLinearAccelCOM           = 0.35 B0
StrongYawCOM                 = 0.23–0.31 B0
HardYawCOM                   = 0.35 B0
StrongYawApex                = 0.30–0.42 B0
HardYawApex                  = 0.50 B0

# SOFT LIMITS
NormalMaxCOMDisplacement     = 0.45 B0
HardMaxCOMDisplacement       = 0.50 B0
NormalMaxApexDisplacement    = 0.60 B0
HardMaxApexDisplacement      = 0.65 B0
NormalDynamicStretch         = 0.18
StrongDynamicStretch         = 0.25
AbsoluteStretchClamp         = 0.30
NormalVolumeRange            = 0.98–1.01
HardVolumeRange              = 0.96–1.02

# ANISOTROPY
VerticalCompliance           = 1.00
APCompliance                 = 0.95
LateralCompliance            = 0.88
TorsionalCompliance          = 0.80

# ATTACHMENT
StrongRootFraction           = 0.26
RootAnchor                   = 0.90–1.00
RearIntermediateAnchor       = 0.55–0.85
MidVolumeAnchor              = 0.25–0.55
DistalAnchor                 = 0.05–0.25
RootDeformationExponent      = 1.5–1.9

# COLLISION
BreastBreastRestitution      = 0.04
BreastChestRestitution       = 0.02
EnableBreastBreastCollision  = true
EnableChestCollision         = true
EnableExternalCollision      = true

# GARMENT
GarmentSupport               = 0.00
GarmentCompression           = 0.00
GarmentDynamicDamping        = 0.00

# SECONDARY TISSUE MODE
SecondaryJiggleAmplitude     = 0.03–0.07
SecondaryJiggleHardMax       = 0.10
SecondaryFrequency           = 4.4 Hz
SecondaryDampingRatio        = 0.60

# EFFECTIVE PRIMARY VERTICAL SPRING
VerticalEffectiveMass        = 1.05 kg
VerticalEffectiveStiffness   ≈ 142 N/m
VerticalEffectiveDamping     ≈ 8.1 N·s/m

# SOLVER
RecommendedEffectiveRate     >= 120 Hz
MinimumSubstepsAt60FPS       = 2
HardImpactSubsteps           = 3–4
```

## 39. Expected Visual Signature — Maia Acheron

Maia Acheron shall read as **very large, heavy, soft, substantially inertial and visibly affected by
body orientation.**

Compared with Keira Hagai, the same movement shall generate more COM lag; more apex excursion;
lower-frequency bounce; larger gravity-induced deformation; considerably greater supine spreading;
greater hanging elongation; stronger lateral movement; stronger breast-to-breast interaction;
greater torso contact; more visible shape redistribution; longer settling.

**The difference should communicate mass and volume, not merely a larger jiggle coefficient.**

When Maia Acheron becomes upright and completely motionless, Projection = 100%, Width = 100%,
Height = 100%, COM = P0, and the original authored standing model is restored exactly.

---

# Cross-Character Calibration Reference

| Parameter | Keira Hagai | Maia Acheron |
|---|---|---|
| Nominal volume / breast | 525 mL | 1,100 mL |
| Nominal mass / breast | 0.50 kg | 1.05 kg |
| B/A volume ratio | 1.00× | 2.10× |
| Extra standing sag | 0% | 0% |
| Standing mesh | 100% reference | 100% reference |
| Vertical frequency | 2.30 Hz | 1.85 Hz |
| AP frequency | 2.50 Hz | 2.00 Hz |
| Lateral frequency | 2.65 Hz | 2.10 Hz |
| Damping ratio | 0.35 | 0.33 |
| First rebound | 31% | 33% |
| Supine projection | 70% | 57% |
| Supine width | 123% | 140% |
| Supine height | 109% | 118% |
| Hanging length | 123% | 133% |
| Hanging transient max | 130% | 145% |
| Hanging width | 90% | 87% |
| Normal max COM | 35% B0 | 45% B0 |
| Hard max COM | 40% B0 | 50% B0 |
| Normal max apex | 42% B0 | 60% B0 |
| Hard max apex | 50% B0 | 65% B0 |
| Strong stretch | 21% | 25% |
| Absolute stretch | 25% | 30% |
| Strong root fraction | 30% | 26% |
| Secondary frequency | 5.2 Hz | 4.4 Hz |
| Secondary normal amplitude | 2–5% | 3–7% |
| Typical settling | 1.0–1.5 s | 1.3–1.8 s |

The two specs use exactly the same model, definitions, section structure and reference convention.
The second character is not just Keira Hagai with an amplitude multiplier: her roughly 2.1×
mass/volume feeds coherently into lower frequency, larger displacement, greater orientation
deformation, stronger collision interaction and longer settling.

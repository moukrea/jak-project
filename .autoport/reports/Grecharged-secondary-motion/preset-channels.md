| cle | Keira | Maia | differe | etat du canal | site |
|---|---|---|---|---|---|
| `APCompliance` | 0.9 | 0.95 | oui | **CONSTANTE MOTEUR** | PHYS-MOB-AP = 0.9 (preset 0.9) — TAUTOLOGIQUE |
| `AbsoluteStretchClamp` | 0.25 | 0.3 | oui | **CONSTANTE MOTEUR** | PHYS-DYN-MAX = 0.25 (preset 0.25) — TAUTOLOGIQUE |
| `AdditionalStandingSag` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `BreastBreastRestitution` | 0.06 | 0.04 | oui | **CONSTANTE MOTEUR** | PHYS-RST-BB = 0.06 (preset 0.06) — TAUTOLOGIQUE |
| `BreastChestRestitution` | 0.02 | 0.02 | non | **CONSTANTE MOTEUR** | PHYS-RST-CH = 0.02 (preset 0.02) — TAUTOLOGIQUE |
| `DistalAnchorHi` | 0.3 | 0.25 | oui | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `DistalAnchorLo` | 0.05 | 0.05 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `EnableBreastBreastCollision` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `EnableChestCollision` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `EnableExternalCollision` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `FirstBounceRatio` | 0.31 | 0.33 | oui | **CANAL ABSENT** | aucun lecteur |
| `GarmentCompression` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `GarmentDynamicDamping` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `GarmentSupport` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `GlobalDampingRatio` | 0.35 | 0.33 | oui | **CANAL FICHIER (indirect)** | damping= sur la ligne `chain` |
| `GlobalFrequencyAP` | 2.5 | 2 | oui | **CANAL ABSENT** | aucun lecteur |
| `GlobalFrequencyLateral` | 2.65 | 2.1 | oui | **CANAL ABSENT** | aucun lecteur |
| `GlobalFrequencyVertical` | 2.3 | 1.85 | oui | **CANAL FICHIER (indirect)** | stiffness / sqrt(mass) sur la ligne `chain` — f = 2.300 Hz mesure |
| `HangingCOMDisplacement` | 0.24 | 0.33 | oui | **CANAL ABSENT** | aucun lecteur |
| `HangingLengthScale` | 1.23 | 1.33 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `HangingThicknessScale` | 0.91 | 0.87 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `HangingTransientLengthMax` | 1.3 | 1.45 | oui | **CANAL ABSENT** | aucun lecteur |
| `HangingWidthScale` | 0.9 | 0.87 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `HardImpactSubstepsHi` | 4 | 4 | non | **CANAL ABSENT** | aucun lecteur |
| `HardImpactSubstepsLo` | 3 | 3 | non | **CANAL ABSENT** | aucun lecteur |
| `HardLandingApex` | 0.5 | 0.65 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardLandingCOM` | 0.4 | 0.5 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardLinearAccelCOM` | 0.3 | 0.35 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardMaxApexDisplacement` | 0.5 | 0.65 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardMaxCOMDisplacement` | 0.4 | 0.5 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardVolumeRangeHi` | 1.02 | 1.02 | non | **CANAL ABSENT** | aucun lecteur |
| `HardVolumeRangeLo` | 0.96 | 0.96 | non | **CANAL ABSENT** | aucun lecteur |
| `HardYawApex` | 0.35 | 0.5 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardYawCOM` | 0.28 | 0.35 | oui | **CANAL ABSENT** | aucun lecteur |
| `LateralCompliance` | 0.82 | 0.88 | oui | **CONSTANTE MOTEUR** | PHYS-MOB-LAT = 0.82 (preset 0.82) — TAUTOLOGIQUE |
| `LowerBreastCompression` | 0.2 | 0.28 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `MassPerBreast` | 0.5 | 1.05 | oui | **CANAL FICHIER (indirect)** | mass= sur la ligne `chain` — JAUGE : le solveur ne lit la masse que dans stiffness/sqrt(mass), donc sa valeur absolue est inerte |
| `MidVolumeAnchorHi` | 0.55 | 0.55 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `MidVolumeAnchorLo` | 0.25 | 0.25 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `MinimumSubstepsAt60FPS` | 2 | 2 | non | **CANAL ABSENT** | aucun lecteur |
| `NeutralCOMOffset` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `NeutralHeight` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `NeutralProjection` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `NeutralWidth` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `NominalVolumePerBreast` | 0.525 | 1.1 | oui | **CANAL ABSENT** | aucun lecteur |
| `NormalDynamicStretch` | 0.15 | 0.18 | oui | **CANAL ABSENT** | aucun lecteur |
| `NormalMaxApexDisplacement` | 0.42 | 0.6 | oui | **CONSTANTE MOTEUR** | litteral (* 0.42 b0e) dans le moteur (preset 0.42) — TAUTOLOGIQUE |
| `NormalMaxCOMDisplacement` | 0.35 | 0.45 | oui | **CONSTANTE MOTEUR** | litteral (* 0.35 b0e) dans le moteur (preset 0.35) — TAUTOLOGIQUE |
| `NormalVolumeRangeHi` | 1.01 | 1.01 | non | **CANAL ABSENT** | aucun lecteur |
| `NormalVolumeRangeLo` | 0.98 | 0.98 | non | **CANAL ABSENT** | aucun lecteur |
| `RearIntermediateAnchorHi` | 0.85 | 0.85 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `RearIntermediateAnchorLo` | 0.55 | 0.55 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `RecommendedEffectiveRate` | 120 | 120 | non | **CANAL ABSENT** | aucun lecteur |
| `RootAnchorHi` | 1 | 1 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30, mesure sur le mesh livre |
| `RootAnchorLo` | 0.9 | 0.9 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30, mesure sur le mesh livre |
| `RootDeformationExponentHi` | 2 | 1.9 | oui | **HORS RUNTIME (asset)** | gradient racine->apex de la 31, cuit dans les poids |
| `RootDeformationExponentLo` | 1.6 | 1.5 | oui | **HORS RUNTIME (asset)** | gradient racine->apex de la 31, cuit dans les poids |
| `SecondaryDampingRatio` | 0.65 | 0.6 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `SecondaryFrequency` | 5.2 | 4.4 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `SecondaryJiggleAmplitudeHi` | 0.05 | 0.07 | oui | **CANAL ABSENT** | aucun lecteur |
| `SecondaryJiggleAmplitudeLo` | 0.02 | 0.03 | oui | **CANAL ABSENT** | aucun lecteur |
| `SecondaryJiggleHardMax` | 0.07 | 0.1 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `SideGravityCOM` | 0.19 | 0.27 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongDynamicStretch` | 0.21 | 0.25 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongJumpApexLagHi` | 0.38 | 0.5 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongJumpApexLagLo` | 0.3 | 0.4 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongJumpCOMLagHi` | 0.32 | 0.4 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongJumpCOMLagLo` | 0.25 | 0.32 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongLandingApexHi` | 0.42 | 0.58 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongLandingApexLo` | 0.3 | 0.45 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongLandingCOMHi` | 0.35 | 0.45 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongLandingCOMLo` | 0.25 | 0.32 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongLinearAccelCOMHi` | 0.27 | 0.32 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongLinearAccelCOMLo` | 0.18 | 0.23 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongRootFraction` | 0.3 | 0.26 | oui | **HORS RUNTIME (asset)** | barre de repesage : >= 30 % des sommets de la chaine doivent avoir le nouvel os pour joint MAJORITAIRE (DIRECTIVES 2026-08-18 08:55). Verifiee a la cuisson, pas a l'execution. |
| `StrongYawApexHi` | 0.3 | 0.42 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongYawApexLo` | 0.2 | 0.3 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongYawCOMHi` | 0.24 | 0.31 | oui | **CANAL ABSENT** | aucun lecteur |
| `StrongYawCOMLo` | 0.17 | 0.23 | oui | **CANAL ABSENT** | aucun lecteur |
| `SupineCOMDepth` | 0.23 | 0.33 | oui | **CANAL ABSENT** | aucun lecteur |
| `SupineCOMLateral` | 0.07 | 0.11 | oui | **CANAL ABSENT** | aucun lecteur |
| `SupineHeightScale` | 1.09 | 1.18 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `SupineProjectionScale` | 0.7 | 0.57 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `SupineWidthScale` | 1.23 | 1.4 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `TorsionalCompliance` | 0.72 | 0.8 | oui | **CONSTANTE MOTEUR** | PHYS-MOB-TOR = 0.72 (preset 0.72) — TAUTOLOGIQUE |
| `UpperBreastMedialShift` | 0.14 | 0.21 | oui | **CANAL ABSENT** | aucun lecteur |
| `VerticalCompliance` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `VerticalEffectiveDamping` | 5.1 | 8.1 | oui | **CANAL ABSENT** | aucun lecteur |
| `VerticalEffectiveMass` | 0.5 | 1.05 | oui | **CANAL ABSENT** | aucun lecteur |
| `VerticalEffectiveStiffness` | 104 | 142 | oui | **CANAL ABSENT** | aucun lecteur |

CANAL FICHIER               10 / 90
CANAL FICHIER (indirect)     3 / 90
CONSTANTE MOTEUR             8 / 90
HORS RUNTIME (asset)        11 / 90
CANAL ABSENT                58 / 90
dont TAUTOLOGIQUES           8
cles dont la valeur DIFFERE entre les deux presets : 62
   dont CANAL FICHIER             10
   dont CANAL FICHIER (indirect)   3
   dont CONSTANTE MOTEUR           7
   dont HORS RUNTIME (asset)       4
   dont CANAL ABSENT              38

CANAL PARTIEL — `SupineProjectionScale` est LU par le tenseur de deformation et
  reste ECRIT EN DUR dans `phys-vol-floor` sous sa forme complementaire :
  PHYS-FLESH-YIELD = 0.30, soit 1 - 0.7. Tourner le bouton deplace le tenseur et PAS ce plancher.
  Premier point du cycle suivant : `phys-vol-floor` ne recoit pas `sc`, donc le
  cabler demande un parametre de plus et la mise a jour de ses appelants.

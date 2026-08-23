PROVENANCE — ce tableau decrit CES fichiers-la, et l'empreinte le prouve :
  jak-hd-physics.gc 7dee7efee593
  phys-room.gc f9b12924dbfa
  kmachine.cpp 7be159f2865a
  physics_chains.txt 688b93eaa48b
  physics_room_table.py 4b5df9522738
Regenere par : python3 .autoport/preset_channel_audit.py > .../preset-channels.md

BALAYAGE PAR VALEUR (cycle 114, etendu a l'INSTRUMENT au cycle 115) — moteur, salle ET
les constantes de module de `physics_room_table.py` : tout litteral egal a une valeur du
preset. Une coincidence doit etre JUSTIFIEE pour etre ignoree, elle n'est plus ignoree
par oubli. Entrees d'allowlist : 50. Sites non tries : 0.
  ANGLE MORT DECLARE : les valeurs 0, 1, 2, 3, 4, 120 sont FILTREES (elles sont partout et sans portee),
  donc une cle qui vaut 1, 2, 3, 4 ou 120 ne peut PAS etre trouvee par ce balayage. Les
  trois qui etaient dans ce cas (VerticalCompliance 1, MinimumSubstepsAt60FPS 2,
  HardImpactSubstepsHi 4) ont ete trouvees A LA LECTURE et cablees au cycle 114 ; les
  suivantes ne le seront pas par cet outil. Le balayage reduit l'angle mort, il ne le
  supprime pas, et le dire ici vaut mieux que laisser croire a une preuve d'exhaustivite.

CONSTANTES AJUSTEES SUR UN RAPPORT DE DEUX CLES — pas un litteral, donc invisibles au
balayage, et publiees ici pour qu'elles ne disparaissent pas :
  PHYS-SEC-K     = 0.05    CONSTANTE MOTEUR SANS CLE (cycle 115). Gain d excitation du mode secondaire (36). Ce n est le rapport d AUCUNE paire de cles : NOTE-169 decrit un BALAYAGE (2.5 -> 0.05) mene jusqu a ce que la sortie tombe dans la bande — `never-fit-a-parameter-to-the-instrument` a l etat pur. COINCIDENCE NOMMEE POUR QU ELLE NE SOIT PAS « DECOUVERTE » COMME UN CABLAGE EVIDENT : SecondaryJiggleAmplitudeHi vaut AUSSI 0.05 chez Keira, et la cabler serait bit-identique ici et rendrait 0.07 chez Maia — un canal qui AURAIT L AIR de tirer sur une egalite fortuite, les natures ne correspondant pas (un gain sur une vitesse normalisee contre une amplitude en fraction d epaisseur). La paire qui DEVRAIT la gouverner est SecondaryJiggleAmplitudeLo/Hi, par NORMALISATION et non par affectation ; le gain de l oscillateur qui la rendrait derivable est NON ETABLI. Voir [NOTE-504].

| cle | Keira | Maia | differe | etat du canal | site |
|---|---|---|---|---|---|
| `APCompliance` | 0.9 | 0.95 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `AbsoluteStretchClamp` | 0.25 | 0.3 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `AdditionalStandingSag` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `BreastBreastRestitution` | 0.06 | 0.04 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `BreastChestRestitution` | 0.02 | 0.02 | non | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `DistalAnchorHi` | 0.3 | 0.25 | oui | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `DistalAnchorLo` | 0.05 | 0.05 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `EnableBreastBreastCollision` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `EnableChestCollision` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `EnableExternalCollision` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `FirstBounceRatio` | 0.31 | 0.33 | oui | **CANAL ABSENT** | aucun lecteur |
| `GarmentCompression` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `GarmentDynamicDamping` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `GarmentSupport` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `GlobalDampingRatio` | 0.35 | 0.33 | oui | **CANAL FICHIER (indirect)** | damping= sur la ligne `chain` (SPEC 25) — PROUVE PAR PERTURBATION : x1.5 sur la cle change 2 ligne(s) `chain` (p.ex. chestL) |
| `GlobalFrequencyAP` | 2.5 | 2 | oui | **CANAL ABSENT** | aucun lecteur |
| `GlobalFrequencyLateral` | 2.65 | 2.1 | oui | **CANAL ABSENT** | aucun lecteur |
| `GlobalFrequencyVertical` | 2.3 | 1.85 | oui | **CANAL FICHIER (indirect)** | stiffness= sur la ligne `chain` (SPEC 24 : f = stiffness/sqrt(mass)) — PROUVE PAR PERTURBATION : x1.5 sur la cle change 2 ligne(s) `chain` (p.ex. chestL) |
| `HangingCOMDisplacement` | 0.24 | 0.33 | oui | **CANAL ABSENT** | aucun lecteur |
| `HangingLengthScale` | 1.23 | 1.33 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `HangingThicknessScale` | 0.91 | 0.87 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `HangingTransientLengthMax` | 1.3 | 1.45 | oui | **CANAL ABSENT** | aucun lecteur |
| `HangingWidthScale` | 0.9 | 0.87 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `HardImpactSubstepsHi` | 4 | 4 | non | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `HardImpactSubstepsLo` | 3 | 3 | non | **CANAL ABSENT** | aucun lecteur |
| `HardLandingApex` | 0.5 | 0.65 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardLandingCOM` | 0.4 | 0.5 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardLinearAccelCOM` | 0.3 | 0.35 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardMaxApexDisplacement` | 0.5 | 0.65 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `HardMaxCOMDisplacement` | 0.4 | 0.5 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `HardVolumeRangeHi` | 1.02 | 1.02 | non | **CANAL ABSENT** | aucun lecteur |
| `HardVolumeRangeLo` | 0.96 | 0.96 | non | **CANAL ABSENT** | aucun lecteur |
| `HardYawApex` | 0.35 | 0.5 | oui | **CANAL ABSENT** | aucun lecteur |
| `HardYawCOM` | 0.28 | 0.35 | oui | **CANAL ABSENT** | aucun lecteur |
| `LateralCompliance` | 0.82 | 0.88 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `LowerBreastCompression` | 0.2 | 0.28 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `MassPerBreast` | 0.5 | 1.05 | oui | **JAUGE (inerte par construction)** | mass= sur la ligne `chain` — JAUGE : le solveur ne lit la masse que dans stiffness/sqrt(mass), sa valeur absolue est inerte (DIRECTIVES 2026-08-19 20:25). Declaree, jamais comptee comme un canal. |
| `MidVolumeAnchorHi` | 0.55 | 0.55 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `MidVolumeAnchorLo` | 0.25 | 0.25 | non | **HORS RUNTIME (asset)** | profil d'ancrage de la 30 |
| `MinimumSubstepsAt60FPS` | 2 | 2 | non | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `NeutralCOMOffset` | 0 | 0 | non | **CANAL ABSENT** | aucun lecteur |
| `NeutralHeight` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `NeutralProjection` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `NeutralWidth` | 1 | 1 | non | **CANAL ABSENT** | aucun lecteur |
| `NominalVolumePerBreast` | 0.525 | 1.1 | oui | **CANAL ABSENT** | aucun lecteur |
| `NormalDynamicStretch` | 0.15 | 0.18 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `NormalMaxApexDisplacement` | 0.42 | 0.6 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `NormalMaxCOMDisplacement` | 0.35 | 0.45 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
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
| `TorsionalCompliance` | 0.72 | 0.8 | oui | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `UpperBreastMedialShift` | 0.14 | 0.21 | oui | **CANAL ABSENT** | aucun lecteur |
| `VerticalCompliance` | 1 | 1 | non | **CANAL FICHIER** | lu par le moteur (kPhysPresetKeys), pose par preset_apply.py |
| `VerticalEffectiveDamping` | 5.1 | 8.1 | oui | **CANAL ABSENT** | aucun lecteur |
| `VerticalEffectiveMass` | 0.5 | 1.05 | oui | **CANAL ABSENT** | aucun lecteur |
| `VerticalEffectiveStiffness` | 104 | 142 | oui | **CANAL ABSENT** | aucun lecteur |

CANAL FICHIER                     24 / 90
CANAL FICHIER (indirect)           2 / 90
CONSTANTE MOTEUR                   0 / 90
HORS RUNTIME (asset)              11 / 90
JAUGE (inerte par construction)    1 / 90
CANAL ABSENT                      52 / 90
dont TAUTOLOGIQUES           0
cles dont la valeur DIFFERE entre les deux presets : 62
   dont CANAL FICHIER                   20
   dont CANAL FICHIER (indirect)         2
   dont CONSTANTE MOTEUR                 0
   dont HORS RUNTIME (asset)             4
   dont JAUGE (inerte par construction)   1
   dont CANAL ABSENT                    35

CANAL PARTIEL — RESOLU. `PHYS-FLESH-YIELD` n'existe plus dans le moteur : `phys-vol-floor` recoit
  `sc` et lit la cle DERIVEE `DerivedSupineProjectionYield` (= 1 - SupineProjection-
  Scale, calculee en decimal exact par preset_apply.py pour rester identique au
  litteral qu'elle remplace). La seconde copie de la cle 0 est donc branchee elle
  aussi : le bouton n'est plus a moitie connecte.

CLES DERIVEES CABLEES (3) — pas dans le document, deduites par soustraction EXACTE :
  DerivedApexSoftBand              0.08
  DerivedCOMSoftBand               0.05
  DerivedSupineProjectionYield     0.3
  Elles existent parce que le moteur consomme la BANDE (genou -> plafond) et non les
  deux bornes separement : sans elles il resterait un litteral en dur a cote d'un
  canal, c'est-a-dire un bouton a moitie branche.

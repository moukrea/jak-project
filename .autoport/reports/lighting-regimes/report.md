# lighting-regimes — essai 3 — DIRECTIVES v61d5175764
Verdict : le sol noir de village3 est corrigé (107 % de sa luminosité d'origine au lieu de 7 %), et
l'ombre enlève désormais une part nette du sol ensoleillé ; la porte tient (0 image fautive).
## Cause (mesurée, pas supposée)
Sonde sol neuve, AVANT correctif (notes/probe-village3-before.log) : village3 `on_off=0,070`, 95 % du sol
sous 0,5, et 95 % du sol avec une normale d'ombrage OPPOSÉE à la face (enroulement pile ou face). Une
normale vers le bas lisait l'ambiante du DESSOUS du ciel capturé (~0) : noir. Le pont (TIE) avait des
normales justes. Ombre/soleil valait 1,643 : le sol à l'ombre sortait PLUS clair qu'au soleil.
## Ce qui a changé
- `shade.glsl` : la normale d'ombrage est orientée vers la face vue (gN) avant tout calcul.
- Composite : le cuit est séparé en indirect = cuit×(1−f)×forme du ciel (compressée ×0,5, bornée
  [0,6 ; 1,4]) et direct = cuit×f, remplacé selon le poids direct par sa version temps réel (×ombre
  ×1,15). f = ce qui dépasse l'ambiante plate de la table, plafonné par lgt·N·L/(amb+lgt·N·L) (SPEC 5.2,
  ambiante plate de lighting-bake). La marge anti-blanc ne borne plus que ce qui éclaircit.
- `background_common.cpp` : pousse `u_rt_bake_al` (ambiante, lumières projetées sur la clé), publie
  `regime_bake_*`. Directions sans NaN (`rt_safe_dir`). Sonde `floor_probe.{h,cpp}` (x86, armée seulement).
- backlog : proof_env épinglé sur `village3-start` (scène du défaut).
## Preuve (proof.txt, x86, village3-start 12 h, essai lighting-regimes@3, HEAD 57102cdfce)
    FEATURE lighting-regimes armed=1 hits=1993786     crash=0 frames=4071
    regime_sun_override_wrong=0                       (--off : 3294, armed=0 hits=0, frames=4008)
    floor_on_off_x1000_village3=1068                  (avant : 70)
    floor_dark_px_ppm_village3=0  floor_dark_levels=0 (avant : 950503 / 1)
    floor_normal_flipped_ppm_village3=950173          (normales stockées, corrigées à l'ombrage)
    floor_shadow_sun_x1000_village3=568  floor_direct_share_x1000_village3=432  (avant : 1643 / 0)
    floor_px_nan=0  regime_dir_sign_wrong=0  lighting_legacy_sh_readers=0  env_source=1
    regime_bake_amb_x1000=369  regime_bake_lgt_x1000=486  regime_bake_valid=1
Hors preuve, même binaire, village1-out 12 h (notes/probe-village1-after.log) : on_off 1,001,
dark 0,16 %, ombre/soleil 0,577 → part du direct ~42 % (avant : NaN sur la sonde ; ancien composite
= 1/1,15 = 0,87 par construction, 1,0 sur texel clair).
arm64 : `cmake --build build-android --target gk -j` rc=0 (notes/arm64-build.log).
## Ce que l'owner doit regarder
village3 premier écran (sol), village de départ en plein jour (ombres nettement plus visibles),
marais et tube de lave (ne doivent pas avoir bougé).
## Non prouvé
- rendu appareil ; heure de l'owner à village3 (seul 12 h mesuré) ; sols TIE/shrub (sonde tfrag seule).
- rapport ON/OFF calculé dans le fragment (OFF = base), pas sur une course OFF ; bit-identité §7.3 par
  construction seulement. Capture non jointe (pas d'outil sur le bureau, `--no-capture` posté).

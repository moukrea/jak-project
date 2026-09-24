# lighting-regimes — essai 2 — DIRECTIVES v61d5175764
Verdict : les deux défauts signalés avant le test sont corrigés : la lumière vient maintenant du bon
côté, et la nuit n'éclaire plus en plein sur les niveaux où le soleil se voit ; la porte tient (0 image fautive).
## Ce qui a changé
- `background_common.cpp`, boucle kLightGroup : négation `-lg_dir` RETIRÉE (la direction d'un créneau
  pointe déjà vers la lumière) ; vaut aussi pour le bras désarmé et les lumières 1/2.
- `gfx.h:296` : commentaire corrigé (« dirs VERS la lumière »), plus « light-travel ».
- `regime::frame` : le poids direct suit l'élévation de l'astre (rampe −0,05..0,18 de l'ancien code) en
  proportion de sun-fade : village1 (sun-fade 1) s'éteint la nuit comme avant ; lave/marais (sun-fade 0) non.
- Deux relevés neufs : `regime_dir_sign_*` (signe cle·créneau, chaque créneau pondéré, les deux bras) et
  `regime_direct_w_x1000` / `regime_night_*` (valeur réellement poussée dans `u_rt_sun_elev`).
## Preuve (proof.txt, x86, swamp-start, 12 h, essai lighting-regimes@2, HEAD 556f3a94)
    FEATURE lighting-regimes armed=1 hits=1529052      crash=0  frames=3334
    regime_sun_override_wrong=0                        (--off : 2633 sur 2635 images auditées)
    regime_dir_sign_wrong=0  regime_dir_sign_checked=10537
    regime_direct_w_x1000=448  regime_sun_fade_x1000=0 (marais : dôme couvert, pas de soleil visible)
    lighting_legacy_sh_readers=0  lighting_env_sh_readers=3  env_source=1
    --off : FEATURE lighting-regimes armed=0 hits=0, crash=0 frames=3441
Hors preuve (course de 110 s, même binaire, `notes/village1-night-raw.log`), village1-hut à 1 h :
    regime_sun_fade_x1000=1000  regime_sun_up_p1000=42 (astre à −0,958)  regime_direct_w_x1000=0
    regime_night_frames=1647  regime_night_direct_frames=0  regime_dir_sign_wrong=0 / 3323
arm64 : `cmake --build build-android --target gk -j` rc=0 (`notes/arm64-build.log`).
## Ce que l'owner doit regarder
Village1 de jour : les ombres et l'éclairement tombent du côté du soleil. Village1 la nuit : plus de
lumière directe bleue en plein, on revient au niveau sombre d'avant. Marais et tube de lave : lumière
diffuse du ciel (marais) / de la lave (tube), plus de soleil invisible.
## Non prouvé / non fait
- non prouvé : signe des créneaux de lavatube et snow (seuls swamp et village1 ont tourné) ; rendu appareil ;
  bit-identité des deux origines (§7.3) — tenue par construction (`light_dir` n'est lu que sous `u_rt_light_on`), pas mesurée.
- capture non jointe au ticket : la capture de fenêtre du bureau a échoué (FINDINGS).

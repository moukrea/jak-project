# Jak, les PNJ et les ennemis eclaires comme le sol sur lequel ils marchent

## Defaut cite
- 2026-09-03 : « Les acteurs je sais que leur lighting est faked, faut plus que ce soit le cas ! »
- 2026-09-03 : « l'ombre que cast Jak, ennemies et PNJ est tres bizarre, on dirait une version ultra low poly projete sur le sol, c'est pas la bonne methode pour un truc modern »
- 2026-09-05 : « Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. merc2.vert eclaire PAR SOMMET et merc2.frag ne fait que vtx_color*T0*2 : ni normale par pixel, ni ombre recue, ni AO. Et l'ombre projetee est un shadow-geo de 115 sommets extrude en stencil. SPEC 3.5.

## Livrable
merc, generic et emerc passent par shade() : memes astres, memes ombres, memes locales, meme environnement, meme AO. L'indirect vient des sondes, light-index reste honore comme surcharge artistique. SPEC 4.13. PREUVE : `FEATURE lighting-actors armed=1 hits=<pixels merc ayant lu la carte d'ombre>` + la ligne `merc_legacy_light_draws=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-actors"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`merc_legacy_light_draws == 0` dans `reports/lighting-actors/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-actors device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Jak et les PNJ a Sandover, puis dans une hutte, puis la nuit sous un lampadaire.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. Le reciblage des modeles HD n'est pas touche.

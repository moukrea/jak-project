> LIS D'ABORD `prompts/item-lighting-flipped-faces-everywhere-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Aucune surface a l'envers ne tombe au noir, dans aucun niveau ni aucune famille de rendu (decor et personnages)

## Defaut cite
- 2026-09-24 : « Et retourner dans les assets directement histoire qu'on ait… »

## Cause connue
Demande de l'owner le 25/09 (ticket dedie). lighting-regimes a corrige a village3 un sol NOIR : des faces dont la normale pointait a l'envers (enroulement des strips tfrag = pile ou face, voir memoire feedback_tfrag_strip_winding_is_not_an_orientation). Correctif : dans shade() de game/graphics/opengl_renderer/shaders/shade.glsl, la normale est retournee vers la face vue (g_shade_flip, commit 57102cdfce). shade() est inclus par tfrag3, etie_base, tie_wind, shrub, grass, ocean_common : en principe tout le decor. MAIS rien ne prouve que c'est regle PARTOUT : la sonde sol (floor_probe.cpp, `floor_normal_flipped_ppm_<niveau>`) n'a tourne que sur quelques niveaux, et les personnages (merc) ne pas […suite dans le contrat]

## Livrable
1. Recenser, pour CHAQUE niveau du jeu et chaque famille (tfrag, TIE, TIE au vent, shrub, herbe, ocean, merc), la part de pixels dont la normale pointe a l'envers ET qui tombent sous un seuil de noir anormal (comparaison eclairage recharge ON / OFF, meme image).
2. Corriger toute famille ou niveau qui en a encore (merc compris si concerne).
3. `flipped_faces_dark` = nombre de couples (niveau, famille) en defaut ; doit valoir 0. Publier le tableau et le nombre de couples mesures (un couple non mesure = defaut).
4. Devient ensuite un ACQUIS (acquis/flipped-faces.sh). Preuve programmatique seulement, pas de capture.
5. COUT (question de l'owner, 25/09 : « Le correctif actuel est un shader qui f […suite dans le contrat]

## Preuve exigee
`flipped_faces_dark == 0` dans `reports/lighting-flipped-faces-everywhere/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-flipped-faces-everywhere x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

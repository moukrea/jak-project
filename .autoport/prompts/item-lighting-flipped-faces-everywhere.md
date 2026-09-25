> LIS D'ABORD `prompts/item-lighting-flipped-faces-everywhere-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Aucune surface a l'envers ne tombe au noir, dans aucun niveau ni aucune famille de rendu (decor et personnages)

## Defaut cite
- 2026-09-25 : « Pourquoi le moteur devrait porte le truc des fliped faces de… »

## Cause connue
Demande de l'owner le 25/09 (ticket dedie). lighting-regimes a corrige a village3 un sol NOIR : des faces dont la normale pointait a l'envers (enroulement des strips tfrag = pile ou face, voir memoire feedback_tfrag_strip_winding_is_not_an_orientation). Correctif : dans shade() de game/graphics/opengl_renderer/shaders/shade.glsl, la normale est retournee vers la face vue (g_shade_flip, commit 57102cdfce). shade() est inclus par tfrag3, etie_base, tie_wind, shrub, grass, ocean_common : en principe tout le decor. MAIS rien ne prouve que c'est regle PARTOUT : la sonde sol (floor_probe.cpp, `floor_normal_flipped_ppm_<niveau>`) n'a tourne que sur quelques niveaux, et les personnages (merc) ne pas […suite dans le contrat]

## Livrable
CONTRAT RESSERRE LE 25/09 SUR ORDRE DE L'OWNER (« Pourquoi le moteur devrait porter le truc des flipped faces defects si c'est un truc qu'on fait sur les assets du jeu directement ? Je crois que tu te complique la vie sur les preuves… reprend et boucle ce sujet c'est pas un truc de fou que je demande »). Tout ce qui precede sur des sondes moteur, des couples niveau/famille au noir et des mesures sur telephone est ABANDONNE.
1. L'outil de notre chaine d'assets lit chaque niveau extrait de l'ISO (original intact), oriente les normales fautives, et ecrit la version corrigee dans le zip d'assets RECHARGES. Le jeu la prend si elle est la, sinon l'original tel quel. Aucun retournement de normale d […suite dans le contrat]

## Preuve exigee
`flipped_asset_defects == 0` dans `reports/lighting-flipped-faces-everywhere/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-flipped-faces-everywhere x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

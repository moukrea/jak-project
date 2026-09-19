> LIS D'ABORD `prompts/item-res-scale-submenu-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'échelle de rendu se choisit dans un sous-menu (10 à 100 %) qui affiche la résolution de rendu calculée en direct

## Defaut cite
- 2026-09-19 : « Alors tu m'a même pas répondu… et tu continues à me lister q… »

## Cause connue
Owner 17/09 (Linear) : « le truc de l'échelle de rendu… Le slider c'est chiant, je préfèrerais un sous menu avec 10, 20, 30, 40, 50, 60, 70, 80, 90 et 100… Mais avec à côté la résolution de rendu calculée live en raccord à la résolution utilisée dans le picker de résolution ».

19/09 RETOUR OWNER (JAK-172, photo owner-feedback/res-scale-submenu/20260919T0758-1.jpg) : « je validerais bien parce que ca fonctionne mais… c'est quoi cette resolution xxxxXyyy (BASE xxxxXyyy), on a choisi natif, donc t […suite dans le contrat]

## Livrable
`res_scale_menu_defects` = 0, somme de termes publies SEPAREMENT.

1. LE SOUS-MENU EXISTE : dix entrees, 10 % a 100 % par pas de 10, a la place du curseur ; publier le nombre d'entrees (=10) et l'absence du curseur (site de dessin du curseur = 0 appel).

2. LA RESOLUTION CALCULEE EST VRAIE : a cote de chaque entree, largeur x hauteur = resolution choisie dans le picker x pourcentage, arrondie comme le moteur l'arrondit REELLEMENT ; publier pour chaque entree la valeur affichee et la valeur que l […suite dans le contrat]

## Preuve exigee
`res_scale_menu_defects == 0` dans `reports/res-scale-submenu/proof.txt`.
Le proof se produit par `lib/proof_run.sh res-scale-submenu x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Affichage. Trois choses a lire sur le menu, oui/non : (1) la ligne de resolution affiche « Résolution : 2414x1080 (Native) » — la resolution choisie, la mention Native quand c'est le natif, PLUS de « BASE xxxxXyyy », pas de capitales partout ; (2) la ligne d'echelle affiche « Échelle de rendu : 70% (1689x756) » ; (3) l'espace avant les deux-points suit la langue (espace fine en francais, pas d'espace en anglais). Le fonctionnement lui-meme est valide par l'owner..

## Hors perimetre
Ne touche pas au picker de resolution ni a l'echelle dynamique. Tout ce qui n'est pas cet item.

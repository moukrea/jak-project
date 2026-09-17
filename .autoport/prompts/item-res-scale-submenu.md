# L'échelle de rendu se choisit dans un sous-menu (10 à 100 %) qui affiche la résolution de rendu calculée en direct

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Owner 17/09 (Linear) : « le truc de l'échelle de rendu… Le slider c'est chiant, je préfèrerais un sous menu avec 10, 20, 30, 40, 50, 60, 70, 80, 90 et 100… Mais avec à côté la résolution de rendu calculée live en raccord à la résolution utilisée dans le picker de résolution ».

## Livrable
`res_scale_menu_defects` = 0, somme de termes publies SEPAREMENT.

1. LE SOUS-MENU EXISTE : dix entrees, 10 % a 100 % par pas de 10, a la place du curseur ; publier le nombre d'entrees (=10) et l'absence du curseur (site de dessin du curseur = 0 appel).

2. LA RESOLUTION CALCULEE EST VRAIE : a cote de chaque entree, largeur x hauteur = resolution choisie dans le picker x pourcentage, arrondie comme le moteur l'arrondit REELLEMENT ; publier pour chaque entree la valeur affichee et la valeur que le framebuffer prend une fois l'entree choisie : identiques.

3. LE LIBELLE SUIT LE PICKER : changer la resolution dans le picker met a jour les dix libelles ; publier un temoin avant/apres.

4. LE CHOIX SURVIT AU REDEMARRAGE : publie.

PREUVE : `FEATURE res-scale-submenu armed=1 hits=<entrees dessinees>` + la ligne `res_scale_menu_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`res_scale_menu_defects == 0` dans `reports/res-scale-submenu/proof.txt`.
Le proof se produit par `lib/proof_run.sh res-scale-submenu x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Affichage > Échelle de rendu : un sous-menu de 10 % à 100 %, chaque ligne montrant la résolution de rendu réelle qui en résulte avec la résolution choisie juste au-dessus..

## Hors perimetre
Ne touche pas au picker de resolution ni a l'echelle dynamique. Tout ce qui n'est pas cet item.

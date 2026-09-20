# L'échelle de rendu se choisit dans un sous-menu (10 à 100 %) qui affiche la résolution de rendu calculée en direct — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Owner 17/09 (Linear) : « le truc de l'échelle de rendu… Le slider c'est chiant, je préfèrerais un sous menu avec 10, 20, 30, 40, 50, 60, 70, 80, 90 et 100… Mais avec à côté la résolution de rendu calculée live en raccord à la résolution utilisée dans le picker de résolution ».

19/09 RETOUR OWNER (JAK-172, photo owner-feedback/res-scale-submenu/20260919T0758-1.jpg) : « je validerais bien parce que ca fonctionne mais… c'est quoi cette resolution xxxxXyyy (BASE xxxxXyyy), on a choisi natif, donc tu mets "Résolution : 2414x1080 (Native)" (avec le : correctement espace en fonction de la locale, et pas de all caps !). Pareil pour l'echelle de rendu, tu mets "Échelle de rendu : 70% (1689x756)". Le BASE <resolution> on s'en cogne dans le choix de resolution principale, on veut montrer la resolution, et garder la precision quand c'est la resolution native… la resolution de rendu affecte la partie jeu rendue alors que la resolution c'est TOUT, y compris l'UI ». PERIMETRE UNIQUE : les LIBELLES des deux lignes, exactement comme ci-dessus, dans toutes les langues du menu (le separateur « : » et son espacement viennent de la locale, pas d'un litteral). Le fonctionnement est acquis. PORTE : la chaine REELLEMENT rendue (sonde *font-str-trace*, pas la chaine remise) pour les deux lignes, en francais ET en anglais, egale au gabarit ; aucun « BASE » sur la ligne de resolution ; aucune ligne tout en capitales.

## Livrable — le contrat, en entier

`res_scale_menu_defects` = 0, somme de termes publies SEPAREMENT.

1. LE SOUS-MENU EXISTE : dix entrees, 10 % a 100 % par pas de 10, a la place du curseur ; publier le nombre d'entrees (=10) et l'absence du curseur (site de dessin du curseur = 0 appel).

2. LA RESOLUTION CALCULEE EST VRAIE : a cote de chaque entree, largeur x hauteur = resolution choisie dans le picker x pourcentage, arrondie comme le moteur l'arrondit REELLEMENT ; publier pour chaque entree la valeur affichee et la valeur que le framebuffer prend une fois l'entree choisie : identiques.

3. LE LIBELLE SUIT LE PICKER : changer la resolution dans le picker met a jour les dix libelles ; publier un temoin avant/apres.

4. LE CHOIX SURVIT AU REDEMARRAGE : publie.

PREUVE : `FEATURE res-scale-submenu armed=1 hits=<entrees dessinees>` + la ligne `res_scale_menu_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne touche pas au picker de resolution ni a l'echelle dynamique. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Options > Affichage. Trois choses a lire sur le menu, oui/non : (1) la ligne de resolution affiche « Résolution : 2414x1080 (Native) » — la resolution choisie, la mention Native quand c'est le natif, PLUS de « BASE xxxxXyyy », pas de capitales partout ; (2) la ligne d'echelle affiche « Échelle de rendu : 70% (1689x756) » ; (3) l'espace avant les deux-points suit la langue (espace fine en francais, pas d'espace en anglais). Le fonctionnement lui-meme est valide par l'owner.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-19
> Alors je validerais bien parce que ça fonctionne mais… coe tu vois dans le screen, c'est quoi cette résolution xxxxXyyy (BASE xxxxXyyy), on a choisi natif, donc tu mets "Résolution : 2414x1080 (Native)" (avec le `:` correctement espacé en fonction de la locale, et pas de all caps !  Pareil pour la résolution de Échelle de rendu, tu mets "Échelle de rendu : 70% (1689x756)" avec le `:` correctement espacé en fonction de la locale   Le "BASE <résolution>" on s'en cogne dans le choix de résolution principale, on veut montrer la résolution, et garder la précision quand c'est la résolution native… pas savoir la résolution de rendu là dessus, car la résolution de rendu affecte la partie jeu rendu alors que la résolution c'est TOUT, y compris l'UI… je sais pas si je suis clair ?  ![71575.jpg](https://uploads.linear.app/a0a96fbe-70d3-4d8d-9350-9c6c972f09b2/41b78529-c4f0-402a-ba2f-d0df514dda82/39cc5204-a483-4bd6-b271-0724f8e66c4f) [images enregistrees : .autoport/owner-feedback/res-scale-submenu/20260919T0758-1.jpg]

### 2026-09-19
> Alors tu m'a même pas répondu… et tu continues à me lister que c'est dans le build X… oui mais t'as pris mon feedback et tu l'as traité ?

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


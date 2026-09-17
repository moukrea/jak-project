# La liste des résolutions est classée par nombre total de pixels, du plus petit au plus grand

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Owner 17/09 (Linear) : « dans la liste de résolutions, les résolutions sont pas classées par nombre de pixels au total, donc on peut se retrouver avec des résolutions plus basses après des résolutions très élevées ».

## Livrable
`res_list_unsorted_pairs` = 0 : nombre de paires consecutives de la liste PROPOSEE (celle que le menu affiche, par aspect) dont largeur x hauteur decroit. Publier la liste effective (largeur x hauteur, dans l'ordre affiche) pour chaque aspect, et le nombre de paires comparees (non nul). Le classement se fait a la construction de la liste, pas a l'affichage.

PREUVE : `FEATURE res-list-sorted-by-pixels armed=1 hits=<listes construites>` + la ligne `res_list_unsorted_pairs=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`res_list_unsorted_pairs == 0` dans `reports/res-list-sorted-by-pixels/proof.txt`.
Le proof se produit par `lib/proof_run.sh res-list-sorted-by-pixels x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Affichage > Résolution : la liste va du plus petit au plus grand nombre de pixels, quel que soit l'aspect choisi..

## Hors perimetre
Ne change ni les resolutions proposees ni le comportement de l'echelle de rendu. Tout ce qui n'est pas cet item.

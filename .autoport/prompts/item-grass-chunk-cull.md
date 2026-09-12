# L'herbe hors du champ de vision cesse de couter

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, et il porte le lien vers l'investigation complete que l'owner a validee le 12/09. SPEC section 10. Il y a DEUX appels de dessin et AUCUN culling : le vertex shader s'execute pour les 727 000 instances a chaque image, et les hors-portee sont repliees sur un point degenere apres avoir ete transformees. Aucun frustum, aucun chunk au dessin — la grille de chunks existante n'est construite que sous un drapeau de diagnostic et n'est lue que par un journal. S'y ajoutent une trentaine de `glGetUniformLocation` par image sans cache, ce qui sur Adreno est un appel de pilote par nom. C'est la fondation de toute la campagne : aucun enrichissement visuel n'est accepte avant elle.

## Livrable
`grass_offscreen_submitted` = 0, somme de termes publies SEPAREMENT.
1. AUCUNE INSTANCE HORS DU CHAMP N'EST SOUMISE. Publier, a TROIS orientations de camera nommees, le compte d'instances soumises et le compte d'instances dont la boite englobante intersecte le frustum. L'ecart est le defaut.
2. LE COUT DE SOUMISSION EST MESURE, pas suppose : temps processeur de preparation et nombre d'appels de dessin, AVANT et APRES. Passer de deux appels a plusieurs dizaines peut couter plus qu'il ne rapporte, et c'est cette mesure qui tranche.
3. LA PARTITION EST CUITE ET DETERMINISTE : bounds par chunk dans le fichier, une touffe traversant une frontiere appartient au chunk de son ORIGINE. Publier le compte de chunks et la dispersion du nombre d'instances par chunk.
4. L'IMAGE NE CHANGE PAS : identique au bit a un vantage nomme, camera immobile. Le culling retire du travail, jamais des pixels.
PREUVE : `FEATURE grass-chunk-cull armed=1 hits=<chunks testes par le culling>` + la ligne `grass_offscreen_submitted=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_offscreen_submitted == 0` dans `reports/grass-chunk-cull/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-chunk-cull device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir. Le gain se mesure en cadence, surtout camera tournee vers le vide..

## Hors perimetre
Ne change ni la densite, ni les distances d'affichage, ni le rendu d'un brin. Ne touche pas au LOD, qui est un autre item. Tout ce qui n'est pas cet item.

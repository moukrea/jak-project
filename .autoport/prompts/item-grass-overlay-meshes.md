# Les meshes de sable ou de terre poses par-dessus un sol herbeux, etablis ou ecartes

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 9. L'owner affirme qu'un second mesh est parfois pose AU-DESSUS d'un sol herbeux pour simuler l'absence d'herbe. L'investigation n'a PAS pu le confirmer ni l'infirmer : c'est la seule de ses affirmations restee indeterminee. Le seul compteur voisin, les triangles strictement coincidents, vaut zero sur training — mais il ne regarde que les triangles DEJA filtres par les trois textures d'herbe, donc un triangle de sable n'y entre jamais. Et le systeme actuel traverserait la superposition par construction : le terrain tfrag n'est jamais collecte comme occulteur, seuls les objets TIE le sont.

## Livrable
`grass_overlay_unclassified` = 0, somme de termes publies SEPAREMENT.
1. LA MESURE D'ABORD, SANS PREJUGE. Sur les dix niveaux, compter les paires de triangles de sol dont les empreintes au sol se recouvrent, normales toutes deux vers le haut, ecart vertical faible, et textures DIFFERENTES dont l'une est herbeuse. Publier le compte par niveau et la liste des textures impliquees. Un zero se lit « la superposition n'existe pas », et c'est une reponse valable qui ferme l'item.
2. LA CONTRE-EPREUVE PAR LA COLLISION : croiser avec le materiau. Un triangle de collision `grass` recouvert d'un triangle de rendu texture sable ou terre EST la superposition, prouvee par deux sources qui ne se copient pas. Publier le compte des deux methodes et leur intersection.
3. LA CLASSIFICATION EST NOMMEE : chaque superposition trouvee est rangee en vrai chemin, patch decoratif, ou cas ambigu. Publier les trois comptes. Un cas ambigu est NOMME, pas arbitre en silence.
4. RIEN NE CHANGE DANS LE PLACEMENT. Cet item mesure et publie ; c'est l'item des transitions qui agira.
PREUVE : `FEATURE grass-overlay-meshes armed=1 hits=<paires de triangles testees>` + la ligne `grass_overlay_unclassified=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_overlay_unclassified == 0` dans `reports/grass-overlay-meshes/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-overlay-meshes x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu. Vue de debug : les superpositions trouvees, colorees par leur classe..

## Hors perimetre
Ne place ni ne retire aucun brin. Tout ce qui n'est pas cet item.

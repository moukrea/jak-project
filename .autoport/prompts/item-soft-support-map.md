# Le support et l'epaisseur de chaque point de matiere, cuits

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC sections 2, 3, 7. Neige compacte et sable : epaisseur du profil (3,5 cm = 143 u au depart) avec falloff aux frontieres ; congeres : lancer de rayon de la surface rendue vers l'ilot de collision le long de la direction de couche. Direction = normale lissee bornee, verticale a plat, NULLE en frontiere. Objets statiques cuits en depressions (caisses jamais mobiles). Murs, faces retournees, pente > seuil : rejetes et comptes.

## Livrable
`soft_thickness_defects` = 0, somme de termes publies SEPAREMENT.
1. CHAQUE SOMMET A UN SUPPORT : compte de sommets de coque sans support sous eux le long de la direction de couche = zero, avec le compte de sommets testes.
2. AUCUNE EPAISSEUR NEGATIVE, ET LES CONGERES SONT CHIFFREES : compte d'epaisseurs < 0 = zero ; epaisseur min, mediane, max par ilot deepsnow publiee en unites et en m.
3. LES FRONTIERES SONT FIGEES : compte de sommets de frontiere a epaisseur non nulle = zero ; distance aux objets statiques cuite et depressions comptees par niveau (objets, aire).
4. LES REJETS SONT NOMMES : murs, faces retournees, pente > seuil, meshes superposes sable-sur-grass (decision 12) — chacun compte par niveau, non nul la ou l'investigation les a vus (training : 2 952 murs).
PREUVE : `FEATURE soft-support-map armed=1 hits=<sommets de coque ayant recu une epaisseur>` + la ligne `soft_thickness_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_thickness_defects == 0` dans `reports/soft-support-map/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-support-map x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu. Vue de debug : epaisseur en rampe, direction en aiguilles, rejets en rouge..

## Hors perimetre
Ne subdivise pas encore, ne serialise pas : c'est soft-bake-format. Tout ce qui n'est pas cet item.

# Une surface est de neige ou de sable selon DEUX sources, et jamais aussi de l'herbe

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC sections 1 et 11. sand=5, snow=9, deepsnow=10 dans les bits 6..11 de pat-surface ; le lecteur de ces bits est celui de grass-surface-truth, a PARTAGER. Desaccords connus a compter : jng-beach-01 sur une collision dirt (jungle) ; 2 952 triangles de sable en mode MUR a training.

## Livrable
`soft_surface_unclassified` = 0, somme de termes publies SEPAREMENT.
1. LES DEUX SOURCES SONT LUES ET PUBLIEES SEPAREMENT : par niveau, classification par texture et par materiau pour sand, snow, deepsnow ; le compte de triangles qu'AUCUNE source ne classe doit valoir zero.
2. LE DESACCORD SE COMPTE, IL NE SE DEVINE PAS : compte de triangles ou les deux sources divergent, avec les noms de texture impliques, par niveau. Le desaccord n'est pas un defaut de cet item.
3. L'EXCLUSIVITE AVEC L'HERBE EST PROUVEE : compte de triangles eligibles a la fois a l'herbe et a la coque = zero, calcule avec le lecteur de grass-surface-truth, pas un second.
4. RIEN NE CHANGE ENCORE : aucune coque, aucun placement, image bit-identique ; cet item lit et publie.
PREUVE : `FEATURE soft-surface-truth armed=1 hits=<triangles de sol classes par au moins une source>` + la ligne `soft_surface_unclassified=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_surface_unclassified == 0` dans `reports/soft-surface-truth/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-surface-truth x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu. Vue de debug : chaque triangle de sol colore par sa classe et ses desaccords..

## Hors perimetre
Ne cree aucune coque. Ne touche pas au lecteur de l'herbe autrement qu'en l'appelant. Tout ce qui n'est pas cet item.

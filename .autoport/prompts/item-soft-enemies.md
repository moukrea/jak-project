# Les ennemis vivants deforment ; les morts, non, par construction

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 5. Spheres racine et d'os des nav-enemies balayees ; collision retiree a l'image 0 de nav-enemy-die, la chute balistique ne touche pas le sol. snow-bunny, yeti-slave, ice-cube, ram-boss (snow) ; lurkercrab, lurkerpuppy (beach) ; starfish (village1).

## Livrable
`soft_enemy_defects` = 0, somme de termes publies SEPAREMENT.
1. AUCUN FANTOME : compte de tampons d'un id apres son image de mort = zero, compte par ennemi tue pendant la course (non nul : la course tue au moins trois ennemis).
2. LES VIVANTS DEFORMENT : compte de tampons par espece pendant la course, non nul pour chaque espece presente.
3. LE BUDGET TIENT : N ennemis simultanes (declare par palier) ; priorite publiee (distance x taille x nouveaute) ; compte d'ennemis ignores faute de budget.
4. LA SPHERE D'OS EST UTILISEE QUAND ELLE EXISTE : compte de tampons issus d'une sphere d'os vs racine, publie.
PREUVE : `FEATURE soft-enemies armed=1 hits=<tampons d ennemis appliques>` + la ligne `soft_enemy_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_enemy_defects == 0` dans `reports/soft-enemies/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-enemies device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Un snow-bunny qui traverse la neige compacte laisse des traces ; un yeti tue n'en laisse plus une..

## Hors perimetre
Pas les objets, pas les PNJ. Tout ce qui n'est pas cet item.

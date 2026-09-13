# Le canal d'acteurs : pieds, vitesses, pas — un tableau, un appel, zero par image en plus

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 5. Le canal de l'herbe transporte UNE position racine, 4 echantillons de trainee, ≤ 8 disques, sans velocite ni pied. Le pont GOAL->C accepte 6 arguments GPR ; au-dela, un tableau GOAL inline enregistre une fois (patron *hd-ring*, jak-hd.gc:90). Les tags de pas sont resolus AVANT do-joint-math! ; ne JAMAIS armer le bit 0 des flags d'effect-control chez Jak. Regle perf : scalaires en slot par image, jamais un pointeur lu par le fil de rendu.

## Livrable
`soft_channel_defects` = 0, somme de termes publies SEPAREMENT.
1. JAK TRANSITE ENTIER : trans, transv, quat, drapeaux, ground-pat, classe d'etat et les 4 noeuds de pieds (Lankle 29, Rankle 33, Lball 69, Rball 73) lus apres ja-post ; ecart entre position publiee et `control trans` sur 300 images ≤ 1 u hors interpolation, publie AVEC l'interpolation activee.
2. LES ACTEURS MOBILES TRANSITENT AVEC LEUR VITESSE, CHAQUE IMAGE POUR LES N PLUS PROCHES : compte publie par image ; un ennemi disparait du canal a l'image 0 de sa mort (compte par id apres `nav-enemy-die` = zero).
3. UN SEUL APPEL AU SITE ND : les tags de pas gauche/droit arrivent avec joint et materiau par un appel unique dans effect-control-method-11 ; compte d'appels FFI supplementaires par image hors le slot = zero.
4. LE FIL GOAL NE PAIE RIEN : `goal_busy_ms` ≤ baseline sur le Redmi, publie avant/apres.
PREUVE : `FEATURE soft-actor-channel armed=1 hits=<interacteurs publies par image>` + la ligne `soft_channel_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_channel_defects == 0` dans `reports/soft-actor-channel/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-actor-channel device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir : la vue de debug dessine les capsules et vitesses publiees..

## Hors perimetre
Aucune deformation par un acteur reel encore ; le canal alimente, il ne stampe pas. Tout ce qui n'est pas cet item.

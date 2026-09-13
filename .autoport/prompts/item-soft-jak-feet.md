# Les pieds de Jak laissent des empreintes gauche et droite, jamais en l'air

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-surfaces-meubles.md : c'est le contrat, approuve par l'owner le 13/09. SPEC section 5. Deux capsules cheville -> plante ; contact si la capsule est sous la surface de repos ET root `onground` ET classe d'etat autorisee ; le tag de pas CONFIRME et date, il ne cree pas seul. Le sprite footprntr ND (part 2376 / 94) est desactive quand la coque est active sur ce materiau, sinon double empreinte.

## Livrable
`soft_foot_defects` = 0, somme de termes publies SEPAREMENT.
1. AUCUNE EMPREINTE AERIENNE : compte de tampons de pied avec root hors sol ou en etat jump/falling = zero, avec le compte de contacts testes.
2. GAUCHE ET DROITE ALTERNENT : sur une marche scriptee de 20 pas, sequence G/D publiee, compte de doublons = zero ; la forme est la capsule projetee (rectitude publiee), pas un disque.
3. PAS DE DOUBLE EMPREINTE : compte de sprites footprntr emis sur un materiau a coque active = zero, non nul coque eteinte.
4. LA CONFIRMATION PAR TAG EST MESUREE : compte de contacts confirmes par un tag dans les 2 images, et compte de tags sans contact geometrique (publies, pas juges).
PREUVE : `FEATURE soft-jak-feet armed=1 hits=<contacts de pied valides>` + la ligne `soft_foot_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Preuve exigee
`soft_foot_defects == 0` dans `reports/soft-jak-feet/proof.txt`.
Le proof se produit par `lib/proof_run.sh soft-jak-feet device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur la neige compacte et le sable : deux pieds distincts, pas de rond ; rien quand Jak saute..

## Hors perimetre
Pas les jambes, pas les ennemis, pas les profils fins. Tout ce qui n'est pas cet item.

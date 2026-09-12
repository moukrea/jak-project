> LIS D'ABORD `prompts/item-grass-edge-falloff-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'herbe se penche vers le vide au bord des plateformes, au lieu de s'arreter net

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 16, qui reprend mot pour mot les onze exigences de l'owner. La tentative precedente a produit de l'herbe flottante, des brins a l'envers, des brins detaches du sol et des alignements sur des lignes inexistantes ; l'owner l'a parquee le 2026-07-15 sur un verdict de QUALITE. Il veut la feature, pas la tentative : « on recycle pas la daube qu'on avait fait par le passe, mais j'ai clairement dit d […suite dans le contrat]

## Livrable
`grass_falloff_defects` = 0, somme de termes publies SEPAREMENT.
1. AUCUN BRIN NE FLOTTE, AVEC SON DENOMINATEUR. Pour chaque brin d'une bande de retombee, le triangle support de sa racine CONTIENT sa racine. Publier le compte d'echecs — qui vaut zero — et le compte de brins testes a cote. Brin genere au-dela de la surface, racine migrant dans le vide et brin detache tombent dans ce meme compteur.
2. L'INCLINAISON EST PROGRESSIVE ET ORIENTEE PAR LE VIDE. Publier l'angle moyen de penche par PALIER […suite dans le contrat]

## Preuve exigee
`grass_falloff_defects == 0` dans `reports/grass-edge-falloff/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-edge-falloff device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Au bord des plateformes du niveau d'entrainement, puis sur les terrasses de village1. L'herbe doit se pencher de plus en plus fort en approchant du vide, jamais flotter, jamais partir a l'envers..

## Hors perimetre
Aucune des quatre primitives deja refusees de pres : plaques de couleur unie, ficelles, mousse, cartes texturees posees comme une jupe. La retombee se fait avec les brins du systeme. Ne change ni l'oracle de bord (c'est `grass-edge-truth`) ni les transitions vers les chemins. Tout ce qui n'est pas cet item.

> LIS D'ABORD `prompts/item-shrub-trunk-contact-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le tronc d'un mini-palmier ne s'ecrase pas comme un brin d'herbe, et ses feuilles restent solidaires

## Defaut cite
- 2026-09-14 : « bah oui faut que ça avance »

## Cause connue
Signale par l'owner le 13/09. FAIT MESURE (investigation du 13/09) : `shrub.vert:20-21` inclut `tie_sway.glsl` et `vegetation_contact.glsl` et applique la loi de contact de l'HERBE (rayon 2,2 m autour de Jak, bande d'altitude -1,5..+2 m, MAX des echantillons) a TOUS les sommets du shrub, tronc compris. Un tronc n'est pas un brin : il ne doit pas se coucher, et les feuilles doivent rester attachees a lui. Il faut une classe par sommet ou par draw (tronc rigide / feuillage souple) — a etablir depu […suite dans le contrat]

## Livrable
`shrub_trunk_squash_defects` = 0, somme de termes publies SEPAREMENT.
1. LE TRONC NE BOUGE PAS : deplacement maximal des sommets classes tronc sous contact, sur les mini-palmiers de Geyser Rock : zero au quantum pres, avec le compte de sommets tronc testes (non nul).
2. LES FEUILLES RESTENT ATTACHEES : ecart de deplacement a la jonction feuille/tronc (sommets partages ou coincidents) = zero ; les feuilles bougent toujours sous contact (deplacement max des sommets feuillage NON NUL — un zero glob […suite dans le contrat]

## Preuve exigee
`shrub_trunk_squash_defects == 0` dans `reports/shrub-trunk-contact/proof.txt`.
Le proof se produit par `lib/proof_run.sh shrub-trunk-contact device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur Geyser Rock, marcher dans un mini-palmier : les feuilles s'ecartent, le tronc reste droit, rien ne se detache..

## Hors perimetre
Ne change pas la loi de contact de l'herbe ni le vent. Tout ce qui n'est pas cet item.

Campagne explicitement autorisee par l owner le 2026-09-14 (« bah oui faut que ça avance »), proof_plan du backlog : instrumenter les deplacements reels tronc/feuillage et les paires de jonction ; Geyser Rock / training-warp, trois courses maximum au TOTAL de 130 s chacune, reference anterieure justifiee, ON corrige et OFF corrige. Preparer le parcours comparable et les instruments avant les courses ; conserv […suite dans le contrat]

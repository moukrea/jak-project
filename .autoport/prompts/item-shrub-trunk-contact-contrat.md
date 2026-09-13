# Le tronc d'un mini-palmier ne s'ecrase pas comme un brin d'herbe, et ses feuilles restent solidaires — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Signale par l'owner le 13/09. FAIT MESURE (investigation du 13/09) : `shrub.vert:20-21` inclut `tie_sway.glsl` et `vegetation_contact.glsl` et applique la loi de contact de l'HERBE (rayon 2,2 m autour de Jak, bande d'altitude -1,5..+2 m, MAX des echantillons) a TOUS les sommets du shrub, tronc compris. Un tronc n'est pas un brin : il ne doit pas se coucher, et les feuilles doivent rester attachees a lui. Il faut une classe par sommet ou par draw (tronc rigide / feuillage souple) — a etablir depuis les donnees (texture, hauteur au-dessus de la racine, prototype), jamais a la main.

## Livrable — le contrat, en entier

`shrub_trunk_squash_defects` = 0, somme de termes publies SEPAREMENT.
1. LE TRONC NE BOUGE PAS : deplacement maximal des sommets classes tronc sous contact, sur les mini-palmiers de Geyser Rock : zero au quantum pres, avec le compte de sommets tronc testes (non nul).
2. LES FEUILLES RESTENT ATTACHEES : ecart de deplacement a la jonction feuille/tronc (sommets partages ou coincidents) = zero ; les feuilles bougent toujours sous contact (deplacement max des sommets feuillage NON NUL — un zero global serait un defaut, pas une reussite).
3. LA CLASSE VIENT DES DONNEES : publier la regle de classement tronc/feuillage et le compte de sommets par classe et par prototype de shrub, sur les niveaux qui en portent ; aucune liste tenue a la main.
4. RIEN D'AUTRE NE CHANGE : le vent des shrubs (valide par l'owner le 13/09) et le contact de l'herbe gardent leurs cles ; OFF bit-identique par binaire-temoin.
PREUVE : `FEATURE shrub-trunk-contact armed=1 hits=<sommets de shrub classes>` + la ligne `shrub_trunk_squash_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Hors perimetre

Ne change pas la loi de contact de l'herbe ni le vent. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Sur Geyser Rock, marcher dans un mini-palmier : les feuilles s'ecartent, le tronc reste droit, rien ne se detache.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-13
> je sais pas pour qu'elle raison les mini palmiers... Les feuilles bougent quand on collisionne avec (ça OK) mais le tronc s'écrase aussi comme si c'était un vulgaire brin d'herbe c'est débile (et en plus les feuilles sont donc desolidarisees du tronc quand ça se produit).

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


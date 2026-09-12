# L'herbe se penche vers le vide au bord des plateformes, au lieu de s'arreter net — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 16, qui reprend mot pour mot les onze exigences de l'owner. La tentative precedente a produit de l'herbe flottante, des brins a l'envers, des brins detaches du sol et des alignements sur des lignes inexistantes ; l'owner l'a parquee le 2026-07-15 sur un verdict de QUALITE. Il veut la feature, pas la tentative : « on recycle pas la daube qu'on avait fait par le passe, mais j'ai clairement dit dans mon giga prompt que je voulais la feature ». La methode doit rendre ces classes d'erreur IMPOSSIBLES PAR CONSTRUCTION, pas les corriger apres coup.

## Livrable — le contrat, en entier

`grass_falloff_defects` = 0, somme de termes publies SEPAREMENT.
1. AUCUN BRIN NE FLOTTE, AVEC SON DENOMINATEUR. Pour chaque brin d'une bande de retombee, le triangle support de sa racine CONTIENT sa racine. Publier le compte d'echecs — qui vaut zero — et le compte de brins testes a cote. Brin genere au-dela de la surface, racine migrant dans le vide et brin detache tombent dans ce meme compteur.
2. L'INCLINAISON EST PROGRESSIVE ET ORIENTEE PAR LE VIDE. Publier l'angle moyen de penche par PALIER de distance au bord, paliers declares : la suite doit croitre en s'approchant du bord. Publier a cote le compte de brins dont la direction de penche s'ecarte de la direction sortante cuite par `grass-edge-truth` au-dela d'une tolerance declaree : zero.
3. AUCUN BRIN A L'ENVERS, AUCUNE LIGNE FANTOME. Publier le compte de brins dont la pointe passe au-dessus de la racine au-dela de la penche maximale declaree : zero. Publier une mesure de rectitude de la frontiere exterieure de la bande, sous un plafond declare : une frontiere qui suit les aretes de triangles est un defaut.
4. LA RETOMBEE REMPLACE L'ANCIENNE TEXTURE, ET LE RESTE NE BOUGE PAS. Publier le compte de brins de retombee qui recouvrent une bande d'ancienne texture d'overhang, non nul la ou cette texture existe. Publier a cote, HORS des bandes, les comptes de familles, de touffes et l'amplitude de vent : identiques a avant.
PREUVE : `FEATURE grass-edge-falloff armed=1 hits=<brins situes dans une bande de retombee>` + la ligne `grass_falloff_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Hors perimetre

Aucune des quatre primitives deja refusees de pres : plaques de couleur unie, ficelles, mousse, cartes texturees posees comme une jupe. La retombee se fait avec les brins du systeme. Ne change ni l'oracle de bord (c'est `grass-edge-truth`) ni les transitions vers les chemins. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Au bord des plateformes du niveau d'entrainement, puis sur les terrasses de village1. L'herbe doit se pencher de plus en plus fort en approchant du vide, jamais flotter, jamais partir a l'envers.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


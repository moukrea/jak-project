# Plusieurs silhouettes de brins simples, au lieu d'une seule forme hachee — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 6. Trois geometries existent, toutes generees depuis `gl_VertexID` sans aucun asset, mais ce sont trois REPRESENTATIONS DE DISTANCE, pas trois especes : un ruban de 10 sommets en proche, deux quads croises en moyen, une carte suspendue pour l'overhang. Hauteur, courbure, largeur, teinte et phase sont cinq hachages de la MEME forme. L'owner l'a dit et c'est verifie.

20/09 RETOUR OWNER (JAK-120) : « tu fais juste des touffes avec toutes les geometries, pas de touffes d'herbe differentes, pas de variations de hauteur… certaines des geometries… on voit clairement leurs polygones de pres, c'est nul ! ». LA PORTE ETAIT AVEUGLE a ces trois choses : elle comptait la diversite des BRINS, pas l'organisation en TOUFFES. PERIMETRE : (1) la variante se tire au niveau de la TOUFFE (hachage de la racine de touffe), avec une silhouette dominante par touffe et une minorite (<= 20 %) d'autres formes ; les touffes voisines different ; (2) hauteur PAR TOUFFE : facteur 0,7-1,3 tire par touffe, en plus de la variation par brin ; (3) de pres (< 6 m), aucun polygone visible : profil de largeur lisse et assez de segments pour que l'angle entre deux segments consecutifs reste sous 12 degres a la distance de LOD 0 ; le compte de sommets soumis ne monte pas (replier les rangees comme aujourd'hui). PORTE : part de touffes a silhouette dominante >= 80 % ; ecart-type de hauteur ENTRE touffes >= 15 % ; angle max entre segments a LOD 0 <= 12 degres, mesure sur les sommets emis ; sommets soumis inchanges. Capture jointe au passage en test.

## Livrable — le contrat, en entier

`grass_variant_defects` = 0, somme de termes publies SEPAREMENT.
1. LES VARIANTES EXISTENT ET SONT DISTRIBUEES : publier le compte de brins par variante et le compare aux proportions declarees par le profil. Un ecart au-dela d'une tolerance declaree est le defaut.
2. LE BUDGET GEOMETRIQUE TIENT : publier le nombre de sommets par variante et le total de sommets transformes par image, compare a la mesure de reference. La diversite ne se paie pas en geometrie.
3. LE PALIER COMMANDE LE NOMBRE DE VARIANTES, et la selection reste DETERMINISTE : un brin donne recoit la meme variante a tous les paliers qui la proposent. Publier le compte de brins changeant de variante entre deux paliers : zero.
4. AUCUNE MODELISATION : publier le compte d'assets de maillage charges par le systeme d'herbe, qui vaut zero. C'est l'ordre explicite de l'owner.
PREUVE : `FEATURE grass-blade-variants armed=1 hits=<brins ayant recu une variante>` + la ligne `grass_variant_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Pas de fleurs, pas de fougeres, pas de plantes detaillees, aucun asset de maillage. Ne change ni la couleur ni le vent. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Niveau d'entrainement, de pres. Trois oui/non : (1) une touffe a-t-elle UNE silhouette dominante, et les touffes voisines des silhouettes differentes (au lieu de toutes les formes melangees dans chaque touffe) ? (2) les touffes ont-elles des hauteurs differentes entre elles ? (3) de pres, voit-on encore les polygones des brins (aretes, cassures) ?

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-19
> Ce chantier ne touche pas le jeu ? Qu'es-ce ce que tu racontes, comment tu peux être autant à côté de la plaque ?

### 2026-09-20
> Alors tu fais juste des touffes avec toutes les géométries, pas de touffes d'herbe différentes, pas de variations de hauteur… certaines des géométrie… on voit clairement leurs polygones de près, c'est nul !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


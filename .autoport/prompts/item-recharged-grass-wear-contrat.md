# L'usure et la hauteur variable de l'herbe — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md (contrat) PUIS prompts/phase-Grecharged-grass-wear.md — 11 274 octets, la SPEC VERBATIM de l'owner du 2026-07-12 et les quatorze criteres qu'il a poses. SPEC section 12.
POURQUOI CET ITEM ETAIT VIDE. Il portait un spike de conception de 402 lignes — architecture en quatre couches, quatorze criteres d'acceptation, budget chiffre, decoupage en treize etapes — et ZERO ligne de code. Une regeneration de son prompt le 11/09 a efface tout ce contenu : l'item ne portait plus ni cause, ni livrable, ni retour d'owner. Un worker lance dessus serait reparti de zero. Le spike, lui, n'a jamais bouge. Il se REPREND, il ne se refait pas.
CE QUE L'OWNER DEMANDE, ses mots : « L'herbe 3D est actuellement placee automatiquement sur les surfaces identifiees comme utilisant une texture d'herbe. Le resultat visuel fonctionne bien, mais l'ensemble parait artificiel, car tous les brins ou groupes d'herbe ont approximativement la meme hauteur. [...] Le systeme doit produire une impression d'usure naturelle : herbe plus courte dans les zones frequemment parcourues ou importantes pour le gameplay, et plus haute dans les zones ou le joueur est peu susceptible de passer. [...] Le resultat doit donner l'impression que la vegetation a ete placee et ajustee manuellement par un level artist, bien que tout soit genere programmatiquement. »
ETAT MESURE : la hauteur est aujourd'hui du BRUIT BLANC PUR par brin, un hachage de la graine du triangle. Aucun signal spatial. `GrassInstance` est verrouille a 64 octets, donc un tampon satellite est obligatoire, sur le motif de celui de la lumiere.
DONNEES REELLEMENT DISPONIBLES HORS LIGNE : 1 233 orbes posees, 26 cellules posees et 28 declarees, 110 mouches eclaireuses portees par des caisses, 553 acteurs portant un champ `path`, la collision complete par triangle et la praticabilite par le mode de `pat-surface`. NON DISPONIBLE : le maillage de navigation. Le champ existe dans la structure d'acteur mais l'extracteur ne l'exporte pas — seules 494 REFERENCES le sont. Ne pas le supposer disponible.

## Livrable — le contrat, en entier

`grass_wear_defects` = 0, somme de termes publies SEPAREMENT. Les quatorze criteres de l'owner sont dans le spike et font foi ; les quatre termes ci-dessous sont la facon dont la machine les juge.
1. LE CHAMP EXISTE ET IL EST SPATIAL : publier la correlation entre la hauteur d'un brin et celle de ses voisins, aujourd'hui nulle par construction, au-dessus d'un plancher declare. Un bruit blanc a la correlation d'un bruit blanc, et c'est exactement ce que l'owner refuse.
2. LES REGLES SE VERIFIENT CHACUNE : herbe plus courte pres des collectibles et le long des trajectoires, plus haute dans les recoins, et RIEN sur les murs sans gameplay. Publier la hauteur moyenne de chaque population nommee, et l'ecart entre elles. Une paroi qui recoit de l'herbe courte est un defaut : c'est le cinquieme critere de l'owner.
3. AUCUNE BANDE BINAIRE : publier une mesure de nettete des frontieres du champ, sous un plafond declare, plus l'histogramme des hauteurs. Un histogramme a deux pics veut dire un masque, pas une transition.
4. LES COLLECTIBLES RESTENT LISIBLES : publier le compte de collectibles dont la hauteur d'herbe environnante depasse un plancher de lisibilite declare, qui vaut zero. C'est le deuxieme critere de l'owner et il prime sur l'effet.
5. TOUT EST CUIT : publier le compte d'operations d'analyse de trajet executees au chargement, qui vaut zero. Le runtime lit un tampon, il ne recalcule aucun itineraire.
PREUVE : `FEATURE recharged-grass-wear armed=1 hits=<brins dont la hauteur est pilotee par le champ>` + la ligne `grass_wear_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Hors perimetre

Ne modifie ni la collision, ni le gameplay, ni la position des collectibles. Ne remplace aucun mesh ni aucune texture de chemin : les vraies surfaces de chemin restent des zones d'exclusion explicites, traitees par grass-path-transitions. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Sur le niveau d'entrainement et a Sandover : l'herbe doit etre plus courte la ou on passe et plus haute dans les recoins, sans qu'on voie ni bande ni couloir dessine. Les collectibles restent visibles.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


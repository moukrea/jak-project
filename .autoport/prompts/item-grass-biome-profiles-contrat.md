# Geyser Rock et la jungle n'ont pas la meme herbe — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 18. Section 3 du prompt de mission de l'owner, sautee par la premiere redaction de la SPEC et ajoutee le 12/09 apres relecture : « Geyser Rock ne doit pas utiliser exactement la meme herbe que la jungle ou les autres zones. » Aujourd'hui un seul jeu de parametres sert partout. La texture de sol est un indice UTILE MAIS FAIBLE : elle informe la couleur et le caractere de la zone, elle n'impose pas un unique type de brin.

## Livrable — le contrat, en entier

`grass_profile_defects` = 0, somme de termes publies SEPAREMENT.
1. UN PROFIL EST UNE DONNEE, PAS DU CODE. Publier le compte de champs de profil lus depuis le fichier cuit, non nul, et le compte de valeurs de profil ecrites en dur dans une source C++ ou GLSL : zero. Changer un profil ne doit rien recompiler — publier le temoin qui le dit.
2. DEUX ZONES DONNENT DEUX HERBES, MESURABLEMENT. Sur deux vantages NOMMES, un par biome, publier les proportions de familles, la hauteur moyenne, la couleur moyenne et l'amplitude de vent. L'ecart entre les deux doit depasser un plancher DECLARE sur au moins un nombre declare de ces axes.
3. LA TEXTURE DE SOL EST UN INDICE, PAS UNE LOI. Publier le compte de variantes de brins et de types de touffes qui coexistent sur une MEME famille de texture de sol : superieur a un. Publier le compte de surfaces ou la texture seule a decide du profil : zero.
4. LE DETERMINISME TIENT. Deux chargements du meme niveau donnent la meme affectation de profil, brin par brin. Publier le compte de brins changeant de profil entre deux chargements : zero.
PREUVE : `FEATURE grass-biome-profiles armed=1 hits=<brins ayant recu un profil>` + la ligne `grass_profile_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Hors perimetre

Ne cree aucune nouvelle variante de brin ni aucun nouveau modele de vent : il compose ce que `grass-blade-variants`, `grass-shading` et `grass-wind` ont livre. Aucun asset de maillage. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Comparer l'herbe du niveau d'entrainement et celle de la jungle : couleur, hauteur, densite et forme doivent se lire comme deux endroits differents, pas comme la meme pelouse recoloree.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


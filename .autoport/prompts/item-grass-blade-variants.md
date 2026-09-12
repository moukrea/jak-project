# Plusieurs silhouettes de brins simples, au lieu d'une seule forme hachee

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 6. Trois geometries existent, toutes generees depuis `gl_VertexID` sans aucun asset, mais ce sont trois REPRESENTATIONS DE DISTANCE, pas trois especes : un ruban de 10 sommets en proche, deux quads croises en moyen, une carte suspendue pour l'overhang. Hauteur, courbure, largeur, teinte et phase sont cinq hachages de la MEME forme. L'owner l'a dit et c'est verifie.

## Livrable
`grass_variant_defects` = 0, somme de termes publies SEPAREMENT.
1. LES VARIANTES EXISTENT ET SONT DISTRIBUEES : publier le compte de brins par variante et le compare aux proportions declarees par le profil. Un ecart au-dela d'une tolerance declaree est le defaut.
2. LE BUDGET GEOMETRIQUE TIENT : publier le nombre de sommets par variante et le total de sommets transformes par image, compare a la mesure de reference. La diversite ne se paie pas en geometrie.
3. LE PALIER COMMANDE LE NOMBRE DE VARIANTES, et la selection reste DETERMINISTE : un brin donne recoit la meme variante a tous les paliers qui la proposent. Publier le compte de brins changeant de variante entre deux paliers : zero.
4. AUCUNE MODELISATION : publier le compte d'assets de maillage charges par le systeme d'herbe, qui vaut zero. C'est l'ordre explicite de l'owner.
PREUVE : `FEATURE grass-blade-variants armed=1 hits=<brins ayant recu une variante>` + la ligne `grass_variant_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`grass_variant_defects == 0` dans `reports/grass-blade-variants/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-blade-variants device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur le niveau d'entrainement, de pres : les brins ne doivent plus avoir tous la meme silhouette. Hauteurs, largeurs, courbures et pointes differentes..

## Hors perimetre
Pas de fleurs, pas de fougeres, pas de plantes detaillees, aucun asset de maillage. Ne change ni la couleur ni le vent. Tout ce qui n'est pas cet item.

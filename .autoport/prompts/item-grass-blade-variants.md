> LIS D'ABORD `prompts/item-grass-blade-variants-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Plusieurs silhouettes de brins simples, au lieu d'une seule forme hachee

## Defaut cite
- 2026-09-20 : « Alors tu fais juste des touffes avec toutes les géométries,… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 6. Trois geometries existent, toutes generees depuis `gl_VertexID` sans aucun asset, mais ce sont trois REPRESENTATIONS DE DISTANCE, pas trois especes : un ruban de 10 sommets en proche, deux quads croises en moyen, une carte suspendue pour l'overhang. Hauteur, courbure, largeur, teinte et phase sont cinq hachages de la MEME forme. L'owner l'a dit et c'est verifie.

20/09 RETOUR OWNER (JAK-120 […suite dans le contrat]

## Livrable
`grass_variant_defects` = 0, somme de termes publies SEPAREMENT.
1. LES VARIANTES EXISTENT ET SONT DISTRIBUEES : publier le compte de brins par variante et le compare aux proportions declarees par le profil. Un ecart au-dela d'une tolerance declaree est le defaut.
2. LE BUDGET GEOMETRIQUE TIENT : publier le nombre de sommets par variante et le total de sommets transformes par image, compare a la mesure de reference. La diversite ne se paie pas en geometrie.
3. LE PALIER COMMANDE LE NOMBRE DE VAR […suite dans le contrat]

## Preuve exigee
`grass_variant_defects == 0` dans `reports/grass-blade-variants/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-blade-variants device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Niveau d'entrainement, de pres. Trois oui/non : (1) une touffe a-t-elle UNE silhouette dominante, et les touffes voisines des silhouettes differentes (au lieu de toutes les formes melangees dans chaque touffe) ? (2) les touffes ont-elles des hauteurs differentes entre elles ? (3) de pres, voit-on encore les polygones des brins (aretes, cassures) ?.

## Hors perimetre
Pas de fleurs, pas de fougeres, pas de plantes detaillees, aucun asset de maillage. Ne change ni la couleur ni le vent. Tout ce qui n'est pas cet item.

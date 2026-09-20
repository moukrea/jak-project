> LIS D'ABORD `prompts/item-grass-biome-profiles-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Geyser Rock et la jungle n'ont pas la meme herbe

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-herbe.md : c'est le contrat, valide par l'owner le 12/09. SPEC section 18. Section 3 du prompt de mission de l'owner, sautee par la premiere redaction de la SPEC et ajoutee le 12/09 apres relecture : « Geyser Rock ne doit pas utiliser exactement la meme herbe que la jungle ou les autres zones. » Aujourd'hui un seul jeu de parametres sert partout. La texture de sol est un indice UTILE MAIS FAIBLE : elle informe la couleur et le caractere de la zone, elle n'impose pas un unique type de brin.

COHERENCE HERBE (owner 20/09, sur les tickets variantes ET couleur : « a voir avec l'ensemble des tickets lies… j'aurais cru que c'etait compris depuis le debut ») : les c […suite dans le contrat]

## Livrable
`grass_profile_defects` = 0, somme de termes publies SEPAREMENT.
1. UN PROFIL EST UNE DONNEE, PAS DU CODE. Publier le compte de champs de profil lus depuis le fichier cuit, non nul, et le compte de valeurs de profil ecrites en dur dans une source C++ ou GLSL : zero. Changer un profil ne doit rien recompiler — publier le temoin qui le dit.
2. DEUX ZONES DONNENT DEUX HERBES, MESURABLEMENT. Sur deux vantages NOMMES, un par biome, publier les proportions de familles, la hauteur moyenne, la couleur moyenne et l'amplitude de vent. L'ecart entre les deux doit depasser un plancher DECLARE sur au moins un nombre declare de ces axes.
3. LA TEXTURE DE SOL EST UN INDICE, PAS UNE LOI. Publier le compte d […suite dans le contrat]

## Preuve exigee
`grass_profile_defects == 0` dans `reports/grass-biome-profiles/proof.txt`.
Le proof se produit par `lib/proof_run.sh grass-biome-profiles device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Comparer l'herbe du niveau d'entrainement et celle de la jungle : couleur, hauteur, densite et forme doivent se lire comme deux endroits differents, pas comme la meme pelouse recoloree..

## Hors perimetre
Ne cree aucune nouvelle variante de brin ni aucun nouveau modele de vent : il compose ce que `grass-blade-variants`, `grass-shading` et `grass-wind` ont livre. Aucun asset de maillage. Tout ce qui n'est pas cet item.

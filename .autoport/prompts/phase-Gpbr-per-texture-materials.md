# Gpbr-per-texture-materials — des matieres par texture, et d'abord un repere tangent juste

## La demande, mot pour mot (owner 2026-08-28)

> « on a toujours un problème où on dirait que ça marche d'un côté mais pas de l'autre, certaines
> faces n'ont l'air d'avoir aucun displacement/tesselation/etc, d'autres oui nickel, d'autres on
> dirait que c'est inversé [...] on applique un specular truc machin et un relief globalement, ça
> devrait être texture par texture, et ça devrait faire partie de "presets" propres à chaque
> textures "rechargées", parce qu'un tissu n'a pas les mêmes propriétés qu'un mur en pierres
> taillées ou que du sable [...] c'est un peu light il me semble juste ces deux params [...] je
> pense que ça devrait tout être fait dans le dépôt d'assets. »

## Mesure deja faite

Il n'existe QUE DEUX reglages de matiere dans tout le moteur :
`recharged_pbr_texture_relief = 1.5` et `recharged_pbr_spec_intensity = 0.15`
(`game/graphics/gfx.h:427-428`). Un commentaire de `CustomTextureReplacements.cpp` le dit
lui-meme : la loi de parallaxe est « une matiere a une position de curseur ».

**Le point d'accroche existe deja** : les textures sont identifiees par leur nom de fichier nu
(« sand-01 »), et une table de diagnostic par texture indexee sur ce meme nom existe deja dans
`CustomTextureReplacements.cpp`.

## ORDRE IMPOSE — le repere tangent AVANT les matieres

Le premier defaut decrit (relief present / absent / **inverse** selon les faces) est la signature
classique d'un **repere tangent** casse : orientation des UV, signe de la bitangente, ou normales
dans le mauvais espace. Il n'est consigne dans aucun rapport, il est donc a instrumenter.

**Regler des presets par-dessus un repere faux rendrait les deux problemes indemelables.** Donc :

1. **Instrumenter par FACE** : publier, sur un echantillon de faces, l'orientation UV, le signe
   de la bitangente et l'espace des normales. Trouver la population qui differe.
2. Corriger le repere. Prouver que la meme texture rend le meme relief sur toutes ses faces.
3. **Puis** la table de matieres par texture, indexee sur le nom de fichier nu.

## Ce qu'une matiere doit porter

Au-dela des deux actuels : rugosite, metallicite, amplitude ET echelle du relief, anisotropie
(le tissu et le bois brosse en ont, la pierre non), reflectance de base, et le signe / l'espace
de la normale.

Materiaux a definir par famille : sable, pierre taillee, tissu, bois, metal, feuillage, eau,
peau.

## Peuplement de la table — methode autorisee par l'owner

> « Tu peux utiliser Haiku en mode vision pour obtenir des descriptifs de chaque texture (la
> version couleur, pas les normales et compagnie évidemment) pour en déduire des présets »

Passe de vision sur la version COULEUR uniquement, une fois, resultat **versionne dans le depot
d'assets** (`moukrea/recharged-assets`), jamais recalcule au runtime.

## Critere de reussite

1. La meme texture rend le meme relief sur toutes ses faces, mesure par face.
2. Deux matieres distinctes rendent des reliefs mesurablement differents sur la meme scene.
3. Les presets vivent dans le depot d'assets, pas en dur dans le moteur.

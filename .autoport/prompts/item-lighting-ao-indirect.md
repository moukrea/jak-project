> LIS D'ABORD `prompts/item-lighting-ao-indirect-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'occlusion ambiante multiplie l'indirect, plus l'image finale

## Defaut cite
- 2026-09-12 : « pour l'occlusion ambiante par contre je remarque que en qual… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. ao_composite.frag multiplie l'image opaque FINALE, apres l'encodage gamma, ce qui assombrit aussi le direct — d'ou le masque de luminance, qui est le symptome du mauvais emplacement. SPEC 4.7.

## Livrable
Prepasse profondeur+normale+rugosite. L'AO ecrit une texture ; shade() l'applique au SEUL terme indirect, en lineaire, avant le tone map. SPEC 4.6, 4.7. PREUVE : `FEATURE lighting-ao-indirect armed=1 hits=<px dont l'indirect a recu l'AO>` + `ao_direct_leak_px=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene. Acquis 10/09 a tenir : l'ancienne AO n'est pas compilee, les deux chemins sont comptes, la ligne vit dans « Recharged Lighting ». S'AJOUTE (refus 10/09 au soir) : (a) AUCUN MOTIF VISIBLE, A TOUTE QUALITE : pas de damier ni de pixelisation dans le resultat. Publier, par palier de qualite, la force du motif periodique mesuree dans le tampon d'AO ; elle reste sous un plafond declare. Une passe de lissage bon marche est autorisee et son cout est publie. Un palier de qualite plus laid qu'AO ETEINTE est un DEFAUT, pas un compromis. (b) L'ALPHA EST RESPECTE : aucun fr […suite dans le contrat]

## Preuve exigee
`ao_direct_leak_px == 0` dans `reports/lighting-ao-indirect/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-ao-indirect x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Recharged Lighting > Ambient Occlusion : essaie CHAQUE palier de qualite — aucun damier ni pixelisation. Et regarde les shrubs : plus d'ombre qui flotte au-dessus des brins d'herbe..

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines bit-identiques : master OFF, et recharged_lighting OFF ; tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Pas de mesure visuelle. Les estimateurs SSAO/HBAO/GTAO eux-memes ne changent pas. Precision par variable dans shade() : SPEC 4.4 amendee.

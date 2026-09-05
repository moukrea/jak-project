# Un seul modele d'eclairage au lieu de cinq, sans changer un pixel

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. 4106 lignes de shading monde en 4 quasi-copies, dont deux chemins morts et 4 samplers lies a une texture noire 1x1. SPEC 2.2, 2.4 et l'annexe D (le sort des 94 uniformes, un par un).

## Livrable
Une fonction shade() dans un chunk unique, incluse par les 5 shaders monde ; chaque renderer remplit Surface et ne decide plus de rien. Retrait des seules couches RECHARGED mortes. Sortie STRICTEMENT identique sur les deux references. SPEC 4.2 donne l'interface GLSL exacte. PREUVE : `FEATURE lighting-unify armed=1 hits=<draws passes par shade()>` + la ligne `shade_variants=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-unify"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`shade_variants == 1` dans `reports/lighting-unify/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-unify x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien de visible : la sortie doit etre identique a aujourd'hui.

## Hors perimetre
Tout ce qui n'est pas cet item. Le mode ORIGINE (master OFF) doit rester bit-identique : la garde de reference de lighting-census le verifie. Ne touche a aucune feature validee. Pas de mesure visuelle. Le chemin d'origine n'entre pas dans shade() : il reste tel quel.

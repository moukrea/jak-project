# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Framebuffer RGBA8, pow(1/2.2) dans six shaders, un genou maison par chemin : aucune marge au-dessus de 1, donc ni eclat, ni bloom, ni exposition possibles. SPEC 2.3 cause 6.

## Livrable
Monde en RGBA16F, exposition et tone map appliques UNE fois au resolve, repli declare et mesure. Le mode ORIGINE ne passe PAS par la chaine HDR. SPEC 4.5. PREUVE : `FEATURE lighting-hdr armed=1 hits=<images passees par le tone map>` + la ligne `tonemap_sites=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-hdr"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`tonemap_sites == 1` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Tout ce qui n'est pas cet item. Le mode ORIGINE (master OFF) doit rester bit-identique : la garde de reference de lighting-census le verifie. Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de bloom, pas d'exposition automatique : ils viennent apres.

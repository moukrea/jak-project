> LIS D'ABORD `prompts/item-lighting-regimes-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La lumiere cle n'est pas toujours un soleil

## Defaut cite
- 2026-09-24 : « Alors ça a l'air ok sur les niveaux que tu me dis de vérifie… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. pc-set-pbr-sky-sun! est pousse sans garde et ecrase la lumiere cle : dans 16 niveaux sur 20 la clef du monde suit un soleil que le joueur ne voit pas. SPEC 3.2, 3.3 et l'annexe A.

APPRIS PAR lighting-bake (24/09, reports/lighting-bake/FINDINGS.txt) — a lire AVANT de coder :
* SPEC §5.2 : la formule baked = [amb*skyvis + lgt*N.L*vis]*art ne decrit PAS le bake de ND (village1 : mediane […suite dans le contrat]

## Livrable
Le shader lit le REGIME du creneau au lieu de supposer un soleil ; sun-fade module la part directe. La ou il y a un ciel, sa FORME est capturee et renormalisee sur amb-color : le ciel donne la distribution, la table donne le ton. SPEC 4.10 et 4.11. PREUVE : `FEATURE lighting-regimes armed=1 hits=<images dont le regime a ete lu dans la table>` + la ligne `regime_sun_override_wrong=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/a […suite dans le contrat]

## Preuve exigee
`regime_sun_override_wrong == 0` dans `reports/lighting-regimes/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-regimes x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : swamp et lavatube : la lumiere ne doit plus venir d'un soleil invisible.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. Les modeles d'ambiante analytiques sont deja retires par lighting-unify.

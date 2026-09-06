# La lumiere cle n'est pas toujours un soleil

## Defaut cite
- 2026-09-03 : « Il y a aussi des niveaux et/zones ou le ciel n'est pas visible (tunels, overcast) come le lava tube ou le niveau de swamp par example [...] Dans le cas de ciels overcast (ie. Swamp level) la lumiere est diffusee par le ciel, pas le soleil car il n'y est pas vraiment visible »
- 2026-09-03 : « Pour l'ambiance qui vient du ciel attention avec l'artistic intent [...] faut etre super smart la dessus »
- 2026-09-05 : « Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. pc-set-pbr-sky-sun! est pousse sans garde et ecrase la lumiere cle : dans 16 niveaux sur 20 la clef du monde suit un soleil que le joueur ne voit pas. SPEC 3.2, 3.3 et l'annexe A.

## Livrable
Le shader lit le REGIME du creneau au lieu de supposer un soleil ; sun-fade module la part directe. La ou il y a un ciel, sa FORME est capturee et renormalisee sur amb-color : le ciel donne la distribution, la table donne le ton. SPEC 4.10 et 4.11. PREUVE : `FEATURE lighting-regimes armed=1 hits=<images dont le regime a ete lu dans la table>` + la ligne `regime_sun_override_wrong=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-regimes"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`regime_sun_override_wrong == 0` dans `reports/lighting-regimes/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-regimes x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : swamp et lavatube : la lumiere ne doit plus venir d'un soleil invisible.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. Les modeles d'ambiante analytiques sont deja retires par lighting-unify.

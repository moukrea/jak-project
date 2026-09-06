# Les matieres PBR eclairees par la lumiere temps reel, sans fusion

## Defaut cite
- 2026-09-03 : « les materiaux, PBR et tesselation viendront apres car ils dependent du lightning pour etre au top »
- 2026-08-31 : « j'ai l'impression que ca prend pas en compte les proprietes individuelles de Recharged assets et que ca applique le PBR uniquement aux 7 textures PBR qui etaient dans le projet depuis un bail et que ca ignore les autres »
- 2026-09-05 : « Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. 25 rounds sans acceptation, parce que « fusionner » deux chemins qui ne partagent ni normale, ni tone map, ni espace colorimetrique n'a pas de solution. SPEC 4.14.

## Livrable
Les cartes PBR deviennent des entrees ordinaires de shade(). surfaces.json etendu a TOUTE matiere, y compris sans aucune carte : la porte qui exigeait une carte disparait. _orm fusionne trois cartes. SPEC 4.14. PREUVE : `FEATURE lighting-materials armed=1 hits=<matieres atteintes au draw avec leur enregistrement>` + la ligne `materials_named_but_unreached=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-materials"), jamais armed(), et n'en ecris pas un second. Les matieres PBR passent SOUS « Eclairage Recharge » dans le menu (SPEC 6.2).

## Preuve exigee
`materials_named_but_unreached == 0` dans `reports/lighting-materials/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-materials x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > PBR Materials : le sable, la pierre et le tissu de Sandover.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. La tessellation et le displacement ne changent pas ici : ils sont re-heberges tels quels dans le chemin unique.

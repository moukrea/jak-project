# Les interieurs gardent leur lumiere, sans fuite par les murs

## Defaut cite
- 2026-09-05 : « Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. La grille de sondes a ete supprimee et son remplacant est un degrade CPU sans notion d'interieur : les huttes recoivent le ciel a travers leurs murs. SPEC 4.12.

## Livrable
Volume de sondes epars L1 avec visibilite inter-sondes CUITE : etanche par construction, cout nul a l'execution. C'est aussi la source d'ambiante des 7 niveaux sans ciel. SPEC 4.12 et 5.3.5. PREUVE : `FEATURE lighting-interiors armed=1 hits=<sondes echantillonnees par image>` + la ligne `probe_leak_permille=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-interiors"), jamais armed(), et n'en ecris pas un second.

## Preuve exigee
`probe_leak_permille <= 10` dans `reports/lighting-interiors/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-interiors x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la hutte du Sage Vert et les huttes de Sandover, contre l'exterieur.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle.

## Appris par lighting-bake (24/09, reports/lighting-bake/FINDINGS.txt)
- `common/custom_data/LightBake.cpp` (version 1) ecrit PROBES, LIGHTS, LIGHTVIS VIDES (count=0) : sondes, emetteurs et visibilite par lumiere ne sont PAS encore cuits. A produire ici.
- Le compagnon derive part dans le pack de l'APK via `android/build_custom_pack.sh`, pas `scripts/package_game_assets.sh` (SPEC 5.6 perimee sur ce point).

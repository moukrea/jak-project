# Le baked devient l'indirect, et l'original reste intact — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Le chemin valide fait color.rgb *= rt_mod : le soleil teinte le bake au lieu de s'y ajouter, donc il ne peut jamais eclairer ce que le bake a laisse sombre. La decomposition a pourtant une forme CLOSE. SPEC 3.1 et 5.2.

## Livrable — le contrat, en entier

tools/light_bake ecrit <niveau>.lightbake A COTE du fr3 : palette B, residu artistique, visibilite du ciel, AO, normales coudees, sondes, regimes, emetteurs. La palette A n'est JAMAIS reecrite. Le moteur verifie la reconstruction au chargement. SPEC 5 en entier, format octet par octet en 5.4. PREUVE : `FEATURE lighting-bake armed=1 hits=<index de couleur reconstruits et verifies>` + la ligne `bake_reconstruction_maxdelta=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-bake"), jamais armed(), et n'en ecris pas un second. AMENDEMENT 09-09 (perf) : les trois LUT TOD par arbre : les deux statiques televersees une fois au chargement ; la dynamique reecrite seulement quand itimes change et jamais dans la texture que le GPU lit encore (ping-pong avec orphaning) ; tod_uploads_per_frame publie.
AVERTISSEMENT DU 11/09 (reports/hdr-source-range/FINDINGS.txt) : les cles `tod-palette-*` sont enregistrees DANS UNE BOUCLE PAR ARBRE (TFragment.cpp:512, Tie3.cpp:679, Shrub.cpp:471) : les N arbres s'ecrasent dans `s_inputs` et il ne reste que 2 entrees par famille quel que soit le niveau. `hdr_plan_s2_bytes_total` et `_bytes_8bit` SOUS-COMPTENT donc les palettes d'un facteur N_arbres : le chiffrage memoire du PLAN §2.1 pour ce chantier est un PLANCHER, pas un total. Le recompter par arbre avant de dimensionner quoi que ce soit.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. Les 22 autres niveaux viennent apres les quatre de la premiere livraison.

## Ou l'owner regardera

les quatre niveaux de la premiere livraison : village1, swamp, lavatube, snow

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-07-19
> moins beau que du baked

### 2026-09-03
> j'imagine qu'ils utilisent du baked aussi, faut qu'on soit en phase, et que malgre nos changements ca suive le ton du jeu original, juste plus "real time possible"

### 2026-09-05
> Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


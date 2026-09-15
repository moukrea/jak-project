# Diagnostic local essai8
DIRECTIVES vaff5c1afea

## Première opération attribuée

Cas archivé : sample13, s4=64, s5=256, fade=7fc12345. Le débogueur
exécute les binaires de l'essai7 jusqu'à ce cas, trace les instructions
arithmétiques avant/après puis s'arrête ; aucune nouvelle campagne du candidat
inchangé. Commandes, SHA des binaires et sorties : `trace/commands.log`,
`trace/binaries.sha256`, `trace/{x86,arm}.log`.

Les étapes amont concordent : vf14 reçoit +Inf (−Inf multiplié par −Inf),
puis vf11.xyz reçoit le NaN de −Inf + +Inf. Le calcul d'amortissement dans
vf15.w conserve le NaN 7fc12345 du fade. Les deux NaN se rencontrent pour
la première fois dans `vmulw.xyz vf11,vf11,vf15`, composante z.

| Exécution ciblée | Instruction avant | Instruction après | Résultat avant → après |
|---|---|---|---|
| x86 GDB | 401938: vmulss %xmm2,%xmm7,%xmm7 | 401be4: vmulss %xmm8,%xmm0,%xmm0 | ffc00000 → 7fc12345 |
| ARM GCC QEMU/GDB | 4013f8: fmul s27,s27,s25 | 4015fc: fmul s29,s31,s29 | 7fc00000 → 7fc12345 |

Les traces PRE/POST relèvent les opérandes avant l'instruction et le résultat
après son exécution : avant = vitesse puis amortissement ; après = amortissement
puis vitesse. La différence est ainsi attribuée à l'ordre effectif des deux
opérandes NaN, et non plus seulement supposée depuis les sorties du comparateur.
Les voies x/y gardent le même résultat entre les deux versions de chaque banc.
Les contextes VF finaux corroborent la propagation vers vf17.z puis vf8.z.

Le chercheur retrouve la même inversion dans le banc Clang ARM archivé
(before 11008: fmul s1,s1,s3 ; after 11278: fmul s16,s21,s16).
Cette dernière attribution est statique ; aucune trace GDB Clang ajoutée.

## Reproducer minimal et frontières

`nan-order.cpp` charge des bits et exécute les deux ordres de multiplication
observés, au moyen d'une instruction assembleur par appel. Ce programme isole
la propagation des NaN par le matériel/émulateur ; il ne prétend pas reproduire
l'allocation des registres du compilateur à partir d'une expression C++ réduite.
Commandes exactes et codes retour : `nan-order-manifest.json` et les logs associés.

Six paires seulement : NaN généré/NaN fade positif, fade négatif, deux payloads
qNaN, qNaN/sNaN, sNaN/qNaN, et deux nombres finis. Les cas signalants servent
à ne pas généraliser abusivement la priorité du premier opérande à tout NaN.
Résultat exécuté : 5 différences/6 sur x86, 3/6 sur ARM GCC et Clang/QEMU.
Sur ARM les cas mixtes signalant/silencieux conservent le payload signalant
quel que soit l'ordre ; les deux nombres finis concordent sur les trois builds.
Les 6048 cas du comparateur de bloc sont conservés, sans ajout ni filtre.

## Limite du banc extrait

La comparaison d'objets complets de l'essai7 retrouve l'inversion sur Android :
`before-android-same-headers-3d.asm:514` (7b0, multiplication vectorielle y/z)
contre `candidate-android-same-headers-3d.asm:505` (78c, multiplication scalaire z).
Le symbole x86 complet ne l'inverse pas à ce site : avant 27ef, candidat 10d6.
Le contexte de compilation change donc l'ordre retenu ; le banc x86 ne démontre
pas cette divergence précise dans le moteur x86 complet. Une absence de défaut
dans le seul banc extrait ne suffirait pas davantage à garantir le moteur.

## Unique correction examinée

Après attribution dynamique, restauration locale des publications vf11/vf15,
appel `c->vmul_bc(DEST::xyz, BC::w, vf11, vf11, vf15)`, puis reprise de r11.
Les autres calculs et publications du candidat restent identiques.
`correction-only.patch` et `correction-diff-verification.json` bornent ce changement.
Le candidat reste dans les notes pendant son évaluation ; aucun fichier moteur
livré n'est remplacé et aucun build gk, appareil ou proof_run n'est lancé.

Les anciens refus de `validator-007.txt` concernent notamment la preuve essai1
(identité, empreintes, acquis et trois défauts). Ils ne sont ni corrigés ni
effacés par ce diagnostic local. Le validateur reste lancé par l'orchestrateur.

## Verdict de la correction unique

Sept compilations isolées réussies, mêmes options par couple avant/après :
`tested-manifest.json`. Trois runs uniques du comparateur existant :
x86 343/6048, ARM GCC 163/6048, ARM Clang 153/6048, tous exit1/RESULT FAIL.
Les entrées, le contexte entier, les 512 octets mémoire et la branche ne sont
ni filtrés ni normalisés. Les sources compilées sont empreintées avant/après.

La revue des nouveaux objets de banc retrouve statiquement l'inversion sample13 :
x86 after 401be9 (vmulss %xmm7,%xmm1,%xmm1), ARM GCC after 401604
(fmul s28,s29,s28), avec amortissement premier. Les publications ajoutées
restent visibles dans le codegen, mais ne fixent pas l'ordre arithmétique.
Aucune nouvelle trace GDB de cette correction : attribution statique corroborée
par les sorties du comparateur, distincte de la trace dynamique essai7 ci-dessus.

Clang remet la vitesse en premier à 112c4 (fmul s16,s16,s23 ; référence11048).
Son premier défaut devient sample15,s4=128,s5=64,fade=7fc12345 :
vf10.x ffc54321→7fc12345 (`tested-block-parity-arm-clang-run.log:2–3`).
L'analyse statique identifie une autre permutation à l'addition vf10+vf19 :
référence110f0 fadd v16.4s,v3.4s,v17.4s (vf19 premier),
correction112fc fadd v24.4s,v19.4s,v21.4s (vf10 premier).
Le fade recouvre ici vf10.x, car s5+96 = s4+32 =160.
Aucun deuxième correctif tenté ; tous les autres défauts ne sont pas attribués.

Codegen intégral des quatre objets et des trois bancs conservé dans `tested-*-full.asm`.
Symboles complets3D : x86 4867→5069 octets (959→972 instructions dans les bornes
exactes du symbole), Android3740→3852 (935→963). Les instructions d'alignement
après la fin du symbole sont exclues du comptage, et les ret inclus.
Symboles2D : mêmes tailles, x866210 et Android4884 octets ; cela ne constitue
pas une comparaison exécutée de tous les chemins2D.

Correction rejetée, uniquement archivée ; rien à retirer du moteur car aucun
fichier livré n'a été remplacé. Source moteur SHA93117b90c7b101bb47373369ef8fcb167b3180ccfcaeb816f83a449f1c36761b.
La comparaison `preservation-before.json`/`preservation-after.json` confirme
l'identité des sources surveillées, de la preuve historique et du validateur.
Aucun gain ou résultat en jeu revendiqué. Le contrat borné est épuisé.

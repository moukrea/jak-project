# Qualification locale du comparateur — essai9
DIRECTIVES vaff5c1afea

## Verdict et portée

Le banc appelle les fonctions complètes archivées avant/après le candidat de
l'essai7. Leur entrée réelle est exécutée jusqu'au premier appel GOAL externe,
qui est capturé puis interrompu par exception, sans valeur de retour fabriquée.
Le banc extrait n'est plus utilisé comme substitut au contexte de compilation.
Qualification limitée à cette frontière : aucun retour du chemin arithmétique,
callback ou résultat moteur complet n'est certifié. Aucune optimisation nouvelle
ni réévaluation de la correction essai8. Le candidat essai7 reste rejeté.

## Compilation et objets

`build-frontier.py` compile les deux fichiers `attempt7/{before,candidate}-sparticle.cpp`
intégraux, chacun dans son unité de traduction. Les SHA des sources et de tous
les fichiers inclus figurent dans `{x86,arm-clang}-manifest.json` : dépendances
communes identiques par paire, vérifiées par le script (500 x86, 362 ARM).
Les options x86 viennent de `attempt7/before-x86-compile-command.txt` ; ARM Linux
Clang reprend le manifeste CRT corrigé `supervisor-clang-20260915/manifest.json`.
Les deux architectures utilisent O3, NDEBUG, gnu++20 et ffp-contract=off ; x86 AVX.
Ajout commun de function/data-sections et lien gc-sections pour éliminer les
fonctions link/2D non appelées et leurs dépendances inutilisées, sans stub de succès.
`objcopy` renomme les définitions fortes APRÈS compilation pour lier les deux
objets ensemble. Les tables de renommage, objets avant/après renommage, nm,
désassemblages intégraux, relocalisations readelf et maps du lien sont conservés.

`review-codegen.py` lit les symboles ELF : les octets AVANT relocalisation des
deux execute x86 sont strictement identiques aux objets complets essai7
(4867/5085 octets ; `codegen-byte-review.json`). Le renommage ne change aucun
octet du symbole execute dans les quatre objets. Cette vérification ne prétend
pas rendre les adresses du banc égales à celles d'un moteur chargé.
ARM Linux/QEMU utilise Clang du NDK avec CRT/libstdc++ Linux ARM explicites ;
ce binaire n'est ni Android ni un instrument de performance matérielle.

## Entrées, préconditions et dépendances

Le `seed` est identique au texte essai7. Les 168 samples ×6 couples d'adresses
×6 frictions (nom historique CSV `fade`) restent présents, sans filtre IEEE.
La mémoire initiale de 512 octets suit le générateur existant ; elle est étendue
à4096 pour loger frame-time et pile. Toutes les entrées restent synthétiques,
notamment les alias CPU/sprite et les bits arbitraires : aucune population en jeu.

ABI avant execute : a0=1024, a1=cpu, a2=sprite, a3=0, t0=1 particule,
t1=s7=768 (#f cohérent64), s6=0, sp=4096 aligné16. Les hauts64 des GPR128 sont
préservés ; les valeurs VF/FPR/acc/Q/I/hi/lo ne sont pas filtrées. Frame-time à512
reçoit les16 octets vf16 d'entrée. Caches hôte→cellules32 : frame512, quaternion2048,
free2064, relaunch2080. Les trois derniers sont des identifiants de frontière,
aucun code de callback n'existe à ces offsets dans ce banc.

Adaptations CPU limitées à func+112=0, next-launcher+120=0, valid+128=772.
Elles ne recouvrent aucune lecture arithmétique du candidat dans les six couples.
timer+100, flags+104, next-time+116 et cache-alpha+124 restent bruts. Pour
{sprite128,cpu64}, timer/flags recouvrent color.y/z : le moteur les modifie
légitimement avant l'intégration (timer décrémenté, flag64 retiré, alpha éventuel).
Le prologue écrit aussi v1 depuis vf16 : les GPR à l'entrée du bloc diffèrent
du banc extrait. Les totaux des deux bancs ne sont donc pas un A/B à frontière égale.

`sparticle.cpp:203/237` : func/relaunch évités par ces préconditions.
`:312/321` : quaternion*! est obligatoire après l'intégration ; l'octet bas
de frame-time choisit le premier site. La vraie dépendance est du GOAL compilé
(`goal_src/jak1/engine/math/quaternion.gc:253`), appelé par le pont ABI
`mips2c_private.h:397`. Le banc C++ ne charge pas ce code ni le runtime GOAL.
`:404` : un timer nul mène à sp-free-particle avant intégration ; ses dépendances
système/allocation ne sont pas chargées non plus. Ces frontières restent nommées.
L'interception capture avant tout retour ; aucun appel n'est remplacé par un no-op.
L'exception déroule la pile C++ (et le compteur de temps ARM), pas l'épilogue EE.

## Exécutions et comparaison

Commandes, SHA binaires/CSV/logs, deux builds0 et deux runs uniques exit1 :
`run-manifest.json`. Aucun bloc isolé relancé, aucun build gk ni outil appareil.
Comparer tous les1216 octets ExecutionContext, tous les4096 octets mémoire
(pile comprise), adresse GOAL externe, huit arguments, zero/pp/st et cohérence
de la base mémoire. Aucun registre ignoré, aucune normalisation NaN.
Les compteurs de temps hôte SpartProf ne sont pas une composante EE comparée ;
aucun temps issu de leur déroulement sur exception n'est publié comme gain.

| Mesure exécutée | x86 | ARM Clang Linux/QEMU |
|---|---:|---:|
| Entrées |6048|6048|
| Frontière quaternion, par variante |5976|5976|
| Frontière free avant intégration, par variante |72|72|
| Retours execute / frontière inconnue |0 /0|0 /0|
| Cas avec écart contexte |226|335|
| Cas avec écart mémoire |147|258|
| Cas avec écart appel/arguments |0|0|

Sources : lignes LAB/RESULT de `x86-run.log` et `arm-clang-run.log` ; tous les
cas détaillés dans les CSV, IDs continus0..6047 vérifiés dans `test-checks.json`.
Les72 cas free n'exercent pas l'intégration et ne constituent pas une preuve
de sa parité. Les5976 autres atteignent le callback après le candidat.

Cas472 (sample13,sprite64,cpu256,friction7fc12345) : x86 contexte/mémoire identiques,
vf11.z=ffc00000 des deux côtés ; ARM contexte/mémoire divergent,
vf11.z=7fc00000→7fc12345 (`test-checks.json`, deux traces CASE).
L'écart précis du banc extrait x86 ne se reproduit donc pas à cette frontière
du symbole complet ; d'autres écarts existent. L'écart NaN ARM reste observable.
Pas de nouvelle attribution instruction par instruction ni correction tentée.

## Limites et conservation

Non prouvé : callbacks/quaternion, instructions postérieures, retour complet,
chemins func/relaunch/pause/invalide, cas en jeu, trois optimisations actives,
parité600 images, hd-mtx-check-all, replay0, gain matériel, fraîcheur/crash/acquis.
Le contrat a interdit proof_run/appareil/refset/déploiement/validation pendant
cette qualification locale ; la preuve.txt essai1 reste historique et non valide.
Le validateur008 a refusé cette ancienne preuve (identité essai1, empreintes,
acquis et critère3≠0). Ni ses exigences ni le backlog ne sont modifiés ici.
Empreintes de conservation : `preservation-before.json` / `preservation-after.json`.

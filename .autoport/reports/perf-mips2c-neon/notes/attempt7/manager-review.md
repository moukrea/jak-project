# Revue du candidat local rejeté
DIRECTIVES vaff5c1afea

Un seul candidat préparé, conformément au contrat local du 15/09. Aucun appareil,
proof_run, capture, refset, validateur ou daemon lancé. Le validateur reste à
l'orchestrateur ; les huit refus de validator-006.txt ne sont pas effacés.

## Choix et frontière
Le chemin 2D ARM par défaut travaille déjà sur des tableaux locaux (source avant
sparticle.cpp:684–751). Retirer ses quatre écritures VF changerait son état ;
optimiser son fallback ne réduirait pas le travail de ce chemin livré.
Le candidat porte donc uniquement sur l'intégration 3D, avant les quatre sqc2.
Les sept sources deviennent locales ; tous les VF intermédiaires sont publiés
en fin de bloc. Aucun SIMD explicite ni changement du chemin os ajouté.

Revue researcher puis manager : VF11.w et VF9.xyz conservés ; VF15 conditionnel
reçoit les 128 bits du GPR v1, y compris haut64, puis les quatre multiplications.
Le contexte peut être dans la mémoire EE (asm_funcs_arm64.s:286–317), mais les
régions particules de l'appel sont dans le scratchpad (sparticle.gc:262–274),
distinct du contexte pile. Le banc couvre aussi les recouvrements s4/s5.

## Comparaison locale
make-block-bench.py reprend seed() et le comparateur de contexte entier du banc
existant vu_simd_parity.cpp ; il extrait les blocs réels avant/après et compare
également 512 octets de mémoire synthétique et le booléen de branche.
6048 cas par architecture : 168 graines, six dispositions mémoire et six
amortissements (+0, -0, 0.5, 1, NaN silencieux, NaN signalant négatif).
2304 cas ont une mémoire initiale de plage finie ; certains amortissements
restent NaN. Ce sont des entrées de BANC, aucune capture d'une population en jeu.

Les logs block-parity-x86-run.log et block-parity-arm-gcc-run.log donnent
respectivement 343 et 163 cas divergents, RESULT FAIL, exit1.
Exemple sample13, s4=64/s5=256, fade=7fc12345 : vf11.z passe de ffc00000
(x86) ou 7fc00000 (ARM GCC/QEMU) à 7fc12345 ; vf8.z/vf17.z diffèrent aussi.
La revue de l'ordre C++ n'était donc pas une preuve de conservation des bits.
L'arbitrage des opérandes NaN par le compilateur est une hypothèse explicative,
pas un défaut de codegen démontré ni une autorisation de modifier les seuils.

## Décision
Candidat retiré après cet échec, sans second candidat ni correctif spéculatif.
candidate.patch et candidate-sparticle.cpp conservent exactement la tentative.
Source moteur restaurée à SHA256
93117b90c7b101bb47373369ef8fcb167b3180ccfcaeb816f83a449f1c36761b.
Les objets de laboratoire et désassemblages sont conservés pour la comparaison
machine ; aucun build gk complet ni déploiement n'est nécessaire après rejet.
La preuve historique reste identique : preservation-before/after.json.
Non prouvé : parité compilateur Android en jeu, gain matériel, trois noyaux,
600 images, hd-mtx-check-all, replay0, fraîcheur et non-régression appareil.

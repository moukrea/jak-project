## ÉTABLI
DIRECTIVES vaff5c1afea
Essai7 : étape locale effectuée, un candidat3D compilé/comparé puis rejeté ; aucune validation.
2D ARM déjà local : raison technique d’exclusion, aucune modification du chemin2D.
Banc adapté de vu_simd_parity : contexte+mémoire+branche,6048 cas synthétiques par architecture.
x86343 défauts, ARM GCC/QEMU163 ; logs notes/attempt7/block-parity-*-run.log, exit1.
Exemple NaN vf11.z avant ffc00000(x86)/7fc00000(ARM), après7fc12345, sample13.
Compilations isolées avant/candidat x86/Android : quatre exit0, flags/headers identiques.
ARM bloc142→118 instructions/load-store80→61 ; symbole3740→3812 octets ; x864867→5085.
Sources moteur restaurées ; sha sparticle93117b90c7b101bb47373369ef8fcb167b3180ccfcaeb816f83a449f1c36761b.
Preuve historique/ripple/validateur intacts : notes/attempt7/preservation-after.json.
## TENTÉ
Transferts de contexte remplacés par locaux, même ordre C++, writebacks de tous les VF.
Parité échoue sur NaN malgré revue ; aucune permutation machine exacte attribuée comme cause prouvée.
Candidate.patch et candidate-sparticle.cpp conservés ; pas de deuxième transformation.
Banc Clang NDK/Linux : lien échoue sur CRT x86 ; parité Clang non mesurée, pas de campagne ajoutée.
Aucun build gk complet après rejet ; seules compilations de laboratoire, aucun appareil/proof_run.
Codegen avant/après : notes/attempt7/candidate-test-codegen-notes.md et isolated-codegen-stats.json.
## RESTE
Ne pas reproposer ce candidat inchangé ni déduire un gain du bloc statiquement raccourci.
Le contrat de cette étape bornait à un candidat ; toute suite doit partir de ces données concrètes.
Trois optimisations actives/références origine qualifiées toujours nécessaires à livraison finale.
Ne pas réauditer sans raison les absences établies ni lancer la même course historique incomplète.
Non prouvés : gain matériel, parité en jeu600 images,hd-mtx-check-all,replay0,crash/non-régression.
Non prouvée : fraîcheur appareil ; aucune preuve de l’essai1 présentée comme celle de l’essai7.

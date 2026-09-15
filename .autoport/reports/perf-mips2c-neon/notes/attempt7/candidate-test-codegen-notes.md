# Candidat rejeté : parité et code machine
DIRECTIVES vaff5c1afea

Verdict : échec bit à bit x86 (343/6048) et ARM GCC (163/6048), aucun build moteur lancé.
Banc block-parity.cpp : 6048 cas, 2304 cas mémoire finie, 5040 branches friction et 1008 bypass ; comparaison contexte entier, mémoire et décision de branche.
Exemple sample13 fade=7fc12345 : vf11.z/vf17.z/vf8.z avant=ffc00000 x86 (7fc00000 ARM), après=7fc12345.
Le changement de payload NaN est mesuré ; l’attribution à un changement d’ordre des opérandes est une hypothèse, pas une preuve.
Journaux commandes et rc : block-parity-{x86,arm-gcc}-build2.log (0), block-parity-{x86,arm-gcc}-run.log (1).
Premiers essais échoués conservés dans *-build.log : symbole assert absent x86 et headers cross incohérents ARM.
Résolution banc uniquement : assert-fail-fast.cpp conserve fprintf+abort en échec ; ajout -isystem /usr/aarch64-linux-gnu/include au cross GCC (headers C++12 et runtime12).
Clang NDK Linux tenté : erreur de lien crt x86 sélectionnés automatiquement, block-parity-arm-clang-build.log exit1 ; parité Clang non mesurée.

Quatre compilations isolées avant/candidat x86/Android réussissent (exit0), sources snapshot et sorties notes uniquement, tous les flags du graphe Ninja conservés.
Commandes : {before,candidate}-{x86,android}-isolated-build.log ; objets/disasm {before,candidate}-{x86,android}-same-headers*.
Headers courants identiques ; seules les options chemins -c/-o/-MF/-MT ont été adaptées. Aucun arbre configuré ni cible moteur construite.

| Architecture | Symbole3D avant → candidat | Instructions avant → candidat | Symbole2D |
|---|---|---|---|
| x86 | 4867 → 5085 octets (+218) | 961 → 980 (+19) | 6210 octets inchangés |
| Android | 3740 → 3812 octets (+72) | 935 → 953 (+18) | 4884 octets inchangés |

Le bloc Android reconnu des loads initiaux aux quatre stores raccourcit de 142 à 118 instructions (568→472 octets), malgré l’augmentation du symbole entier.
Bornes avant 0x6c4..0x8f8 ; candidat 0x6d4..0x8a8. Le candidat emploie fmul v2.4s à 0x730 et davantage de résultats en registres locaux.
Les assertions restent actives et les chemins froids/emplacements sources différents contribuent à la taille globale ; aucune réduction globale machine démontrée.
Compteurs exacts et SHA256 objets dans isolated-codegen-stats.json.

Non prouvé : parité Clang, performance appareil, gain temps/énergie, comportement du jeu. Aucun appareil, QEMU seulement pour correction, aucune chronométrie annoncée.

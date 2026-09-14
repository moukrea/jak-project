## ÉTABLI
DIRECTIVES vaff5c1afea
Sources moteur au commit e8620fd5df ; builds x86/Android frais, APK installé sur eae4df44.
Lib MD5 local/appareil : 0dd3d1afd188bd6e20f5c5328fc59b08. Voir notes/build-summary.md.
Preuve USB neuve : course 20260914T211200Z-949576-04ffe282, 13920 images, crash=0.
Gate=3, bit_defects=0, bones_compared_ops=0, parity_frames=0.
Joints=20183198 et particules=159438 opérations comparées sans écart.
Refset USB : hutte maxdiff=233 ; beach-start-h09 et beach-sun-h09 absents ; gate=255.
SSE et NEON QEMU : 951808 cas par mode livré/verify/off, tous sans divergence.
Lot OOB absent du binaire normal (nm) ; ripple.cpp inchangé à l'octet.

## TENTÉ
Helpers VU SSE2/NEON sur bones-mtx-calc, cspace-parented-transformq-joint, sp-launch-particles-var.
Appels apply supprimés par inline ; oracle/comparaison cold/noinline, seuls vérifiés en preuve.
Fenêtre initiale consommée au boot corrigée : elle attend un passage des trois noyaux.
Mais bones.gc:477/526 définit *use-new-bones*=#t et utilise new-bones-mtx-calc-asm : ancien noyau inactif.
L'ancien ARM vectorisait déjà os/joints : l'hypothèse de départ était fausse.
A/B x86 complet : 6980/6990 images sans crash ; refset=255 dans les deux bras.
Durées par seau consignées, gain non établi car la comparaison reste active en attente des os.
Aucun validateur modifié ni exécuté ; aucune validation owner fabriquée.

## RESTE
Revoir la sélection des trois noyaux d'après le chemin réellement exécuté ; ne pas forcer l'ancien os pour fabriquer des hits.
Traiter les références manquantes/non équivalentes ; aucun zéro global possible avec ce refset.
Prouver hd-mtx-check-all et les 600 images qualifiées après résolution du périmètre.
Établir un gain avec les seaux existants, comparaison de preuve hors fenêtre mesurée.
Lire FINDINGS.txt (dont cleanup /dev/null du harnais, hors périmètre) ; ne pas relancer cette même course à l'identique.

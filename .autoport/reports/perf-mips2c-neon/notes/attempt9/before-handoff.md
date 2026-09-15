## ÉTABLI
DIRECTIVES vaff5c1afea
Essai8 local terminé : cause sample13 attribuée, une correction testée puis rejetée ; aucune livraison.
GDB x86/ARM QEMU exit0 : première différence vmulw.xyz vf11,vf11,vf15 lane z, ordre NaN inversé.
x86 avant401938 ffc00000*7fc12345→ffc00000 ; après401be4 ordre inverse→7fc12345.
ARM avant4013f8 7fc00000*7fc12345→7fc00000 ; après4015fc ordre inverse→7fc12345.
Toutes étapes antérieures concordent ; notes/attempt8/trace/{findings.log,x86.log,arm.log}.
Reproducer nan-order.cpp : six paires,5 différences x86,3 ARM GCC/Clang,aucun NaN normalisé.
Attention : objet moteur x86 complet essai7 n’inverse pas z à ce site ; banc extrait sensible au contexte.
## TENTÉ
Unique correction : publication vf11/vf15 + appel vmul_bc original + reprise r11, reste candidat inchangé.
Comparateur6048 cas identique :343 défauts x86,163 ARM GCC,153 ARM Clang ; trois exit1.
Trois bancs et quatre objets complets compilés exit0 ; tested-manifest.json,codegen intégral dans notes/attempt8.
Symbole3D x864867→5069 octets, Android3740→3852 ; aucune utilité/gain exact démontré.
Candidat rejeté conservé corrected-sparticle.cpp/corrected.patch ; jamais appliqué aux sources livrées.
Moteur sparticle SHA93117b90c7b101bb47373369ef8fcb167b3180ccfcaeb816f83a449f1c36761b inchangé.
Preuve historique/ripple/validateur préservés ; aucun appareil,proof_run,refset,déploiement ou validateur lancé.
## RESTE
Ne pas relancer les candidats essai7/8 inchangés ; le contrat à une correction est épuisé.
La cause sample13 est désormais démontrée ; ne pas refaire sa découverte ni la sélection2D/3D.
Une suite requiert une nouvelle borne explicite à partir de ces résultats ; aucun élargissement effectué.
Trois optimisations actives/références origine qualifiées toujours nécessaires à livraison finale.
non prouvé : gain matériel,parité en jeu600 images,hd-mtx-check-all,replay0,crash/non-régression/fraîcheur.
Preuve.txt reste celle de l’essai1 et ne décrit pas l’essai8 ; dettes complètes dans FINDINGS.txt.

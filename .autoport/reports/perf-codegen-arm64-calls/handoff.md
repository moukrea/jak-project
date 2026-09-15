## ÉTABLI
DIRECTIVES vd321fc8caf
Essai 2 USB eae4df44 : proof.txt frais, frames=5100, crash=0, codegen_lot_defects=1.
47 sites dans 5 marqueurs : tous 2 instructions ; codegen_markers_complete=5.
Capture a2 : 4920 images, 1 échantillon ; rejeu refset maxdiff=61, diffpx=577, compared=1.
Provenance valide, missing/size/decode/provenance_bad=0 ; data=4eabb0fc1e6d0a6c input=f97b073c2df76fb4.
Ancre 901, sample 1081, slip 0 dans les 2 courses ; refset_fixed_tick_armed=0 dans les 2.
libcompiler SHA 85431722c4ebec8056e7370a35180d7119bbaa64f6633c05fa18ccd6952047a3 ; goalc charge cette .so.
libgk md5 a65acc137c3f34e71c77c82f96ff62cc ; pack c7b7c7fbc96ef ; livraison CGO 28/28, textes 23/23.
Encoding 438/247 passe ; NDK oracle mips2c 7 instructions conforme ; CGO 1324 cibles, x86 restauré 28/28.
## TENTÉ
GPR sauvegardés en callee normal Jak1, ADD+BLR aux appels ; autres jeux gardent live-out précédent.
Correction nécessaire du stub mips2c Jak1 : X12 sauvegardé AVANT LDR stack_size, sans changer helper C++.
Symboles dynamiques Jak1 ADRP+LDR/STR (2 instructions) ; 56 fixes X14 (1). asm_funcs/kscheme inchangés.
Capture/rejeu courts via proof_run.sh seulement ; props épinglées, pad neutre réellement chargé.
Référence a2 capturée UNE fois, puis rejeu UNE fois ; le rejeu échoue réellement, aucune cause inventée.
Notes a2/refset-candidate conserve la référence appareil ; logs capture/replay-engine.log.gz et preuves capture.
## RESTE
Diagnostiquer les 577 différences avec traces existantes avant toute nouvelle course ; ne pas recapturer a2.
Les deux courses autorisées de cet essai sont consommées ; aucune campagne additionnelle exécutée.
Une recapture candidate ne prouve pas parité ancien rendu ; état/RNG acteur non restauré par sidecars (log).
Symboles dynamiques 1 instruction : offset connu seulement au chargement ; exige garantie ou relaxation, non implémenté.
Gain goal_busy_ms non prouvé ; stub mips2c interne 4->7 instructions, coût distinct des sites GOAL à 2.
Rapport/FINDINGS renseignés ; generic.sh réservé à l'orchestrateur. Ne pas refaire builds/audits déjà établis.

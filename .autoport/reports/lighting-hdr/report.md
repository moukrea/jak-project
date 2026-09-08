DIRECTIVES ve7fcbe0116
Non validé : hdr_tonemap_defects reste à 4 ; aucun correctif photométrique retenu, rendu33 restauré.
Livré : hdr_batches conserve les échecs partiels quand les blancs OFF manquent ; la provenance nuages exige ALPHA additif et ABE.
Tests hors appareil : 249 réussis ; tests synthétiques, jamais preuve jeu. Aucun critère ni validateur assoupli.
Candidat conversion avant interpolation construit et testé, puis retiré : bénéfice non établi ; sources, binaires et mesures avant/après conservés notes/essai34/.
Lib locale/APK/Redmi restaurée dbc383605d0125ed543accfca9f8f471ecbee83839edf76e8492026700fef8b5 ; APK c03d2cd01b9ba4eb940110d25ae4042dca609ea492a0c0d4de713f26d534967e.
Huit lignes du proof.txt produit par proof_run.sh, agrégat essai34-restored-compatible/20260908T105825-4009021 :
sha=dbc383605d0125ed
crash=0
frames=1740
FEATURE lighting-hdr armed=1 hits=309098
hdr_batch_errors=0
hdr_owner_regressions_measured=0
hdr_owner_regressions_missing=5
hdr_tonemap_defects=4
Agrégat : 2 lots, 5 paires/cellules, 336 cellules manquantes ; défauts courbe/sites/rétrécissement intermédiaire chacun0. Nuages et portail ont des échecs mesurés ; cinq cas restent non qualifiés.
État restauré : ciel36captures/crash0/2040frames ; portail24captures/crash0/1740frames ; 146 sources scellées copiées à l’identique, originaux conservés.
Comparaison candidat/restauré : même configuration78108670, mais résolution dynamique et projection portail variables ; aucune causalité shader précise revendiquée.
Diagnostic modulation unitaire : pré-sprites ON/OFF h12 .372284/.370209, h18 .326578/.324636 ; ROI différente du témoin, ampleur causale non isolée. Ce réglage n’est pas livré.
Premier diagnostic conservé rouge : reserve-root déjà présent, log4733, crash1/captures0 ; son remplacement comporte24captures/crash0 et une absence disque conservée.
Redmi rendu normal : PID24040 stable12s, propriétés debug vides, verrou absent (notes/essai34/portal-modulation-unit-retry/normal-restoration.json).
Retour interrupteur : réglages master/lighting ON, PBR/temps réel OFF ; les campagnes forcent RT1. Le geste menu et son effet en usage normal ne sont pas prouvés.
À regarder dans Options > Recharged : blancs des nuages, éclat du soleil et de l’éco bleue, sol devant la vraie hutte et portail, effet du bouton Lighting après restauration.
non prouvé : correction des cinq cas, attribution du sol, bilan21niveaux×8heures/ciels/intérieurs/hutte, acquis complets, coût GPU du candidat retiré ; HDR natif hors périmètre courant.
Validateur laissé à l’orchestrateur ; aucun jeton owner-ok ni validation owner.

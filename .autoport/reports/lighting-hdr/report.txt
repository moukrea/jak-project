DIRECTIVES ve7fcbe0116
Verdict : HDR non validé, hdr_tonemap_defects=4 ; attributions corrigées et livrées, aucun correctif du rendu établi.
DirectRenderer distingue maintenant les nuages additifs du gradient ; Sprite3 conserve l’union du portail et distingue son disque dans les mêmes lectures GPU.
Build incrémental gk et repack réussis ; lib locale/APK/Redmi SHA256 dbc383605d0125ed543accfca9f8f471ecbee83839edf76e8492026700fef8b5 (notes/essai33/build-deploy/build-deploy.log).
Courbe, exposition et shaders inchangés ; les sources32 restent diagnostic, sans réemploi comme preuve du nouveau binaire.
Preuve officielle proof_run : essai33-compatible/20260908T102706-3974235, deux lots33 copiés identiquement, 146 sources scellées (aggregate-lineage.json).
Huit lignes recopiées de proof.txt :
duration_s=118
crash=0
frames=1800
FEATURE lighting-hdr armed=1 hits=323259
tonemap_sites=1
hdr_batch_pairs=5
hdr_owner_regressions_missing=5
hdr_tonemap_defects=4
Ciel : 36 témoins TBP8096/ALPHA(0,2,0,1,0), aucun gradient8064 ; 36captures/360compositions/crash0 (sky/attribution-check.json).
Nuages h12 ROI[0,0,320,106] : blancs ON92.5/OFF105.17, quasi-blancs270.67/262.83, luma154.365/155.539 (sky/image-region-summary.json).
Soleil h18 : trois composants visibles, blancs/quasi-blancsOFF0 ; région[142,68,178,111], détailON8.558/OFF8.367 ; éclat non jugé.
Portail : région disque native7020pixels identique avant/après sur23/24samples ; sampleONh12-t03 sans fragments, alpha source0, conservé absent (hut-portal/disc-coverage.json).
À18h, luma pondérée des codes avant sprites ON.260116/OFF.319271 ; ajout du groupe dans ROI .046298/.045019 (hut-portal/native-normalized.json).
L’écart existe donc avant les particules et le tone map ; ce constat ne désigne pas encore le terme d’éclairage à corriger.
Sol : candidat asset vil1-jng-leafyground localisé, mais liaison au matériau/ROI du défaut en jeu non établie ; éco29/30 exploité sans nouvelle campagne.
Agrégat : errors0, 5cellules, 336manquantes, ownermeasured0/failed2/missing5 ; absence et échecs restent rouges.
App normale restaurée PID16091 stable12s, propriétés debug vides, verrou absent (restoration-summary.json).
À regarder par l’owner : Options > Recharged, nuages blancs, éclat du soleil, éclairs éco, petites zones devant la vraie hutte et portail.
non prouvé : correction des cinq régressions, bilan21niveaux×8heures/ciels/intérieurs/vraie hutte, acquis complets et HDR natif.
Aucun validateur/owner-ok modifié ; generic non lancé, décision laissée à l’orchestrateur. Handoff et notes conservés.

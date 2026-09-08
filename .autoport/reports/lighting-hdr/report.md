DIRECTIVES ve7fcbe0116
Non validé : le dernier run plante avant capture ; aucune correction photométrique démontrée.
Livré : attribution bornée du soleil et des nuages, réutilisant projections, queries et lectures natives existantes.
Le helper raccorde ces régions aux captures scellées ; il conserve les cas absents, partiels ou échoués en rouge.
Les 210 tests hors appareil passent (notes/essai31/hdr-batches-tests.log) ; ils ne prouvent pas le jeu.
Deux builds incrémentaux : cinq objets puis un objet ; dernière lib build/APK/Redmi SHA243591e44243b084.
Preuve officielle finale (8 lignes recopiées de proof.txt) :
sha=243591e44243b084
crash=1
frames=420
hdr_chain_frames=0
hdr_tonemap_defects=5
hdr_batch_errors=6
hdr_owner_regressions_measured=0
hdr_owner_regressions_missing=5
Lot final essai31-sky-final/20260908T094715-3936986 : 0/36 captures, 11 sources scellées vérifiées.
SIG11 à la frame431 : PC_GOAL0x268920c, LR0x2688e5c, avant la caméra à500m et les nouvelles sondes.
Signature conservée dans notes/essai31/final/gk_crash.txt ; cause non établie.
Avant cette dernière garde : deux lots plage sans crash, chacun24 captures et288 compositions complètes.
Nuages h12, premier lot plage : blanc natif ON5505/OFF5667 ; courbe simulée ON3226,33.
Cette mesure avant décor ne qualifie pas les blancs de la région finale (attribution/attributed-native-summary.json).
Soleil : association exacte, mais disque occulté ; seconde vue :9 rayons passés OFF, aucun ON, sans attribution causale.
La caméra village1 à50m bloquait le chargement VIS ; lot noir conservé, plage ne remplace pas la couverture village1.
Application normale restaurée : PID8102 stable12s, propriétés vides, verrou absent (final/normal-restoration.json).
À regarder par l’owner : Options > Recharged, nuages, éclat du soleil, éclairs éco, sol de la vraie hutte et portail.
non prouvé : correction des cinq régressions, activation de la garde finale, absence de crash en campagne,
couverture21 niveaux×8h/ciels/intérieurs/vraie hutte, acquis complets et HDR natif.
Pas de réglage couleur livré ; générique et owner-ok inchangés. Rapport de reprise : handoff.md.

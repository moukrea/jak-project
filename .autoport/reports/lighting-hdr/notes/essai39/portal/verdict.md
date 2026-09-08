DIRECTIVES v708c60642a
Portail39 : quatre captures sans crash ; lot rejeté car arrêt du producteur avant dernière télémétrie.
Source : batches/essai39-portal-stackfix/20260908T134702-4150835,21fichiers scellés,0hash divergent.
Preuve producteur : durée385s/crash0/frames4500 ; dernier sample lf4503 ; hdr_tonemap_defects2 n'est pas un succès.
REFSET done4captured4 à15:53:13.963 après dernier refset_captured3/refset_temporal_captured3/hdr_paired1 à15:53:13.23.
Le prédicat proof_run utilisait done4 + paired1 déjà publié : coupure prématurée, rejet temporal_capture_accounting_inconsistent.
Attentes repin→capture : ON56.013/111.704s, OFF42.171/84.822s ; âges659/1319 chaque bras (timing-and-witnesses.json).
8témoins portal_disc,4passed ; aucun crash/poolnul. Les réglages/propriétés restaurés exactement (restoration.json).
Disque ROI[147,42,173,79] : ON/OFF blancs28.5/34.5,quasiblancs40/56,luma103.693/130.777,détail25.002/27.618,saturation.4817/.4125.
Ces ROI incluent le fond ; le lot refusé reste diagnostic, pas validation des cinq cas.
Composition native warp-gate (native-summary.json),7020pixels : avant sprites RGB ON(.263528,.242374,.313507),OFF(.373391,.350832,.455406).
Après sprites RGB ON(.435990,.408371,1.346925),OFF(.515725,.485630,.653210) ; déficitRG déjà avant sprites et hausseB différente après.
BlancsON après sprites288.5→tonemap278 ; OFF438.5. Pas d'attribution complète du défaut à la seule courbe.
Aucun réglage artistique/courbe/effet modifié. Source finale du run inchangée ; correctif producteur suivant sans changement binaire.

DIRECTIVES v708c60642a

Reprise essai40 : crashes de chargement et menu ON/retourON acquis39, alpha monde borné40 ; aucun rejeu de ces acquis.
Source nuages : notes/essai39/sky/native-summary.json, h12 ON après dessin, mêmes pixels : blancs1537.5→1117 après simulation du tone map.
Source portail : notes/essai40/portal-final/native-summary.json,7020pixels,avant sprites RG ON(.263163,.242458) contreOFF(.373860,.350957).
La courbe intervient après ces snapshots : elle n'explique pas ce déficit amont ; dessin responsable non attribué, aucune modification d'éclairage supposée.
Le surplus bleu après sprites inclut toutes couches dans bornes du disque, pas contribution isolée. Témoins40 : mode_bits4206765820,blend enum2,Cs*As+Cd.
Les particules ne sont pas identiques entre bras : LF2521 alpha source .831373,LF3843 alpha0 ; âges comparables ne prouvent pas sources identiques.

Candidat livré à mesurer : gfx.h genou.95→.98, formule/exposition/effets inchangés. Le genou ancien a f(1)=.9875,nouveau.995.
Seuil entrée arrondissant au blanc255 :1.030197→1.007476 ; plateau1.05→1.02. La compression moindre peut augmenter clipping/aplats, donc contrôler les deux.
Test shader GPU réel : curve/curve_gpu.log,8001samples/genou,failures0,max_slope_jump.0250936<.05 ; sortie .995 pour entrée1, pas blanc255 garanti.
Ce test n'est ni preuve jeu ni attestation esthétique. Build incrémental unique et deux lots officiels ciel puis portail prévus.

Couverture sémantique inchangée : helper soleil impose encore whiteOFF>0 même lorsque source orange ; ne pas interpréter ce refus seul comme défaut rendu.
Soleil39 composants12/12,white/nearwhite0, lumaON191.997<minOFF192.820 : information existante, non isolée du fond.
Nuages/portail restent partiellement attribués, sol sans ROI runtime, vraie hutte non établie (HUT_VIEWS vide). Aucun absent transformé en réussite.
Éco29/30 conservé en diagnostic, pas répétition négative. Les cinqcas et21niveaux8h restent obligatoires ; une correction partielle ne ferme rien.

Résultat candidat.98 : sky/image-region-summary.json, nuagesh12 ON129.333blancs/OFF105.167,contre91.5ON39 ; excès nouveau, candidat écarté.
La luma reste154.386/155.539 et détail3.776668/3.791984 ; la hausse genou ne corrige pas tout le déficit amont, pas de succès revendiqué.
Un candidat intermédiaire.96 est préparé, formule inchangée, ciel en premier avant autre lot ; pas de balayage de valeurs.

Candidat.96 mesuré ciel : sky96/image-region-summary.json, nuagesh12 blancsON106.667/OFF105.167, enveloppeOFF99..114 ; le défaut white a disparu dans cette ROI.
Quasi-blancs272.833/262.833,détail3.77118/3.79198,aplats.205687/.199378 restent en échec, casnuages toujours nonvalidé. Aucun verdictglobal assoupli.
Soleilh18 luma192.0253/193.1798,blancs/quasi-blancs0/0 ; disque/rayons mesurés, éclat nonqualifié.
Snapshots nuagesh12 : moyenne sourceblancs1537.5 inchangée39→41,simulationtonemap1117→1214 ; quasi-blancssource2087,après2087 pour.96.
Lot96ciel complet36captures/85fichiers scellés,crash0,frames1980,durée234s,hits404636,knee960,curve0,sites1,batcherrors0,defects4.
Sources39/40 restent diagnosticavant ; leurs binaires ne sont jamais comptés comme preuve96. Comparaisons dans before-after.json, sources98 dans before-after98.json.
Deuxprotocoles temporaux incompatibles selon comparaison effective actuelle du helper (6×12 vs2×660), campagnes séparées conservées ; aucune normalisation fabriquée.

DIRECTIVES va841fb32b6
Diagnostic régional livré ; rendu non corrigé dans cet essai, tâche non validée : hdr_tonemap_defects=4.
La capture éco devient une séquence de six images par bras ; le gel des particules est levé uniquement dans ce mode de diagnostic.
Les instances éco/portail sont associées par texture et proximité des ancres, puis leurs fragments et coins projetés sont relevés sur le GPU.
Correction du diagnostic de projection : le w intermédiaire est signé ; les traces appareil confirment camera_w négatif et des régions désormais exploitables.
Le helper mesure les régions avec ImageMagick et conserve les cellules/séquences absentes pour remplacement explicite. Aucun validateur ou seuil qualité modifié.
La courbe de rendu livrée à l’essai23 reste inchangée ; aucune correction artistique des cinq cas n’est revendiquée.
Build incrémental/repack/install rc0 ; MD5 bibliothèque build/APK/Redmi ba3d5711227381380fc9857c70f071b8 (notes/essai24/projection-build/build-deploy.log).
Tests hors appareil : 133 passed, 52.88s (notes/essai24/harness-tests.log) ; ils ne constituent pas une preuve jeu.
Huit lignes exactes de proof.txt :
```text
serial=eae4df44
crash=0
frames=1140
FEATURE lighting-hdr armed=1 hits=253744
tonemap_sites=1
hdr_batch_pairs=4
hdr_owner_regressions_missing=5
hdr_tonemap_defects=4
```
Deux lots officiels : essai24-projected/20260908T060523-3743175 et 20260908T060731-3746070 ; 24 captures chacun, crash=0, quatre paires cumulées, zéro erreur.
Éco10012/10013 : éclairs avec fragments visibles dans 6/6 images de chaque bras à 12h et 18h ; 2867 témoins (notes/essai24/analysis-projected.json).
ROI éco10012 : blancs moyens OFF→ON à midi 89,33→0, à 18h 25→0 ; quasi-blancs 217,83→146,33 et 89,33→109,67.
ROI éco10013 : blancs moyens OFF→ON à midi 15,5→0, à 18h 10→0. Les régions incluent du décor ; conservation des détails lumineux non qualifiée.
Portail : 4707 témoins, 686 requêtes avec fragments visibles ; rectangles [0,0,281,180] et [0,0,277,180], trop étendus pour qualifier localement le violet.
Le lot précédent a planté à la transition vers l’éco : SIGILL frame1143, 24/48 captures. Il reste conservé en diagnostic, sans réutilisation incompatible comme preuve.
AVANT/APRÈS conservés : notes/essai24/before-after-regional.json ; AVANT figé et APRÈS animé, comparaison diagnostique seulement. Binaires précédents préservés.
À regarder après correction dans Options > Recharged : blancs des nuages, éclairs éco, éclat du soleil couchant, petites zones devant la hutte et couleur du portail.
non prouvé : correction des cinq régressions ; nuages, soleil et sol de la hutte toujours sans région sémantique qualifiée ; détail/couleur du portail non qualifiés.
non prouvé : équilibre21niveaux/8h, tous acquis, alpha destination des autres mélanges ; aucune campagne complète reprise avant les cinq cas. HDR natif hors essai.
Redmi relancé normalement, PID31713 stable après12s, 58 propriétés debug vides et aucun verrou (notes/essai24/device-restored.json).
Handoff écrit ; aucun owner-ok, aucun generic exécuté : le validateur reste réservé à l’orchestrateur.

DIRECTIVES v8aed688f73
Lot3vues×8heures achevé sans crash ; qualité finale/couverture totale non validées.
Commande officielle : coverage/run.py, campagne essai43-coverage, timeout600,temporal2,échelle40, aucune ablationB.
duration_s=393
crash=0
frames=3180
hdr_batch_errors=0
hdr_batch_pairs=24
hdr_batch_cells=24
hdr_batch_missing=296
hdr_batch_quality_bad=0
96PNG320x180 : par vue et par bras,2samples pour chacune des heures0,3,6,9,12,15,18,21.
205fichiers scellés SHA256 tous conformes ;96images/pixels.json concordants,manifest errors[].
3vues : training-start(training),jungle-tower(jungleb),village1-out(village1) ;24cellules sur ce lot.
Lib ab2f8019a399c9c1b251714c3f118f8faae1d80e09efd8a52254ac8759e1f6e5
APK 7a4e6c292353b66e9f82e7958e5cc0c8f55a44acba65e1066b7f9624c75a961a
Sources relevées au lancement inchangées ; jak-hd.gc correspond au snapshot du build GOAL déployé.
Mesures pixels entiers ON−OFF moyennes8h :
training luma−5,074811, détail−0,164459, aplats+0,012193, pixels canal écrêté−861.
jungle luma−11,216491, détail−0,898319, aplats+0,029197, pixels canal écrêté+9,8125.
village1 luma−4,617237, détail−0,524221, aplats+0,007173, pixels canal écrêté−604,625.
Ces mesures ne qualifient aucune ROI sol extérieur, vraie hutte ni portail ; caméra candidate et limites dans coverage-view-plan.md.
Qualité publiée : hdr_batch_quality_bad0 mais hdr_tonemap_defects4, owner_missing5, owner_failed1 ; aucun verdict vert final.
Restauration : settings SHA78108670e26658496f33a2a0dc50c45fe16a0f2e59c774ea70499c7fefb52fd6 exact, props vides, PID25268stable12s.
Audit détaillé : audit.json ;24comparaisons images entières : whole-image-cells.json ; aucune preuve réécrite.
non prouvé : couverture21niveaux×8heures/ciels/intérieurs/vraie hutte, cinq cas owner, ombresOFF, Honor.
Aucune relance ni generic.sh ; aucun source/validateur modifié par tester.

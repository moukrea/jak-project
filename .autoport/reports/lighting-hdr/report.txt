DIRECTIVES va841fb32b6
Correctif de courbe livré sur Redmi ; tâche non validée, hdr_tonemap_defects=4 et cinq cas owner non prouvés.
L'épaule C1 s'applique désormais par canal : un canal lumineux n'atténue plus ses voisins ; exposition, genou, Filmique et alpha inchangés.
Le diagnostic de différence au clamp suit cette épaule ; aucun seuil, cumul par lots ou validateur modifié.
Test GPU GLSL réel : (2,1,2) passe de (.997727,.498864,.997727) à (.997727,.975,.997727) ; 27 cas, failures=0 (notes/essai23/curve_gpu.log).
Cette exécution Mesa isole le mécanisme ; elle ne prouve pas les cinq scènes sur appareil.
Build incrémental gk/repack/install réussi ; MD5 build/APK/Redmi 78ed373e74b40a8aa56ccfe28464d083 (notes/essai23/build-deploy.log).
Huit lignes exactes de proof.txt, run officiel 120 secondes :
```text
serial=eae4df44
crash=0
frames=1200
FEATURE lighting-hdr armed=1 hits=672253
tonemap_sites=1
hdr_batch_pairs=4
hdr_owner_regressions_missing=5
hdr_tonemap_defects=4
```
Lot APRÈS : batches/essai23-channel/20260908T053521-3717470 ; quatre paires, deux cellules niveau/heure, zéro erreur de lot, aucun LOADSCREEN-SHOW.
Comparaison ImageMagick AVANT/APRÈS avec hashes vérifiés : notes/essai23/after-analysis.json ; sources AVANT essai22-alpha et binaires conservés.
Extérieur village1 h12 : quasi-blancs ON 0→1264, OFF1340 ; blancs exacts ON toujours0, OFF768. Luma ON123,474→128,986, OFF133,197.
Ces statistiques portent sur l'image entière : ni les nuages, ni le soleil, ni les petites régions du sol ou du portail ne sont identifiés par ces chiffres.
Les données donnent des ancres portail/éco ; aucune présence effectivement rendue dans une ROI n'est mesurée. Le refset actuel fige les particules et ne produit aucune séquence éco.
À regarder dans Options > Recharged : nuages blancs, éclairs éco bleue, éclat du soleil couchant, sol devant la hutte du Sage vert, blancs et couleur du portail.
La courbe rapproche certaines hautes lumières colorées du blanc ; leur couleur attendue reste à juger localement (contre-exemple GPU dans diagnostic.md).
non prouvé : correction des cinq régressions, blancs voulus conservés par région, séquence électrique, tous acquis et alpha des autres mélanges accumulatifs.
non prouvé : équilibre21niveaux/8h du nouveau binaire ; campagne complète non reprise avant qualification des cinq cas prioritaires. Sortie HDR native hors essai.
La garde des cas absents reste rouge ; anciens lots conservés pour diagnostic, aucune réutilisation incompatible comme preuve.
Redmi relancé, PID24706, propriétés debug vides et verrou absent (notes/essai23/device-restored.json). Aucun owner-ok ; generic réservé à l'orchestrateur.

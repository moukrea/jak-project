DIRECTIVES v6133a247b4
Non validé : les blancs éco reviennent partiellement, mais le cas mesuré échoue et quatre cas restent non jugés.
Épaule SDR quadratique C1 à blanc fini dans tonemap.frag et miroir hdr.cpp ; exposition/alpha inchangés.
Ce correctif reste expérimental : son plateau peut aplatir les hautes lumières ; aucun effet artistique ajouté.
owner_regressions juge maintenant les séquences éco : mesure, échec et réussite distincts ; absences/doublons/remplacements protégés.
Preuve officielle, lot essai25-finite-white/20260908T063147-3766137, huit lignes recopiées :
```text
crash=0
frames=1140
FEATURE lighting-hdr armed=1 hits=271323
tonemap_draws=388
tonemap_sites=1
hdr_owner_regressions_measured=1
hdr_owner_regressions_failed=1
hdr_tonemap_defects=4
```
Comparaison ImageMagick, rectangles AVANT/APRÈS identiques : notes/essai25/before-after-regions.json.
Éco10012 à12h : blancs ON0→56,67, OFF88,67 ; quasi-blancs ON146,33→155,83, OFF217,17.
À18h : blancs ON41,67/OFF25,5 ; excès global clipped75 après tolérance existante, donc aucun succès qualité.
Le lot précédent a planté avant captures dans intern_from_c ; ses deux cellules sont remplacées explicitement, sources conservées.
158 tests harnais passent ; GPU hors appareil8001échantillons de courbe et27cas, zéro échec ; ces tests ne valent pas preuve jeu.
Build incrémental/repack/install réussis, bibliothèque build/APK/Redmi MD5 4040690090e5b5aa4a3989dc2c78d124.
Redmi restauré normal : PID6459 stable12s, swap1200,58propriétés debug vides, aucun verrou (device-restored.json).
À regarder par l'owner, Options > Recharged : éclairs éco midi/soir, nuages, éclat du soleil, petites zones devant vraie hutte et portail.
non prouvé : correction complète éco, nuages/soleil/sol/portail, tous acquis, équilibre21niveaux×8h et sortie HDR native.
Campagne complète non lancée : le scope la place après les corrections ciblées encore en échec ; aucun owner-ok ni appel generic.
Reprise technique détaillée dans handoff.md ; notes/essai25/diagnostic.md conserve les limites et le transitoire des particules.

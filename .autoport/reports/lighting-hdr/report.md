DIRECTIVES v6133a247b4
Verdict : correctif livré sur Redmi, mais lighting-hdr reste non validé (hdr_tonemap_defects=4).
Quatre shaders Direct bornent maintenant les couleurs source legacy après texture/brouillard, avant blend ; destination HDR, alpha, courbe et exposition inchangés.
La sonde existante projette le disque 3D harddot du portail ; le helper sépare sa région et conserve les défauts partiels sans valider le portail entier.
GPU synthétique : 162 PASS/0 FAIL, dont 48 comparaisons SDR exactes ; helper : 189 tests passés. Ce ne sont pas des preuves jeu.
Build/APK/Redmi : lib SHA256 d3a7658defe4286424968852bb7e4ac87e68eb9c20d6c1960687f0bf7a66047f.
Deux lots officiels : 48 captures, aucun crash ; agrégat 4 paires, errors=0, aucun des cinq cas owner réussi.
Preuve produite par proof_run.sh, huit lignes recopiées :
```
source=device
sha=d3a7658defe42864
crash=0
frames=1140
FEATURE lighting-hdr armed=1 hits=253928
tonemap_sites=1
hdr_owner_regressions_failed=2
hdr_tonemap_defects=4
```
Éco10012 à18h : blancs ON14,67/OFF65,83 ; avant26 ON14,83/OFF65,5. Le correctif Direct ne résout pas la perte lumineuse.
Portail : disque visible23/24 captures ; à18h aplats ON0,06061 > OFFmax0,04978. Défaut partiel conservé malgré blancs OFF=0 ; couleur/halos non qualifiés.
Agrégation seule après jugement : 122 fichiers scellés et date originale intacts ; sources avant24/26 et après27 conservées sous notes/essai27/.
Redmi restauré : PID17645 stable12s, A35-RENDER frame360/draws88, propriétés debug vides et verrou absent (normal-restoration.json).
Owner : Options > Recharged ; vérifier éclairs éco, nuages blancs, soleil couchant, sol devant vraie hutte Sage vert et portail.
non prouvé : correction des cinq régressions, acquis complets, couverture21niveaux×8heures/ciels/intérieurs/vraie hutte, HDR natif. Campagne complète reste après corrections ciblées.
Le validateur est laissé à l’orchestrateur ; aucun owner-ok écrit. Reprise détaillée dans handoff.md.

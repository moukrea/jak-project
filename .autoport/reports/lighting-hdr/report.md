Essai35 non abouti : livraison d’entrée restaurée, aucun correctif de rendu conservé ; critère machine non satisfait.
DIRECTIVES ve7fcbe0116
Le raccordement du menu au champ RT a été essayé puis retiré ; le bridge lit toujours le sélecteur legacy caché.
Le candidat de neutralisation scissor/stencil/cull/colorMask au composite a aussi été retiré.
Une compilation GOAL et une compilation C++ incrémentale ; aucun réglage de courbe retenu.
Diagnostic : les lots sky-fixed/sky-normal/sky-shadow-off/sky-composite contiennent respectivement 24/24/4/24 captures achromatiques (leurs summary.json).
La source 3D reste colorée après sprites : sky-fixed lf1601 RGB moyen(.978299,.762801,.759622) ; rupture ultérieure non attribuée.
Le protocole raccourci omettait h9 présent en34 : absence de référence identique avant candidat, donc aucune causalité attribuée au raccordement.
Preuve officielle de l’état restauré, proof_run.sh device --timeout65, started_at=2026-09-08T11:57:06Z :
```
source=device
sha=dbc383605d0125ed
crash=0
frames=720
FEATURE lighting-hdr armed=1 hits=6711
tonemap_draws=720
hdr_owner_regressions_missing=5
hdr_tonemap_defects=5
```
Identités restaurées : lib dbc38360…, APK c03d2cd0…, GAME ca2b90ba…, ENGINE2080b539… (notes/essai35/restore-entry/restored-identity.json).
Usage normal rétabli : PID4776 stable12s, debug vides, verrou absent ; settings SHA78108670… identique (restored-proof/normal-restoration-summary.json).
L’owner devra regarder les nuages blancs, l’éclat du soleil, les éclairs éco, le sol de la vraie hutte et le portail après au moins10s ; aucune nouvelle amélioration annoncée.
non prouvé : correction des cinq régressions, équilibre21niveaux×8h/ciels/intérieurs/hutte, acquis, geste du menu, sortie HDR native.
Pas de campagne finale : les corrections ne sont pas établies ; lots incompatibles conservés comme diagnostic, jamais additionnés en verdict.
Aucun generic exécuté, aucune validation owner. Détails et reprise dans notes/essai35/diagnostic.md et handoff.md.

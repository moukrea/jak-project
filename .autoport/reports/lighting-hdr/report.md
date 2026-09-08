DIRECTIVES v6133a247b4
Non abouti : perte éco reproduite sans chaîne HDR ; aucun correctif rendu livré, porte à 4 défauts.
Aucun changement jeu/harnais ni build ; diagnostic uniquement, une ablation appareil par proof_run.
Binaire build/APK/Redmi inchangé : 4da80ef748d4b54c5e916a1205bc00259b3d8941339900d2dc072ad99e8dfdda.
Lot diagnostic29 20260908T083423-3872799 : HDRfalse24/24, hdr_chain_frames0, crash0, frames1200.
Source : notes/essai29/hdr-disabled-analysis.json, proof-hdr-disabled.txt ; rejet HDR conservé, lot séparé.
Éco10012 h18 natif après sprites : état28 ON553,83/OFF1149,67 ; ablation29 ON543,67/OFF1148,33.
ROI finale commune : blancs HDR ON14,5/OFF64,83 ; ablation ON8,67/OFF65,67. Le déficit persiste sans tone map.
compare-ablation.py : 61+61 fichiers scellés intacts, 4188 événements sprites par run identiques horslf sur24cas.
Identité limitée aux champs journalisés entre état et ablation ; aucune identité ON/OFF/pixels requise.
Les populations ON/OFF diffèrent : éco10012 h18 sprites visibles239/265 ; fond et recouvrements restent mélangés.
Aucune cause locale corrigible établie ; clamps/quantification/courbe ne sont pas retouchés sans cette attribution.
Distort : piste alpha retirée après vérification du swizzle GL_ONE déjà présent ; aucun correctif redondant.
Preuve livrée réémise par proof_run aggregate-only du lot28 compatible ; timestamp original, pas nouveau run livré.
Huit lignes recopiées du proof.txt produit officiellement :
```
crash=0
frames=1140
tonemap_draws=390
tonemap_sites=1
hdr_batch_errors=0
hdr_batch_pairs=2
hdr_owner_regressions_passed=0
hdr_tonemap_defects=4
```
Redmi normal restauré PID25963 stable12s, propriétés debug vides, verrou absent : normal-restoration.json.
Owner : Options > Recharged ; vérifier nuages blancs, éclairs éco, soleil couchant, sol vraie hutte Sage vert, portail.
non prouvé : correction des cinq régressions, contribution individuelle des effets, acquis complets, HDR natif.
non prouvé : couverture21niveaux×8h/ciels/intérieurs/vraie hutte ; campagne complète conditionnée aux corrections non acquises.
Notes : notes/essai29/ ; sources24/27/28/29 conservées. Aucun generic exécuté, aucun owner-ok créé.

## ÉTABLI
DIRECTIVES v1707e53cb2
Preuve USB fraîche : serial=eae4df44, sha=fc08e6e1b73d8b9b, frames=2520, crash=0, soft_baseline_gaps=0.
37 îlots attribués géométriquement, 25 niveaux, références census exactes après arrondi, quatre densités et quatre coûts R16 par cible.
Snapshot indivisible par image : 2520, 19 systèmes, aucun draw manquant dans cette publication.
## TENTÉ
Le premier banc USB refusait une erreur GL 1282 antérieure ; frontière bornée corrigée, code R16 identique entre cibles vérifié par SHA.
La revue finale a corrigé la publication par image susceptible de mélanger deux frames ; nouvelle preuve USB produite après rebuild.
Le census complet dépasse 200 µs, voir notes/counter-costs.json ; aucun chiffre de coût vert revendiqué.
## RESTE
L’orchestrateur doit lancer le validateur ; le worker ne le lance pas.
Réduire le coût du census pour tenir le plafond de 200 µs ; les limites sont dans FINDINGS.txt.
Extrema continus et provenance sérialisée non prouvés : mesures de centroïdes et attribution géométrique explicitement documentées.

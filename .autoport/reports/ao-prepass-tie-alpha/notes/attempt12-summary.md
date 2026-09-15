DIRECTIVES v775512c234
# Essai12 — reconstruction retirée ; raccord non corrigé

## Résultat livré
Le shader conserve le noyau centré de l'essai10 et le ridge historique. L'enveloppe concave
ajoutée à l'essai11 est retirée : elle masque le premier pixel sans supprimer le pic secondaire,
et sa propagation hors raccord n'est pas justifiée. Aucun rendu TIE, alpha, shrub ou ordonnanceur
modifié. La causalité alpha reste dans alpha-table.tsv ; aucun nouvel audit alpha.
Le défaut owner reste ouvert. Aucun résultat appareil courant, aucun proof_run, aucun APK/install.

## Contrôle complémentaire avant les variantes
`attempt12-analyze.py` reprend les425pixels/15contacts du JSON, la qualification physique
`crosses_segment` existante, les9échantillons maximum et le seuil strict>4. Verdict natif recopié
sans modification. Les profils complets, minima, dépassements sur toute fenêtre et descentes
ultérieures sont publiés séparément ; une remontée intérieure naturelle n'est pas un défaut établi.
Manquants/censurés restent null, jamais zéro. Autotests133,138,135 et130,130,138,138,130 passent.
Essai11 : SSAO conserve3échantillons avec descente ultérieure>4, GTAO1 ; HBAO1manquant+1censuré.
Au mur100,550 : SSAO133,138,135,133,131,130,130,131,132 ; indices1/2 restent rouges.
Hors425 :11551/10769/11105pixels changés SSAO/HBAO/GTAO, dont5327/4995/5164 classés localement plans.
Classes calculées sur profondeur complète : ciel/plan/concave/convexe/autre ; ce sont des proxies,
pas des identités physiques horsROI. Une innocuité sémantique ne peut en être déduite.
Les4passes de ridge amplifient le changement : maximum SSAO61octets au(457,163), loin de la hutte.
Le retrait supprime cette contribution, sans prétendre réparer les défauts de la référence.

## Trois variantes locales conservées et rejetées
Toutes repartent du flou centré/ridge antérieur, sans enveloppe11, sur mêmes entrées Intel/Mesa.
| Variante | Préfixes SSAO/HBAO/GTAO | Échantillons avec descente ultérieure>4 | Pixels modifiés |
|---|---|---|---|
| Référence/livré12 |12/2/7|12/2/7|0/0/0|
| Réflexion à l'intersection de deux plans |26/7/25|26/7/27|79336/68022/70790|
| Rayon réduit avec plans aux extrémités |65/29/68|67/41/68|85889/91480/84180|
| Recherche locale du pli dans le support du flou |3/8/9|4/10/9|148678/158806/152063|
La réflexion ne suffit pas : diffusion sur le même côté et mélange entre côtés contribuent.
La prédiction par deux plans sur tout le support rate les changements de surface proches.
La recherche locale réduit100,550 à SSAO[67,74,79,74,85,97,99,97,106], mais assombrit jusqu'à203octets
ailleurs et laisse davantage de bandes HBAO/GTAO. Ni cette seule amélioration ni son préfixe ne valent succès.
Sources et résultats détaillés : attempt12-{reflect,contract,ray}.frag, attempt11-a12-*/summary.json,
attempt12-*-full-diagnostic.json, masques NPZ complets et attempt12-comparison.json.

## Phases — cas où le nouveau filtre est réellement actif
Le banc `attempt12-fold-phases.cpp` reprend le fixture EGL/chaîne d'attempt11-invariants.cpp.
Deux plans concaves fixes,16translations du même motif4x4 ; même pilote, formatsR8/R32F.
La variante ray passe les16témoins plans/ciel/silhouette existants mais échoue au pli :
R8 range0.109803915024 (~28octets) contre0 référence ; R32F0.109219610691 contre7.7486038208e-7.
Réduire le rayon normal détruit ici l'annulation des phases. Ne pas réintroduire cette variante.
L'état livré reproduit la référence au pli : R8range0, R32F7.7486038208e-7 pour les deux.
Logs : attempt12-{ray,delivery}-fold-phases.log. Ce test synthétique ne prouve pas la géométrie appareil.

## Livraison et limites
Compilation GLSL410/GLES,16témoins existants, build arm64 incrémental : exit0.
Les36sorties complètes (8blur+4ridge ×3modes) sont bit-identiques à la référence pré11 sur ce pilote.
Native final : SSAO12/max3, HBAO2/max1, GTAO7/max2 ; chaque mode29valides+1manquant,0censuré.
Le retrait rétablit donc les défauts pré11 explicitement ; aucune correction complète revendiquée.
Source9bda9d04174d8256, libgk4d0bb4978ac9f9b6 ; payload GLES complet présent dans blob etlib, offset1992232.
Commandes/codes/empreintes : attempt12-build-delivery.json. Silhouette synthétique ~0.502 préexistante.
non prouvé : raccord corrigé, couleur OFF, troisvues, acquis/stabilité/qualité/performance sur appareil.
Budgets9/9 et6/6 clos. Validateur laissé à l'orchestrateur. Aucun verdict owner.

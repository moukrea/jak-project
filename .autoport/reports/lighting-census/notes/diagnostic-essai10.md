# Diagnostic — essai 10
DIRECTIVES v6fca51fe40

## Périmètre et corrections
Reprise des mesures8/9, sans nouvelle tournée de cadrages ni modification des origines.
Le producteur construit le préfixe historique564 et les108 compléments en suffixe.
Les six masques historiques restent h09/h21 : misty-bike, village2-dock,
sunkenb-helix, swamp-start, swamp-cave1, snow-fort. Chaque cas est nommé dans le log.
Les compléments utilisent exclusivement supplement-v1/<jeu>/<cas>.png ; pas de repli
sur les huit anciens fichiers hors capture complète. Les futures captures neuves
réservent ces dossiers et des témoins propres. Provenance complète non encore contrôlée.
La frame DMA est copiée sous mutex à l'acquisition ; une soumission refusée ne peut
plus écraser son identité. Les horloges renderer x86 lisent cette copie ; Android inchangé.
Il reste des états accumulés (acteurs, vent filtré, particules, contacts/trail herbe).
Le suffixe ne prétend donc pas rendre chaque cas indépendant d'un état initial complet.

## Attribution
Diagnostic explicite OG_REFSET_TRACE_ROI=1, limité aux24 premières captures refset.
Lectures avant/après buckets Jak1 et draws Merc2, région x285..315,y13..72.
Couleur lue sans retrait de draw, masque d'image, tolérance ou verdict visuel.
RGBA8 et HDR float x86 ; cibles multisample/default invalides ignorées.
Les temps GPU de cette course incluent les synchronisations de ces lectures ponctuelles.
Un draw écrivant la région est un candidat attribué au rendu, pas à lui seul une cause
prouvée de la divergence par rapport à une référence.

## Sunkenb — recherche native lecture seule
Les conditions de rendu sont drawable.gc:819–839 : masque sky, context.sky et *sky-drawn*.
context.sky provient du OR des drapeaux actifs (time-of-day.gc:191–202).
sunken=#f et sunkenb=#t ; seul ciel actif => poids1 dans sky-tng.gc:904.
copy-sky-texture pose *sky-drawn* (sky-tng.gc:868) pour l'image suivante.
Pas de désactivation spécifique à la profondeur identifiée dans ce chemin.
Les traces existantes ne donnent pas ces booléens ni les paquets ciel effectifs
pour les cadrages à0‰ : aucun occulteur attribué, aucun nouveau cadrage justifié.
0‰ est arrondi et ne signifie pas nécessairement zéro pixel de fond.
L'émersion recharge village2 avant la sortie : elle ne qualifie pas sunkenb.
Conserver les8 manques ; visibilité admissible non prouvée.

## Vérification
Revue native de la séparation des cas et du transfert DMA : aucun défaut bloquant trouvé.
Compilation incrémentale code0 ; unique preuve150s code0, crash0, frames8363.
SHA moteur43ce233c4be6e229 ;575/575 références inchangées, daemon2541075 repris Ss.
Aucun generic.sh lancé : jugement laissé à l'orchestrateur. Aucun appareil touché.

## Résultats nouveaux d'exécution
Le log runtime contient672 lignes REFSET case : indices0..671, préfixe564 exactement
égal aux noms/ordre REFSET cap du log historique, suffixe108 unique et disjoint.
Les24 PNG legacy ont le même SHA que l'essai9. Le correctif DMA n'a donc pas changé
leurs pixels dans cette course ; il ne suffit pas à corriger le défaut historique.
Origine/h00 reste maxdiff202/diffpx794. Le calcul RGB via le chargeur existant
.autoport/tools/refset_compare.py donne zéro pixel divergent hors ROI sur les24 PNG
(ecarts-legacy-essai10.txt). Aucun pixel n'est masqué dans la comparaison du moteur.
REFSET-ROI capture1 : modèle hutlamp-lod0, hash b872b73f9b7e5d2e.
Draw34395/texture429 :590 pixels, bbox288,43,314,67.
Draw34488/texture430 :117 pixels, bbox292,38,310,72.
Draw34583/texture431 :58 pixels, bbox300,13,308,37.
Bucket52 l1-pris-merc :765 pixels, bbox288,13,314,72.
Ce sont les seuls draws Merc modifiant cette ROI à la capture1 ; les buckets sky/tfrag/tie
y écrivent aussi auparavant. L'attribution établit la présence de la lampe dans la région.
Le diagnostic compare RGBA alors que le PNG impose alpha255 ; séparer RGB/alpha est
nécessaire pour une attribution RGB stricte. Les compteurs ne ferment aucune porte.
La cause de phase reste à établir : village-obs.gc:765–766 initialise clock.output
avec rand-vu ; :727–730 accumule inc*time-adjust-ratio ; :755–756 transforme joint3.
Le réancrage existant ne restaure que les particules, pas l'état de cet acteur.
Aucune trace historique de clock.output retrouvée : réinitialiser à une valeur arbitraire
ou figer la lampe ne permettrait pas de revendiquer l'identité avec les origines.

## Limites de livraison
37/672 comparaisons ; refset_replay_maxdiff254, census_replay_runs0, coverage_missing244.
Draws total3427130/residual0/rb_mismatch0 ; gpu_ms_buckets7.5422 avec diagnostic activé.
Aucun correctif spéculatif de lampe, aucune référence complémentaire fabriquée,
aucun rejeu supplémentaire : la preuve économique reste unique et courte.
Le contrôle de provenance des futurs témoins supplement-v1 reste à compléter ; aucun
complément n'est adopté et les huit fichiers préexistants n'ont aucun repli automatique.
Non prouvé : phase historique de lampe, état indépendant par cas, bit-identité564,
108 nouvelles références, cinq rejeux exacts, couverture actuelle complète, ciel sunkenb,
non-régression globale et qualité HDR. Aucun verdict owner émis.

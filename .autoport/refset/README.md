# Références de lighting-census

Trois jeux sont comparés par le moteur, octet par octet :

| Répertoire | Configuration |
|---|---|
| `origine/` | master OFF : ORIGINE-TOTAL |
| `origine-lumiere/` | master ON, éclairage OFF : ORIGINE-LUMIÈRE |
| `recharged/` | master ON, éclairage ON : RECHARGED |

Les deux origines sont immuables. Un écart est à diagnostiquer ; recapturer par-dessus
ne constitue pas une correction. Le mode capture réserve un **répertoire neuf** et
refuse une destination existante, même vide ou symbolique. Le lanceur prépare un
candidat sous `.autoport/refset-candidates/`, sans l’adopter.

## Plan et état des références

Le plan est défini par `kVantages` dans `game/graphics/refset.cpp` : 28 vues × huit
heures fixes (0, 3, 6, 9, 12, 15, 18, 21) × trois jeux = 672 étapes.
Le producteur construit deux blocs : les 564 étapes historiques, dans leur ordre
initial, puis les 108 heures complémentaires des six vues auparavant à h09/h21.
Chaque ligne `REFSET case` nomme l'index, le bloc et le cas ; `REFSET sample` donne
la frame de chaîne effectivement capturée et son ancre de téléport.

**Les références présentes ne couvrent pas encore ce plan.** La dernière capture
complète journalisée contient 564 étapes (`refset-capture.log`, ligne `REFSET done`).
Les différences de couverture sont listées dans
`../reports/lighting-census/notes/references-manquantes-essai7.txt` et
`references-hors-derniere-capture-essai7.txt`. Un fichier présent ne suffit pas à
établir sa provenance dans cette capture.

Les compléments se lisent exclusivement sous `supplement-v1/<jeu>/` : les huit
anciens PNG hors capture complète ne servent pas de repli. Aucune référence
supplémentaire n'est encore établie. Une future capture neuve réserve aussi ces
trois répertoires et y écrit leurs propres témoins de binaire ; cela ne constitue
pas encore un contrôle complet de leur provenance.

Le suffixe évite d'insérer des heures au milieu du parcours historique. Sur x86,
les horloges utilisées par le renderer lisent désormais l'identité transportée
avec la chaîne DMA, sous verrou à son acquisition. Ces corrections ne prouvent
ni la bit-identité avec les origines, ni l'indépendance complète par cas : les
acteurs, particules et filtres conservent encore des états accumulés.

Le log historique publie 21 niveaux et 13 vues intérieures, avec huit couples
ciel/heure manquants pour `sunkenb` (`refset-capture.log:1232952`, `:1232954`,
`:1233165`). Il ne prouve ni la couverture actuelle ni cinq rejeux exacts.
Le 22e niveau jouable du contrat n’est pas identifié dans les données livrées :
l’index 22 désigne `intro`. `halfpipe` et `test-zone` ne disposent pas de DGO ici.

## Grandeurs et limites

`refset_sky_levels` vient du drapeau `level-load-info.sky` transmis par le pont GOAL
pour les niveaux actifs. `make-sky-textures` consulte ce drapeau pour contribuer au
ciel global ; il ne suffit pas à prouver que du ciel est visible dans une vue.

La sonde relit le tampon de profondeur après le monde 3D. Les pixels restés à la
valeur d’effacement sont comptés comme arrière-plan ; ce n’est pas une attribution
individuelle des pixels au shader de ciel. `refset_sky_missing` exige une fraction
d’au moins 150 pour mille dans chaque couple niveau à ciel/heure. Les valeurs brutes
et les manques restent publiés ; `sunkenb` n’est pas retiré parce que ses vues échouent.

Le moteur compare les images ; `proof_run.sh` seul écrit `proof.txt`.
`refset_replay_maxdiff=254` indique une condition incomplète ; 255 peut signaler une
référence manquante ou un écart réel maximal. Les lignes `REFSET cmp` donnent les
écarts des comparaisons déjà faites. Une course partielle ne certifie aucun tour.
Le registre exige cinq courses complètes de couverture qualifiée pour cette tâche,
avec les empreintes du binaire, des références, des données et de la configuration.

Les images réelles présentant un écart sont enregistrées dans
`../reports/lighting-census/refset-actual/`. Leur comparaison numérique hors ligne
sert au diagnostic ; ces fichiers peuvent provenir de courses différentes, donc
il faut les apparier au log avant d’en tirer une conclusion.

## Exécution

La preuve autorisée passe par :

```bash
bash .autoport/lib/proof_run.sh lighting-census x86 --timeout 150
```

Ce plafond court produit une preuve partielle honnête. Avec les attentes actuelles,
un tour complet demande au moins 137760 frames, soit 38 min 16 s à 60 Hz avant
surcoûts ; ne pas multiplier les tours tant que les premiers écarts sont inexpliqués.
`OG_REFSET_VANTAGES=legacy` reste réservé aux sous-plans historiques des autres items ;
il ne satisfait pas la couverture de lighting-census.

Pour les usages de capture/rejeu autorisés, `lib/refset.sh capture|replay` accepte
`REFSET_DIR` et un plafond en secondes comme deuxième argument. La capture produit
un candidat neuf. Le replay utilise `.autoport/refset` par défaut.
Le lanceur prend un verrou avec PID et nettoyage ; ne pas mesurer pendant qu’un
constructeur réécrit `out/jak1/iso`.

Les références x86 et Android restent séparées. La sonde de couverture de scène
est actuellement dans le renderer x86. Le régime de modèles dépend du choix pris
au chargement : les compteurs `hd_fr3_stock` et `hd_fr3_enhanced` doivent être lus ;
la bascule du master seule ne prouve pas la substitution des modèles déjà chargés.

## Attribution ciblée des écarts

`OG_REFSET_TRACE_ROI=1` active des lectures avant/après buckets Jak1 et draws Merc2
sur les 24 premières captures du parcours. La région examinée est x285..315,
y13..72 en coordonnées 320×180 depuis le haut. Les lignes `REFSET-ROI` rapportent
les pixels écrits dans cette région et la correspondance modèle/hash ; elles ne
changent ni les pixels comparés ni les seuils. Un draw qui écrit dans la région
n'est pas à lui seul la preuve qu'il produit l'écart avec l'origine.

Les cibles multisample, invalides ou le framebuffer par défaut sont ignorés ;
les changements de cible sont signalés. Le HDR float est lu sur x86. Les temps
GPU d'une course portant ce diagnostic incluent le coût de ses synchronisations
ponctuelles : ne pas les présenter comme une mesure de performance normale.

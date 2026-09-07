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
heures fixes (0, 3, 6, 9, 12, 15, 18, 21) × trois jeux = 672 étapes. Les intérieurs
supplémentaires suivent désormais les huit heures également.

**Les références présentes ne couvrent pas encore ce plan.** La dernière capture
complète journalisée contient 564 étapes (`refset-capture.log`, ligne `REFSET done`).
Les différences de couverture sont listées dans
`../reports/lighting-census/notes/references-manquantes-essai7.txt` et
`references-hors-derniere-capture-essai7.txt`. Un fichier présent ne suffit pas à
établir sa provenance dans cette capture.

L’ajout d’étapes intermédiaires décale aussi les instants des vues suivantes.
Les horloges vent/herbe utilisent la frame logique absolue : conserver le même nom
de PNG n’établit donc pas la compatibilité entre les deux plans.

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

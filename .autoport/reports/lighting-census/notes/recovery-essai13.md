# Récupération des références — essai 13
DIRECTIVES v6fca51fe40

## Identités et archives mesurées

`legacy-check-before-13.log` contrôle les 575 entrées du manifeste essai12 :
572 PNG et trois `captured-by.txt`, tous SHA256 identiques. Le nombre « 575 références »
des anciens handoffs comptait donc aussi ces trois témoins.
`essai12-avant13/` conserve preuve, log et handoff avant le run courant.
Les images et les écarts historiques ne sont ni remplacés ni adoptés dans le candidat.

`baseline-identities-essai13.json` relève le clone propre
`/home/emeric/code/jak-original-v033` au commit
`c4bc4d3ff4691902ff023319cb33df71c0040501`, ainsi que son exécutable SHA256
`2801189bff17a731e2697971deccd224a590d902ee54c0b28eb9eb0955fde38a`.
Cette baseline source est indépendante ; son binaire n'a pas exécuté le protocole courant.
Le même relevé trouve GAME.CGO, ENGINE.CGO et GAME.fr3 différents entre les deux arbres,
mais SUB.DGO identique. Leurs données par défaut ne constituent donc pas un bras identique.

L'identifiant historique `485f09d6c07bc24c` est le FNV64 de l'exécutable
(`self_fingerprint`/`hash_file` dans refset.cpp), pas un SHA de commit.
Le log `.autoport/refset/refset-capture.log:2` annonce `c61aab58ba` ; l'état sale
du producteur et son binaire exact ne sont pas reconstitués par cette seule ligne.
Le témoin `gk-origin-ablate`, SHA256 `57cd788728f9c2b640cb347a9912eeaaa8f1328599537ab529c3c3f95064894c`,
conserve des changements communs GOAL/GLSL/police : ce n'est pas le clone pristine.

## Changement de production et limites

Le patch refset.cpp introduit des sidecars v2 pour chaque image candidate : case,
config du plan, binaire FNV, flavour, PNG FNV, frame logique, données FNV et input FNV.
Le marqueur racine distingue ce format sans renommer ni modifier les historiques.
Une catégorie CGO/DGO/FR3 absente ou illisible invalide l'empreinte des données ;
les noms incluent iso/fr3/enhanced pour distinguer les homonymes.
Ce changement d'algorithme invalide les anciennes clés data des registres v1 ; les lignes
restent archivées, mais leurs anciens crédits ne sont pas reconduits avec cette nouvelle clé.
Les empreintes au démarrage ne constituent pas une surveillance des mutations pendant le run.
L'entrée identifiée est le fichier configuré, pas les octets internes déjà chargés dans pad_replay.
Le manifest source/diff du script est une provenance de laboratoire, pas un contrôle moteur
de toutes les sources/configurations externes. Cette partie reste à compléter.
L'état des acteurs et la qualification baseline sont absents : v2 garde census=0 et la
sentinelle 254 de qualification, même si des autorejeux sont exacts. Les écarts bruts restent publiés.

## Ce qui manque au protocole d'état

Audit source : pad_replay expose reseed et dump, aucun restore. La sauvegarde game-save.gc
porte la progression/permanence, pas les processus vivants et registres RNG.
`level_warp_run` appelle start puis reseed ; start recrée Jak, pas les acteurs résidents.
Le point de naissance pertinent est l'appel actors-update dans drawable.gc:928.
`reset-actors` dans entity.gc:966 modifie permanences et quotas : ce n'est pas un restore.
Il faut une frontière commune avant naissance, après chargement terminé, avec inventaire
des acteurs/permanences, horloges, RNG, visibilité/caméra et ordre des pas enregistrés/rejoués.
Le clone pristine ne possède pas les crochets OG_REFSET/OG_PAD_REPLAY/OG_LEVEL_WARP.
L'adaptation commune et la compatibilité des mêmes données restent à implémenter/mesurer.
Un reseed ponctuel, un gel supplémentaire ou le replay du seul candidat ne remplace pas cela.

Sunkenb demeure manquant : ressources établies essai12, visibilité effective non démontrée.
Pas de nouvelle calibration ni cinq runs d'un candidat déjà non qualifiable.
La correction HDR/tonemap SDR n'est pas livrée par cet essai.

## Arrêt du harnais

Le commit superviseur 41654a34b3 combine maintenant échec normalisé et contenu des sources
dans fingerprint_failure. `forensics-essai13.log` : neuf tests passent, dont
test_stuck_requires_same_failure_on_same_implementation. Aucun patch supplémentaire du
harnais ni modification de generic.sh dans cet essai ; le validateur revient à l'orchestrateur.

## Mesure finale

`summary-essai13.json` : crash0, 8510frames, 37/672 comparaisons, porte254,
575 SHA historiques OK et 0 GL_INVALID_OPERATION. `legacy-diffs-comparison-essai13.json`
compare les 37 grandeurs par cas : identiques à essai12 (diffpx total52907, origine/h00 maxdiff202).
`shade_gate_reads_outside=5` dans les deux preuves ; ce compteur existant ne disparaît pas.
Le lecteur v2 n’a pas été exécuté ; seul son écrivain a produit un candidat partiel.

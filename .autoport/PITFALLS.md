# REGISTRE DES PIÈGES — un piège rencontré, un verrou mécanique, vérifié automatiquement

Owner, 2026-08-12 : « fais en sorte que tes soucis récurrents, défauts de comportement et pitfalls
ne se reproduisent plus, ça fait partie de l'amélioration continue que tu te fous de gérer de façon
autonome ».

Règle de ce fichier : **un piège qui a coûté quelque chose une fois y entre avec son verrou**, et
`preflight.py` vérifie à chaque tentative que le verrou est toujours en place. Un verrou qui
disparaît est signalé — c'est ainsi qu'on empêche la rouille, pas en s'en souvenant.

Format : `GUARD <id> <fichier> <marqueur à retrouver>` suivi du récit court.

---

GUARD pid-files .autoport/watch_the_watcher.sh kill -0
**Compter des processus par correspondance de motif.** `ps | grep -c motif` compte le grep
lui-même ; `pkill -f motif` se tue lui-même (exit 144) ; une boucle d'attente sur son propre motif
attend indéfiniment. Tombé **quatre fois en 24 h** sous quatre formes, et a fait tuer la chaîne de
livraison toutes les deux minutes pendant une nuit entière. Verrou : chaque démon écrit son PID,
le superviseur teste `kill -0`. Un PID ne se confond avec rien.

GUARD metric-frame .autoport/lib/preflight.py check_metric_frame_declared
**Mesurer la mauvaise grandeur.** Une variance ne décrit pas un affaissement soutenu ; un scalaire
ne décrit pas une forme ; le repère monde masque le mouvement propre d'un maillon (la pointe hérite
de son parent). Trois faux verts en un jour, tous démentis par l'œil de l'owner. Verrou : trois
questions obligatoires avant toute mesure (nature du défaut, repère, lecture quand le défaut est
absent), et un check qui signale toute grandeur publiée sans déclarer son repère.

GUARD discriminant .autoport/validators/phase-Grecharged-secondary-motion.sh DISCRIMINANT
**Une mesure qui ne distingue rien.** 16 chaînes sur 22 rendaient la même amplitude sous une
secousse, une translation et une inclinaison à 60°. Verrou : moins de 25 % d'écart relatif entre le
stimulus le plus fort et le plus faible = mesure non discriminante, rejetée.

GUARD control-scale .autoport/validators/phase-Grecharged-secondary-motion.sh SIDE-CONTROL
**Un contrôle positif qui n'exerce pas le défaut à son échelle.** 43 événements injectés là où le
phénomène réel en produisait 11 446 — 0,4 %. Il prouvait que le compteur sait compter, pas que le
défaut était corrigé, et j'ai livré un faux zéro sur cette caution. Verrou : un contrôle doit
atteindre au moins 20 % de la ligne de base.

GUARD motion-floor .autoport/validators/phase-Grecharged-secondary-motion.sh FLOOR
**Payer une correction avec le mouvement.** Trois ajouts légitimes pris ensemble ont divisé le
mouvement par 8 à 14 ; l'owner a reçu un build « muted as heck ». Verrou : plancher par chaîne,
calé sur l'état qu'il a **approuvé** (jamais sur le maximum jamais vu), −40 % fait échouer.

GUARD weak-floor .autoport/validators/phase-Grecharged-secondary-motion.sh FLOOR-WEAK
**Protéger ce qu'on regarde, pas ce que l'owner regarde.** Le plancher gardait l'amplitude maximale ;
lui juge la réponse aux mouvements **subtils**, et la baisse est passée inaperçue. Verrou : plancher
séparé sur le stimulus le plus faible de chaque chaîne, −30 % fait échouer.

GUARD owner-tuning .autoport/validators/phase-Grecharged-secondary-motion.sh TUNING
**Les réglages issus de son œil effacés par une régénération.** Arrivé **trois fois** ; il a testé
des builds dont ses propres corrections avaient disparu. Verrou : ses réglages vivent dans un
fichier à part, réappliqués **par le producteur lui-même**, et une gate vérifie qu'ils sont dans le
fichier livré — quelle que soit la forme de la directive (`chain`, `collider`, `+chain`, `+collider`).

GUARD dirty-tree .autoport/auto_build_apk.sh arbre sale
**Livrer depuis un arbre à moitié réécrit.** 366 lignes non commitées dans le moteur au moment du
build ; l'owner a testé un moteur incohérent et l'a jugé « loupé complet ». Verrou : on ne construit
que depuis un état commité, ou depuis un arbre sale **qui compile** (le seul test objectif de
cohérence), auquel cas on en fait un point de commit.

GUARD build-identity .autoport/build_tag.sh tag de 6 caracteres
**Un build livré sans étiquette est un build invisible.** Il a jugé un APK vieux de 28 minutes en
croyant tester le dernier, puis conclu « zéro build poussé » alors qu'un APK venait d'arriver avec
une description périmée de 45 minutes. Verrou : tag `<commit6>-<pack6>` écrit à chaque build,
lisible sur son téléphone dans `files/.custom_pack_stamp_jak1`, et description écrite par le
constructeur lui-même à chaque build.

GUARD gate-deadlock .autoport/orchestrator.py OPEN-DEFECTS
**Poser un garde-fou sans tester son mode d'échec.** `OPEN-DEFECTS` échoue par construction tant que
l'owner voit un défaut : elle a d'abord épuisé les 14 tentatives, puis déclenché l'arrêt pour erreur
récurrente — deux blocages complets de la boucle. Verrou : la signature attendue est exemptée du
détecteur, et `max_retries` est dimensionné pour une phase itérative.
**Règle générale qui en découle** : avant d'ajouter une gate, répondre à trois questions —
(1) peut-elle passer ? (2) que se passe-t-il si elle échoue trois fois de suite ? (3) qui peut la
satisfaire, et cette personne est-elle dans la boucle ?

GUARD comment-not-proof .autoport/DIRECTIVES.md UN COMMENTAIRE N'EST PAS UNE PREUVE
**Rapporter un commentaire comme du comportement vérifié.** J'ai affirmé que la salle de test
n'avait pas de joueur en citant le docstring du fichier ; l'owner voyait Jak jouer à l'écran.
Verrou : toute affirmation sur ce que le programme fait cite une trace d'exécution.

GUARD hand-capsules recharged_assets/keira-owner-tuning.txt MES CAPSULES ONT
**Écrire des volumes de collision à la main.** J'ai ajouté quatre capsules aux rayons devinés, plus
fines que celles que le rig génère, posées sur les mêmes segments — exactement ce que l'owner
condamne depuis le début. Verrou : si un volume manque ou est trop petit, ça se corrige dans la
**génération**, jamais par un rayon deviné.

GUARD tabula-rasa-inventory .autoport/DIRECTIVES.md INVENTAIRE AVANT DE RASER
**Une table rase jette aussi ce qui marchait.** Owner, 2026-08-12 : « la branche parkée contient des
commits où la physique des cheveux de Keira fonctionnait bien, je comprends pas pourquoi tu t'en
sors pas alors que tu travailles UNIQUEMENT sur Keira et UNIQUEMENT sur le modèle HD, alors que
là-bas on traitait tous les personnages ». Il a raison. En « repartant propre » j'ai réduit le
moteur à 51 lignes et tout re-dérivé de zéro : j'ai jeté l'empilement de suppresseurs (le mal) **et
les solutions acquises sur des semaines** (le bien), puis j'ai passé trois jours à redécouvrir à la
main des choses probablement déjà résolues — rotation du dernier maillon, couverture de peau,
dimensionnement des volumes. **Repartir propre ne veut pas dire repartir vide.**
Verrou : avant toute table rase, produire l'**inventaire des acquis** de l'état parké — ce qui
fonctionnait, avec la mesure qui l'atteste — et porter ces acquis un par un, mesurés contre le
plancher, au lieu de tout réécrire à l'aveugle. Un état parké se **mine**, il ne s'oublie pas.

GUARD adjacent-fix .autoport/reports/Grecharged-secondary-motion/owner-defects.txt CE N'EST PAS LE `tear`
**Corriger ce qui est à côté du défaut, et croire l'avoir corrigé.** L'owner a signalé **trois fois**
que sur les grosses mèches « une partie de la géométrie reste ancrée et ça casse ». J'ai fermé la
**couture** (`tear` rmidhair 82 → 0) — proprement, la mesure est vraie — mais la géométrie ancrée est
restée ancrée : 14 à 27 % des sommets pesés `head 100%`. Lisser un raccord enlève la fissure, ça ne
fait pas bouger le morceau figé. Il l'a vu immédiatement et m'a dit « j'ai pas l'impression que t'as
saisi ce feedback ». Verrou : une mesure ne ferme un défaut que si elle **porte sur la grandeur que
l'owner décrit**, pas sur une grandeur voisine du même fichier. Quand il répète un défaut après une
correction verte, c'est la correction qui visait à côté, jamais lui qui n'a pas vu.

GUARD paired-control .autoport/reports/Grecharged-secondary-motion/owner-defects.txt CONTROLE QUE L'OWNER M'A DONNE
**Chercher une cible chiffrée alors qu'il vient d'en approuver une.** Il approuve les mèches fines et
rejette les grosses : même moteur, même salle, même repère — un **contrôle apparié** offert. Les deux
défauts ouverts suivaient exactement ce partage (couverture 0.977 vs 0.73–0.86 ; paramètres dérivés
vs ronds génériques 1.80/0.18/0.90), et la conclusion tombait toute seule : les grosses mèches n'ont
jamais reçu la passe que les fines ont reçue. Verrou : dès qu'il valide un échantillon et en rejette
un autre de la même classe, la cible n'est plus un nombre que je choisis — c'est la valeur **mesurée
sur l'échantillon qu'il a approuvé**, et la correction se formule comme un écart à combler.

GUARD target-is-response .autoport/DIRECTIVES.md la cible est la RÉPONSE MESURÉE
**Désigner une cible par le réglage qui la produit, pas par la grandeur observable.** J'ai écrit « la
cible est la valeur mesurée sur lbang/rbang » en pensant *réponse* ; le worker a lu *paramètre* et a
recopié `damping=0.0784` sur trois chaînes de raideur et de masse différentes. Résultat mesuré : ça
atteint la cible sur deux d'entre elles et rate la troisième — `backhair`, la plus raide, reste à
28 frames de ballottement contre 84–96 visés, exactement la mèche dont l'owner se plaint le plus.
Verrou : une cible se formule **toujours** par la grandeur observable (durée de ballottement, retard
racine→pointe), jamais par le réglage ; et un réglage se dérive de la géométrie de SA chaîne.

GUARD regenerable-is-not-unused decompiler/config/jak2/jak2_config.jsonc "rip_levels": true
**Supprimer des « sorties régénérables » qui sont en fait des ENTRÉES.** Le 2026-08-13 à 12:17 j'ai
libéré 7 Go en effaçant `decompiler_out/jak2` et `jak3`, classés « sorties de build régénérables ».
Ils contenaient les **onze rips donneurs HD** dont dépend tout le pipeline de maillages HD.
Conséquence : `build_enhanced_models.sh` sortait en deux lignes sans rien faire, les deux défauts
PRIORITÉ 1 de l'owner étaient impossibles à corriger, et **j'ai passé trois cycles à reprocher au
worker de ne pas lancer une injection que ma propre commande rendait incuisable**. Régénérable ne
veut pas dire inutilisé, et « je peux le refaire » ne dit rien du coût ni de la recette.
Verrou : avant d'effacer un répertoire produit, chercher qui le LIT (`grep -rn <chemin> scripts/`) ;
et si la recette de régénération dépend d'un réglage non évident, la rendre permanente — ici
`rip_levels` était à `false`, donc une simple redécompilation ne rendait PAS les rips. Il est
maintenant à `true` dans la config suivie, pour que la réparation soit à un `decomp2.sh` de distance.

GUARD target-bounded-by-window .autoport/DIRECTIVES.md cible ANNULÉE, elle venait d'un artefact
**Fixer une cible à une valeur que l'instrument ne peut pas dépasser.** J'ai posé « retard
racine→pointe ≥ 5 » en lisant `lag12=5` sur la chaîne approuvée. Or la fenêtre de recherche vaut
`dmax = round(tapp/2)` = 5 : la mesure était **au bord de sa propre fenêtre**, et un retard n'est
déterminé que modulo une demi-période — `lbang mono=yes` et `backhair lag12=0` étaient la même
mesure. Recalculée sur ±14, la corrélation montait encore là où la fenêtre s'arrêtait. J'ai donc
demandé pendant trois cycles qu'on atteigne un chiffre qui ne voulait rien dire.
Verrou : avant de faire d'une valeur une cible, vérifier qu'elle n'est pas **saturée par la borne de
son propre calcul** — si la grandeur maximale observée égale la limite de la fenêtre, ce n'est pas un
résultat, c'est le bord. Élargir la fenêtre et regarder si la courbe monte encore.

GUARD recipe-not-transferable .autoport/DIRECTIVES.md aurait été un maillon inerte
**Généraliser une recette qui a marché ailleurs sans vérifier que le cas est le même.** L'injection
d'un 4e os avait réussi sur `lbang`/`rbang` ; j'ai prescrit la même chose aux trois grosses mèches.
Mesure : il n'y a **aucune géométrie au-delà de leur pointe** (`tail_m` 0,0000) — l'os ajouté aurait
été inerte. Leur défaut réel est ailleurs : 60 à 93 % de la masse sur un seul segment libre contre
35–37 % sur les chaînes approuvées, ce qui appelle une **subdivision**, pas une extension.
Verrou : avant de transposer une recette, mesurer que la chaîne cible présente le même manque que
celle où la recette a marché — « même famille » ne veut pas dire « même défaut ».

GUARD sum-hides-concentration .autoport/reports/Grecharged-secondary-motion/owner-defects.txt cov` SOMME sur les joints
**Publier une somme là où le défaut est une concentration.** `ROOM-SKINCOV` additionne les sommets
pilotés par n'importe quel joint de la chaîne. Sur la nuque elle affichait **0,83** — que j'ai
rapporté à l'owner comme un progrès — alors que **les 124 sommets étaient sur UN SEUL joint** (0, 0,
124, 0 contre 94, 9, 10, 36 sur la chaîne qu'il approuve). Une pièce rigide pendue à une charnière
unique : « la géométrie reste ancrée » et « ça part en bloc » étaient le même mécanisme, invisible à
la somme. Verrou : quand un défaut se décrit par une **répartition** (« une partie ne suit pas »,
« tout part ensemble »), la mesure doit publier la distribution, jamais son total — un total élevé et
une concentration totale sont indiscernables. Voir aussi [[measurement must discriminate]].

GUARD floor-ratchet-mirror .autoport/validators/phase-Grecharged-secondary-motion.sh FLOOR-WEAK
**Un plancher qui encliquette sa propre plus haute excursion.** `FLOOR-WEAK` stocke un maximum
courant. Sur `kneeflapL`/`kneeflapR` — paire miroir aux paramètres **identiques** et aux réponses
mesurées quasi identiques (tilt 0,0412 contre 0,0334) — les planchers stockés valaient **0,0884 et
0,0174, un facteur 5,1**. Sur une grandeur à faible signal, le plancher retient le bruit le plus
favorable jamais vu et exige ensuite de le reproduire : la gate rouge n'était pas une régression,
c'était mon propre encliquetage. Verrou : sur une paire miroir, les planchers doivent être calés
ensemble ; et un plancher se calibre sur une statistique robuste, pas sur le maximum jamais observé.
Même famille que [[feedback_ratchet_running_max_eats_itself]].

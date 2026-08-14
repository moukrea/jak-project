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

GUARD hyst-substring .autoport/PITFALLS.md `HYST` matchait `PHYSTILT`
**Conclure « c'est déjà instrumenté » sur une correspondance de sous-chaîne.** J'ai cherché `HYST`
pour savoir si l'hystérésis était mesurée : 10 occurrences, donc oui. En réalité `HYST` matchait
`PHYSTILT` et le mot « hystériques » dans des commentaires citant l'owner — **la grandeur n'existait
pas**. J'ai failli rapporter comme instrumenté le défaut PRIORITÉ 1 du moment. Même famille que
[[feedback_gate_field_name_substring]], que j'avais déjà consigné : un compteur de sous-chaîne ne
prouve l'existence de rien. Verrou : chercher le **nom exact publié** (`ROOM-<NOM>:`) et exiger une
valeur mesurée dans un rapport, jamais une occurrence dans du source.

GUARD invented-owner-approval .autoport/DIRECTIVES.md J'AI INVENTÉ DEUX VALIDATIONS
**Transformer un « c'est moins pire » en validation, et s'en servir de cible.** L'owner a écrit que
les mèches fines étaient « vraiment pas mal » ; j'ai lu une approbation et bâti toute la méthode de
la journée dessus — contrôle apparié, cible « combler l'écart vers `lbang` », plancher calé sur cet
état. Il n'avait jamais validé : elles étaient du pudding elles aussi, simplement moins pires.
**Je visais donc du pudding comme objectif.** J'ai de même écrit « verdict owner positif » sur un
état de la branche parkée qu'il n'a jamais approuvé — un verdict inventé à partir d'un message de
commit écrit par moi. Verrou : une validation de l'owner se cite **verbatim, avec sa date**, et rien
d'autre ne peut servir de cible ; une formulation comparative (« mieux », « moins pire », « pas
mal ») n'est PAS une validation ; et un message de commit n'est jamais une source de verdict.

GUARD gate-vetoes-the-owner .autoport/DIRECTIVES.md MA GATE BLOQUAIT SA SPEC
**Une gate calée sur l'état courant qui finit par interdire ce que l'owner demande.** `FLOOR-WEAK`
protégeait l'amplitude observée ; quand la calibration **exacte de la §24 de sa propre spécification**
(2.300 Hz, vérifiée) a été appliquée, la flèche statique a été divisée par 3,65 et la gate a échoué —
alors que ses §2 et §9 exigent justement `AdditionalStandingSag = 0`. La calibration a donc été
retirée **pour satisfaire mon garde-fou**, et le worker l'a consigné noir sur blanc dans le fichier
de réglages. Le plancher protégeait un affaissement que la spec interdit, sur un état que l'owner
n'a jamais approuvé, avec un encliquetage déjà connu.
Verrou : une gate qui contredit une ligne de spécification de l'owner est fausse par construction —
on corrige la gate. Et avant d'en poser une, répondre à une quatrième question, en plus des trois
déjà en vigueur : **« que se passe-t-il si l'owner demande précisément ce qu'elle interdit ? »**
Une gate calée sur l'état courant transforme le statu quo en obligation.

GUARD truncated-series .autoport/DIRECTIVES.md série de **15 échantillons** alors que la trace en contient **149**
**Graver une conclusion tirée d'une série tronquée.** À 03:10 j'ai posé en PRIORITÉ ABSOLUE que « le
solveur draine linéairement au lieu de résoudre son équation », d'après des écarts successifs
`16.4 15.8 14.7 13.1` — 15 échantillons cités sur les **149** que contenait la trace. Sur la série
complète le rebond existe (4,7 % / 9,5 %) et la décroissance n'est pas linéaire ; le vrai défaut
était ailleurs — une excursion à 1,10–1,41 B0 contre un plafond de 0,50 B0. **Une fenêtre trop
courte sur une exponentielle ressemble exactement à une droite.** Verrou : avant de conclure sur la
FORME d'une décroissance, publier le nombre d'échantillons de la trace ET celui des échantillons
utilisés ; un rapport inférieur à 1 interdit toute conclusion sur la forme. Même famille que
[[target-bounded-by-window]] : la borne de la mesure fabriquait le résultat.

GUARD deploy-lock-needs-pid .autoport/DIRECTIVES.md verrou `.deploy-in-progress`
**Un verrou de livraison sans détenteur identifiable.** Le 2026-08-14 à 05:32, un
`.autoport/.deploy-in-progress` **vide** a été posé hors des deux scripts prévus (`keira_a3_redeliver.sh`
et `keira_a8_redeploy.sh` écrivent tous deux `pid=$$` et nettoient par `trap ... EXIT`). Personne ne
l'a relâché : le constructeur a refusé trois builds d'affilée (05:22, 05:50, 06:18) et **l'owner est
resté 108 minutes sans APK** alors que l'acquis de 05:52 était prêt. Seule la borne aveugle de 60 min
a fini par débloquer la chaîne. Le message de refus affichait `(, 2707s)` — champ détenteur vide,
donc aucun diagnostic possible sans recouper les horaires à la main.
Verrou : tout processus qui pose ce fichier y écrit **son PID** et installe un `trap` de nettoyage ;
et le constructeur doit traiter comme périmé, **immédiatement**, un verrou dont le PID ne répond plus
à `kill -0` — au lieu d'attendre l'heure. C'est le principe `pid-files` déjà au registre, non appliqué
ici : une borne temporelle est un dernier recours, pas un mécanisme de détection.

GUARD freezing-empties-the-gate .autoport/reports/Grecharged-secondary-motion/owner-defects.txt breast-spec-incomplete
**Geler des défauts vide la gate qui tenait la phase ouverte.** Le 2026-08-14, sur ordre de l'owner,
j'ai passé les 13 défauts non-poitrine de `OPEN` à `GELE`. La gate `OPEN-DEFECTS` compte les lignes
`OPEN` : la liste étant vide, elle est passée, et **la phase s'est refermée deux fois** (08:22 et
10:13) alors que le travail commandé — la spec poitrine — n'était fait qu'à 3 sections sur 12. Sans
la réouverture manuelle, la boucle serait passée à autre chose en silence.
Verrou : quand on retire des lignes d'une liste qui sert de gate, vérifier **ce que la gate mesure
encore**. Un changement de périmètre doit s'accompagner d'une ligne `OPEN` décrivant le travail
NOUVELLEMENT commandé — sinon réduire le périmètre revient à déclarer la phase finie.

GUARD wired-but-disarmed .autoport/DIRECTIVES.md `PHYSAXIS arm=0`
**Rapporter « câblé » un mécanisme dont l'interrupteur est à zéro.** À 10:42 j'ai annoncé les §24 et
§29 de l'owner « câblées dans le calcul » parce que les constantes étaient enfin référencées. Elles
l'étaient — derrière `PHYSAXIS arm=0`, donc **les trois axes rendaient la même valeur**. Deux heures
plus tôt j'avais moi-même relevé ces mêmes sections comme « déclarées, jamais utilisées » : le
défaut a simplement changé de costume, et je l'ai laissé passer parce que je cherchais une
référence au symbole au lieu d'une **valeur mesurée qui discrimine**.
Verrou : une section n'est TENUE que si une mesure montre l'effet du mécanisme — ici, trois axes
rendant des valeurs DIFFERENTES. Une lecture identique sur les trois prouve le désarmement.

GUARD wrong-yardstick .autoport/DIRECTIVES.md `B0` du moteur est FAUX d'un facteur 1.62
**Mesurer une cible de la spec contre une référence qui n'est pas la sienne.** Sa §6 définit `B0`
comme la longueur racine→apex de la CHAIR (602 u) ; le moteur prenait celle de l'OS (977 u), 1.62×
trop grande. J'ai donc annoncé à 06:08 « l'excursion passe sous 0.50 B0 — première cible de sa spec
atteinte » alors qu'elle valait **0.778 / 0.795 B0 contre sa référence, dépassée de 1.59×**. Le
mécanisme (sous-pas + saturation) était bon ; le mètre était faux, et le vert venait du mètre.
Verrou : toute cible exprimée en unité dérivée (`B0`, `W0`, `L0`…) publie **la valeur de l'unité
elle-même et sa provenance** à côté du résultat. Un ratio sans son dénominateur n'est pas une mesure.

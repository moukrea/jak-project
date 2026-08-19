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

GUARD absent-by-wrong-name .autoport/PITFALLS.md deform|shape|scl
**Conclure « absent » parce qu'on a cherché un nom que le code n'emploie pas.** Deux fois le
2026-08-14 : `HYST` ne trouvait que `PHYSTILT` (l'hystérésis semblait instrumentée alors qu'elle
n'existait pas), puis `scale` et `ROOM-SHAPE` rendaient 0 et 1 sur un canal de déformation qui pèse
**+659 lignes** de moteur et **369 occurrences** sous les noms `deform|shape|scl`. La première
erreur inventait une mesure, la seconde a failli faire signaler comme manquant le plus gros
changement de la journée. Verrou : avant de conclure à l'absence d'un mécanisme, vérifier par une
grandeur INDÉPENDANTE du nom — la taille du diff sur les fichiers concernés, ou une valeur publiée à
l'exécution. Une absence ne se prouve pas par un motif de recherche.

GUARD prompt-via-stdin .autoport/orchestrator.py Le prompt part par stdin
**Un contrat qui grossit finit par tuer l'exec qui le transporte.** Le 2026-08-17 à 23:41,
l'orchestrateur est mort en `OSError: [Errno 7] Argument list too long` : le prompt du worker
(directives 106 Ko + preflight 14 Ko + préambule) passait en **un seul argument argv**, et Linux
plafonne chaque argument à `MAX_ARG_STRLEN` ≈ 128 Ko — bien avant l'`ARG_MAX` global de 2 Mo. Chaque
consigne que j'ajoutais au contrat rapprochait silencieusement la boucle de ce mur, et elle est
morte à l'exec, AVANT tout travail, sans consommer une tentative. Diagnostic retardé parce que le
symptôme (« ZERO work done — hard rate limit at the door ») a d'abord été lu comme du quota.
Verrou : le prompt part par **stdin** (`claude -p` sans valeur + write/close), plus jamais en argv.
Et la leçon de lecture : « exited 1 with ZERO work done » a plusieurs causes — vérifier le log
d'erreur du subprocess avant de conclure au quota.

GUARD bone-without-reskin .autoport/DIRECTIVES.md sommets ou il est MAJORITAIRE
**Compter une injection d'os comme faite alors que la peau ne le suit pas.** Trois fois : le
2026-08-13 sur `backHair4` (124 sommets sur un seul joint), au cycle 16 sur la poitrine, puis le
2026-08-18 où `lBooc`/`rBooc` portaient **0 sommet majoritaire** pour 9.0 et 6.8 de poids résiduel,
contre 56.8 et 153.3 sur l'os racine. À chaque fois l'os était bien dans le rig, dans le skin et
résolu par le solveur (`links=2`) — donc tous les contrôles de PRÉSENCE passaient au vert pendant
que l'organe restait mécaniquement une pièce rigide sur une charnière unique. L'owner l'a vu à
l'œil les trois fois avant que la mesure ne le dise.
Verrou : la preuve d'une injection est la **RÉPARTITION** (≥ 30 % des sommets ayant le nouvel os
pour joint majoritaire, w > 0.5, par sa §30), jamais la présence. Le tableau
`os / poids total / sommets majoritaires` se publie à chaque injection.

GUARD measure-the-delivered-mesh .autoport/PITFALLS.md keira-hd-lod0.glb
**Mesurer le donneur au lieu du mesh livré, et publier trois blocages qui n'existaient pas.** Les
2026-08-18 08:55, 10:19 et 10:49 j'ai lu les poids de peau sur `keira-hd-donor-injected.glb` — le
DONNEUR — et rapporté « `lBooc` porte 0 sommet majoritaire, le repesage n'a jamais eu lieu », trois
digests de suite, en accusant l'outil puis une règle manquante. Le mesh que l'owner teste est
`out/jak1/fr3/skin/keira-hd-lod0.glb`, et le worker y mesurait au même moment un profil d'ancrage
§30 **en U** — donc un repesage bien présent mais au profil inversé. Diagnostic faux, cause fausse,
trois cycles de supervision gaspillés. C'est ma propre règle
[[feedback_reskin_measure_the_prepped_input]] que je n'ai pas appliquée à moi-même.
Verrou : toute mesure de peau publiée nomme **le fichier lu ET sa nature** (donneur / prepped /
livré), et une affirmation sur ce que l'owner voit se lit sur le **mesh livré**, jamais sur le
donneur. Les deux divergent par construction — c'est tout l'objet du pipeline entre les deux.

---

GUARD prepend-parent-order .autoport/physics_inject_joints.py hd_parent > k
**Un joint HD ne peut jamais devenir le PARENT d'un joint existant.** Le cycle 22 a dérivé, chiffré
et déposé une injection de nœud PROXIMAL (`prepend` : insérer entre `chest` et `lBoob`, reparenter
`lBoob`). L'injecteur appende les nouveaux joints en FIN de `skin.joints`, donc le nouvel index est
nécessairement supérieur à celui du joint reparenté : `hd_parent > k`. Quatre consommateurs exigent
`hd_parent < k` — `retarget_fill_table.py` (PARENT-ORDER, `sys.exit(2)`), `hd_splice_joint_tables.py`
(invariant append-only), `physics_keira_gen2.py:470`, et la boucle de retarget elle-même
(`goal_src/jak1/pc/jak-hd.gc:497` parcourt les joints dans l'ordre des index ; les modes 1/2/3 lisent
la bone du parent DÉJÀ retargetée cette frame — un parent au-dessus serait lu une frame en retard, en
silence). Le faire marcher demande une INSERTION d'index dans cinq tables, pas un append.
Verrou : `prepend` est implémenté et refuse TOUJOURS, en énonçant la contrainte au point d'échec.
La sortie mesurée est le verbe `reroot` : quand la chaîne est colinéaire (mesuré sur Keira,
`chest`/`lBoob`/`lBooc` à 0.00027 deg, `lBoob` à 0.000000 m de la droite), faire GLISSER la racine
existante à la position dérivée donne la MÊME abscisse SPEC-31 (|ds| max 7.8e-06) et le même
`StrongRootFraction`, sans toucher un seul index. `reroot` préserve l'orientation de bind (la peau y
est liée) et re-base les enfants ; la pose au repos est identique au bit près par construction.

---

GUARD hard-clamp-into-state goal_src/jak1/pc/jak-hd-physics.gc phys-softmin sm0
**Un écrêtage POSITIONNEL DUR écrit DANS L'ÉTAT d'un oscillateur détruit la grandeur qu'on
mesure sur lui.** Le mode secondaire de la SPEC 36 était borné par
`(fmin PHYS-SEC-MAX (fmax (- 0.0 PHYS-SEC-MAX) sm0))`, puis `sm0` était réécrit dans
`*phys-sec*`. Mesuré : **10 frames collées à |s| = 0.0700000 EXACTEMENT**, que l'ajustement de
`zeta` devait EXCLURE — d'où son « DESACCORD — prudence » sur les deux chaînes. Pendant ces
frames, le système livré n'est plus l'oscillateur dont la spec donne `zeta` : on ne mesure plus
rien. Et la SPEC 37 l'interdit en toutes lettres (« soft displacement clamps should be preferred
to abrupt positional clamps »).
Verrou : `phys-softmin` (identité stricte sous `kn = 0.84*cap`, seul l'excès sature, asymptote
exacte à `cap`) remplace le `fmin/fmax`. Mesure après : **0 frame collée**, |s|max 0.0696716.
**LA CONDITION QUI REND ÇA SÛR, et elle se vérifie AVANT d'y toucher :** une borne douce appliquée
par frame À L'ÉTAT compose (piège `saturation-per-frame-compounds`, qui a coûté la régression
« un peu muté » du 2026-08-14). Elle n'est acceptable que si son GENOU tombe **au-dessus** du haut
de la bande normale que la spec chiffre — ici `0.84*0.07 = 0.0588` contre
`SecondaryJiggleAmplitude = 0.02-0.05` — de sorte que la bande normale soit traversée en IDENTITÉ.
La preuve exigée est un pilotage dont la réponse est sous le genou et dont la valeur doit rester
INCHANGÉE À LA DÉCIMALE : ici `updown` 2.41 → 2.41 et `tilt` 1.12 → 1.12. Si ce garde-fou bouge,
la borne compose dans la bande normale et le correctif se RETIRE, il ne s'adoucit pas.

GUARD truncated-listing .autoport/PITFALLS.md app-jak1-HD-recharged.apk
**Tronquer une liste puis conclure sur ce qui reste.** Le 2026-08-18 à 23:19 j'ai listé les assets de
la release avec `| tail -4`, vu `app-jak1-NORMAL-recharged.apk` daté du 3 août, et alerté l'owner
que **ses builds ne lui arrivaient plus depuis quinze jours**. Faux : le publieur envoie
`app-jak1-HD-recharged.apk`, mis à jour le jour même à 21:06 — l'asset que j'accusais n'est
simplement plus alimenté, et ma troncature l'avait laissé seul visible. Deuxième fois cette semaine
qu'une sortie coupée fabrique une conclusion (cf. [[truncated-series]] sur une décroissance).
Verrou : avant d'alerter sur une absence dans une liste, l'afficher ENTIÈRE (ou trier explicitement
sur le critère qui décide) — jamais un `head`/`tail` suivi d'un verdict.

GUARD engine-units-are-not-mm .autoport/DIRECTIVES.md 4096 u = 1 m
**Publier une longueur sans convertir les unités moteur.** Le 2026-08-19 j'ai annoncé à l'owner
« un segment de 14 cm dans un organe de 73 cm » : j'avais divisé les unités de jeu par 10 au lieu de
**4096** (4096 u = 1 m). Les vraies valeurs sont **3,4 cm dans 17,9 cm**. Il a vu l'absurdité
immédiatement — « des seins de 73 cm ? what the fuck » — et il a eu raison de douter du reste.
Le ratio (19 %) était juste, mais un chiffre invraisemblable détruit la confiance dans tous les
autres, y compris les corrects. Déjà consigné en mémoire projet, et j'y suis retombé.
Verrou : toute longueur publiée porte **la valeur brute ET sa conversion** (`734 u = 17,9 cm`), et
tout chiffre destiné à l'owner passe le test de vraisemblance anatomique avant d'être écrit.

GUARD trigger-nobody-calls .autoport/auto_push_builds.sh owner_testable
**Un declencheur differentiel que personne n'appelle impute son delta au mauvais build.**
`owner_testable.py` compare le build publie a un JALON qu'il n'avance qu'en tournant. Il n'etait
cable nulle part — ni demon, ni orchestrateur : il ne tournait qu'a la main. Le 2026-08-19 son
jalon datait de la veille, et il a donc annonce « A TESTER » sur le build de 20:00 en lui
attribuant une hausse de rayon et de couverture faite le 08-18 a 14:23. La physique livree etait
**identique** a celle du build que l'owner avait deja. Envoyer un humain tester deux fois la meme
chose est exactement le bruit que ce script existe pour supprimer.
Verrou : il est appele a CHAQUE publication reussie depuis le demon de push, donc le jalon avance
build par build. Regle generale : un outil qui compare a un etat precedent doit tourner sur CHAQUE
evenement, sinon il ne mesure pas un delta mais un cumul, et il l'attribue au dernier venu.
Voisin de `stale-artifacts` et de `floor-ratchet-mirror`.

GUARD spec-line-quoted-from-memory SPEC-breast-softbody.md Local tissue elongation: common 5–15%, large 15–21%, exceptional 21–25%
**J'ai bati un theoreme sur une ligne de spec qui n'existe pas.** Le cycle 40 a publie qu'il
fallait ×5,23 de chair simulee pour tenir « 25 % d'elongation d'ORGANE a 25 % de deformation
locale ». La spec ne demande nulle part 25 % d'elongation d'organe : §22 dit « **Local** tissue
elongation » sur ses deux lignes, et l'exigence organe est §11 (HangingLengthScale = 1.23), portee
par le tenseur. J'avais multiplie un plafond LOCAL par la longueur de l'ORGANE — echange de
denominateur — et le theoreme reclamait de l'etirement la ou la MEME section interdit en gras que
l'excursion vienne de l'etirement (« Translation, rotation and redistribution shall account for
most of the excursion »). Annonce a l'owner comme un fait, et le chantier qui en decoulait
(allonger la chaine) etait nuisible : ajouter des noeuds FAIT BAISSER la couverture (38 % -> 28 %).
Verrou : avant de deduire quoi que ce soit d'une ligne de la spec, la RELIRE et **citer son texte
exact dans le meme paragraphe**. Une ligne resumee de memoire n'est pas une ligne de la spec.
Voisin de `invented-owner-approval` : la meme faute, appliquee au texte au lieu de la parole.

GUARD gate-must-quote-the-spec .autoport/validators/phase-Grecharged-secondary-motion.sh SPEC-breast-softbody
**Sept gates citaient les sections d'un document qui n'existe pas.** MOVE « SPEC §1 », ROOT
« SPEC §2 », COLLIDE « SPEC §3 », IDLE « SPEC §4 », ANIM « SPEC §5 », ROOM « SPEC §6 », SUPPRESS
« SPEC §7 » renvoyaient a `SPEC-keira-physique.md` — absent du disque ET de tout l'historique git.
C'etait MON resume numerote de ses retours epars d'avant le 2026-08-13. Et chacun de ces numeros
designe une AUTRE section dans la vraie spec : la §3 reelle est « Gravity Calibration », pas une
liste de collisions. Une gate portant un faux numero de section se lit comme une exigence de
l'owner et devient increvable.
Verrou : une gate cite le TITRE et le TEXTE EXACT de la section qu'elle transcrit, ou elle est
supprimee. Quand la spec donne un mot et pas un nombre (« before visible interpenetration »), le
nombre est declare comme MON operationnalisation, avec sa conversion.

GUARD find-newermt-bare-time .autoport
**`find -newermt '21:06'` ne veut pas dire « aujourd'hui a 21h06 ».** Le 2026-08-19 cette forme a
renvoye ZERO fichier alors que l'APK avait un mtime de 21:46:30 — j'ai failli publier une fausse
alerte « le correctif n'est pas dans le build ». Toujours l'horodatage complet :
`-newermt '2026-08-19 21:06:00'`. Et l'erreur symetrique est bien pire : une verification de
fraicheur qui ne trouve rien se lit comme « rien n'a change », donc comme un feu vert.
Verrou : tout controle de fraicheur se valide sur un fichier DONT ON CONNAIT le mtime avant de
conclure quoi que ce soit.

GUARD trigger-blind-to-code .autoport/owner_testable.py solver_fingerprint
**Un declencheur qui ne surveille que les REGLAGES est aveugle aux correctifs de CODE.**
`owner_testable.py` comparait les parametres livres et la couverture de peau. Le build de 21:46 a
supprime l'ecretage qui figeait la reponse — le changement de comportement le plus important de la
journee — et le declencheur est reste muet, faute de parametre modifie. Corrige : l'empreinte du
source du solveur entre dans le jalon, et sa variation declenche a elle seule.

GUARD instrument-fix-stops-at-the-verdict-line .autoport/reports ROOM-COMEX NOTE-112
**Un correctif d'instrument s'arrete quand la LIGNE DE VERDICT lit la nouvelle donnee, pas quand
la donnee existe.** Au cycle 41, `comex` a ete documente comme un MAXIMUM sur deux echantillons la
ou §22 nomme une MOYENNE PONDEREE, et les donnees par maillon ont ete ajoutees pour permettre la
recomposition. La ligne de verdict, elle, n'a jamais ete rebranchee : six cycles durant, le
tableau a publie « HORS BANDE ×2,22 » pour un depassement reel de +18 % / +7 %. C'est un FAUX
ROUGE, et il coute autant qu'un faux vert : il envoie le chantier courir apres un facteur 2
inexistant et masque le vrai defaut, qui est petit. Pire, la note « c'est documente » se lit comme
« c'est corrige » au-dessus d'un chiffre qui ment.
Verrou : un correctif d'instrument n'est clos que quand la ligne publiee a change de valeur ET de
nom. Et une population se publie avec ses trois grandeurs (borne superieure, moyenne, part
au-dessus du plafond), jamais avec son seul maximum.

GUARD no-consolidated-coverage-state .autoport/SPEC-COVERAGE.md
**Sept cycles de rapports narratifs, et aucun etat consolide.** Quand l'owner a demande « la spec
est-elle a 100 % ? », je ne pouvais repondre qu'a l'impression : chaque cycle publiait son recit,
aucun document ne disait section par section ce qui etait tenu. Le premier registre ecrit a donne
**6 tenues sur 38**, et surtout a revele que **onze sections n'avaient jamais ete JOUEES** — un
trou de mesure invisible dans un flux de rapports, parce qu'un rapport parle de ce qu'il a fait,
jamais de ce qu'il n'a pas fait.
Verrou : `.autoport/SPEC-COVERAGE.md` est un artefact obligatoire de chaque cycle, une ligne par
section, `NON ETABLI` par defaut. Regle generale : un travail mesure a l'aune d'un document exige
un TABLEAU de couverture de ce document, tenu a jour, ou l'avancement n'est qu'une opinion.

GUARD code-hash-cannot-see-intent .autoport/owner_testable.py code_changed
**Une empreinte de fichier ne distingue pas un correctif de COMPORTEMENT d'un ajout de SONDE.**
Le 2026-08-19 j'ai fait entrer le hash du solveur dans le declencheur, parce qu'un correctif de
code ne touche aucun reglage et le laissait muet. Des le lendemain 00:33 il a crie « A TESTER »
pour un commit qui n'ajoutait que des compteurs de mesure — le pas tangentiel du cycle 47 etait
bien retire, seules ses sondes restaient. Alerter l'owner a chaque commit d'instrumentation, c'est
le dresser a ignorer l'alerte : exactement ce que le script existe pour empecher.
Verrou : le changement de code sort sur une ligne `VERIF` destinee au superviseur, qui lit le diff
et decide ; il ne declenche JAMAIS a lui seul un « A TESTER ». Regle generale : un signal qui ne
peut pas porter le jugement qu'on lui demande doit remonter a qui peut le porter, pas trancher.

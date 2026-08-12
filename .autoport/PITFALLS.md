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

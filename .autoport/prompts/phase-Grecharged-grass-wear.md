# Phase Grecharged-grass-wear — Procedural Grass Wear and Height Distribution (DESIGN SPIKE FIRST)

## DEPENDS ON: grass-poc edges owner-clean; evolution AFTER Grecharged-grass-overhang / object-clip.
## NATURE: ANALYSIS/ARCHITECTURE phase — DO NOT implement the feature immediately (owner mandate, see
## "Travail demandé" at the end). Deliverable = analysis + architecture + ordered backlog decomposition.
## NOTE (owner): the "paramètres" below are CODE variables/tunables, NOT Recharged Settings menu entries.

## OWNER SPEC (2026-07-12, verbatim — do not reinterpret)

Titre proposé: Procedural Grass Wear and Height Distribution

Contexte: L'herbe 3D est actuellement placée automatiquement sur les surfaces identifiées comme utilisant
une texture d'herbe. Le résultat visuel fonctionne bien, mais l'ensemble paraît artificiel, car tous les
brins ou groupes d'herbe ont approximativement la même hauteur. L'objectif est de remplacer cette hauteur
uniforme par une distribution spatiale crédible et intentionnelle, calculée automatiquement à partir de la
géométrie du niveau, des éléments de gameplay et des trajets probables du joueur. Il ne faut pas simplement
appliquer une hauteur aléatoire à chaque brin. Le système doit produire une impression d'usure naturelle :
herbe plus courte dans les zones fréquemment parcourues ou importantes pour le gameplay, et plus haute dans
les zones où le joueur est peu susceptible de passer.

Objectif fonctionnel: Construire, pour chaque zone herbeuse, un champ continu représentant la probabilité
ou l'intensité de passage du joueur. Ce champ devra ensuite influencer la hauteur de l'herbe :
- probabilité de passage élevée : herbe globalement plus courte ;
- probabilité de passage faible : herbe globalement plus longue ;
- probabilité intermédiaire : transition progressive entre les deux ;
- légère variation procédurale locale dans tous les cas afin d'éviter un résultat uniforme ou binaire.
Le résultat doit donner l'impression que la végétation a été placée et ajustée manuellement par un level
artist, bien que tout soit généré programmatiquement.

Sources principales d'information:
* Collectibles et objets interactifs — détecter notamment : orbes précurseur ; caisses ; éco ; piles
  d'énergie ; objets ramassables ; objets interactifs ou destructibles pertinents ; autres éléments de
  gameplay susceptibles d'attirer le joueur. L'herbe doit être plus courte autour de ces éléments afin
  qu'ils restent lisibles et que leur environnement semble naturellement fréquenté. L'influence ne doit pas
  former un simple cercle parfaitement régulier autour de chaque objet. Elle doit utiliser des gradients
  irréguliers et se combiner avec les autres informations de navigation.
* Chemins suggérés par les collectibles — lorsque plusieurs collectibles sont disposés selon une suite
  cohérente, en déduire un chemin probable (ex : trois orbes successives => corridor d'herbe légèrement
  plus courte reliant leurs positions, pas trois cercles indépendants). Prendre en compte : la distance
  entre les objets ; leur ordre spatial probable ; la continuité du terrain navigable ; les obstacles entre
  eux ; les différences de hauteur ; la pente ; la largeur disponible ; la vraisemblance du trajet pour le
  joueur. Chemins courbes et organiques lorsque pertinent, pas uniquement des lignes droites.
* Plateformes et parcours verticaux — herbe plus courte : à proximité de la zone probable de départ d'un
  saut ; au pied localisé d'une plateforme (sans raccourcir toute sa base) ; dans la direction de la
  plateforme suivante ; le long d'un parcours probable reliant plusieurs plateformes ; dans les zones
  d'atterrissage plausibles. Déterminer points d'approche/saut/atterrissage via la géométrie et les
  capacités de déplacement du joueur. Un simple mur vertical ne doit PAS automatiquement créer une zone
  d'herbe courte — influence seulement si plateforme/collectible/ouverture/élément de gameplay pertinent.
* Géométrie et zones peu fréquentées — herbe généralement plus longue : bordures de plaines ; angles
  morts ; proximité de murs verticaux sans interaction ni plateforme ; derrière des obstacles ; zones
  éloignées des collectibles/objectifs ; grandes surfaces sans contenu de gameplay ; endroits difficiles
  d'accès. Règle SECONDAIRE vs gameplay (une zone près d'un mur peut avoir de l'herbe courte si objet/
  plateforme/trajet probable). Centres de grandes zones vides = herbe plus longue, sauf liaison naturelle
  entre destinations importantes.

Modèle attendu: générer plusieurs champs d'influence puis les combiner — collectibles ; objets
interactifs ; chemins probables ; plateformes et sauts ; navigabilité ; obstacles/murs ; zones ouvertes ou
délaissées ; variation procédurale naturelle. Combinaison = valeur CONTINUE (pas de classification binaire
courte/longue). Plusieurs niveaux de hauteur, transitions douces et larges (pas de traces artificiellement
peintes).

Variation naturelle: légère, DÉTERMINISTE, spatialement cohérente (pas de bruit désordonné entre brins
voisins) ; peut agir sur hauteur individuelle, hauteur moyenne de petits groupes, contours des zones usées,
largeur des chemins, continuité des transitions. Reproductible entre chargements (graine basée niveau/zone/
coordonnées). Ne jamais annuler la lisibilité du gameplay (une zone raccourcie autour d'un collectible
reste globalement plus courte que son environnement).

Direction artistique: adaptée au style Jak & Daxter — interprétation artistique et lisible de l'usure, pas
une simulation réaliste de chaque pas. ÉVITER : cercles parfaitement visibles autour des objets ; lignes
droites artificielles entre collectibles ; chemins de largeur constante ; changements brusques de hauteur ;
deux hauteurs uniques parcouru/non-parcouru ; variation totalement aléatoire ; motifs répétitifs évidents ;
herbe si haute qu'elle masque collectibles, petits ennemis, rebords ou informations importantes.

Paramétrage (VARIABLES CODE, pas des Recharged Settings): hauteur min/max ; intensité influence
collectibles ; rayon d'influence des objets ; largeur moyenne des chemins ; force de l'usure sur les
chemins ; portée de détection des suites de collectibles ; influence des plateformes ; influence murs/
obstacles ; fréquence et amplitude de la variation procédurale ; douceur des transitions ; seuil max de
hauteur près des éléments de gameplay ; graine déterministe ; niveau de qualité/résolution du calcul.
Globaux + si possible par niveau/biome ; résultat stylisé sans réglage manuel objet par objet.

Contraintes techniques: pas nécessairement temps réel par frame. Étudier : précalcul au chargement ;
génération lors de la construction des données d'herbe ; cache par zone/chunk ; texture ou grille de
valeurs du champ d'influence ; calcul CPU ponctuel ; GPU si bénéfice réel ; données précompilées si
nécessaire. Le runtime ne doit PAS faire de pathfinding coûteux par brin. Compatible avec le découpage
spatial, le streaming éventuel et les niveaux de qualité graphique, notamment Android.

Outils de debug souhaités: heatmap de probabilité de passage ; affichage des influences individuelles ;
chemins déduits entre collectibles ; points d'approche/atterrissage des plateformes ; zones peu
fréquentées ; valeur finale de hauteur ; toggle par source d'influence ; rechargement rapide des
paramètres.

Cas particuliers à étudier: collectibles très proches mais séparés par un mur ; à des hauteurs
différentes ; accessibles après un détour ; plateformes au-dessus d'une zone herbeuse mais non accessibles
depuis celle-ci ; falaises/rebords dangereux ; chemins croisés ; grandes plaines à plusieurs groupes
d'objectifs ; zones décoratives volontairement inaccessibles ; surfaces herbeuses très petites ; objets
mobiles ou apparaissant selon l'état du niveau ; zones où l'herbe masquerait un indice visuel ;
téléporteurs/portes/entrées de bâtiments ; points d'apparition ou destinations importantes sans
collectible.

Critères d'acceptation (owner, 14 points): (1) plus de hauteur uniforme par zone ; (2) collectibles
lisibles, entourés d'une végétation plus courte ; (3) une suite cohérente de collectibles peut générer un
trajet visuel implicite ; (4) les parcours entre plateformes influencent localement la hauteur ; (5) les
murs sans intérêt gameplay ne génèrent PAS d'herbe courte automatique ; (6) zones peu visitées = herbe
généralement plus haute ; (7) transitions progressives et organiques ; (8) pas d'impression de masque
binaire ni de formes géométriques simples ; (9) légère variation naturelle visible sans compromettre les
règles principales ; (10) déterministe à niveau+config identiques ; (11) coût CPU/GPU/mémoire compatible
avec les objectifs, particulièrement Android haut de gamme ; (12) fonctionne sans placement/peinture
manuels systématiques ; (13) paramètres ajustables sans modifier l'algorithme ; (14) une visualisation de
debug explique pourquoi une zone a une hauteur donnée.

## Travail demandé (owner, verbatim — THIS PHASE) — NE PAS implémenter immédiatement. Commencer par :
1. analyser le système actuel de détection des textures d'herbe, de placement des instances et de rendu ;
2. identifier les données de niveau déjà disponibles concernant les collectibles, les objets, les
   collisions, les plateformes et la navigabilité ;
3. déterminer quelles informations peuvent être extraites directement et lesquelles nécessitent de
   nouvelles heuristiques ;
4. proposer une architecture adaptée au moteur et aux contraintes Android ;
5. découper la fonctionnalité en tâches de backlog indépendantes et ordonnées ;
6. identifier les risques techniques et les cas nécessitant un prototype ;
7. définir une première version minimale, puis les améliorations optionnelles ;
8. ajouter l'ensemble au backlog du projet avec les dépendances, critères d'acceptation et outils de
   debug nécessaires.
La première version peut reposer sur des heuristiques simples et robustes, à condition que son
architecture permette ensuite d'améliorer la détection des trajets, des plateformes et des zones de
passage sans réécrire tout le système.

## Report (.autoport/reports/Grecharged-grass-wear/report.txt) RESULT: GRASS WEAR DESIGN <verdict>
The 8 analysis deliverables above; the proposed architecture (influence fields + combination + storage);
the MVP definition; the ordered sub-task backlog with dependencies + acceptance criteria + debug tooling.
## Locks: engine goal_src untouched (analysis may read everything); gold READ-ONLY; NO implementation.
## Max: max_turns 2000, max_retries 4. device: false, owner_verify: true.

## NOTE (2026-07-16, owner clarification): the "AO-as-texturing-mask" analogy (dust/wear gathering where
objects meet, from the Blender tutorial the owner shared) is an IDEA TO EXPLORE when this phase resumes
— explicitly NOT a chosen direction or a fact. The design spike's influence-field architecture remains
the baseline; any AO-mask-inspired approach must be proposed and argued on its merits, not assumed.

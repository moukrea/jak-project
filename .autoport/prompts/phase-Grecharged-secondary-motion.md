# ⚠️⚠️ RÉÉCRITURE ORDONNÉE — LIRE SPEC §17 AVANT TOUTE CHOSE
# Le solveur accumulé (6984 lignes, 54 commits, 19 défauts silencieux trouvés dedans) est JETÉ.
# On garde: format de données, tables de reskin, la SPEC.
# LES VOLUMES "DÉRIVÉS DU MESH" SONT JETÉS AUSSI (SPEC §18): 12 des 1335 sont plus GROS que le
# personnage (max r=13646 sur un perso de 9420), et ma fit-error était une tautologie. La collision
# se fait désormais contre le MESH SKINNÉ RÉEL, pas contre des proxys capsules.
# On réécrit: le coeur du solveur (4 étapes, ZÉRO suppresseur au départ) et TOUTE l'instrumentation
# (une seule grandeur primaire: la position ÉCRITE du joint, frame par frame).
# On livre: KEIRA SEULE d'abord, jusqu'au OUI de l'owner. Puis Jak, le Maire, puis le cast.
# Le journal des cycles ci-dessous est de l'HISTOIRE — il documente ce qui a échoué, pas ce qu'il
# faut refaire.

# ⚠️ LA SPEC EST LE CONTRAT — LIRE D'ABORD `.autoport/prompts/SPEC-physique-secondaire.md`
# Elle synthétise TOUS les retours owner (2026-08-04 → 08-08). Les sections « CYCLE N » ci-dessous
# sont un JOURNAL historique : utile pour le contexte, mais EN CAS DE CONFLIT LA SPEC GAGNE.
# Tourner en rond = re-violer un point déjà dans la spec. La checklist §13 mappe chaque plainte
# owner à son gate : c'est la définition de fini.

# Grecharged-secondary-motion — physique secondaire (jiggle / chaînes) sur les personnages HD

## LA VISION (owner, 2026-08-04 — assumée et cadrée)
Jak and Daxter est un platformer de teenager où Keira est volontairement sexualisée (hanches larges,
taille fine, poitrine affirmée, sous-vêtements qui dépassent, ventre exposé) — c'est assumé par le jeu
(Daxter la drague, love interest de Jak). Pour le remake, maintenant que Keira est en HD :
**jiggle physics de poitrine** — « rien de fou », un mouvement **naturel et cohérent**, indépendant du
corps, comme ç'aurait été fait à l'époque si la PS2 l'avait permis. Subtilité = la barre ; l'owner juge.

## PÉRIMÈTRE (dans l'ordre de valeur)
1. **Keira (HD)** : poitrine — chaîne(s) de physique subtile.
2. **Samos (HD)** : la barbe — APRÈS résolution de ses défauts (clip + bout vers l'avant, cycle 3).
3. **Jak (HD)** : vraie physique sur les vêtements — col, partie bleue au-dessus du pantalon blanc,
   toutes les lanières de cuir qui pendent, cheveux. (Remplace/complète « l'illusion de physique »
   actuelle des vêtements.)
4. **Cheveux longs, tous personnages concernés** : Keira, Samos, Jak, le méchant (Gol) — FERME,
   pas de discussion par personnage (owner 2026-08-04 : « c'était juste une façon de dire — non,
   on le fait puis c'est tout ! »).
5. **Maia + l'archéologue** (designs attractifs assumés) : PAS de modèle HD aujourd'hui → évaluer la
   faisabilité honnêtement : leurs squelettes stock n'ont probablement pas d'os de chaîne au bon
   endroit ; options = injection d'os + transfert de poids sur le modèle stock (même mécanique que le
   prep HD), ou attendre un modèle HD. Ne PAS promettre avant l'évaluation.

## MÉCANISME PRESSENTI (réutilise l'infra existante, ne réinvente pas)
- Les companions HD ont déjà la main sur chaque os À CHAQUE FRAME après le retarget (do-joint-math!) :
  c'est exactement l'endroit canonique du secondary motion. Une chaîne ressort/verlet par zone
  (ancre = l'os parent animé ; les enfants suivent avec inertie/amortissement/limites d'angle).
- Si le donor n'a pas d'os dédiés (poitrine) : le pipeline de prep FABRIQUE déjà les squelettes →
  injecter des os de physique + poids au prep (comme l'align), les exclure de la table k→e (pilotés
  par la sim, pas par le driver).
- Paramètres par chaîne (raideur, amortissement, masse, limites) dans un fichier de données, pas en
  dur — pour itérer vite au verdict de l'owner.
- **GATING (owner, obligatoire)** : feature flag de build dédié `--physics` (FLAG_PHYSICS, généré
  par build.sh comme les autres, fan-out flag-universe complet) **ET** exposition menu :
  (a) **toggle ON/OFF complet** dans les menus (désactivation totale possible in-game) ;
  (b) **sélecteur de PRÉCISION à plusieurs degrés** — SÉMANTIQUE PRÉCISÉE PAR L'OWNER (2026-08-04) :
  une échelle coût↔qualité MONOTONE : « au plus bas ça coûte peu ; au max ça coûte beaucoup plus
  mais c'est plus précis, cohérent, etc. — peut-être avec de la vraie simulation de physique ».
  DEUX BORNES NON NÉGOCIABLES :
    - le niveau LE PLUS BAS reste CRÉDIBLE et cohérent (une approximation légère et propre —
      jamais un truc pourri « pour que ça tourne ») ;
    - le niveau LE PLUS HAUT est LE MEILLEUR RÉALISABLE, pensé pour le bon matériel, JAMAIS bridé
      par les contraintes du bas de l'échelle : vraie simulation (pas de temps fin / substeps —
      « pas » au sens TIME STEP —, collisions chaîne-corps, limites angulaires, plus de chaînes
      actives, itérations de contrainte plus nombreuses…).
  Les leviers par niveau (fréquence/substeps de la sim, nombre de chaînes actives, itérations,
  collisions on/off) sont des DONNÉES réglables, pas du code en dur. L'owner ne maîtrise pas le
  domaine et l'assume : c'est au worker de proposer une échelle honnête et à l'owner de juger le
  rendu à chaque niveau. Persistance via *pc-settings* comme les autres réglages. Comme toujours, assets ND =
  pack externe.

## RÈGLES
- PRÉREQUIS : hd-models4 (cycle défauts) accepté par l'owner ; barbe de Samos réparée avant sa physique.
- Preuves : state dumps des chaînes (positions/vitesses bornées, retour au repos, pas de NaN/explosion)
  + compteurs — PAS de campagnes de captures (règle permanente). L'owner juge le rendu en jouant.
- « Rien de fou » : subtil, crédible, cohérent avec l'esprit du jeu.

## EXTENSION OWNER 2026-08-05 ~11:55 — « on ne laisse RIEN sous le tapis ! »
Le périmètre s'élargit, FERME :
1. **ACCESSOIRES** aussi : les lunettes de Keira (sur sa tête), le bun/chignon de Samos (sa bûche),
   et tout accessoire équivalent qui bougerait naturellement (lunettes de Jak sur son front, sacoches,
   pendentifs…) — même mécanique de chaînes, subtilité de mise.
2. **TOUTES LES VARIANTES DE LOOK** : la physique s'applique à CHAQUE look du carousel (primaires ET
   bonus — le Jak J2, le J3 masqué ou non, Keira J3, Daxter pantalon, Young Samos…), pas seulement
   aux looks par défaut. Les paramètres de chaînes sont par-modèle (data-driven), donc chaque variante
   reçoit ses chaînes propres (cheveux différents, accessoires différents).
3. **TOUS LES PNJ à cheveux longs (et compagnie) — Y COMPRIS MAIA** : l'étude de faisabilité
   Maia/archéologue passe de « évaluer sans promettre » à « DANS LE PÉRIMÈTRE » : pour les
   personnages SANS modèle HD, la voie = injection d'os de physique + poids sur le modèle STOCK
   (le pipeline de prep sait déjà fabriquer/injecter des os — même mécanique que l'align). Recenser
   les PNJ concernés (cheveux longs, barbes, accessoires pendants) et les traiter. Si un cas précis
   s'avère réellement impossible, le documenter avec preuve — pas d'abandon silencieux de catégorie.

## ============================================================
## VERDICT OWNER 2026-08-05 ~16:40 (build physique 15:58) — CYCLE 2 PHYSIQUE
## ============================================================
### A. CONFLIT STRUCTUREL : le FAUX VENT existant se bat avec la physique
Jak1 anime DÉJÀ les lanières, cheveux et vêtements avec un faux vent (canaux d'anim/wind system).
La physique s'ajoute PAR-DESSUS → double animation qui « collide » : vêtements bleus de Jak qui
clippent beaucoup, lanières/cheveux incohérents. FIX : sur toute chaîne pilotée par la physique, le
faux vent doit être NEUTRALISÉ (la physique remplace) — ou converti en simple excitation d'entrée
(source de force), jamais les deux écritures concurrentes sur les mêmes os.
### B. ANCRAGE DES CHEVEUX FAUX : « l'entièreté des cheveux bouge, comme détachée du crâne »
(Jak ET Keira). La RACINE de chaque chaîne de cheveux doit rester VERROUILLÉE au crâne (suit
rigidement la tête) ; gradient de raideur racine→pointe ; seules les pointes ont de l'amplitude.
Vérifier la config des chaînes : la racine est probablement incluse comme os libre.
### C. POITRINE DE KEIRA : « même pas visible du tout, ça bouge pas d'un poil »
Les chaînes rBoob/lBoob sont inertes : vérifier (1) qu'elles sont réellement actives/simulées,
(2) l'excitation — le mouvement du torse doit exciter les chaînes (inertie), pas seulement la
gravité statique ; (3) la raideur (trop haute = figé). Rappel de la barre : « rien de fou », mais
VISIBLE et naturel.
### D. ACCESSOIRES MANQUANTS : pas de physique sur les lunettes de Keira (périmètre élargi 11:55).
### E. BUG MENU (régression-class, priorité) : l'option « Physics Detail » OUVRE LE MESH BROWSER !
Collision de binding dans l'ancien menu (la row physique pointe l'action/entry du mesh browser).
Le toggle « Physics » affiche bien max. Auditer les bindings des rows physique (value-to-modify +
actions) comme au Gmenu-flag-off — ligne par ligne, unicité prouvée.
Priorités : E (menu) + A (conflit vent) d'abord — ce sont eux qui cassent l'expérience ; puis B
(ancrage), C (poitrine), D (lunettes). Les paramètres hot-éditables ne suffisent PAS ici : A/B/E
sont structurels. Timing : après le cycle 5 HD en cours (ou avant si l'owner re-priorise).

## ============================================================
## PRINCIPE DIRECTEUR OWNER 2026-08-05 ~16:50 — LA PHYSIQUE PARTOUT OÙ ELLE EST LOGIQUE (tout le cast)
## ============================================================
« Tout ce qui logiquement aurait de la déformation physique / du mouvement de gravité devrait avoir
de la physique ! Sur TOUS les personnages (PNJs et Jak) ! »
### L'indice-méthode de l'owner (à exploiter systématiquement) :
Beaucoup de personnages ont des PSEUDO-MOUVEMENTS PRÉ-FAITS pour simuler la physique (l'effet vent
sur vêtements/cheveux/lanières de Jak en est un). => Ces canaux de fake-motion sont une CARTE DE
DÉCOUVERTE : scanner les rigs/anims de tout le cast pour trouver où ND a simulé — chaque site simulé
= un site où la vraie physique s'applique (et où le fake doit être neutralisé, cf. cycle-2 A).
### Périmètre universel (liste owner, non exhaustive — le recensement complète) :
- vêtements qui flottent, cheveux, lunettes ;
- la binocle de Samos qui bascule ;
- les poitrines des personnages féminins ;
- objets suspendus/attachés ;
- les fesses (si voluptueuses) des personnages féminins ;
- les ventres des personnages en surpoids (ex. LE PÊCHEUR) ;
- les chapeaux des personnages qui en ont.
### Architecture requise (honnête) :
Les PNJ sont des modèles STOCK sans companion HD → généraliser la sim AU-DELÀ des companions :
un hook de post-anim sur les process-drawables stock (classe joint-mod : la sim écrit les os de
chaîne après l'anim, comme le font les joint-mods existants), chaînes déclarées par nom de joint
dans physics_chains.txt par art-group. Même gating (--physics + toggle + niveaux). Recensement
cast-complet (rigs + canaux fake-motion) au rapport, puis implémentation par vagues (cycles),
personnages les plus visibles d'abord (villageois fréquentés, PNJ de cinématiques).
Ordre global : cycle 2 (les fixes du build actuel : vent×physique, ancrage, poitrine, lunettes,
bug menu) PUIS l'extension cast-complet par vagues.

### PRÉCISION OWNER 2026-08-05 ~16:55 — la carte des faux-mouvements N'EST PAS UN FILTRE
« ND n'a PAS fait de jiggle sur poitrines, fesses et ventres — ça c'est NOUVEAU. Je précise pour que
tu ne skippes pas parce qu'il n'y a pas de faux-physics dessus. »
=> DEUX CATÉGORIES distinctes, toutes deux OBLIGATOIRES :
1. **Sites hérités** (là où ND a simulé : vent sur vêtements/cheveux/lanières, binocle, chapeaux…) —
   découverts via la carte des canaux fake-motion, la vraie physique REMPLACE le fake.
2. **Sites NOUVEAUX** (aucun précurseur ND) : poitrines, fesses, ventres (le pêcheur…) — ce sont des
   AJOUTS du remake, listés par l'owner, à implémenter même sans aucun canal fake existant (ancrage
   sur les os disponibles, ou injection d'os si le rig n'en a pas).
L'absence de fake-motion sur un site owner-listé n'est JAMAIS une raison de l'exclure.

### PRÉCISION OWNER 2026-08-05 ~17:35 — COLLIDERS : exigence explicite anti-clipping
« Faut des colliders et compagnie j'imagine pour éviter le clipping ! »
=> Le cycle 1 a bien des body-sphere collisions, mais le résultat clippe encore (vêtements bleus de
Jak, bretelles de Keira). EXIGENCE CYCLE 2 : un VRAI volume de collision par personnage, suffisant
pour qu'aucune chaîne ne traverse le corps :
- capsules/sphères sur torse, hanches, cuisses, bras, tête/cou (pas 1-2 sphères symboliques) ;
- rayon des chaînes pris en compte (épaisseur du vêtement/lanière), pas juste le point de l'os ;
- colliders SUIVANT les os animés (torse qui tourne, cuisses qui bougent), pas statiques ;
- résolution de pénétration + friction/amortissement au contact pour éviter le jitter ;
- gating par NIVEAU DE PRÉCISION (le niveau max = colliders complets ; les niveaux bas peuvent
  réduire le nombre de colliders, JAMAIS au point de laisser traverser visiblement).
Barre : aucune chaîne ne traverse le corps sur les animations courantes (course, saut, roulade,
cinématiques) ; preuve par compteurs (pénétrations résiduelles par frame = 0 / résolues), jamais
par captures. Les bretelles de Keira sont le cas-test canonique (clip frontal historique).

## ============================================================
## EFFICACITÉ D'ITÉRATION (superviseur 2026-08-06 01:35, demande owner « pas moyen d'être plus efficient ? »)
## ============================================================
Constat : un cycle de tuning a coûté un rebuild C++ COMPLET (1310 objets, y compris les mips2c de
jak2 — reconfigure cmake) + Android, soit des heures pour changer des raideurs. Inacceptable comme
boucle par défaut. TROIS VITESSES, à utiliser dans cet ordre :
1. **PARAMÈTRES SEULS (raideur/amorti/gravité/angles/rayons) = AUCUN BUILD.**
   physics_chains.txt est lu au RUNTIME (kmachine.cpp:1013, get_recharged_assets_dir()). Sur device il
   vit dans `files/custom/jak1/recharged_assets/physics_chains.txt` (vérifié sur eae4df44) :
   `adb shell run-as org.opengoal.gk.jak1 sh -c 'cat > files/custom/jak1/recharged_assets/physics_chains.txt' < fichier`
   puis relancer l'app. Itère le tuning COMME ÇA, pas en rebuildant.
2. **GOAL seul** : make-group iso + gradle repack (pas de NDK/libgk).
3. **C++ modifié** : rebuild complet (le seul cas légitime). ÉVITER les reconfigures cmake inutiles
   (ils invalident tout l'arbre) ; préférer `cmake --build <dir> --target gk` incrémental.
### AMÉLIORATION À LIVRER (owner-facing, priorité haute) :
physics_chains.txt est aujourd'hui packé DANS l'APK (custom pack), et get_recharged_assets_dir() donne
la PRÉCÉDENCE au pack APK sur l'externe => pour l'owner (à distance), un simple retuning = 581 Mo
d'APK à retélécharger. FIX : faire GAGNER une copie présente dans le pack EXTERNE
(<ext>/assets/recharged_assets/physics_chains.txt) sur celle de l'APK (override explicite, log de la
source retenue). Résultat : une itération de tuning owner = un fichier de quelques Ko à déposer,
plus un APK entier. À faire dans ce cycle.

## ============================================================
## WAVE 2 (2026-08-06) — LA PHYSIQUE SUR TOUT LE CAST (priorité owner, après le cycle 2 accepté)
## ============================================================
Le cycle 2 est clos (menu, vent, ancrage, jiggle, lunettes, colliders resid=0). WAVE 2 = le principe
universel déjà spécifié plus haut, à EXÉCUTER :
1. **RECENSEMENT** (rapide, dans le rapport) : scanner les rigs + canaux fake-motion de TOUT le cast
   jak1 (villageois, pêcheur, Maia, l'archéologue, Gol, PNJ de cinématiques...) et lister les sites de
   physique : cheveux longs, barbes, vêtements flottants, chapeaux, binocle de Samos, objets
   suspendus/attachés, POITRINES/FESSES/VENTRES (sites NOUVEAUX sans précurseur ND — obligatoires).
2. **ARCHITECTURE** : les PNJ sont des modèles STOCK sans companion HD => généraliser la sim via un
   hook post-anim de classe joint-mod sur les process-drawables stock ; chaînes déclarées par nom de
   joint dans physics_chains.txt par art-group ; injection d'os quand le rig stock n'en a pas.
3. **LIVRAISON PAR VAGUES** : les personnages les plus vus d'abord (villageois fréquentés, PNJ de
   cinématiques, le pêcheur, Maia). Chaque vague = un build livré à l'owner, pas une vague monstre.
4. Même gating (--physics + toggle + niveaux) ; économie de preuve (compteurs existants, pas de
   nouveaux harnais) ; l'owner juge le rendu.
RAPPEL : livrer aussi l'override externe de physics_chains.txt (tuning owner = quelques Ko, pas 581 Mo)
s'il n'a pas été fait au cycle 2.

## ============================================================
## VERDICT OWNER 2026-08-06 ~07:40 (build 06:28, cycle2+wave2) — CYCLE 3 : LE GROS morceau
## ============================================================
Acquis à NE PAS régresser : lanières de cuir de Jak « vraiment pas mal », mèches avant de Keira
« vraiment pas mal », cheveux de Jak qui tiennent au crâne (ancrage OK).

### A. PRINCIPE ARCHITECTURAL (le plus important — owner) : PRIORITÉ À L'ANIMATION D'AUTEUR
« Il faudrait laisser les animations originales faire leur travail quand elles font des ACTIONS
FORCÉES prévues par Naughty Dog, AU MOMENT où elles le font, et laisser reprendre la physique après —
pour éviter les collisions et garder les intentions originales (c'est cartoon, parfois des animations
sont forcées à juste titre). »
=> Mécanisme à implémenter : par chaîne, détecter quand le canal d'anim PILOTE délibérément les os de
la chaîne (déplacement authored significatif) ⇒ l'ANIMATION GAGNE pendant ce temps (physique
suspendue), puis REPRISE progressive de la physique (blend-out/in, pas de saut). Cas cités :
les OREILLES de Jak, les LUNETTES de Keira quand elles sont SAISIES pour être mises devant ses yeux
(la physique doit être suspendue pendant toute l'animation de saisie/port).
=> EXCEPTION déjà traitée : le faux VENT forcé sur Jak reste éliminé... MAIS idée owner à retenir :
on POURRAIT le laisser reprendre en IDLE quand Jak est EN EXTÉRIEUR (pas en intérieur).

### B. SPAWN & GROSSES TRANSITIONS : « ça part un peu en live »
Sur les grosses transitions de pose, et AU SPAWN de TOUS les acteurs à physique, les chaînes partent
n'importe où. => initialiser les chaînes à la pose de bind au spawn (pas de vélocité héritée),
détecter les téléports/deltas de pose énormes et RESET+blend au lieu de simuler la transition.

### C. FIDÉLITÉ DES COLLIDERS (hypothèse owner, très probablement juste)
« Le bas de sa veste qui va par-dessus son pantalon clip TOUJOURS ÉNORMÉMENT — je pense que tes
colliders ne prennent pas en compte que le pantalon est ÉVASÉ vers le bas. » => capsules à rayon
CONSTANT insuffisantes : il faut des volumes CONIQUES/évasés (rayon différent à chaque extrémité)
pour les jambes/pantalon, et un collider d'épaules correct (le COL de la veste de Jak clippe dans
ses épaules).

### D. PORTÉE / DÉGRADÉ DES CHAÎNES mal réglés (deux symptômes opposés)
- JAK cheveux : « c'est juste le BOUT DU BOUT de sa coiffe qui bouge, ça rend pas bien » ⇒ rootlock
  trop long et/ou gradient trop raide : il faut que plus de la longueur bouge.
- KEIRA cheveux ARRIÈRE (courts) : « a l'air de ne pas être dans le rayon d'influence (dégradé ?) et
  donc est complètement stiff » ⇒ chaînes courtes exclues/figées : le dégradé doit s'adapter à la
  LONGUEUR de la chaîne (une chaîne de 2 maillons doit quand même bouger).

### E. CHAÎNES MANQUANTES
- JAK : l'ANNEAU EN MÉTAL sur son plastron tenu par des lanières de cuir — aucune physique.
- JAK : les OREILLES devraient avoir une physique LÉGÈRE (et respecter A quand l'anim les pilote).

### F. RÉGRESSION (priorité haute) : LES BRETELLES DE KEIRA
« C'est bien, bien PIRE qu'avant, c'était très largement mieux AVANT la physique. Elles clippent au
travers de la poitrine et font des ANGLES TRÈS ARRÊTÉS au lieu de suivre la forme de son corps sur le
devant. » ⇒ soit on les fait suivre le buste correctement (collider de poitrine + contrainte de
surface + lissage des angles), soit on RETIRE la physique de ces chaînes pour revenir au comportement
d'avant. Ne pas laisser en l'état.

### G. AMPLITUDE POITRINE KEIRA : « ça bouge un poil, faut regarder à la loupe — faudrait que ça
jiggle BEAUCOUP PLUS que ça ! » ⇒ monter nettement l'amplitude (raideur/amorti/excitation), tout en
restant crédible. Le « rien de fou » initial était trop timide.

### H. DÉFAUT PRÉ-EXISTANT à corriger au passage : la lanière AVEC BOUCLE MÉTAL dans le DOS de Jak —
la boucle clippe bizarrement avec la lanière (« ça rendait déjà un peu bizarre AVANT la physique »).

### I. GÉNÉRALISATION (owner) : « je pense que tu peux déjà adopter ce feedback à beaucoup d'autres
personnages et PNJs » ⇒ appliquer A/B/C/D à TOUT le cast (spawn, priorité anim, colliders évasés,
dégradé adapté à la longueur), pas seulement Jak/Keira.

## ============================================================
## CYCLE 3b — AJOUT OWNER 2026-08-06 ~08:35 (à traiter DANS cette phase)
## ============================================================
### J. LES OREILLES : TOUT LE MONDE, PAS QUE JAK
« Les oreilles c'est pas seulement celles de Jak qu'il faut mettre en physique hein ! C'est TOUS les
persos ! » ⇒ recenser les os d'oreille sur les 458 rigs (Daxter, Keira, Samos, les sages, les
villageois, Maia, Gol, les lurkers…) et leur donner une physique LÉGÈRE. Contraintes inchangées :
priorité aux animations forcées (section A) et cohérence avec la GRAVITÉ (une oreille pend, elle ne
part pas vers le haut).

### K. MAIA — LA MASSE MANQUE (défaut de MODÈLE physique, pas d'amplitude)
« Sa poitrine n'est pas dégueu niveau physique MAIS son jiggle est bizarre, comme si sa poitrine ne
pesait RIEN, on ne sent pas la masse... L'amplitude de mouvement est pas mal mais c'est trop léger et
JELLY, pas cohérent. En gros oui ça doit bien bouger mais PAS être de la gélatine. »
⇒ Ne PAS toucher à l'amplitude : c'est le comportement qui est faux. Il manque de l'INERTIE — la
réponse doit avoir du retard à l'amorce, de l'élan, et un amortissement qui décroît comme une masse
suspendue, pas comme un ressort sans poids qui frétille. Autrement dit : masse/inertie réelles par
chaîne, fréquence plus basse + amortissement plus lourd à amplitude conservée. À généraliser à TOUTES
les poitrines/ventres/fesses (Keira incluse : au cycle 3 on monte son amplitude — elle ne doit pas
devenir jelly pour autant).

### L. MAIA — GLITCH DE SPAWN, QUELQUE CHOSE « SCALE ÉNORME »
« Son spawn quand on la voit de loin on dirait que ça glitche, difficile de savoir quoi exactement
mais un truc SCALE ÉNORME. » ⇒ corrobore la section B (spawn/transitions), avec un indice précis :
une ÉCHELLE qui explose, pas seulement une position qui part. HYPOTHÈSE À VÉRIFIER EN PRIORITÉ : la
matrice réécrite par la sim n'est pas orthonormale — le write-back compose une rotation/swing avec un
reste d'échelle au lieu d'écrire une rotation pure. Un os d'échelle non-unitaire au premier frame
donne exactement « un truc qui scale énorme » vu de loin. Vérifier l'orthonormalité du write-back
(déterminant ~1, colonnes unitaires) et le clamp au frame de bind.

### M. CHAÎNES DÉCLARÉES MAIS INERTES : MAIA ET GOL
« Ses cheveux n'ont pas de physique (tout comme Gol il semblerait). » Or le recensement vague 2
DÉCLARE déjà pour evilsis (Maia) une queue de cheval 8 maillons + 3 chaînes de cheveux arrière, et
pour evilbro (Gol) cheveux + bouc + capes. ⇒ Elles sont déclarées et NE TOURNENT PAS. C'est la preuve
que « déclaré » ≠ « actif » : le compteur agrégé de la vague 2 n'a pas su le voir. Trouver pourquoi
(nom d'os qui ne résout pas ? hook post-anim non atteint pour ces classes ? chaîne filtrée par le
dégradé ?) et poser un compteur PAR ACTEUR ET PAR CHAÎNE : pour chaque acteur à l'écran, chaque
chaîne déclarée doit montrer un déplacement non nul, sinon c'est un échec. Ce compteur doit
apparaître dans le rapport pour Maia ET Gol nommément.

## ============================================================
## CYCLE 3c — PRÉCISIONS OWNER 2026-08-06 ~09:05 (prioritaires — corrigent 3b)
## ============================================================
### N. MAIA AU SPAWN : CE N'EST PAS UNE ÉCHELLE, CE SONT LES COLLIDERS
Correction de l'owner sur la section L : « Le gros truc qu'on voit de loin, je crois en fait que ce
sont ses CHEVEUX qui passent AU TRAVERS de son corps — ce qui implique qu'ils ont bien de la physique,
mais que les COLLIDERS ne sont pas bons ! »
⇒ L'hypothèse « write-back non orthonormal / échelle » passe en SECONDAIRE (à vérifier vite, sans y
passer du temps). La piste PRIMAIRE : evilsis (Maia) n'a pas de volume de corps correct — ses cheveux
traversent son torse/sa tête/ses épaules. Il faut un VRAI volume corporel sur elle (capsules suivant
ses os animés, comme pour Jak/Keira), et l'audit de pénétration doit être rapporté POUR MAIA
NOMMÉMENT (resid=0), pas seulement en agrégat.
⇒ Nuance sur la section M : les cheveux de Maia BOUGENT (ils pénètrent), donc « déclaré mais inerte »
n'est pas la bonne lecture pour elle au spawn. Le compteur par acteur ET par chaîne reste exigé — il
doit dire, pour Maia et pour Gol, chaîne par chaîne : active oui/non, et déplacement mesuré.

### O. RÈGLE DE SOLVEUR (générale, s'applique à TOUT ce qui est sous contrainte forte)
« Pour le col de Jak dans la cinématique d'intro, quand il est allongé (tout premier plan), j'ai
l'impression que la contrainte des colliders le fait JITTER COMME UN FOU au lieu d'essayer de se
conformer. Si ça ne se conforme pas, au lieu que ça bouge dans tous les sens comme un fou, ça devrait
juste RESTER TRANQUILLE tout en essayant TRANQUILLEMENT de se conformer. Idem pour TOUTES les choses
soumises à contraintes fortes, sinon ça fait très glitchy ! »
⇒ Exigence de conception, pas un réglage : une contrainte INSATISFIABLE ne doit JAMAIS produire
d'oscillation. Concrètement :
  * projection SOUPLE et amortie (correction positionnelle bornée par frame), jamais une projection
    dure ré-appliquée chaque frame — c'est ça qui crée la boucle d'énergie ;
  * la correction de contrainte ne doit PAS réinjecter de vitesse (tuer la composante de vélocité
    ajoutée par la projection, sinon le solveur se nourrit lui-même) ;
  * hystérésis / zone morte : sous pénétration persistante, on converge lentement vers la surface et
    on se STABILISE, on ne rebondit pas ;
  * état de repos détecté : si la contrainte reste insatisfaite N frames, la chaîne se fige
    doucement (amortissement fortement augmenté) au lieu de vibrer.
⇒ Cas de test cité par l'owner : le COL de Jak, cinématique d'intro, Jak ALLONGÉ, tout premier plan
(contact fort col/épaule/sol). À traiter comme un cas de non-régression.

## ============================================================
## CYCLE 3d — OWNER 2026-08-06 ~09:20 (dernier point sur l'état actuel)
## ============================================================
### P. TRANSITION EN CRAN SUR LES OREILLES DE DAXTER
« J'ai l'impression que la MOITIÉ HAUTE de ses oreilles a de la physique, mais la transition est trop
BRUTALE à mi-hauteur : ça fait un CRAN bizarre. »
⇒ C'est le même réglage que la section D, mais le défaut n'est pas « trop peu / trop de mouvement » :
c'est une DISCONTINUITÉ. Un `rootlock=N` binaire (les N premiers maillons rigides, les suivants
libres) crée par construction une cassure nette exactement à la frontière. Il faut un profil
d'influence CONTINU le long de la chaîne — la liberté doit monter progressivement de la racine vers
la pointe, sans marche. Le pli visible est le symptôme d'une dérivée discontinue, pas d'une amplitude
mal choisie.
⇒ EXIGENCE : rapporter le PROFIL D'INFLUENCE par maillon (poids maillon 0..n) pour les oreilles de
Daxter, et montrer que l'écart entre deux maillons voisins est borné (pas de saut). À appliquer à
TOUTES les chaînes courtes où le cran se verrait (oreilles, mèches, sangles).

### Q. RAPPEL OWNER (déjà section A, à ne pas perdre de vue) : les ANIMATIONS ORIGINALES ONT LA
PRIORITÉ sur la physique, et la physique REPREND APRÈS. « Ça doit être le cas sur les oreilles de
Daxter comme sur le reste. » ⇒ les oreilles de Daxter sont hand-keyées par ND dans plein
d'animations : quand l'anim les pilote, elle gagne ; la sim revient en blend ensuite.

## ============================================================
## CYCLE 4 — VERDICT OWNER 2026-08-06 ~14:45 sur le build 14:12 (cycle 3)
## ============================================================
Acquis : « les cheveux sont mieux animés, les oreilles aussi ». MAIS : « l'hystérésis est HORRIBLE,
et il reste beaucoup, beaucoup de choses à améliorer ».

### R. LA QUESTION DE L'OWNER EST PROBABLEMENT LA CAUSE RACINE — À TRAITER EN PREMIER
« Es-tu sûr d'avoir défini un HAUT et un BAS, une MASSE ? »
Trois symptômes distincts pointent tous vers le même défaut :
  * la MANCHE DE GOL « a de la physique mais pointe VERS L'AVANT au lieu de suivre la gravité » ;
  * la poitrine de Maia « se balade MÊME SANS MOUVEMENT et FLOTTE » ;
  * rien ne se repose vraiment nulle part.
HYPOTHÈSE PRIMAIRE : la gravité n'est PAS appliquée dans le bon repère. Si le vecteur de gravité est
exprimé en espace LOCAL (os / acteur) au lieu de l'espace MONDE, alors « le bas » tourne avec l'os —
une manche horizontale reçoit une gravité horizontale et pointe vers l'avant, et une chaîne au repos
n'a aucune direction de repos stable donc elle dérive. VÉRIFIER EXPLICITEMENT :
  1. le vecteur gravité est-il transformé en espace monde à chaque frame ? (le prouver, pas le
     supposer : imprimer la direction effective de gravité vue par une chaîne, sur un acteur tourné
     de 90° et sur un os horizontal — elle doit rester (0,-1,0) monde) ;
  2. la MASSE participe-t-elle réellement à l'intégration (a = F/m) ou `mass=` n'est-elle qu'une clé
     de données lue et jamais utilisée ? Le prouver en montrant le chemin de code, pas la clé.
  3. existe-t-il une POSE DE REPOS stable vers laquelle une chaîne converge sans entrée ?

### S. MON INSTRUMENT DE JITTER MESURAIT LA MAUVAISE CHOSE — À RECONSTRUIRE
Le rapport du cycle 3 annonce jitter=3..7 « calme », et l'owner voit une hystérésis HORRIBLE sur
Jak (cheveux, oreilles, col, veste par-dessus le pantalon), derrière la nuque de Keira, et sur les
PATTES DES LURKERS. Donc la métrique ment. Cause identifiée : en cours de cycle 3 la métrique a été
restreinte aux « inversions de CONTACT » en écartant explicitement « l'oscillation normale d'un
ressort ». C'est précisément ce qui a été écarté que l'owner voit. La sonnerie (ringing) en espace
LIBRE est le défaut, pas seulement la bagarre contre un collider.
=> Reconstruire la mesure sur deux grandeurs qui ne peuvent pas mentir :
  * DÉRIVE À VIDE : acteur immobile, animation sans delta => déplacement de chaîne ≈ 0 après
    stabilisation. Toute chaîne qui bouge sans entrée est en faute (cas Maia).
  * TEMPS DE STABILISATION : après l'arrêt du mouvement moteur, l'amplitude doit décroître
    monotonement jusqu'au repos en un temps borné. Mesurer la décroissance, pas l'absence de contact.
INTERDICTION : ne pas re-restreindre la métrique pour la faire passer. Si elle est rouge, c'est le
solveur qui change.

### T. KEIRA : SEULS LES BOUTS BOUGENT
« On dirait que seuls les bouts de ses seins bougent un peu au lieu de l'entièreté de sa poitrine. »
=> Même classe que le cran des oreilles : le profil d'influence est trop verrouillé à la racine. Une
poitrine doit se déplacer en VOLUME, pas juste au bout de la chaîne. Revoir le profil des chaînes de
poitrine (et vérifier que `mass` ne se contente pas de ralentir la pointe).

### U. MAIA : LES CHEVEUX TRAVERSENT TOUJOURS SON CORPS
Le cycle 3 rapporte `resid=0` pour Maia et l'owner voit toujours la pénétration. Donc l'audit ne
mesure pas ce qu'il voit : soit les capsules ne couvrent pas le volume réel (tête/nuque/épaules/dos),
soit la chaîne de cheveux ne teste pas contre ces capsules, soit l'audit n'échantillonne pas la pose
où ça arrive. Trouver LEQUEL des trois, le dire, et rendre l'audit représentatif.

### V. RESTE OUVERT DU CYCLE 3 (non résolu, ne pas re-livrer sans)
  * la VESTE de Jak par-dessus le pantalon clippe TOUJOURS (section C : colliders évasés) ;
  * hystérésis sur les PATTES DES LURKERS et derrière la NUQUE de Keira (nouveaux sites).

## ============================================================
## CYCLE 4 — ORDRE DE TRAVAIL IMPOSÉ (superviseur, après 3h15 sans avancée sur les défauts)
## ============================================================
La tentative précédente a écrit 645 lignes, construit Android, ajouté `hang`/`swing`... et n'a touché
AUCUN des endroits où l'owner voit le défaut. Elle a en plus brûlé ~100 minutes dans un build x86
"pour la preuve" qui a affamé la jambe device. On inverse l'ordre.

### ÉTAPE 1 — DONNÉES SEULES, AUCUN BUILD (à faire AVANT toute compilation)
`hang=` est à 0 sur : poitrines (0/14), col (0/6), chemise (0/4), cheveux (0/28), oreilles (0/84),
lanières (0/50). Ce sont EXACTEMENT les pièces citées par l'owner. Couvrir ces chaînes dans
`physics_chains.txt`. C'est un fichier de DONNÉES lu au runtime : zéro compilation, `adb push` suffit.
Livrable de l'étape 1 : les compteurs de couverture, par pièce, avant/après.

### ÉTAPE 2 — L'INSTRUMENT QUI MANQUE (GOAL seul, pas de C++)
`idledrift`, `settletime`, `unsettled` sont déclarés mais ne produisent RIEN (`n/a` partout depuis
3 heures). Sans eux, rien ne prouve « ses seins se baladent même sans mouvement ». Les faire ÉMETTRE
une valeur par chaîne et par fenêtre, et les faire apparaître dans les jambes.
ATTENTION classe de faux-vert déjà rencontrée aujourd'hui : `resid=0` avec `push=0` ne prouvait rien.
Un `jitter=0` ou un `idledrift=0` doit être accompagné du compteur qui prouve que la mesure a bien
tourné (fenêtres échantillonnées > 0), sinon c'est un zéro vide.

### ÉTAPE 3 — PREUVE SUR ANDROID UNIQUEMENT
Le build x86 "evidence only" est INTERDIT pour ce cycle : il a coûté 100 minutes et n'a rien prouvé
que la jambe device ne prouve. Android est déjà construit. Ne jamais faire tourner un build lourd en
parallèle d'une jambe device (la précédente est tombée à 4 fenêtres au lieu de 20).

### ÉTAPE 4 — RAPPORT
Le rapport sur disque date du cycle 3 (13:55). Le réécrire pour le cycle 4, section par section
(R, S, T, U, V), avec les nombres réellement mesurés.

## ============================================================
## CYCLE 5 — SPÉCIFICATION OWNER 2026-08-06 ~21:10 (builds 19:05 + 20:48)
## CETTE SECTION CORRIGE LE CYCLE 4 : la couverture `hang=` étendue aux CHEVEUX, OREILLES et
## POITRINES était une ERREUR de direction. Lire W avant tout le reste.
## ============================================================

### W. LE MODÈLE 3D EST LA SOURCE DE VÉRITÉ DE LA POSE DE REPOS (règle fondamentale)
« Pour les cheveux, les seins, les oreilles (et probablement d'autres choses), même si sujets à la
gravité, la position IDLE devrait être EXACTEMENT celle du modèle de base — pas plus haut, pas plus
bas. C'est là que ça retourne naturellement. Le bounce est naturel, l'élasticité aussi. »
« Hormis les accessoires et les lanières / trucs supposés pendre, la FORME des éléments soumis à la
physique doit se baser sur la source de vérité du modèle, car c'est la représentation des
personnages VOULUE PAR NAUGHTY DOG : pas plus écrasé, pas plus tassé, pas plus bas. En idle ça doit
être comme le modèle original ; lors d'un mouvement c'est soumis à la physique, ça se déforme / se
déplace, et ÇA REVIENT EN POSITION. »
=> PRÉCISION OWNER (21:20, à ne pas se tromper) : « PAS exactement le modèle, mais REGAGNER cette
   forme quand en idle ou dans une position classique, MAIS SUJETS À LA PHYSIQUE. »
   Autrement dit : la chaîne reste simulée EN PERMANENCE — on ne la fige jamais, on ne la clampe
   jamais sur la pose du modèle. Ce qui change, c'est la CIBLE D'ÉQUILIBRE : le point vers lequel le
   ressort converge est la POSE DU MODÈLE, pas une pose déplacée par la gravité.
   * pendant le mouvement : déformation et déplacement NORMAUX et souhaités (bounce, élasticité) ;
   * quand ça se calme, en orientation classique : ça REVIENT à la forme du modèle, ni plus haut,
     ni plus bas, ni plus écrasé.
   Donc la mesure correcte n'est PAS « déviation instantanée ~0 » (ce serait interdire le bounce),
   c'est « déviation APRÈS STABILISATION ~0 » — le retour à la forme d'origine.
=> La GRAVITÉ agit donc sur la DYNAMIQUE de ces éléments, pas sur leur point d'équilibre.
=> EXCEPTION explicite de l'owner : quand l'orientation du personnage n'est PLUS approximativement
   celle d'origine (penché en avant, tête en bas...), la gravité reprend ses droits — « si tu pends
   Maia par les pieds, forcément ses seins ne seront pas à la même position que debout ».
=> DONC : retirer / neutraliser `hang=` (attraction vers le bas monde) sur les chaînes de CORPS
   (cheveux, oreilles, poitrines, et tout ce qui n'est pas censé pendre), et le CONSERVER seulement
   là où l'owner le veut (section X). Ce que le cycle 4 a fait sur 84 oreilles / 28 cheveux /
   14 poitrines doit être revu à cette aune.

### X. CE QUI DOIT PENDRE PEND VRAIMENT — SAUF À S'ÉCRASER
« Pour les trucs qui doivent pendre (accessoires, lanières, vêtements qui pendent), eux sont bien
soumis à la gravité par cohérence logique. Mais attention par exemple au COL DE JAK qui ne doit pas
s'écraser pour autant ! »
=> Garder la gravité de repos sur : accessoires, lanières de cuir, pans/vêtements pendants.
=> Mais aucun élément ne doit se TASSER : longueur/volume de la chaîne au repos ≈ celle du modèle.
   Le col de Jak est le cas nommé — à mesurer et à rapporter.

### Y. POITRINES — SPÉCIFICATION PAR PERSONNAGE (à traiter au cas par cas, tout doit être cohérent :
### masse, élasticité, fermeté, bounce)
Règle commune : **la position sur le modèle de base est la position attendue en idle. Ne PAS les
faire tomber plus sous le poids de la gravité.** Le jiggle/bounce n'existe QUE quand ça bouge ou que
l'angle diffère de l'idle.
  * KEIRA — ronds et FERMES sur le modèle. En physique : ça bouge bien, mais surtout ça
    S'ENTRE-CHOQUE (contact entre les deux), peu de droop, peu de déformation. « Jeune et fraîche ».
    Le mouvement doit rester bien visible malgré la fermeté.
  * MAIA — morphologie plus mûre, GROS seins : naturellement plus tombants, plus lâches, moins
    fermes. Mais l'idle reste celui du modèle.
  * LA VIEILLE AUX OISEAUX (bird-lady) — a une poitrine, même règle.
  * L'ARCHÉOLOGUE — trentenaire, seins plus petits que Maia : un ENTRE-DEUX entre Keira et Maia.
=> Les paramètres (masse, raideur, amorti, contact inter-sein) doivent DIFFÉRER entre ces quatre
   personnages et la différence doit être justifiée dans le rapport, pas copiée-collée.

### Z. COLLIDERS — « SI ÇA PEUT COLLIDE AVEC X, ALORS ÇA DOIT CONSIDÉRER X »
Deux cas nommés par l'owner :
  1. Les CHEVEUX DE MAIA passent au travers du BAS de son corps ⇒ sa chevelure doit collisionner avec
     le corps ENTIER (bassin/jambes compris), pas seulement tête/torse/épaules.
  2. Le BAS DE LA VESTE DE JAK : « certes les deux pendants sont scopés à une jambe chacun, mais il
     ne faut pas ignorer la jambe OPPOSÉE. Sur les deux derniers builds le pendant gauche finit au
     travers de la jambe droite et le pendant droit au travers de la jambe gauche, CROISÉS,
     complètement incohérents. »
  ⇒ Le scoping par chaîne est une optimisation, pas une autorisation de traverser. Toute chaîne doit
     tester contre TOUT volume qu'elle peut physiquement atteindre. Rapporter, par chaîne, la liste
     des colliders testés et un compteur de traversées croisées = 0.

## ============================================================
## CYCLE 5 — RÈGLE STRUCTURANTE (owner 21:30, 3e répétition : IMPRIMER)
## « C'EST DU CAS PAR CAS ! SOIS COHÉRENT »
## ============================================================
CHAQUE chaîne doit être CLASSÉE dans une famille, et la famille détermine le comportement au repos.
La classification doit apparaître dans `physics_chains.txt` ET dans le rapport, chaîne par chaîne.

### FAMILLE A — PARTIES DU CORPS : cheveux, seins, oreilles, et « probablement d'autres choses »
  * Simulées en permanence, soumises à la gravité pendant le mouvement.
  * MAIS leur point de retour est la POSE DU MODÈLE : « la position idle devrait exactement être
    celle du modèle de base, PAS PLUS HAUT, PAS PLUS BAS, c'est là que ça retourne naturellement ».
  * Bounce et élasticité = naturels et voulus.
  * Exception : orientation non naturelle (penché, tête en bas) => la gravité reprend ses droits.

### FAMILLE B — CE QUI PEND VRAIMENT : accessoires (lunettes, sacs), lanières de cuir, vêtements
### pendants
  * « ÇA PEND, ÇA PEND, c'est normal et cohérent ! » => elles NE DOIVENT PAS regagner la pose du
    modèle. Leur repos est dicté par la GRAVITÉ, point.
  * NE JAMAIS leur appliquer le critère de la famille A. Un pan de veste qui « revient à la pose du
    modèle » serait un BUG au même titre qu'un sein qui s'affaisse.
  * Seule contrainte : rien ne doit se TASSER / s'écraser (col de Jak = cas nommé).

### INTERDIT
  * Un réglage unique appliqué aux deux familles.
  * Des paramètres copiés-collés entre personnages (masse, élasticité, fermeté, bounce se traitent
    AU CAS PAR CAS et doivent être cohérents entre eux).

### DÉRIVATION DE LA FAMILLE — C'EST AU FRAMEWORK DE TRANCHER, PAS À L'OWNER
(owner 22:00 : « tu devrais, toi et le framework, être à même de déterminer si c'est A ou B ! »)
La famille se déduit de la NATURE de l'élément, mécaniquement :
  * FAMILLE A (corps — retour à la forme du modèle) : cheveux sous toutes leurs formes (hair, bang,
    braid, ponytail, backhair, midhair, fro...), barbe/bouc/moustache (beard, goatee, stache),
    OREILLES, poitrine (chest), ventre (belly), fesses, joues/bajoues, fourrure (fur), queue (tail),
    cornes, crête, plumes de la créature — tout ce qui EST le personnage.
  * FAMILLE B (ça pend — la gravité dicte le repos) : sangles et lanières (strap, belt, lace),
    pans et rabats de vêtement (flap, hem, coatflap, kneeflap), capes, tabliers, pendeloques
    (dangler, dangle, ball), accessoires (goggles, hat, bandana, earring, chain, necklace, bag,
    pouch), cordes, entraves — tout ce qui est PORTÉ ou ACCROCHÉ.
  * Cas ambigu : trancher par la question « si le personnage s'immobilise, est-ce que cet élément
    doit revenir à la forme sculptée par ND, ou pendre ? » — et écrire la réponse dans le rapport.

### CONTRAINTE MÉCANIQUE QUI EN DÉCOULE (état constaté à 22:00 : 158 chaînes family=A portent encore
### hang>0, donc leur repos est encore tiré vers le bas — c'est la contradiction à éliminer)
  * `family=A` => AUCUNE attraction gravitaire sur la POSE DE REPOS. La gravité n'agit que sur la
    dynamique. Si la clé `hang` reste présente sur une chaîne A, il faut prouver dans le rapport
    qu'elle ne touche plus le point d'équilibre — sinon `hang` doit valoir 0 sur toute la famille A.
  * `family=B` => attraction gravitaire au repos ASSUMÉE, et surtout PAS de retour à la pose du
    modèle.

## ============================================================
## CYCLE 5 — CONSIGNE RESSERRÉE (superviseur, 00:25, après 3h de mesure sans convergence)
## ============================================================
L'INSTRUMENTATION EST BONNE ET NE DOIT PLUS BOUGER. Elle est désormais fiable : `restdevA` est
échantillonné sur 51281 frames réelles (le 0.0000 précédent était un zéro vide, `restwin=0`), et
elle dit la vérité — la spec de l'owner n'est PAS respectée. Ne pas retoucher les compteurs, ne pas
en ajouter, ne pas redéfinir de métrique. Le travail restant est un travail de SOLVEUR et de DONNÉES.

TROIS CIBLES CHIFFRÉES, RIEN D'AUTRE. Ne pas ouvrir d'autre sujet tant que les trois ne sont pas
tenues simultanément sur la même exécution device :
  1. `restdevA` ≈ 0 AVEC `restwin` > 0   (état: 948.27 sur 51281 échantillons)
     => une chaîne de CORPS doit se reposer sur la forme du modèle. C'est LA règle de l'owner.
  2. `lenmin` et `lensim` >= 0.97        (état: 0.6757 / 0.7761)
     => rien ne s'écrase. Une chaîne à 68 % de sa longueur modélisée est un défaut visible.
  3. `xleg` = 0                          (état: 2, et 50 sur une autre jambe)
     => plus aucune traversée du volume opposé.
Plus : zéro pénétration résiduelle, et les 40 marqueurs `@@...@@` du rapport doivent être remplis.

MÉTHODE IMPOSÉE : traiter les trois cibles UNE PAR UNE, en vérifiant après chacune que les deux
autres n'ont pas régressé. Les allers-retours des dernières heures viennent de changements
simultanés (xleg est repassé de 0 à 50 pendant qu'on travaillait l'écrasement).
INTERDIT : rebuild x86, nouvelle campagne de preuve, nouvel instrument.

## ============================================================
## CYCLE 6 — BLOCKER OWNER 2026-08-07 ~01:20 (build 00:54)
## ============================================================
### RÈGLE BLOQUANTE (owner, mot pour mot)
« Les objets / parties ayant de la physique NE DOIVENT PAS PASSER AU TRAVERS DU MESH DE LEUR
PERSONNAGE ! QU'IMPORTE LA RAISON ! C'est un gros blocker ça ! »
=> Ce n'est pas un objectif chiffré parmi d'autres : c'est une condition de livraison. Aucun build
   ne part tant qu'une chaîne traverse le corps de son propre personnage.

### L'INSTRUMENT EST FALSIFIÉ PAR L'OBSERVATION — IL DOIT ÊTRE REFAIT
Le cycle 5 rapporte `xleg=0` pour les DEUX pans de la veste de Jak, et l'owner voit toujours,
sur le build 00:54, « ce qui recouvre la jambe gauche qui va dans la jambe droite et inversement ».
Donc l'audit de pénétration ne mesure PAS ce que l'owner voit. C'est le seul cas où l'on a le droit
de reconstruire un instrument : il est réfuté par l'observation directe.
EXIGENCE ABSOLUE — CONTRÔLE POSITIF : avant de rapporter le moindre zéro, l'audit doit PROUVER
qu'il sait détecter une pénétration. Injecter délibérément une chaîne dans le corps, montrer que le
compteur monte, puis retirer l'injection. Un zéro sans contrôle positif est refusé (on a déjà eu
`resid=0` avec `push=0`, `idledrift=0` avec `idlewin=0`, `restdevA=0` avec `restwin=0` — trois zéros
vides en une journée).
Le volume testé doit approcher le MESH du personnage, pas un jeu de capsules qui laisse passer entre
elles. Si deux capsules laissent un interstice, l'élément passe : c'est ce que l'owner voit.

### SITES DE CLIPPING NOMMÉS PAR L'OWNER (build 00:54) — chacun doit être vérifié individuellement
  1. JAK — le COL clippe avec ses ÉPAULES.
  2. JAK — la BOUCLE MÉTAL du dos clippe avec la GROSSE LANIÈRE de cuir qui pend
     (=> deux éléments à physique qui se traversent l'un l'autre : le test ne doit pas être
     seulement chaîne-vs-corps, mais aussi CHAÎNE-vs-CHAÎNE).
  3. JAK — la partie de la veste qui dépasse sur les jambes clippe TOUJOURS EN CROISÉ
     (gauche -> jambe droite, droite -> jambe gauche). NON RÉSOLU malgré xleg=0. Voir ci-dessus.
  4. KEIRA — les cheveux de la NUQUE clippent au travers de son COU.
  5. KEIRA — les LUNETTES clippent au travers de sa POITRINE.
  6. KEIRA — les MÈCHES DE DEVANT clippent au travers de son VISAGE (parfois) et de ses OREILLES
     (souvent).

### POITRINE DE KEIRA — RÉGLAGE (acquis à ne pas perdre)
« Beaucoup mieux, mais mériterait PLUS DE JIGGLE et UN POIL PLUS DE FERMETÉ. »
=> Augmenter l'amplitude ET la fermeté ensemble (plus de rebond, retour plus franc), sans revenir au
   comportement gélatineux ni casser `restdevA`.

### PORTÉE DU BLOCKER : TOUT LE CAST (owner 01:35)
« Le clipping des parties sujettes à la physique sur le reste du personnage concerne QUASIMENT TOUS
LES PERSONNAGES ! Pas juste Keira et Jak ! »
=> La règle s'applique aux **60 modèles** qui portent de la physique (345 chaînes). Les six sites
   nommés par l'owner sont des EXEMPLES, pas la liste des choses à corriger.
=> ÉTAT CONSTATÉ AU 01:35 : 235 volumes déclarés au total, mais **4 modèles ont de la physique et
   AUCUN collider** : `lightning-mole-lod0`, `lurkerpuppy-lod0`, `sidekick-human-lod0`,
   `swamp-rat-lod0`. Leurs chaînes n'ont donc littéralement rien contre quoi buter. À corriger.
=> Pour les 56 autres, le problème n'est pas l'absence de volume mais sa QUALITÉ : des capsules qui
   laissent des interstices entre elles laissent passer une mèche ou un pan. C'est ce que l'owner
   voit sur Keira (cou, poitrine, visage, oreilles) et sur Jak (épaules, jambes croisées).
=> LIVRABLE : un audit de pénétration PAR MODÈLE couvrant les 60, avec le contrôle positif appliqué
   à chacun (un compteur qui n'a jamais su monter sur ce modèle ne prouve rien pour ce modèle).
   Rapporter la liste des modèles audités et, pour chacun, pénétration = 0 AVEC contrôle positif.

### CAUSE RACINE DONNÉE PAR L'OWNER (01:45) — DEUX PROBLÈMES LIÉS
« Je pense surtout que les colliders sont NULS À CHIER et ne suivent pas les formes des mesh avec
suffisamment de détail (ou carrément à côté de la plaque). Ensuite les éléments ayant de la physique
EUX-MÊMES n'ont pas de colliders, donc évidemment si deux entrent en collision ça clip. »

#### PROBLÈME 1 — LES VOLUMES DE CORPS NE SUIVENT PAS LE MESH
Les capsules sont écrites À LA MAIN dans `physics_chains.txt` (rayon + deux os). Une capsule ne peut
pas épouser un torse, une épaule, une mâchoire ou une cuisse : soit elle est trop fine et le mesh
dépasse (l'élément passe à travers la peau), soit elle est trop grosse et l'élément flotte.
=> LA COLLISION DOIT ÊTRE DÉRIVÉE DU MESH, pas devinée. Construire les volumes À PARTIR de la
   géométrie merc réelle : pour chaque os, prendre les sommets qui lui sont skinnés et en déduire le
   volume englobant (enveloppe convexe par os, boîte orientée, ou chapelet de sphères ajusté). Les
   capsules manuelles ne restent acceptables que là où l'ajustement mesuré est bon.
=> MESURE OBLIGATOIRE, « fit error » : pour chaque os, la distance maximale dont un sommet du MESH
   SORT du volume de collision. Un sommet qui dépasse = un trou par lequel un élément passera. À
   rapporter PAR MODÈLE, avec le pire os nommé. C'est ce chiffre qui dit si les colliders sont
   « à côté de la plaque », et il ne dépend d'aucun jugement visuel.

#### PROBLÈME 2 — LES ÉLÉMENTS À PHYSIQUE N'ONT PAS DE VOLUME PROPRE
Aujourd'hui une chaîne est une ligne de points : elle peut buter contre le corps, mais deux chaînes
ne se voient pas. D'où la boucle métal de Jak qui traverse sa propre lanière, les lunettes de Keira
qui entrent dans sa poitrine, ses mèches qui traversent ses oreilles.
=> Donner à CHAQUE MAILLON son propre volume (rayon par maillon, dérivé lui aussi de l'épaisseur du
   mesh qu'il porte), et activer la collision CHAÎNE ↔ CHAÎNE en plus de CHAÎNE ↔ CORPS.
=> Rapporter un compteur de contacts chaîne-chaîne (avec contrôle positif : il doit savoir monter).

## ============================================================
## CYCLE 7 — VERDICT OWNER 2026-08-07 ~07:50 sur le build 07:17
## ============================================================
« Il n'y a AUCUNE DIFFÉRENCE avec les builds précédents. Seul truc remarqué : la poitrine de Keira
bouge un peu plus, mais elle est beaucoup plus FLASQUE, [devrait être] plus FERME, et ne bouge PAS
ASSEZ. Sinon vraiment mes feedbacks précédents sont TOUJOURS VRAIS. »

### AA. DEUXIÈME COMPTEUR RÉFUTÉ — LE SOUPÇON N°1 EST LA CORRESPONDANCE OS <-> MESH
Le cycle 6 a mesuré le pan gauche de Jak à −47,68 unités dans le volume de la jambe DROITE, a changé
l'ordre de résolution, et rapporte `xleg=0` avec `xheld=7299`. L'owner ne voit AUCUN changement.
Comme pour `resid=0`/`push=0` hier, la conclusion la plus probable n'est pas « le correctif est
faible » mais « on ne pilote pas la géométrie que l'owner regarde ».
CONSTAT À VÉRIFIER EN PRIORITÉ : sur `jak-hd`, la chaîne `shirtL` ne pilote QU'UN SEUL os,
`shirtLthigh` (idem `shirtR`/`shirtRthigh`). Si la partie de veste qui pend sur les jambes est
majoritairement skinnée sur l'os de CUISSE (jambe) et non sur `shirtLthigh`, alors la physique agit
sur quelques sommets seulement et le pan continue de suivre la jambe — ce qui produit exactement
« aucune différence ».
=> EXIGENCE : pour CHAQUE défaut nommé par l'owner, PROUVER la correspondance avant de corriger.
   Pour la géométrie fautive, lister les JOINTS qui la skinnent et le POIDS que chacun porte
   (nombre de sommets et poids cumulé). Puis dire si ce ou ces joints sont dans une chaîne.
   Si la géométrie visible n'est pas majoritairement pilotée par la chaîne, aucun réglage de solveur
   ne la corrigera : il faut soit étendre la chaîne aux bons joints, soit injecter le joint manquant.
   À faire pour : le pan de veste de Jak, son col, la boucle du dos, les cheveux de nuque de Keira,
   ses lunettes, ses mèches de devant.
=> Ce diagnostic doit apparaître dans le rapport AVANT toute nouvelle valeur de paramètre.

### AB. POITRINE DE KEIRA — LE RÉGLAGE EST PARTI DANS LE MAUVAIS SENS
Demandé au cycle 6 : « plus de jiggle ET un poil plus de fermeté ». Résultat : plus flasque et
toujours pas assez de mouvement. Il faut les DEUX ensemble : amplitude nettement plus grande ET
retour plus franc (fermeté), pas un compromis mou. Rappel de la spec : ronds et FERMES, ils
s'entre-choquent, peu de droop, peu de déformation, mais ça BOUGE bien.

### AC. TOUS LES AUTRES RETOURS RESTENT VRAIS
L'owner confirme que ses retours précédents sont inchangés : col dans les épaules, boucle du dos dans
la lanière, pans croisés, cheveux de nuque dans le cou, lunettes dans la poitrine, mèches dans le
visage et les oreilles — et le clipping physique-vs-mesh sur QUASIMENT TOUS les personnages.

### AD. MAIA — POITRINE INERTE (owner 09:50, run Redmi)
« Les seins de Maia ne bougent PAS DU TOUT, sauf quand elle s'élève en l'air vue de loin. Ses cheveux
passent aussi au travers de son corps. Dommage, c'est elle qui a les seins les plus gros ! »
DIAGNOSTIC MESURÉ dans `physics_chains.txt` :
  * Maia  (evilsis-lod0) : stiffness=2.46 damping=0.46 mass=4.2
  * Keira (keira-hd)     : stiffness=1.60 damping=0.14 mass=1.6
  => Maia a un amortissement **3,3× plus fort** que Keira. « Plus mûre / plus lourde » a été traduit
     en « plus amortie », ce qui est physiquement faux : une masse plus lourde sur un ressort donne
     une fréquence PLUS BASSE et une amplitude PLUS GRANDE avec du retard, pas moins de mouvement.
     Un amortissement à 0.46 tue le mouvement — d'où « ça ne bouge que quand elle s'envole », c'est-
     à-dire uniquement sous une accélération énorme de l'ancre.
  => CORRECTION ATTENDUE : garder la masse élevée (elle est juste), RÉDUIRE FORTEMENT l'amortissement
     pour obtenir de l'ampleur et du retard — le comportement « lourd et lâche » que l'owner décrit —
     sans repasser en gelée. Elle doit bouger PLUS que Keira, pas moins.

### AE. LE RESKIN NE COUVRE QUE LES MODÈLES HD — LES ~50 PNJ STOCK N'ONT RIEN
`physics_reskin.txt` ne déclare des transferts que pour : keira-hd, keira3-hd, jak-hd, samos-hd,
jak2-hd, jakp-hd, jak3-hd, jakm-hd, daxp-hd, ysamos-hd. Aucun modèle `-lod0`.
Or Maia (`evilsis-lod0`), Gol, les villageois, les créatures sont TOUS des rigs stock. Le défaut
d'autorité de peau qui explique « la physique ne déplace rien de visible » n'est donc corrigé que
pour une dizaine de personnages sur 60 — alors que l'owner a répété deux fois que le problème
concerne quasiment tous les acteurs.
=> Mesurer l'autorité de peau sur les rigs STOCK aussi, et dire honnêtement si un transfert y est
   applicable (la géométrie stock vient du fr3 du niveau, pas d'un GLB HD). Si ce n'est pas
   applicable par le même chemin, proposer le chemin qui l'est — ne pas laisser 50 personnages
   hors du correctif sans le dire.

### AF. LES LUNETTES DE KEIRA TOMBENT PENDANT QU'ELLE LES TIENT (owner 10:05, Sandover, boucle Zoomer)
Contexte exact donné par l'owner : à Sandover, Keira boucle son animation de travail sur le Zoomer.
Elle se pose, une main sur la hanche, puis PREND SES LUNETTES avec une main et fait semblant de souder
de l'autre. « Quand elle LÈVE les lunettes ça va bien. Mais pendant qu'elle les TIENT devant ses yeux
(ça ne bouge pas), les lunettes TOMBENT et reviennent se poser au-dessus de ses seins (avec un peu de
clipping)... alors qu'on voit clairement que sa main continue de tenir les lunettes. »

CAUSE TRÈS PROBABLE — À VÉRIFIER EN PREMIER : la détection de priorité anim (section A) est ARMÉE SUR
LA VITESSE. Un commit de cette nuit le dit explicitement : « arrival armed on speed, not on a
counter ». Donc pendant le geste (les lunettes montent) l'anim gagne, mais dès que la main SE FIGE en
tenant les lunettes, la vitesse du canal authored tombe à zéro, le détecteur conclut « plus
d'animation » et rend la main à la physique — qui les fait tomber sur la poitrine.
=> RÈGLE : « TENU IMMOBILE » N'EST PAS « PLUS TENU ». La libération de l'autorité ne doit PAS dépendre
   de la VITESSE du canal d'animation. Elle doit dépendre du fait que l'anim PILOTE ENCORE le joint —
   par exemple l'écart persistant entre la pose authored et la pose de repos physique : tant que
   l'animateur maintient la chaîne loin de son repos, c'est qu'il la tient, même à vitesse nulle.
=> Cas de non-régression nommé : Sandover, Keira, boucle de travail sur le Zoomer, phase où elle tient
   les lunettes devant ses yeux. Les lunettes doivent rester dans sa main pendant toute la tenue, puis
   redescendre quand l'animation les relâche.
=> Ce défaut vaut pour TOUT accessoire tenu ou porté par une main pendant une pose statique.

### AG. POITRINE DE KEIRA — PRESQUE BON (owner 10:05)
« Sa poitrine maintenant bouge bien (mériterait un poil plus), mais c'est un poil trop JELLY. Comme
j'ai dit, ses seins sont censés être RONDS ET FERMES, elle est JEUNE ! »
=> Un cran d'amplitude en plus, et surtout MOINS de mollesse : retour plus franc, moins de
   dépassement mou. Fermeté = le mouvement s'arrête net et revient sur la forme du modèle, il ne
   continue pas d'onduler. Ne pas confondre avec « amortir » (l'erreur commise sur Maia).

## ============================================================
## CYCLE 8 — VERDICT OWNER 2026-08-07 ~11:55 (APK 11:30 + pack 10:13)
## ============================================================
### AH. RÉGRESSION : LA POITRINE DE KEIRA EST DEVENUE DE LA GELÉE
« Plus du tout les seins ronds et fermes qui bougent en gardant leur fermeté, maintenant on dirait
des POCHES LOSE PLEINES D'EAU, ça n'a aucun sens. »
HISTORIQUE MESURÉ dans `physics_chains.txt` (chain chestR, keira-hd) :
  * 09:13 : stiffness=2.60 damping=0.100 stretch=0.05  <- l'owner disait alors « bouge bien, un poil
            trop jelly » : c'est la MEILLEURE version connue, on repart de LÀ.
  * 11:30 : stiffness=1.55 stretch=0.11   |  actuel : stiffness=1.60 damping=0.16 stretch=0.11
  => raideur −40 %, élasticité ×2,2. On a cherché l'amplitude en RAMOLLISSANT le ressort. C'est le
     mauvais levier et ça produit exactement la poche d'eau.
=> RÈGLE : la FERMETÉ vient de la RAIDEUR et d'une faible élasticité de chaîne (`stretch`).
   L'AMPLITUDE vient du COUPLAGE À L'ANCRE (`swing`, réponse à l'accélération du buste) et de la
   masse — PAS d'un ressort mou. Monter `stiffness` AU-DESSUS de 2.60 et redescendre `stretch` À
   0.05 ou moins, puis chercher l'amplitude par `swing`/masse.
   Cible qualitative de l'owner : ronds, fermes, ils BOUGENT bien et s'ENTRE-CHOQUENT, peu de droop,
   peu de déformation. « Elle est jeune. »
=> Interdiction de redescendre sous les valeurs de fermeté du 09:13. Gate posé.

### AI. CHEVEUX DE KEIRA <-> SES OREILLES : DEUX ÉLÉMENTS À PHYSIQUE QUI SE TRAVERSENT
« Ses cheveux clippent ÉNORMÉMENT avec ses oreilles, j'ai l'impression PLUS QU'AVANT. » Et les
lunettes clippent toujours dans les seins. => La collision CHAÎNE ↔ CHAÎNE n'est pas effective. Les
mèches, les oreilles, les lunettes et la poitrine sont quatre chaînes du même personnage : elles
doivent se voir mutuellement. C'est le problème 2 de la cause racine (chaque maillon a besoin de son
propre volume). Le fait que ce soit PIRE qu'avant doit être expliqué, pas seulement corrigé.

### AJ. HYPOTHÈSE OWNER — LA PHYSIQUE SEMBLE DÉSACTIVÉE PENDANT LES ANIMATIONS (à traiter en premier)
« J'ai l'impression que la physique est souvent DÉSACTIVÉE sur les animations, comme si des BONES NON
LIÉS qui bougent stoppaient les bones/éléments avec physique d'avoir la physique activée. »
=> C'est très probablement le même sous-système que le bug des lunettes (AF) : la détection de
   priorité à l'animation. Si elle est armée sur le mouvement de l'ACTEUR (ou d'un os parent, ou d'un
   os voisin sans rapport) au lieu du mouvement des JOINTS DE LA CHAÎNE ELLE-MÊME, alors dès qu'une
   animation joue — c'est-à-dire presque tout le temps — l'anim prend l'autorité et la physique est
   suspendue. Ça expliquerait d'un coup : « la physique ne se voit que quand elle s'envole » (Maia),
   « aucune différence entre les builds », et cette impression de physique éteinte en animation.
=> À VÉRIFIER EN PRIORITÉ ET À PROUVER : la détection doit être STRICTEMENT PAR CHAÎNE, calculée sur
   les joints de cette chaîne uniquement. Rapporter, sur une animation courante (Keira au Zoomer,
   Jak qui marche), le pourcentage de frames où chaque chaîne est sous autorité ANIM plutôt que
   PHYSIQUE. Si ce pourcentage est élevé sur des chaînes que l'animation ne pilote pas, c'est le bug.

### AK. « LIQUIDE » = EXCURSION ANGULAIRE, PAS DOSAGE (owner 13:20, build 12:41)
« Les seins de Keira bougent BEAUCOUP PLUS (excellent !) mais sont carrément LIQUIDES, c'est
n'importe quoi, au moins 10 fois plus jelly qu'avant. »
CONSTAT : la chaîne de poitrine est UN SEUL OS (`rBoob` / `lBoob`) — ce n'est donc pas une corde qui
se déforme. Le paramètre fautif est `maxangle=50` : on autorise l'os à basculer de CINQUANTE DEGRÉS.
Un sein qui pivote de 50° est une poche d'eau PAR CONSTRUCTION, quelle que soit la raideur.
=> RÈGLE : l'AMPLITUDE VISIBLE que veut l'owner n'est PAS une grande EXCURSION. Un sein ferme fait un
   petit débattement, RAPIDE et net, et revient sur la forme du modèle. Réduire fortement `maxangle`
   (ordre de grandeur 15-22°, à ajuster), garder `stiffness` haut, et obtenir la VIVACITÉ par le
   couplage à l'ancre (`swing`) plus qu'en ouvrant la butée.
=> Résumé des trois leviers, à ne plus confondre :
     * `stiffness` / `stretch` -> FERMETÉ (le retour est net, la forme ne change pas)
     * `maxangle`              -> DÉBATTEMENT MAX ; trop grand = aspect liquide
     * `swing` / `mass`        -> RÉACTIVITÉ à l'accélération du buste = ce que l'owner appelle
                                  « ça bouge bien »
=> Appliquer le même raisonnement aux autres poitrines (Maia, bird-lady, archéologue) et aux ventres.

### AL. « GIGA POINTE OU QUASIMENT PLAT » = L'OS SE DÉPLACE AU LIEU DE PIVOTER (owner 15:25)
« Les seins de Keira sont toujours extrêmement liquides et partent en GIGA POINTE TRÈS LONGUE ou
QUASIMENT PLAT (les deux extrêmes). »
MÉCANISME IDENTIFIÉ : `couple=3.6` (ajouté pour gagner de l'amplitude sans ramollir) injecte
l'accélération de l'ancre comme une DÉVIATION POSITIONNELLE — l'équation du solveur est
`d'' + 2·zeta·w·d' + w²·d = -(1+couple)·a_ancre`, donc `d` est un DÉPLACEMENT de l'os.
Or les sommets du sein sont PARTAGÉS avec l'os du torse (le reskin a réparti les poids entre `chest`
et `rBoob`). Un déplacement de `rBoob` par rapport à `chest` ÉTIRE la peau entre les deux : dans un
sens ça part en pointe, dans l'autre ça s'aplatit. Les deux extrêmes de l'owner sont les deux signes
du même défaut.
=> RÈGLE POUR TOUTE PARTIE DU CORPS À UN SEUL OS (poitrines, ventres, fesses) : le mouvement doit
   être une ROTATION AUTOUR DE L'ANCRE, pas une translation. La déviation calculée par `couple` doit
   être convertie en ANGLE autour de la racine, avec la longueur de l'os CONSERVÉE — la forme ne
   change pas, seule l'orientation change. Translation résiduelle ≈ 0.
=> Corollaire : `stretch` doit être ~0 sur ces chaînes (aucune élasticité de longueur), et la
   distance racine->pointe doit être rapportée comme invariante (min/max sur la capture).
=> C'est la traduction correcte de la demande d'origine : « ronds et FERMES, ils bougent bien et
   s'entre-choquent, PEU DE DÉFORMATION ». Un volume rigide qui oscille sur son ancrage, pas une
   poche qui se déforme.

## ============================================================
## CYCLE 12 — REJET OWNER 2026-08-08 08:30 : « ÉCHEC MASSIF, PAS VALIDÉ »
## ============================================================
« Les mèches de Keira passent au travers de son crâne et de ses oreilles en mouvement, ses lunettes
clippent à travers sa poitrine. Le col de Jak passe toujours au travers de ses épaules. Les pans de
sa veste clippent toujours comme des fous. Le noeud du maire passe au travers de son ventre. Pas
besoin d'être plus exhaustif, c'est TOUJOURS BROKEN. Et encore plus les éléments à physique avec
d'autres éléments à physique. »

### LA CAUSE, TROUVÉE DANS LES DONNÉES — ET MON AUDIT NE POUVAIT PAS LA VOIR
  * **169 chaînes sur 345 portent `colskip=1`** : elles ne testent AUCUNE collision. Parmi elles
    37 `earL` + 36 `earR` (les oreilles que l'owner voit traversées), 5 `hair`, des `flap`, `tail`,
    `ponytail`, `hairL`. Une chaîne qui saute la collision ne peut pas produire de pénétration
    résiduelle : elle sort mécaniquement de l'audit.
  * **Les 2384 volumes portent TOUS un filtre `chains=`** : chaque volume ne teste que les chaînes
    explicitement listées. Le reste passe au travers sans être compté.
  * La `fit-error = 0.000` que j'ai acceptée comme preuve mesurait « est-ce que le volume d'un os
    contient les sommets de SON PROPRE os » — une question SANS RAPPORT avec « est-ce qu'une chaîne
    a le droit de traverser ce volume ».
  * Le contrôle positif valide le COMPTEUR, pas le VOLUME ni le PÉRIMÈTRE. Un compteur juste, appliqué
    à un périmètre qui exclut la moitié des chaînes, donne un zéro parfaitement exact et parfaitement
    faux. C'est le 4e faux-vert de cette famille : après resid/push, idledrift/idlewin,
    restdevA/restwin, voici resid/PÉRIMÈTRE.

### CE QU'IL FAUT FAIRE
  1. **`colskip` doit disparaître comme échappatoire.** Toute chaîne teste la collision. Si le coût
     est le problème, c'est le niveau de précision qui l'arbitre — jamais un opt-out par défaut.
  2. **Le filtre `chains=` est une OPTIMISATION, pas une autorisation.** Par défaut une chaîne teste
     TOUT volume qu'elle peut physiquement atteindre. Le filtre ne peut qu'exclure ce qui est
     géométriquement inatteignable, et cette inatteignabilité doit être PROUVÉE (distance max de la
     chaîne < distance au volume), pas décrétée.
  3. **CHAÎNE ↔ CHAÎNE obligatoire** : l'owner dit que c'est « encore pire » entre deux éléments à
     physique. Mèches vs oreilles, lunettes vs poitrine, boucle vs lanière, noeud du maire vs ventre.
  4. **Nouvelle métrique, la seule qui compte** : pour chaque chaîne, la pénétration dans TOUT volume
     du personnage — pas seulement ceux qu'on a bien voulu lui associer. Rapportée par chaîne et par
     personnage, avec le nombre de volumes réellement testés (un `tested=0` est un aveu).
  5. Cas nommés à vérifier un par un : mèches de Keira vs crâne ET oreilles en MOUVEMENT, lunettes de
     Keira vs poitrine, col de Jak vs épaules, pans de veste de Jak, noeud du maire vs ventre.
     L'owner précise qu'il a arrêté d'énumérer : ce sont des exemples, pas la liste.
  6. La POITRINE de Keira n'est toujours pas bonne (voir AL : rotation, pas translation).

## CYCLE 12 — CONSIGNE RESSERRÉE (superviseur 14:40)
IL NE RESTE QU'UN SEUL CRITÈRE ROUGE : `restdevA` = 8,22 (MAX) / 8,75 (INTRO) pour un seuil de 8,0.
Tout le reste est vert (pénétrations 0, nomask 0, xleg 0, longueurs 0,99+).
=> NE TOUCHER QU'À ÇA. Instruments GELÉS, aucun rebuild x86, aucune nouvelle jambe.
=> ~8 unités ≈ 2 mm : chercher un BIAIS constant, pas une instabilité — un offset de re-glue, une
   référence rest vs targ (cf. feedback_restdev_rest_vs_targ_reference), ou la moyenne qui inclut
   des frames de settle. Vérifier D'ABORD ce que la moyenne échantillonne avant de retoucher le
   solveur : si les 8 unités viennent de frames pré-stabilisation comptées dans la moyenne, c'est
   l'échantillonnage qu'il faut borner (fenêtre post-settle), pas la physique.
=> Puis régénérer le rapport et s'arrêter là.

## ============================================================
## CYCLE 14 — REJET OWNER 2026-08-08 ~17:30 (build 15:42, cycle 13) : « BIEN CLAQUÉ, RIEN N'EST FIX »
## ============================================================
« La physique est massivement TONED DOWN au point où j'en vois limite plus l'intérêt — en courant
les cheveux de Jak ne bougent PAS. La poitrine de Keira est COMPLÈTEMENT STATIQUE. Un truc tente
d'empêcher les mèches de clipper dans ses oreilles mais ça fait des trucs BIZARRES plus gênants
qu'un simple clipping, et EN PLUS ça clippe toujours. Et ça continue de clipper pour plein de PNJ —
le noeud du Maire au travers de son torse. RIEN N'EST FIX. »

### DIAGNOSTIC SUPERVISEUR — POURQUOI TOUS LES CHIFFRES ÉTAIENT VERTS
  1. **La sim a été tuée pour satisfaire les cibles de calme.** restdevA→0, idledrift→0, jitter→0,
     unsettled→0 sont TOUTES à sens unique : une chaîne qui ne bouge plus les maximise. Le correctif
     « les contacts dépensent la vitesse » a sur-amorti l'ensemble — le calme est devenu parfait
     parce que le mouvement est mort. IL FAUT DES PLANCHERS DE MOUVEMENT MESURÉS EN LOCOMOTION,
     tenus SUR LA MÊME EXÉCUTION que les plafonds de calme.
  2. **L'audit mesure les OS, l'owner voit le MESH.** resid teste des centres de maillons ± un rayon
     arbitraire contre des volumes ; la géométrie skinnée s'étend BIEN au-delà. Le noeud du Maire :
     ses maillons sont probablement « dans les clous » pendant que son MESH transperce le ventre.
     L'audit de pénétration doit être évalué À LA SURFACE DU MESH SKINNÉ (échantillonner les sommets
     de la géométrie pilotée par la physique contre les volumes du corps), et le rayon PAR MAILLON
     doit être DÉRIVÉ de l'étendue réelle du mesh qu'il porte — c'est la demande d'origine de
     l'owner, jamais réellement faite.
  3. **Une résolution pire que le clip est pire que pas de résolution.** Le traitement mèches/oreilles
     produit des artefacts « plus gênants qu'un simple clipping ». La correction de collision doit
     être LISSE : borne de déplacement par frame (resjerk), blend, jamais de saut visible.

### CIBLES CYCLE 14 (toutes sur la MÊME exécution device)
  A. PLANCHERS DE MOUVEMENT en LOCOMOTION (Jak qui court, Keira au Zoomer) :
     `hairrun=` span des cheveux de Jak EN COURANT (≥100 unités), `chestrun=` déviation de la
     poitrine de Keira EN MOUVEMENT (≥350 unités). Rapportés par jambe device, ratchetés.
  B. AUDIT AU NIVEAU DU MESH : `meshpen=` pénétration max de la surface skinnée pilotée par la
     physique dans les volumes du corps, avec `meshtested=` sommets réellement échantillonnés > 0
     et contrôle positif au niveau MESH. Le noeud du Maire nommément : clearance mesh-vs-ventre.
  C. RAYON PAR MAILLON DÉRIVÉ DU MESH : pour chaque chaîne, le rayon vient de l'étendue réelle des
     sommets skinnés à ce maillon (rapporter min/max par chaîne, avant/après).
  D. RÉSOLUTION LISSE : `resjerk=` déplacement max appliqué par la résolution en une frame, borné ;
     mèches vs oreilles de Keira montrées SANS oscillation ni saut.
  E. PROFONDEUR DE VÉRIF SUR LES 3 PERSONNAGES QUE L'OWNER TESTE EN PREMIER : Jak, Keira, le Maire —
     les autres gardent leurs chaînes (pas de descope silencieux), mais la preuve mesh-level et les
     planchers de locomotion portent d'abord sur ces trois-là.

### CYCLE 14 — IDÉE OWNER 2026-08-09 21:15 : BANC D'ESSAI DES ACTEURS (voir SPEC §14)
Le Maire échoue sur « warp never landed » : on ne sait rien de sa physique parce qu'on n'arrive pas
à ALLER LE VOIR. C'est un mode d'échec de la mise en scène du test, pas de la physique.
=> PRIORITÉ : construire le banc décrit en SPEC §14 — spawn de n'importe quel acteur PAR NOM dans
   une zone de test, joué à travers TOUTES les animations de son art-group, avec les mesures
   habituelles par acteur/par chaîne + le NOM DE L'ANIMATION au moment du pire chiffre.
=> Il remplace la navigation in-world comme source des chiffres ; garder 1-2 cas en scène réelle
   comme contrôle de non-régression. Ça débloque le Maire immédiatement et rend atteignable la
   couverture des 60 modèles que la spec exige.

### COUVERTURE — OWNER 2026-08-09 22:30 : « sur tous les acteurs du jeu, seulement deux au-dessus du seuil ? »
NON, et il a raison de tiquer. `resjerk`/`meshpen` sont rapportés PAR JAMBE (max toutes chaînes de la
scène), pas par acteur. Un seul modèle (`mayor-lod0`) a une ligne nominative dans le rapport actuel ;
les 45+ autres ne sont mesurés NULLE PART. Trois scènes ne couvrent pas 60 modèles.
=> EXIGENCE : un `resjerk` ET un `meshpen` PAR MODÈLE, plus la FRACTION DE COUVERTURE annoncée
   explicitement (« N / 60 modèles réellement mesurés »). Un maximum de scène ne peut plus passer
   pour une couverture du cast. Gate C14-COV : minimum 20 modèles nominatifs, sinon échec.
=> C'est le banc d'essai (SPEC §14) qui rend ça atteignable : spawn par nom + toutes les animations.

### DEVICE ABSENT — REPLI x86 AUTORISÉ (owner 2026-08-10 : « au pire teste sur un build PC à défaut »)
Le Redmi n'est plus détecté par adb. NE PAS ATTENDRE : prouver sur x86 tout ce qui est indépendant
de la plateforme — le solveur, l'instrument (variation de la position ÉCRITE, verdict par chaîne),
la collision contre la surface réelle, et le contrôle anti-synthèse C20. Les jambes x86 doivent être
de VRAIES exécutions avec les mêmes chiffres par chaîne nommée, pas de la prose.
CE QUE x86 NE PROUVE PAS, à écrire noir sur blanc dans le rapport : le codegen arm64, la perf
device, et les chemins device-only. La DETTE DE PREUVE DEVICE doit être déclarée explicitement ; le
validateur la réclame et refuse un repli silencieux.
Dès que le device revient : refaire la jambe device et lever la dette.

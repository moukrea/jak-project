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

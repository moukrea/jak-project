# SPEC — PHYSIQUE SECONDAIRE (source de vérité, 2026-08-08)

STATUT : ce document est LE CONTRAT. Il synthétise TOUS les retours de l'owner depuis le début de la
physique (2026-08-04 → 2026-08-08). Les sections « CYCLE N » du prompt de phase sont un JOURNAL
historique ; en cas de conflit, CETTE SPEC GAGNE. L'owner n'est jamais revenu en arrière : chaque
retour a AJOUTÉ une précision. Tourner en rond = re-violer un point déjà spécifié ici.

---
## 1. INTENTION
Jak & Daxter est un platformer cartoon d'ados ; Keira y est ouvertement sexualisée. On ajoute le
mouvement secondaire que la PS2 ne permettait pas — y compris là où ND n'a RIEN animé (poitrines,
fesses, ventres) : l'absence de précurseur n'est pas une raison de sauter un site. Les canaux de
faux-mouvement ND = carte de découverte, PAS un filtre. On ne laisse rien sous le tapis : tous les
personnages, tous les PNJ, toutes les variantes de look, créatures comprises.

## 2. DEUX FAMILLES — JAMAIS LE MÊME TRAITEMENT (classification par chaîne, dérivée par le framework)
**Famille A — ce qui EST le personnage** : cheveux (hair/bang/braid/ponytail/backhair/midhair/fro),
barbe/bouc/moustache, OREILLES (tous les persos), poitrines, ventres, fesses, joues, fourrure,
queues, cornes.
  * Simulées EN PERMANENCE — jamais figées, jamais clampées.
  * La gravité agit sur la DYNAMIQUE, pas sur le point d'équilibre : la cible du ressort est LA POSE
    DU MODÈLE. En idle / orientation classique, ça REGAGNE exactement la forme du modèle — pas plus
    haut, pas plus bas, pas plus écrasé. Le modèle 3D est la représentation voulue par ND.
  * Bounce et élasticité pendant le mouvement = naturels et VOULUS.
  * EXCEPTION : orientation non naturelle (penché, tête en bas → « si tu pends Maia par les pieds »)
    ⇒ la gravité reprend ses droits (scalée par l'inclinaison, 0 debout).
**Famille B — ce qui est PORTÉ ou ACCROCHÉ** : sangles/lanières/ceintures, pans et rabats de
vêtements, capes, tabliers, pendeloques, accessoires (lunettes, sacs, chapeaux, bandanas, bijoux),
cordes, entraves.
  * ÇA PEND, ÇA RESTE PENDU : le repos est dicté par la gravité. Ne regagne JAMAIS la pose du
    modèle — un pan qui « revient au bind » est un bug au même titre qu'un sein qui s'affaisse.
**Commun** : rien ne se TASSE ni ne s'écrase (col de Jak = cas nommé ; lenmin/lensim ≥ 0.97).
Cas ambigu : « si le personnage s'immobilise, cet élément doit-il revenir à la forme sculptée par
ND, ou pendre ? » — écrire la réponse dans le rapport.

## 3. LES TROIS LEVIERS — NE JAMAIS LES CONFONDRE (3 erreurs déjà commises)
  * FERMETÉ    = stiffness haut + stretch ~0. PAS l'amortissement (erreur Maia : « plus lourde » a
    été traduit « plus amortie » → inerte. Une masse plus lourde = fréquence plus basse et PLUS
    d'amplitude avec du retard, pas moins de mouvement).
  * EXCURSION  = maxangle. Trop grand = liquide par construction (50° sur un os unique = poche
    d'eau). Poitrines/ventres : ≤ 26°. « Amplitude » ≠ grande excursion : débattement PETIT, RAPIDE
    et net, retour sur la forme du modèle.
  * RÉACTIVITÉ = couplage à l'ancre (swing/couple) + masse. C'est le « ça bouge bien » de l'owner.
RÈGLE GÉOMÉTRIQUE (parties du corps à un seul os — poitrines, ventres, fesses) : le mouvement est
une ROTATION autour de l'ancre, JAMAIS une translation. Longueur d'os INVARIANTE (min/max rapportés),
stretch ~0 — sinon la peau partagée avec l'os parent s'étire : « giga pointe ou quasiment plat ».
Volume rigide qui oscille sur son ancrage, pas une poche qui se déforme.

## 4. POITRINES — CAS PAR CAS, JAMAIS COPIÉ-COLLÉ (masse, élasticité, fermeté, bounce cohérents)
  * KEIRA : ronde et FERME (« jeune et fraîche »). Ça bouge BIEN, ça S'ENTRE-CHOQUE (collision entre
    les deux seins), peu de droop, peu de déformation. Plancher owner-validé : stiffness ≥ 2.60,
    stretch ≤ 0.05 (l'état 09:13 du 08-07 = « bouge bien, un poil trop jelly » est le PIRE acceptable
    en mollesse).
  * MAIA : corps de trentenaire très hot, GROS seins : plus tombants, plus lâches, moins fermes.
    Doit bouger PLUS que Keira, pas moins. Masse haute, amortissement BAS.
  * ARCHÉOLOGUE (geologist) : entre-deux Keira/Maia.
  * BIRD-LADY : a une poitrine, même règle.
  * Idle = la pose du modèle pour TOUTES (ne pas les faire tomber sous la gravité).
Le jiggle n'existe QUE quand ça bouge ou quand l'angle diffère de l'idle.

## 5. PRIORITÉ AUX ANIMATIONS D'AUTEUR
Quand ND pilote délibérément les joints d'une chaîne, L'ANIMATION GAGNE au moment où elle le fait ;
la physique se suspend puis REPREND EN BLEND (jamais de saut). C'est du cartoon : les poses forcées
sont légitimes (oreilles hand-keyées de Daxter, Keira qui SAISIT ses lunettes au Zoomer).
  * Détection STRICTEMENT PAR CHAÎNE, calculée sur les joints DE CETTE CHAÎNE — des os sans rapport
    qui bougent ne suspendent RIEN (l'anim qui joue presque tout le temps ne doit pas éteindre la
    physique globalement).
  * « TENU IMMOBILE » ≠ « PLUS TENU » : la libération ne dépend JAMAIS de la vitesse du canal —
    elle dépend du fait que l'anim maintient la chaîne loin de son repos (offset persistant).
    Cas de non-régression : Sandover, boucle Zoomer, lunettes tenues devant les yeux.
  * engage == release sur la durée ; holdmax borné ; jamais « suspendue et jamais rendue ».
  * Le faux vent ND sur Jak reste supprimé ; PEUT revenir en idle extérieur uniquement.

## 6. COLLISION — LE BLOCKER ABSOLU
« Aucun élément à physique ne passe au travers du mesh de son personnage. QU'IMPORTE LA RAISON. »
Vaut pour LES 60 MODÈLES. Les sites nommés (mèches Keira vs crâne/oreilles EN MOUVEMENT, lunettes vs
poitrine, col de Jak vs épaules, pans de veste vs jambes — jamais croisés —, nœud du Maire vs ventre)
sont des EXEMPLES, pas la liste.
  * L'AUDIT VIT SUR LE MESH, PAS SUR LES OS : pénétration évaluée à la surface du mesh SKINNÉ
    (meshpen, meshtested > 0). Les compteurs os-niveau ont produit 5 faux-verts.
  * Volumes de corps DÉRIVÉS de la géométrie merc réelle (fit-error mesurée = de combien un sommet
    du mesh sort de son volume) — jamais devinés à la main.
  * Rayon PAR MAILLON dérivé de l'étendue réelle du mesh que ce maillon porte.
  * PAS D'OPT-OUT : colskip interdit (169 chaînes en opt-out = le « rien n'est fix »). Le coût
    s'arbitre par les niveaux de précision, jamais par une chaîne qui ne teste rien.
  * Le scoping (filtre chains=) est une OPTIMISATION : n'exclure que l'inatteignable PROUVÉ
    (portée max de la chaîne < distance au volume). Par défaut : tout volume atteignable est testé.
  * CHAÎNE ↔ CHAÎNE obligatoire (boucle vs lanière, lunettes vs poitrine, mèches vs oreilles,
    nœud vs ventre) — chaque maillon a un volume propre.
  * RÉSOLUTION LISSE : une résolution pire que le clip est pire que pas de résolution. Déplacement
    par frame borné (resjerk), pas d'oscillation, pas de saut visible. Une contrainte insatisfiable
    SE POSE calmement (projection amortie bornée, zéro vitesse réinjectée, hystérésis, gel doux) —
    jamais « jitter comme un fou ».
  * Ordre de résolution : la collision a le DERNIER MOT (le blend de sortie passe avant) ; les
    paires côté-opposé re-résolues en dernier.

## 7. VIVACITÉ — PLANCHERS DE MOUVEMENT (la leçon du cycle 13/14)
Une sim morte maximise tous les plafonds de calme. INTERDIT d'acheter le calme en tuant le mouvement.
Sur LA MÊME exécution device que les plafonds de calme :
  * hairrun ≥ 100 (cheveux de Jak, EN COURANT — « en courant les cheveux de Jak bougent pas » = rejet)
  * chestrun ≥ 350 (poitrine de Keira, EN MOUVEMENT)
  * plus la progression du dégradé : ce n'est jamais « que le bout du bout » (profil d'influence
    continu par maillon, pas de cran — les oreilles à 2 os de Daxter en sont le cas limite),
    et une poitrine bouge en VOLUME (la base bouge, pas que la pointe).
Ces planchers sont dans le RATCHET : toute régression échoue, quoi que le run améliore ailleurs.

## 8. CALME — PLAFONDS (l'« hystérésis » de l'owner)
  * Dérive à vide ~0 (acteur immobile ⇒ chaîne immobile après stabilisation) — avec idlewin > 0.
  * Temps de stabilisation borné, décroissance monotone ; freering (sonnerie en espace libre)
    mesuré et bas — c'est LA définition de son « hystérésis », ne jamais re-restreindre la métrique.
  * PAS DE POMPE À VÉLOCITÉ : les corrections sont vélocité-neutres ET les contacts DÉPENSENT la
    vitesse (les deux directions de la règle O).
  * Spawn/téléport/grosses transitions : init à la pose de bind, reset+blend, burst=0.

## 9. PREUVES — LES RÈGLES QUI ONT COÛTÉ 5 FAUX-VERTS
  * TOUT ZÉRO exige un CONTRÔLE POSITIF qui a TIRÉ (injecter le défaut, voir le compteur monter,
    retirer). Zéros creux déjà payés : resid/push=0, idledrift/idlewin=0, restdevA/restwin=0,
    resid/périmètre (colskip), resid-os/mesh.
  * Compteurs PAR ACTEUR ET PAR CHAÎNE, tested= visible (tested=0 est un aveu). Jamais d'agrégat
    qui masque (« resid=0 sur 90 des 101 fenêtres » ≠ zéro).
  * Toute ligne FAIL( citée dans le rapport = échec de la phase. Placeholders @@..@@ = échec.
  * Le ratchet couvre calme ET mouvement. Les instruments ne se redéfinissent pas pour passer —
    un compteur réfuté par l'œil de l'owner se reconstruit (avec contrôle positif), jamais l'inverse.
  * Preuves runtime sur device (eae4df44), builds frais (deploy_verify), jamais de preuve visuelle.

## 10. PÉRIMÈTRE
60 modèles / ~345 chaînes : tout le cast garde ses chaînes (AUCUN descope silencieux). La profondeur
de vérification (mesh-level + planchers locomotion) porte D'ABORD sur Jak, Keira, le Maire — les
trois que l'owner teste en premier — puis s'étend.

## 11. CADRAGE TECHNIQUE
Flag build --physics + toggle menu ON/OFF (OFF == stock, prouvé par l'absence de fenêtres) + niveaux
de PRÉCISION : le plus bas reste crédible et bon marché, le plus haut n'est JAMAIS bridé par le bas.
Les données (physics_chains.txt) restent hot-reloadables sur device (tuning en Ko, pas en APK).
Chaque gate Recharged est ANDé avec le master.

## 12. HORS-PÉRIMÈTRE CONNU (dit à l'owner, accepté)
Anneau du plastron de Jak, boucle métal de son dos, binocle de Samos : AUCUN os dans les 458 rigs —
injection d'os au prep HD + re-skin = LOT D'ASSETS SÉPARÉ. Le défaut visuel boucle/lanière reste
couvert par chaîne-vs-chaîne pour la partie qui a des os.

## 13. CHECKLIST D'ACCEPTATION (plainte owner → critère mesurable)
| Plainte (verbatim) | Critère | Gate |
|---|---|---|
| « rien ne traverse, qu'importe la raison » | meshpen=0, contrôle positif mesh, 60 modèles | C6/C12/C14-B |
| « en courant les cheveux bougent pas » | hairrun ≥ 100 en locomotion | C14-A + ratchet |
| « poitrine complètement statique » | chestrun ≥ 350 en mouvement | C14-A + ratchet |
| « poches d'eau / giga pointe » | rotation-seule, longueur invariante, maxangle ≤ 26, stretch ≤ .05 | AL/AK/AH |
| « trucs bizarres pires que le clipping » | resjerk borné, mèches/oreilles lisses | C14-D |
| « hystérésis horrible » | freering bas + settle borné + zéro pompe | S/O + cycle-13 |
| « lunettes tombent pendant qu'elle les tient » | libération ≠ vitesse ; cas Zoomer exercé | AF |
| « physique éteinte pendant les anims » | autorité par chaîne, % anim-authority rapporté | AJ |
| « ça revient à la pose du modèle » (famille A) | restdevA ≈ 0 AVEC restwin > 0, post-settle | W + S-bis |
| « ça pend ça pend » (famille B) | jamais tiré vers le bind ; hang plein | FAM-ter |
| « le col ne s'écrase pas » | lenmin/lensim ≥ 0.97 | X + ratchet |
| « Maia bouge plus que Keira, pas moins » | damping(Maia) < 1.5× damping(Keira), amplitude comparée | AD |

## 14. BANC D'ESSAI DES ACTEURS (idée owner 2026-08-09 — approche sanctionnée)
« Si tu galères à aller vers les personnages, tu peux les téléporter où tu veux, faire une ZONE DE
SPAWN DÉDIÉE aux tests de tous les acteurs et les tester avec TOUTES LES ANIMATIONS qu'ils ont en
rayon. Ça faciliterait la validation/itération de la physique de chacun d'entre eux. »

C'EST LA BONNE VOIE, ET ELLE EST PRIORITAIRE SUR LA NAVIGATION IN-WORLD :
  * Aller chercher un PNJ à sa place dans le monde est le maillon FRAGILE de toute la chaîne de
    preuve. Le Maire échoue aujourd'hui sur « warp never landed » — donc on ne sait RIEN de sa
    physique, alors que le solveur va peut-être très bien sur lui. Ce mode d'échec a coûté des
    heures et il se reproduira sur chaque acteur difficile d'accès.
  * BANC : une zone/niveau de test où N'IMPORTE QUEL acteur est spawné par NOM, posé devant la
    caméra, et joué à travers **toutes les animations de son art-group** (pas une pose, pas un
    walk-cycle : la liste complète — c'est là que la physique est réellement stressée, et c'est ce
    qui a manqué à toutes les campagnes jusqu'ici).
  * MESURES : les mêmes qu'ailleurs, par ACTEUR et par CHAÎNE — meshpen/meshtested, resjerk,
    planchers de locomotion, restdevA/restwin, chaîne↔chaîne — plus le nom de l'animation en cours
    quand un maximum est atteint. Savoir QUELLE animation casse quoi vaut dix campagnes.
  * COUVERTURE : le banc rend enfin réaliste la couverture des 60 modèles / ~345 chaînes que la
    spec exige, au lieu de trois personnages atteignables.
  * HONNÊTETÉ : le banc est l'outil d'ITÉRATION et de couverture. Il ne remplace pas une passe
    finale dans une VRAIE scène (contexte, LOD, autres colliders, caméra) — mais il devient la
    source des chiffres, et la scène réelle sert de contrôle de non-régression sur 1-2 cas.
  * GRATUIT POUR L'OWNER : gated comme le reste (debug/flag), invisible en jeu normal.

## 15. MÉTHODE — GEL DES GATES ET BOUCLE COURTE (superviseur 2026-08-09, après le constat owner)
CONSTAT : 5 jours, 14 cycles, ~6 verdicts owner seulement. Chaque rejet m'a fait AJOUTER un gate
(60+ aujourd'hui), et le worker passe désormais son temps à arbitrer entre MES contraintes au lieu
de rendre le résultat correct à l'oeil. Les proxies (meshpen, resjerk, restdevA, freering,
idledrift) sont tous mesurables ET tous se sont révélés à côté APRÈS le test de l'owner.
DÉCISIONS :
  1. **GEL DES GATES.** Aucun nouveau gate tant qu'un build livré n'a pas été réfuté par l'owner.
     Le jeu de gates actuel est le contrat ; on le SATISFAIT, on ne l'étend plus.
  2. **BOUCLE COURTE PAR LES DONNÉES.** `physics_chains.txt` (20 Ko) est RECHARGEABLE À CHAUD sur
     device (kmachine.cpp:904 — re-parse + bump de version, effet immédiat sur companions ET riders
     stock, sans respawn). Le fichier sur le téléphone date du 08-06 : cette voie n'a JAMAIS servi à
     itérer. Tout réglage de paramètre = `adb push` + toggle physics, PAS un build. Minutes, pas heures.
  3. **UN PERSONNAGE À LA FOIS, JUGÉ PAR L'OEIL.** Viser Keira seule, réglée jusqu'à ce que l'owner
     la valide, PUIS propager le réglage au cast. Résoudre 60 modèles sous 60 contraintes avant le
     premier "oui" est la raison du sur-place.
  4. **LE BANC (§14) SERT D'ABORD À L'OWNER**, pas à moi : son intérêt n°1 est qu'il puisse voir
     tous les acteurs en 2 minutes, pas qu'il produise plus de chiffres pour mes gates.

## 16. LA CAUSE RACINE DES FAUX VERTS DE LA SEMAINE (2026-08-10, rejet total de l'owner)
Owner sur le build 10:12 : « les pans de veste NE BOUGENT PAS DU TOUT, zéro physique ; le col est
complètement statique ; les mèches de Keira sont ANCRÉES ; ses cheveux et oreilles complètement
statiques ; le nœud du maire aucune physique ; la poitrine de Keira complètement statique. »
Et mes planchers annonçaient hairrun=619,7 / chestrun=352,5. LES DEUX SONT VRAIS EN MÊME TEMPS :

**`crun` (le plancher) mesure `dev` = l'ÉCART À LA POSE DE REPOS, pas le MOUVEMENT.**
(jak-hd-physics.gc:5440 — « the same deviation, but only on a frame whose own anchor moved »)
Une chaîne maintenue à un décalage CONSTANT de 352 unités score 352 en étant visuellement SOUDÉE.
D'où `chestrun=352.4841` IDENTIQUE à chaque relevé pendant trois jours : c'est une constante
déterministe, pas une mesure. J'avais pourtant la règle en mémoire : « magnitude n'est pas mouvement ».

CONSÉQUENCE : les trois suppresseurs de mouvement empilés — plafonds de calme (jitter/idledrift/
freering), priorité aux animations d'auteur (qui suspend la physique presque tout le temps), et
clamps de collision (resjerk borné) — pouvaient tuer la sim JUSQU'AU BOUT sans jamais faire rougir
un seul gate. Toute la semaine de « verts » repose sur cette erreur de définition.

### LE PLANCHER CORRECT : LA VARIATION TEMPORELLE DU BONE ÉCRIT
  * `crun` doit devenir la variation de la position ÉCRITE du joint entre frames consécutives :
    somme ou moyenne de |pos(t) − pos(t−1)| sur la fenêtre de locomotion, PAS |pos − rest|.
  * Un décalage constant doit scorer ~0. Une chaîne qui oscille doit scorer haut.
  * AJOUTER un détecteur d'inertie explicite : une chaîne dont la déviation a une VARIANCE quasi
    nulle pendant que son acteur bouge est INERTE et fait ÉCHOUER la phase, par chaîne et par nom.
  * Rapporter, PAR CHAÎNE NOMMÉE (shirtL/shirtR, collarL/collarR, bangs/midhair/backhair de Keira,
    earL/earR de Jak, chestR/chestL, tieL/tieR du maire) : variation temporelle ET variance. Les
    chaînes que l'owner cite comme statiques doivent être celles qu'on prouve en mouvement.
  * Le cliquet doit ratcheter CETTE grandeur, et les anciens planchers (magnitude) sont RETIRÉS —
    ils ont servi de couverture à une sim morte, ils ne doivent plus jamais pouvoir passer.
  * ET LES TROIS SUPPRESSEURS DOIVENT ÊTRE QUANTIFIÉS : % de frames où la physique est suspendue par
    la priorité anim, % où le clamp de collision a borné le déplacement, % où le gel de calme est
    actif. Si l'un dépasse ~20 % des frames, c'est lui le coupable et il faut le desserrer.

## 17. DIRECTIVE DE RÉÉCRITURE (superviseur 2026-08-10, sur ordre owner « fais le putain de travail
## quoi qu'il en coûte »)
CONSTAT CHIFFRÉ, l'owner a raison : `jak-hd-physics.gc` fait **6984 lignes** après **54 commits** en
six jours, et le rapport de cette semaine documente **19 défauts silencieux trouvés DANS le code
censé être déjà correct** (règle either-end qui jetait 532 volumes, masques miroirs sur 7 modèles,
compteur `cres` qui n'a jamais fonctionné, double-blend qui écrasait `meshpen`, `crun` qui mesurait
la magnitude au lieu du mouvement, `colskip` sur 202 chaînes, filtres `chains=` sur 2384 volumes...).
Ce n'est plus un problème de réglage : chaque cycle a empilé une compensation sur le défaut du cycle
précédent, et les corrections interfèrent entre elles. On arrête de rapiécer.

### ON JETTE : le CŒUR DU SOLVEUR et TOUTE l'instrumentation.
### ON GARDE (validé indépendamment, ne pas retoucher) :
  * le format de données `physics_chains.txt` (chaînes, familles A/B, params) — bon et rechargeable
    à chaud (20 Ko, `adb push` + toggle = boucle en minutes) ;
  * le pipeline de VOLUMES DÉRIVÉS DU MESH (fitter offline, rayons par maillon depuis l'étendue
    réelle des sommets skinnés) — c'est la seule partie neuve et réellement mesurée ;
  * les tables de reskin / autorité de peau ;
  * cette SPEC (§1-§16) comme unique source d'exigences.

### RÉÉCRITURE — UN SEUL PASSAGE, LISIBLE, DANS CET ORDRE
  1. intégrer (ressort + gravité selon la famille) ;
  2. contraindre (longueur invariante, cône) ;
  3. collisionner (corps dérivé du mesh + chaîne↔chaîne, la collision a le DERNIER MOT) ;
  4. écrire le bone.
AUCUN suppresseur de mouvement au départ : priorité anim, gel de calme, clamp de jerk, sommeil,
hystérésis — TOUS ABSENTS. On ne les rajoute QU'UN PAR UN, chacun justifié par un défaut MESURÉ, et
chacun accompagné de son % de frames actives. Un suppresseur qui dépasse ~20 % des frames est refusé.

### INSTRUMENTATION — REFAITE, UNE SEULE GRANDEUR PRIMAIRE
La position ÉCRITE du joint, frame par frame. Tout le reste en dérive :
mouvement = |pos(t) − pos(t−1)| ; inertie = variance ~0 pendant que l'acteur bouge ;
pénétration = surface skinnée dans un volume ; jerk = pire |Δpos| en une frame.
Rien d'autre. Pas de `dev`, pas de proxy, pas de compteur qui ne descende pas d'une position écrite.

### ORDRE DE LIVRAISON — UN PERSONNAGE, JUGÉ PAR L'OWNER
KEIRA D'ABORD, seule : mèches, cheveux, oreilles, poitrine, lunettes, bretelles. Réglée jusqu'à ce
que l'OWNER dise oui sur elle. Puis Jak (pans de veste, col, oreilles, cheveux), puis le Maire, puis
le cast via le banc (§14). Résoudre 60 modèles avant le premier « oui » est ce qui a produit six
jours de faux verts.

## 18. LES VOLUMES « DÉRIVÉS DU MESH » SONT AUSSI À JETER (owner 2026-08-10 : « je remets tout en cause »)
Il a raison, et la mesure le prouve. Distribution des 1335 volumes prétendument ajustés au mesh :
médiane r=967 unités (~24 cm), p90 r=2756 (~67 cm), max r=13646 — soit **3,3 m de rayon sur un
personnage de 2,3 m**. **12 volumes sont plus gros que le personnage entier**, 51 dépassent un
demi-personnage. Ce ne sont pas des colliders qui épousent un corps, ce sont des ballons.
POURQUOI C'ÉTAIT INVISIBLE : ma `fit-error = 0.000` testait « le volume d'un os contient-il SES
PROPRES sommets » — une TAUTOLOGIE. Un volume ajusté sur les sommets d'un os les contient par
construction. Elle ne testait jamais si le volume SUIT LA SURFACE là où les AUTRES chaînes passent.
Donc « dérivé du mesh » ne signifiait que « rayon calculé automatiquement » : MÊME représentation en
capsules, exactement ce que l'owner condamne depuis le premier jour — une capsule ne peut pas
représenter une épaule, une mâchoire, un torse, un pan de pantalon évasé.

### NOUVELLE REPRÉSENTATION : COLLISIONNER CONTRE LE MESH SKINNÉ LUI-MÊME
  * Plus de proxys. La collision se fait contre la GÉOMÉTRIE RÉELLE du personnage (triangles du mesh
    skinné du corps), qui est déjà accessible à l'exécution — on en échantillonne déjà des centaines
    de milliers de sommets pour `meshpen`, donc la donnée est là.
  * Coût : grille spatiale / hachage sur les triangles du corps, reconstruite par frame ou par N
    frames selon le NIVEAU DE PRÉCISION (c'est exactement ce que les niveaux doivent arbitrer —
    densité de triangles testés, pas « une chaîne qui ne teste rien »).
  * Le test devient : distance signée d'un point de chaîne (avec son rayon propre, dérivé de
    l'épaisseur du mesh qu'il porte) à la SURFACE réelle. Pénétration = distance négative.
  * INTERDIT : toute métrique de qualité de collider qui compare un volume à lui-même. La seule
    mesure valable est la distance chaîne ↔ SURFACE RÉELLE, jamais chaîne ↔ proxy.
  * Ce qui survit du pipeline précédent : rien de la géométrie. On garde uniquement l'idée du rayon
    PAR MAILLON dérivé de l'épaisseur locale du mesh, et le fait que la donnée mesh est lisible au
    runtime.

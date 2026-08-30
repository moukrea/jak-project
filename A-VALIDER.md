# À VALIDER PAR L'OWNER

Liste tenue à jour par Claude. Rien ici n'est fermé sans ta parole.
Dernière mise à jour : 2026-08-30.

## 📊 État de tout ce qu'on a discuté

### ✅ Validé par toi
- Mémoire du jeu 1370 → 744 Mo, niveau 122,1 → 40,6 Mo, textures 6208 → 571 ms
- Bouton de saut sur la Shield (propriété de débogage laissée par notre outillage)
- Vue première personne : Jak et Daxter masqués
- Visière de Keira (masque de soudure de Jak 2) supprimée
- Collecteurs d'Eco vert au retour de Geyser Rock
- Boucle et veste de Jak (poids de peau + parentage)

### ⏳ Livré, attend ton œil
- **Propriétés PBR par matière** — 172 matières classées en regardant les albédos, dans le dépôt d'assets
- **Écran de chargement** — cinq chemins d'attente, silhouette animée
- **Cinématiques** — formule remise dans le bon sens le 30/08 (vertical constant, horizontal élargi)
- **Build depuis zéro** — trois constructions, 50 artefacts empreintés, squelette HD enfin dans la chaîne
- **Police Urbanist et fin du tout-majuscules**
- **Ton des textes** (« Appuie sur start »)
- **Barres noires latérales / taille de fenêtre Android**

### 🔧 En travail
- **Écran de chargement** — les 5 points du 30/08 sont traités et livrés, ils attendent ton œil :
  60 images/s réelles (35 images distinctes, une par frame, **aucune interpolation**) ; le gel du
  chemin FROID mesuré puis borné (405 ms → voir le rapport) ; glyphes **vectorisés** (potrace) et
  filtrage corrigé ; texte réduit de 25 % ; silhouette 61 % → 40 % de la hauteur d'écran

### 📋 Au backlog, pas commencé
- **Taille des sous-titres réglable** dans les options
- **Canal langue → chargeur de texture** (bloque le japonais uniquement)
- **Physique de Keira** — gelée à ta demande, 5 sections sur 38
- **Pas de temps fixe + interpolation de rendu**
- **Refonte des menus** — tu l'as rouverte, « pas fini du tout »
- **Garde du pack HD** qui ne teste que le dump Jak 2 alors que le pack contient du Jak 3

---
## 📋 Au backlog, pas encore commencé

- **Modèle HD de Jak : deux défauts de rig sur la sangle du dos** — signalés par toi le 28 août.

  1. **Un point de sa veste bleue est pondéré sur la sangle** qui bouge avec le vent. Les
     polygones de la veste traversent donc la sangle quand elle s'anime. C'est un défaut de
     POIDS DE PEAU : un sommet de vêtement affecté à un os de sangle.
  2. **La boucle métallique de la sangle est attachée aux épaules** au lieu de l'être à la
     sangle. Elle bouge donc indépendamment de ce qu'elle est censée tenir — d'où l'aspect
     glitchy. C'est un défaut de PARENTAGE : le bon os existe, la boucle est accrochée au
     mauvais.

  **Les deux sont dans le rig, pas dans la physique.** Aucun réglage de solveur ne les corrigera :
  tant que la boucle pend des épaules, elle suivra les épaules.

  **Méthode imposée, tirée de mon erreur du même jour sur Keira** : publier les positions de repos
  et les poids AVANT et APRÈS, calculés avec une **vraie inverse de matrice 4×4** — la formule
  simplifiée `-Rᵀt` n'est valable que sans mise à l'échelle et m'a fait annoncer un défaut à 62
  fois la taille du modèle qui n'existait pas.

  **Et la leçon du même jour sur la livraison** : prouver la correction sur le fichier
  RÉELLEMENT LIVRÉ dans `jak1_hd_assets.zip`, pas sur la source. Les corrections de géométrie et
  de poids de peau ne voyagent que par ce zip.

- **Taille des sous-titres réglable dans les options** — demandé par toi le 28 août : « avec la
  nouvelle font c'est cool sur grand écran mais sur un petit écran c'est un peu dur à lire avec la
  taille par défaut ».

  Le besoin est réel et c'est la conséquence directe du nouveau rendu : une police vectorielle
  rendue à une taille fixe en pixels devient plus petite en proportion quand l'écran est petit.
  L'ancienne police ne posait pas le problème parce qu'elle était grossière.

  À faire : un réglage dans les options de jeu, appliqué au rendu des sous-titres. Deux points à
  traiter en même temps, sinon le réglage cassera l'affichage :
  1. **Le retour à la ligne** doit suivre la taille choisie, sinon les lignes longues déborderont
     de l'écran aux grandes tailles.
  2. **La boîte de sous-titres** doit se redimensionner, pas seulement le texte.

  Note : ça vaudrait aussi pour les indices d'interaction, mais l'owner n'a demandé que les
  sous-titres — ne pas élargir sans son accord.

- **Canal langue → chargeur de texture** — au backlog le 28 août. **Portée corrigée le même
  jour : c'est BEAUCOUP plus étroit que ce que j'avais écrit.**

  **Ce que j'avais écrit à tort** : que la ligne précurseur de l'écran de chargement en aurait
  besoin. **Faux, et l'owner l'a relevé** : l'atlas précurseur associe un glyphe à chaque lettre,
  donc afficher `CHARGEMENT` prend simplement les glyphes C, H, A, R, G, E, M, E, N, T. Vérifié :
  **un seul atlas de 26 glyphes** couvre LOADING, CHARGEMENT, CARGANDO, LADEN et CARICAMENTO,
  tous les glyphes requis étant présents. Ma propre preuve les avait déjà rendus depuis le même
  fichier. Aucun canal n'est nécessaire pour ça.

  **Ce dont il s'agit réellement** : le **japonais** doit garder sa police d'origine (359
  caractères CJK qu'Urbanist n'a pas) pendant que les langues latines passent sur Urbanist. Ce
  partage-là demande que la langue courante descende jusqu'à la couche qui choisit l'atlas, et ce
  chemin n'existe pas. Même besoin pour tout futur asset réellement dépendant de la langue.

  **Ce n'est donc PAS un prérequis de l'écran de chargement.** Il ne bloque que le japonais.

- **Cinématiques : recadrer au lieu de masquer, à tous les formats d'écran** — demandé par toi
  le 28 août. J'ai lu le code, et ton diagnostic est exact jusqu'au détail du compteur de FPS.

  **Ce que fait le jeu aujourd'hui** (`goal_src/jak1/engine/game/main.gc:24`, fonction
  `letterbox`) : en mode natif il **force du 16:9 en toutes circonstances**.
  - Écran plus étroit que 16:9 → deux bandes noires en haut et en bas.
  - Écran plus large que 16:9 → **deux bandes noires à gauche et à droite**. C'est le cas
    ultra-large que tu décris.

  **Et le compteur de FPS sous les bandes est expliqué** : les bandes sont dessinées dans le
  bucket `debug-no-zbuf`, qui est un des **derniers** — elles passent donc par-dessus tout, HUD
  compris. Ce n'est pas un problème de position du compteur, c'est un problème d'ordre de
  dessin.

  **La correction, telle que tu la décris** : ne rien masquer, recadrer. On garde le champ de
  vision VERTICAL de la bande prévue, et on déduit l'horizontal du format de l'écran. La
  composition verticale voulue par les auteurs est préservée au pixel près, l'horizontal
  s'étend, et il n'y a plus aucune bande à dessiner — ni en haut, ni sur les côtés, à n'importe
  quel format.

  **Le risque à mesurer avant de livrer, et il est réel** : élargir l'horizontal en cinématique
  montre ce que les auteurs avaient laissé HORS CADRE — décor non construit, acteurs qui
  apparaissent, bords de plateau. C'est le piège classique de l'élargissement de champ dans un
  jeu ancien. À vérifier scène par scène ; certaines demanderont peut-être une limite.

  **Le HUD** : compteur de FPS et sous-titres doivent rester exactement où ils sont d'habitude,
  donc être dessinés en espace ÉCRAN et après le recadrage. Le placement des sous-titres est
  aujourd'hui calé sur la bande 16:9 — il devra suivre le nouveau cadre.

  Ordre : le recadrage de la caméra, puis la suppression des bandes, puis l'ordre de dessin du
  HUD, puis la passe scène par scène sur ce que l'élargissement révèle.

- **PBR : des matières par texture, pas deux curseurs pour tout le jeu** — demandé par toi le
  28 août. Tu as raison sur les deux points, et j'ai vérifié le second.

  **C'est bien global.** Il n'y a que deux réglages de matière dans tout le moteur :
  `recharged_pbr_texture_relief = 1.5` et `recharged_pbr_spec_intensity = 0.15`
  (`game/graphics/gfx.h:427-428`). Un commentaire du code le dit lui-même : la loi de parallaxe
  est « une matière à une position de curseur ». Donc le sable, le tissu et la pierre taillée
  reçoivent exactement le même relief et le même spéculaire. Et tu as raison aussi sur « c'est
  un peu light » : deux paramètres ne décrivent pas une matière.

  **Le point d'accroche existe déjà.** Les textures sont identifiées par leur nom de fichier nu
  (« sand-01 »), et le moteur tient déjà une table de diagnostic par texture, indexée sur ce même
  nom (`CustomTextureReplacements.cpp`). Une table de presets indexée pareil se branche dessus
  sans rien inventer.

  **Ce qu'une matière devrait porter**, au-delà des deux actuels : rugosité, métallicité,
  amplitude et échelle du relief, anisotropie (le tissu et le bois brossé en ont, la pierre non),
  réflectance de base, et le signe/l'espace de la normale — ce dernier point rejoint ton premier
  défaut.

  **Ton premier défaut — relief présent d'un côté, absent ou inversé de l'autre.** Ce n'est pas
  consigné pour l'instant, aucun rapport ne le couvre. La description (marche / absent / inversé
  selon les faces) est la signature classique d'un problème de **repère tangent** : orientation
  des UV, signe de la bitangente, ou normales dans le mauvais espace. À instrumenter par face
  avant de toucher aux matières — sinon on réglera des presets par-dessus un repère faux.

  **Ton idée d'utiliser Haiku en vision** est la bonne façon de peupler la table : les textures
  couleur sont nommées et peu nombreuses (51 images locales, davantage dans le dépôt d'assets).
  Une passe de description sur la version COULEUR uniquement donne la famille de matière, puis on
  en déduit le preset. Fait une fois, versionné dans le dépôt d'assets, pas recalculé au runtime.

  Ordre : le repère tangent d'abord (sinon tout le reste est bâti sur du faux), la table de
  matières ensuite, la passe vision pour la peupler, et enfin le portage des presets dans
  `moukrea/recharged-assets` comme tu le demandes.

- **Écran de chargement à la place de l'écran noir** — demandé par toi le 28 août, maquette
  fournie et conservée dans `.autoport/design/loading-screen-owner-mockup.png` (16:9).
  Ça répond directement aux 6,7 s d'écran noir que je t'avais signalées le matin même : au lieu de
  te demander si le jeu a planté, on te dit qu'il charge.

  **Où ça se branche** : `blackout()` (`goal_src/jak1/engine/game/main.gc:61`) dessine aujourd'hui
  un simple rectangle noir plein écran. C'est là que le contenu vient.

  **Piège à éviter, et il est réel** : l'écran noir sert AUSSI aux coupes de caméra (0,035 s) et
  aux boutons (0,05 s). Afficher « Loading... » à chaque fois ferait clignoter le texte en
  permanence. Il faut le lier à la barrière de chargement précisément, et n'afficher qu'au-delà
  d'un seuil (~0,5 s d'attente). Sans ça, le remède est pire que le mal.

  Quatre morceaux :
  1. **Silhouette** — Jak courant latéralement vers la droite, Daxter sur l'épaule, ~40 % de la
     hauteur d'écran, centrée verticalement à gauche. À capturer depuis la VRAIE animation de
     course, en vue de côté, puis convertie en blanc sur noir. Je propose une image fixe d'abord ;
     une boucle animée est une extension naturelle, mais elle multiplie le coût de capture.
  2. **Texte « Loading... » localisé** — nouvel identifiant de texte à ajouter dans ~20 langues.
  3. **Ligne de glyphes précurseurs** sous le texte, **à la largeur exacte du texte localisé**.
     Point d'implémentation : « Chargement... » est nettement plus large que « Loading... », donc
     la ligne de glyphes doit être **mise à l'échelle par langue** sur la largeur mesurée du texte
     rendu, pas dessinée à taille fixe. Le système de police sait mesurer une largeur.
     Aucun alphabet précurseur n'existe dans le jeu : les textures « precursor » sont des murs de
     la citadelle. Les glyphes sont donc un asset à créer (8 sur ta maquette).
  4. **Police Urbanist** pour le texte — **dépend de l'entrée « police » ci-dessus**. Tel quel, le
     texte sortirait en capitales dans la police d'origine. Deux options : livrer d'abord en
     police actuelle et repasser après, ou attendre Urbanist. Je te recommande d'attendre : un
     « LOADING... » en capitales dans la vieille police irait à l'encontre de tout l'objectif.

  Ordre : le branchement et le seuil d'abord (c'est ce qui supprime l'angoisse), la silhouette
  ensuite, les glyphes et Urbanist en finition.

- **Police du jeu : fini le tout-en-majuscules, passage à Urbanist** — demandé par toi le
  28 août. Ce que j'ai mesuré avant de le chiffrer :

  **Le tout-majuscules n'est pas seulement la police, c'est aussi les données.** Les textes du
  jeu sont écrits en majuscules à la source : 399 entrées dans le texte anglais, ~270 par langue
  dans les textes de base, et **zéro** contient une minuscule. Changer la police ne suffira donc
  pas — il faudra réécrire les textes.

  **La table de glyphes est plus riche qu'on croit** : 250 glyphes en corps 12, 289 en corps 24.
  Bien plus que majuscules + chiffres + ponctuation, donc elle porte déjà les accents de toutes
  les langues. Une note dans le code affirme que les octets minuscules ne tombent pas sur des
  glyphes minuscules et rendent du charabia.

  **Sur la texture de police que tu as en tête** : il y en a bien deux, `ascii.12lo` et
  `ascii.12hi`. Attention, je pense que `lo`/`hi` désigne les bits de poids faible et fort d'une
  texture 4 bits rangée dans le tampon de profondeur, **pas** minuscules/majuscules. Je ne l'ai
  pas encore prouvé — c'est le premier point à vérifier, parce que c'est peut-être une fausse
  piste qui coûterait une journée.

  **Ça n'a pas d'importance si on va jusqu'au bout de ton idée** : si on génère l'atlas depuis
  Urbanist, on l'écrit nous-mêmes et les minuscules viennent gratuitement. Faire la police
  moderne rend la question des minuscules d'origine sans objet.

  Le travail, en trois morceaux indépendants :
  1. **Atlas** — générer les glyphes depuis Urbanist. Point à vérifier d'abord : la police
     d'origine est en 4 bits (16 niveaux) rangée dans le tampon de profondeur. Si ce chemin est
     encore actif sur PC/Android, une police moderne y sera bridée sur l'antialiasing et il
     faudra la sortir de là.
  2. **Table UV + correspondance des caractères** — regénérer les 250/289 entrées et étendre la
     correspondance pour que les octets minuscules tombent sur les bons glyphes.
  3. **Réécriture des textes** — c'est le vrai coût, et il est humain, pas technique. Passer en
     casse normale ~670 entrées par langue, sur une vingtaine de langues. Une minuscule
     automatique donnerait « Eco » là où il faut « eco », des noms propres cassés, des acronymes
     détruits. Anglais et français relisibles ; les autres langues demandent de la prudence.

  Ordre : le point 1 en premier, parce que si le rendu 4 bits bride la police, tout le reste
  change de forme.

- **Seins de Keira** — **en cours, chantier structurel autorisé par toi le 27 août**
  (« laisse courir le chantier, on fait la spec à 100% »). État : **5 tenues mesurées sur 38**
  (§7 est passée le 28 août). Onze des treize sections non tenues partagent la même cause — la
  déformation doit vivre dans le tenseur, pas dans une chaîne de maillons.
  **Correction du 28 août :** j'ai écrit ici « le worker chiffre le travail à quatre unités ».
  C'était faux, et c'était ma faute de lecture : le cycle 130b chiffrait quatre **lignes** de
  budget de code, pas quatre unités de travail. Ce qui est réellement mesuré aujourd'hui : les
  échelles de forme de ta spec sont des échelles d'**organe**, le moteur les applique **par
  maillon**, et seuls ~57 % de la chair sont pilotés par les maillons — donc l'organe ne reçoit
  qu'un peu plus de la moitié de ce que ta spec demande. Chiffré sur six des huit mesures de
  l'axe latéral — les deux qui refusent le modèle sont publiées telles quelles, et sur l'axe
  vertical il n'y a aucune loi. Conséquence directe et mesurée aujourd'hui : la largeur que ta
  §10 demande au coucher (+18 à +28 %) est rendue à +12,4 %, et le rétrécissement que ta §11
  demande au ventre (−7 à −13 %) est rendu à −4,4 %. Pas de date.
- **Pas de temps fixe + interpolation** — pour que le gameplay ne casse plus sous 60 images/s
  et profite au-delà. Ton chantier du 26 août.
- **Garde du pack HD** — elle ne teste que le dump Jak 2 alors que le pack contient du Jak 3 :
  quelqu'un qui fournit Jak 2 sans Jak 3 peut recevoir du contenu auquel il n'a pas droit.
- **Menu** — phase conservée sur ton ordre, à retravailler.
- **Rock village crash** — phase conservée sur ton ordre.

Abandonnée sur ton ordre : *long jump regression*.

---

## 📦 Où récupérer les builds

https://github.com/moukrea/jak-builds/releases/tag/jak1-rtlight-wip

- `app-jak1-android-arm64.apk` — le binaire, **sans aucun asset Naughty Dog**
- `jak1_hd_assets.zip` — les assets extraits des ISO, **canal légal obligatoire**, à poser sur
  le stockage externe de l'appareil

**Piège de livraison** : quand le format des niveaux change, un appareil déjà équipé refuse de
démarrer avec `version mismatch when loading tfrag3 data`. Ça ressemble à un bug moteur, c'est une
livraison incomplète — il faut repousser `out/jak1/fr3/` **et** le zip.

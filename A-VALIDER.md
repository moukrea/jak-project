# À VALIDER PAR L'OWNER

Liste tenue à jour par Claude. Rien ici n'est fermé sans ta parole.
Dernière mise à jour : 2026-08-28.

---

## ✅ Déjà validé par toi (2026-08-27)

### Validé le 2026-08-28

- **Vue première personne avec les modèles HD** — on ne se retrouve plus dans la tête de Jak, et
  Daxter HD ne s'affiche plus. Cause : le miroir de visibilité des modèles HD lisait **un seul
  bit d'une porte qui en compte trois**, donc les modèles d'origine disparaissaient et les HD
  restaient dessinés.
- **La visière flottante de Keira** — c'était le **masque de soudure de Jak 2** (`mask` +
  `maskstrap`, 173 sommets posés au sol sous ses semelles), accroché à la racine du squelette.
  Supprimé, comme tu l'as demandé. Tes bretelles et tes lunettes n'y ont pas touché : elles
  étaient à leur place, mes chiffres du contraire étaient faux (erreur d'inversion de matrice de
  ma part, rectifiée dans `.autoport/reports/OWNER-DEFECT-keira-hd-maskstrap.md`).
- **Le bouton de saut sur la Shield** — une propriété de débogage laissée par notre outillage
  tenait la croix enfoncée en permanence. Vidée, et une garde automatique empêche désormais de
  la reposer.

- **Plafond mémoire** — mémoire du jeu 1370 → 744 Mo, un niveau 122,1 → 40,6 Mo.
  Sur la Shield : 4 min stables, pic 817 Mo, 0 tueur mémoire, 0 plantage (elle mourait vers 75 s).
- **Pré-calcul** — textures au démarrage 6 208 → 571 ms, pire blocage 1 602 → 83 ms, 0 blocage
  au-dessus de 200 ms.

Tu as joué sur le Honor avec tout au maximum, les deux points tenaient.

---

## ⏳ En attente de ton test

- **Les cinématiques n'ont plus de barres noires — l'image est recadrée, pas masquée.**
  Ta remarque : « au lieu d'avoir des barres noires on devrait grossir la partie visible pour
  qu'elle prenne toute la hauteur, et ne rien masquer horizontalement, QUELQUE SOIT L'ASPECT
  RATIO », et « sur les aspect ratio très larges le compteur de FPS se retrouve sous les barres
  noires ».

  Ce que faisait le jeu : il forçait du 16:9 **en toutes circonstances** pendant une cinématique.
  Écran plus étroit que 16:9 → deux barres en haut et en bas. Écran plus **large** → deux barres
  **verticales**, à gauche et à droite. C'est ce second cas que tu vois sur ton téléphone.

  Ce qu'il fait maintenant : il garde **exactement** le champ de vision vertical que les auteurs
  avaient cadré, et il en déduit l'horizontal depuis le format réel de ton écran. Le cadre rendu
  a donc déjà la forme de l'écran — il ne reste plus rien à masquer, à aucun format. Mesuré sur
  sept formats du 4:3 au 32:9 : le vertical rend la **même** valeur partout (0,3514), et la forme
  du cadre égale la forme de l'écran sur chaque ligne. À 16:9 le changement est **nul**.

  **Le compteur de FPS n'était pas mal placé.** Les barres et lui étaient écrits dans le *même*
  paquet de dessin, les barres arrivant plus tard dans la file : elles le repeignaient dessus.
  Zéro barre, donc plus rien pour le recouvrir — et il n'a pas bougé d'un pixel.

  **Les sous-titres**, eux, n'ont jamais été recouverts (ils sont dessinés après les barres).
  Leur défaut était autre : ils étaient **remontés de 11 pixels** pendant une cinématique pour
  dégager la barre du bas. Cette barre n'existe plus, donc ils reviennent à leur hauteur
  habituelle, la même qu'en jeu normal.

  **Ce que je te demande de regarder :** lance n'importe quelle cinématique sur ton téléphone.
  Plus de bandes noires sur les côtés, image pleine largeur, compteur de FPS visible si tu l'as
  activé, sous-titres à leur hauteur normale.

  **Et la seule chose que je ne peux pas mesurer, donc que je te demande vraiment :** en
  élargissant sur les côtés, est-ce qu'une scène laisse voir quelque chose que les auteurs
  avaient laissé hors cadre — décor non construit, acteur qui apparaît, bord de plateau ? Ça se
  juge à l'œil, pas au chiffre. Le nom de la scène me suffit : j'ai déjà la manière de brider
  l'ouverture latérale **sans** remettre de barre, je ne l'ai pas livrée pour ne pas poser un
  réglage qui ne sert à rien tant qu'aucune scène ne le demande. Ce que je peux te dire de sûr :
  verticalement **rien** de neuf n'apparaît, sous 16:9 **rien** non plus, et au-dessus de 16:9 la
  cinématique reste **plus étroite d'un quart** que ce que le jeu te montre déjà en jeu normal.

  **Ce que je n'ai pas prouvé :** pas de course sur l'appareil dans ce cycle. Le changement est du
  code GOAL pur, identique sur PC et sur Android.

  **Ce que je n'ai pas touché :** le mode « rendu d'origine » (celui qui utilise la visibilité
  PS2) garde ses barres — là le champ ne peut pas être élargi. Et Jak 2 / Jak 3 gardent l'ancien
  comportement : ils ne sont pas dans le périmètre de ce lot. À noter, ils divergent maintenant de
  Jak 1 ; si tu veux les trois pareils, c'est Jak 2 qu'il faut aligner sur Jak 1, pas l'inverse.


- **Vue première personne : Jak HD et Daxter HD ne s'affichent plus — et le défaut venait
  d'un bit, pas d'une approximation.**
  Ta remarque : « en caméra première personne on se retrouve (quand on utilise les modèles HD)
  à l'intérieur de la tête de Jak, et on voit aussi le modèle HD de Daxter... faire comme avec
  les modèles originaux ». Tu avais raison sur toute la ligne, et plus précisément que tu ne le
  pensais : les modèles d'origine **sont** masqués par un mécanisme explicite, ce n'est pas un
  hasard de géométrie. En première personne le jeu coupe l'animation de Jak, ce qui lève chez lui
  un drapeau « ne me dessine pas » ; Daxter recopie l'état de Jak chaque image, donc il suit.
  Le compagnon HD, lui, ne regardait **qu'un seul** des trois drapeaux de cette porte — et pas
  celui-là. Il continuait donc à s'afficher alors que le modèle d'origine avait déjà disparu.

  Corrigé en un seul endroit, celui où l'état de dessin passe du modèle d'origine au modèle HD.
  Rien n'a été ajouté au moteur d'origine : le HD est simplement rebranché sur le masquage qui
  existait déjà. Un seul correctif couvre les quatre modèles (Jak et Daxter, origine et HD).

  Mesuré sur une course x86, en lisant le drapeau que **le moteur lui-même** pose quand il a
  réellement dessiné un objet — pas un chiffre que j'aurais construit :

  | | 3e personne | 1re personne | retour 3e personne |
  |---|---|---|---|
  | Jak d'origine | dessiné | **non dessiné** | dessiné |
  | Daxter d'origine | dessiné | **non dessiné** | dessiné |
  | Jak HD | dessiné | **non dessiné** | dessiné |
  | Daxter HD | dessiné | **non dessiné** | dessiné |

  Rien ne reste bloqué en sortant : la 3e personne revient exactement à son état d'avant.

  **Ce que je te demande de regarder :** passe en vue première personne (triangle) avec les
  MODÈLES AMÉLIORÉS actifs. Ni Jak ni Daxter ne doivent apparaître, et rien d'autre ne doit
  changer en vue normale.

  **Ce que je n'ai pas prouvé, et je préfère te le dire :** pas de test sur l'appareil. Le
  changement est du code GOAL pur, identique bit pour bit sur PC et sur Android, et le canal
  qu'il actionne est déjà éprouvé sur appareil depuis le correctif des fantômes de cinématique.

  **Effet de bord que je n'avais pas demandé :** pendant le chargement d'un niveau, l'animation
  de Jak est également coupée — les modèles HD s'éteignent donc maintenant avec lui. Avant, ils
  restaient affichés. Tu ne l'avais pas signalé ; regarde si ça te paraît mieux ou non.

  **Ce que ça ne fait pas :** la vraie vue première personne moderne que tu veux (caméra avancée
  pour voir mains et pieds, corps qui tourne avec la caméra) n'est pas commencée. Ce correctif ne
  la gêne pas — mais note qu'elle devra d'abord **rétablir l'animation de Jak** en première
  personne, que le jeu d'origine coupe, et masquer alors par morceau de maillage plutôt qu'en
  bloc.

- **La barrière de chargement — faite, mesurée, et elle a un coût que je te dis franchement.**
  Ta demande : « un mécanisme de chargement qui s'assure que tout le nécessaire soit bien
  chargé avant de lancer l'écran titre ». C'est fait, et la scène attend maintenant que le
  niveau soit réellement **dessinable** — pas que le jeu dise qu'il est chargé, ce qui
  n'était pas la même chose du tout : au retour de Geyser Rock, le jeu déclarait la plage
  chargée **38 secondes** avant qu'on puisse la dessiner.

  Mesuré sur la Shield, deux démarrages avant et **trois** après (reproductible à 1 ms) :

  | | avant | après |
  |---|---|---|
  | survol du village : décor prêt vs **son** | **4,6 s en retard** | **0,1 s en avance** |
  | logo Naughty Dog (non concerné) | 0,33 / 0,37 s | 0,35 / 0,36 / 0,35 s — inchangé |
  | temps total jusqu'au village prêt | 20,6 s | 22,5 s |
  | pic mémoire | 782 Mo | 777 / 798 / 806 Mo |

  **Le marché, en deux phrases, et la deuxième compte autant que la première.** Le village
  est maintenant **là** quand le survol commence, au lieu d'apparaître d'un bloc au milieu.
  En échange : le logo Jak & Daxter arrive ~1,8 s plus tard, et surtout **l'écran reste noir
  et figé ~6,7 s** pendant que ça charge — le chien de garde du moteur le voit
  (`frame stuck at 926`). Ce n'est pas un plantage (zéro crash, zéro ANR sur les trois
  démarrages), c'est le prix de l'attente que tu as demandée. Tu troques « le décor apparaît
  d'un coup » contre « l'écran attend en noir ». **Dis-moi si c'est le bon échange** — si
  non, je sais où reprendre du temps : pendant les ~15,7 s du logo Naughty Dog le chargement
  tourne au ralenti (budget de 4,5 ms par image), il y a de la marge là.

  **TESTÉ PAR TOI le 2026-08-28 sur le Honor — VERDICT : à moitié.** Tu as chargé une
  sauvegarde à la fin de Geyser Rock. L'écran noir a bien tenu jusqu'à Sandover Village et la
  cinématique s'est lancée chargée : cette moitié-là marche. Mais quand la caméra part sur les
  collecteurs d'Eco vert pendant que Samos en parle, **la plage n'est toujours pas là** — tu
  vois des morceaux de l'endroit, pas les collecteurs. Non corrigé.

  J'ai vérifié statiquement : la scène concernée (`sage-intro-sequence-e`) **est** dans les 18
  scènes que la barrière retient, et elle s'arme bien sur la plage. Le mécanisme n'est donc pas
  contourné, il cède à l'exécution. Deux causes possibles, détail dans
  `.autoport/reports/OWNER-DEFECT-barriere-ne-couvre-pas-les-acteurs-de-beach.md` :
  soit le plafond de 20 s est trop court pour la plage, soit — et ça colle mieux à ce que tu
  décris — la barrière attend que le **décor** de la plage soit prêt alors que la scène a
  besoin de ses **acteurs** (les collecteurs et les évents sont des acteurs, pas du décor).

  **Une seule ligne de ton journal Honor tranche entre les deux** — celle qui commence par
  `LOADGATE open scene=sage-intro-sequence-e`. Ou ta sauvegarde, et je la mesure moi-même. Je
  ne relève pas le plafond au hasard : si c'est la deuxième cause, ça rallonge ton écran noir
  sans rien réparer.

---

## 🔧 En cours de correction

- **Le bouton de saut — RÉSOLU le 28 août, confirmé par toi en jeu sur la Shield.**
  Cause : la propriété de débogage `debug.opengoal.cpad_inject` valait `x` sur la Shield (vide
  sur le Redmi). Le jeu lit cette propriété en continu et `x` = croix : le bouton de saut était
  **tenu enfoncé en permanence**. Un bouton tenu n'émet aucun front, et le saut ne se déclenche
  que sur le front. D'où un jeu qui ne réagit pas alors que toute la chaîne d'entrée mesurait
  saine — les 228 événements arrivaient bien.
  C'est **notre propre outillage de test** qui l'avait laissée. Mes trois hypothèses précédentes
  cherchaient toutes une entrée **absente**, alors qu'elle était **coincée à 1**.

  **La mine derrière, et elle est traitée :** 94 de nos 101 scripts posent cette propriété sans
  jamais la vider. Ajouté le 28 août — `.autoport/device_teardown.sh` (vide toutes nos
  propriétés et le fichier d'injection), et un contrôle automatique avant chaque tentative du
  framework qui compte les scripts fautifs et **bloque** si l'un d'eux est utilisé par la phase
  en cours.

## 📋 Au backlog, pas encore commencé

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

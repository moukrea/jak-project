# À VALIDER PAR L'OWNER

Liste tenue à jour par Claude. Rien ici n'est fermé sans ta parole.
Dernière mise à jour : 2026-08-27.

---

## ✅ Déjà validé par toi (2026-08-27)

- **Plafond mémoire** — mémoire du jeu 1370 → 744 Mo, un niveau 122,1 → 40,6 Mo.
  Sur la Shield : 4 min stables, pic 817 Mo, 0 tueur mémoire, 0 plantage (elle mourait vers 75 s).
- **Pré-calcul** — textures au démarrage 6 208 → 571 ms, pire blocage 1 602 → 83 ms, 0 blocage
  au-dessus de 200 ms.

Tu as joué sur le Honor avec tout au maximum, les deux points tenaient.

---

## ⏳ En attente de ton test

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

- **Le bouton de saut à la manette — JE ME SUIS TROMPÉ SUR LA CAUSE, ET JE N'AI PLUS QU'UNE
  QUESTION POUR TOI (une date).**
  Ce que j'avais écrit ici (« la base de correspondance SDL est absente de l'appareil, SDL ne
  rapporte jamais l'index 0 ») est **faux**. Je l'avais déduit d'un bout de trace tronqué.
  Sur le journal complet de ta session de ce matin sur la Shield, ton bouton A arrive
  **228 fois** jusqu'au moteur, et le moteur le traduit correctement en X/CROIX :

      onPadButton: sdl_button=0 pressed=1 (real gamepad)
      kernel: pad: south pressed

  Et il fait bien sauter : sur tes appuis au sol, l'altitude de Jak monte de ~0,7 m dans la
  seconde qui suit. La chaîne manette → Android → SDL → moteur → saut est intacte, mesurée
  bout en bout. Je n'ai donc **rien décalé** — corriger des index à l'aveugle aurait cassé
  les autres manettes.

  **Tu m'as déjà dit « la manette est en mode Xinput, arrête tes suppositions ».** J'ai
  arrêté. Et j'ai aussi écarté l'autre piste qui traînait dans mes notes (« le fichier
  `sdl_controller_db.txt` manque sur l'appareil ») : ce fichier n'est **jamais** chargé sur
  Android, même à l'époque où ça marchait — le code qui le lit n'existe pas sur ce chemin.
  Son absence ne peut donc pas être une régression. Et la table de correspondance
  réellement utilisée est la bonne : SDL ouvre ta manette sous le nom
  `Xbox One S Controller`, l'entrée qui contient `a:b0`.

  **Donc je te crois sur toute la ligne : ça marchait, ça ne marche plus, et c'est le jeu.**
  Ce que ma mesure ajoute, c'est *où ce n'est pas* : ce n'est pas dans la chaîne d'entrée.
  Le bouton traverse Android, SDL, le JNI et arrive dans le pad du jeu comme CROIX. Le
  défaut est **en aval**, dans ce qui consomme cette croix.

  **Je ne te demande rien, je te dis juste où j'en suis.** L'APK de la Shield a été mis à
  jour ce matin à **08:03:45**, et la session que j'ai mesurée (08:07 → 08:31) tourne sur ce
  binaire. C'est bien quelqu'un qui tenait la manette : 614 appuis, navigation de menu,
  déplacement, sauts. Et le même bouton arrivait déjà correctement dans une trace du **26
  août**. Donc sur les deux builds que je peux mesurer, la chaîne d'entrée est saine.

  **Je n'arrive donc pas à reproduire ton défaut, et je ne le referme pas pour autant.** Il
  reste ouvert ici, avec ce que j'ai établi (ce n'est pas l'entrée) et ce qui manque (dans
  quelle situation précise ça t'arrive : au titre ? en jeu ? après une cinématique ?). Si un
  jour ça te retombe dessus, la seule chose qui m'aiderait est ce contexte-là — pas une
  manip, juste la phrase. En attendant je cherche en aval, du côté de ce qui consomme la
  croix, sans te solliciter.

- **Rien n'attend que les niveaux soient chargés.** Ta demande : une barrière qui ne lance la
  scène que lorsque ce dont elle a besoin est prêt. Concerne le logo qui arrive après son son, et
  le survol de la plage au retour de Geyser Rock avec des éléments manquants.

---

## 📋 Au backlog, pas encore commencé

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

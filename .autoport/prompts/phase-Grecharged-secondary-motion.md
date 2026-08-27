# PHYSIQUE DE KEIRA — DÉPART PROPRE (2026-08-11)

Le contrat est `.autoport/prompts/SPEC-keira-physique.md`, réécrit depuis le message de l'owner.
Il est inliné dans ce prompt : lis-le, c'est la seule source d'exigences.

Branche : `physics-keira-clean`. Toute la physique accumulée est parkée sur
`physics-attic-2026-08-11` — **elle n'est pas une base de travail, on ne va pas y repêcher du code**.
Le moteur est un squelette de 5 prises (`jak-hd-physics.gc`, ~45 lignes) et le fichier de chaînes
est vide. Le jeu compile et tourne sans physique : c'est l'état de départ, il est sain.

## L'ORDRE DE TRAVAIL, ET IL N'Y EN A PAS D'AUTRE

1. **LA SALLE DE TEST, SANS JOUEUR.** C'est l'étape 1 et le validateur échoue dessus en premier.
   Jak n'est **pas spawné** — ni endormi, ni hors champ : absent, et tu le prouves par le log de la
   course (`ROOM-NOPLAYER:`). Le sujet est spawné **par nom**, seul acteur de la zone
   (`ROOM-ACTORS: 1 subject=…`). Tu le déplaces **haut/bas** et **gauche/droite**, avec **diverses
   accélérations** et des **à-coups** (`drive=updown|leftright|accel|jerk`). Tu joues **toutes** les
   animations de son art-group (`ROOM-ANIMS: joué/total`, et joué == total). Chaque chiffre extrême
   porte le **nom de l'animation** (`worst chain=… anim=…`).
2. **LES CHAÎNES DE KEIRA, GÉNÉRÉES depuis son rig** : oreilles, cheveux (racine ancrée), mèches,
   seins, lunettes, ce qui pend. Rien d'autre. Aucune ligne écrite à la main.
3. **LES COLLISIONS** de la liste exacte (SPEC §3), avec de vrais colliders qui suivent la forme du
   personnage — et un contrôle positif qui fait **monter** le compteur.
4. **LE REPOS = LA POSE DU MODÈLE** (sauf ce qui pend), et **l'intention d'animation ND a la
   priorité**, détectée **par chaîne**.

## CE QUI FAIT ÉCHOUER IMMÉDIATEMENT

* une affirmation sur le comportement qui ne cite pas une trace d'exécution (un commentaire n'est
  pas une preuve) ;
* un zéro sans contrôle positif qui a fait **monter** le compteur ;
* une chaîne déclarée mais inerte (tipvar < 0.05) — « ce qu'on veut c'est de la physique sur les
  oreilles, cheveux, mèches, seins, lunettes » ;
* une racine qui dérive ;
* un moteur qui repasse au-dessus de 2500 lignes : l'ancien en faisait 6000 et c'est l'empilement de
  suppresseurs qui a tué le mouvement ;
* un autre modèle que Keira dans les données.

Substrat : **x86** pour découvrir (itération en secondes), device `eae4df44` pour confirmer.
Livraison en **paire cohérente** APK + pack du même commit.

## MANDAT DE L'OWNER — 2026-08-27 : CHANTIER STRUCTUREL AUTORISE

Verbatim : « **Laisse courir le chantier, on fait la spec à 100%** ».

Contexte de la decision. Je lui ai presente l'etat mesure : la couverture est figee a **4 TENUE
sur 38** depuis le cycle 115, et **onze des treize sections NON TENUE demandent la meme chose** —
un deplacement du centre de masse ou de l'apex exprime en pourcentage de `B0` (§11, §14, §16,
§18, §19, §20, §22 et les autres), auxquelles s'ajoutent §8 (conservation du volume), §23 (« a
single spring attached to the nipple/apex is insufficient ») et §33/§34 (collision entre les deux
seins). **Ce ne sont pas treize problemes, c'est un seul** : le modele actuel est une chaine de
maillons, la spec decrit un volume deformable.

Je lui ai propose trois voies : (1) laisser courir le chantier structurel, (2) geler Keira pour le
pas de temps fixe, (3) reduire l'objectif aux 16 sections partielles. **Il a choisi (1)**, et il
avait deja refuse (3) par avance : « la spec a 100%, pas de raccourcis ».

### Ce que ce mandat autorise

- **Un changement de MODELE, pas un reglage.** Le cycle 129 a nomme la bonne cible : le canal de
  deplacement du centre de masse doit vivre dans le **tenseur de deformation**. Le cycle 130b a
  chiffre le travail a **quatre unites** — c'est une serie, pas une tentative. C'est accepte.
- Ne plus chercher un parametre qui ferait passer une section isolee : onze sections partagent la
  meme cause, et les traiter une par une a echoue pendant huit cycles.
- Prendre le temps qu'il faut. L'owner ne demande pas de date, il demande la spec entiere.

### Ce que ce mandat n'autorise PAS

- Aucun raccourci sur la couverture : pas de section declaree TENUE sans mesure nommee, pas de
  redefinition d'une exigence pour la rendre atteignable. Le registre reste la seule mesure.
- Ne pas casser ce qui est deja acquis et **valide par lui** : memoire du jeu 744 Mo, un niveau
  40,6 Mo, textures au demarrage 571 ms, zero plantage sur ses deux appareils.

## ORDRE DE L'OWNER — 2026-08-27, 23h : ECRIRE DU CODE

Verbatim : « **Fais lui ecrire du code, ca sert a rien ces cycles d'instruments... Il serait temps
d'arreter de perdre du temps et faire du taff** ».

### Le constat qui motive l'ordre

Depuis le mandat de chantier structurel donne le meme jour, **ZERO fichier de `goal_src/` modifie**
en six heures. Les cycles 129 a 132b ont produit : un estimateur, deux corrections de grandeur de
jugement (§10, §11), une incompatibilite confirmee, un angle mort etendu retroactivement. Tout cela
est du travail d'instrument. La couverture n'a pas bouge d'un pouce : **4 TENUE sur 38 depuis le
cycle 115**.

### La regle, a partir de maintenant

**Chaque tentative doit se terminer par une modification de `goal_src/` ou du solveur.** Si une
tentative se termine sans, le rapport doit dire EN UNE PHRASE pourquoi, et la tentative suivante
n'a plus le droit de faire de l'instrument : elle ecrit.

**Deux cycles d'instrument consecutifs sont interdits.** Un instrument se corrige EN PASSANT,
pendant qu'on ecrit le correctif qu'il mesure — pas comme un cycle a lui seul.

La cible est nommee depuis le cycle 129 et l'owner l'a validee : **le canal de deplacement du
centre de masse doit vivre dans le tenseur de deformation**. Onze des treize sections NON TENUE en
dependent. Ecrire ce canal EST le travail. Commencer par la premiere des quatre unites chiffrees
au cycle 130b.

### Ce que cet ordre ne leve PAS

Il demande d'ecrire du code, pas de fabriquer du vert.

- Aucune section ne passe TENUE sans une mesure nommee qui la soutient.
- Aucune exigence n'est redefinie pour devenir atteignable.
- Un correctif qui echoue reste un correctif ECRIT : on le mesure, on publie le resultat, on
  itere. C'est ca, avancer. Refuter une hypothese sans avoir rien ecrit, ce n'en est pas.
- Ne pas casser les acquis valides par l'owner : memoire du jeu 744 Mo, un niveau 40,6 Mo,
  textures au demarrage 571 ms, zero plantage sur ses deux appareils.

# SPEC — PHYSIQUE DE KEIRA (contrat propre, 2026-08-10)

Ce document remplace `SPEC-physique-secondaire.md` comme contrat de travail. L'ancien est conservé
comme archive (il documente ce qui a échoué, il ne dit pas quoi faire).
PÉRIMÈTRE : **KEIRA SEULE**, code ET données. Les 59 autres modèles ne sont pas touchés. On étend
seulement après que l'owner ait validé Keira de ses yeux.

---
## 1. CE QU'ON VEUT VOIR SUR KEIRA

| Élément | Comportement attendu |
|---|---|
| **Mèches avant** (`rbang`, `lbang`) | Racine soudée au crâne. La mèche bouge et retombe. Ne traverse jamais visage, oreilles, crâne. |
| **Mèches milieu** (`rmidhair`, `lmidhair`) | Idem, débattement plus ample vers la pointe. |
| **Cheveux arrière** (`backhair`) | Bougent aussi — c'était le défaut « l'arrière est complètement stiff ». Ne traversent pas la nuque ni le cou. |
| **Oreilles** (`earL`, `earR`) | Physique **légère**. L'animation d'auteur passe devant quand elle les pilote. |
| **Poitrine** (`chestR`, `chestL`) | Ronde et **ferme** — « jeune et fraîche ». Bouge **bien** et visiblement, les deux seins **s'entrechoquent**, peu de droop, **peu de déformation**. Rotation autour de l'ancre, longueur invariante : ni pointe, ni aplatissement. |
| **Lunettes** (`goggles`) | Pendent sur les épaules (elles sont *portées*). Ne traversent jamais la poitrine. Quand l'animation les **saisit** pour les mettre devant les yeux, l'animation gagne et les garde en main tant qu'elle les tient — même immobile. |
| **Bretelles** | Suivent la forme du buste, pas d'angles cassés, ne traversent pas la poitrine. |
| **Pans de pantalon** (`kneeflapL/R`, `pantflapL/R`) | Pendent, suivent la gravité, ne traversent pas les jambes ni la jambe opposée. |

## 2. LES DEUX FAMILLES (elles décident du comportement au repos)
* **A — ce qui EST elle** : mèches, cheveux, oreilles, poitrine. Simulées en permanence. La gravité
  agit sur la **dynamique**, pas sur le point d'équilibre : au repos, en position normale, ça
  **regagne exactement la forme du modèle** — ni plus haut, ni plus bas, ni plus écrasé. Bounce et
  élasticité voulus. Exception : si elle n'est plus debout (penchée, tête en bas), la gravité reprend.
* **B — ce qu'elle PORTE** : lunettes, bretelles, pans. **Ça pend, ça reste pendu.** Ne regagne
  jamais la pose du modèle. Mais rien ne se tasse ni ne s'écrase.

## 3. RACINE ANCRÉE, POINTE MOBILE (indissociable)
La racine suit **rigidement** l'os porteur (crâne, torse). Elle ne dérive pas — une racine qui
flotte = cheveux décollés = défaut. Le mouvement croît de la racine vers la pointe, et c'est **sur
la pointe** qu'on juge s'il y a du mouvement.

## 4. LES TROIS LEVIERS — NE PAS LES CONFONDRE
* **fermeté** = raideur + élasticité de chaîne quasi nulle. **Pas** l'amortissement (amortir = tuer).
* **débattement** = angle max. Trop grand = aspect liquide (une poitrine : petit, rapide, net).
* **vivacité** = couplage à l'accélération du buste + masse. C'est le « ça bouge bien ».

## 5. COLLISION
Rien ne traverse Keira, **quelle que soit la raison**. La collision se fait contre la **surface
skinnée réelle** (distance signée à la surface), pas contre des volumes proxy. Ses chaînes se voient
**entre elles** (lunettes vs poitrine, mèches vs oreilles). Une résolution **pire que le clip** est
pire que rien : correction bornée par frame, pas de saut visible, pas d'oscillation. Une contrainte
impossible **se pose calmement** au lieu de vibrer.
Exception légitime : quand l'animation met les lunettes devant ses yeux, elles sont *censées* être
dans le volume de la tête — ce n'est pas une pénétration.

## 6. ANIMATIONS D'AUTEUR
Quand l'animation pilote délibérément une chaîne, elle gagne, puis la physique **reprend en blend**.
Détection **par chaîne** (des os sans rapport ne suspendent rien). **« Tenu immobile » ≠ « plus
tenu »** : la libération ne dépend pas de la vitesse du canal.

## 7. DONNÉES — GÉNÉRÉES, JAMAIS RUSTINÉES
Les chaînes de Keira sont **produites** depuis son rig et ces règles : famille **dérivée**, racine
**verrouillée par construction** sur la famille A, rayon par maillon **dérivé de l'épaisseur du
mesh**. Aucun flag de dérogation (pas de `colskip`, pas de filtre de volumes, pas de masque). Les
seuls réglages exposés sont des **paramètres de style** (raideur, débattement, masse) — jamais des
exceptions aux règles.

## 8. MESURES ADMISSIBLES — UNE SEULE GRANDEUR PRIMAIRE
La **position écrite du joint**, frame par frame. Tout en dérive :
* mouvement = |pos(t) − pos(t−1)| ; **inertie** = variance ~0 pendant qu'elle bouge ;
* ancrage = déviation de la racine (~0) ;
* pénétration = surface skinnée sous la surface du corps ;
* saut = pire |Δpos| en une frame.
**Test d'admissibilité, avant d'ajouter quoi que ce soit** : « si ce chiffre est vert et que l'owner
voit encore le défaut, qu'est-ce qui l'expliquerait ? » S'il y a une réponse, la mesure ne vaut rien.
Tout zéro exige un **contrôle positif qui a tiré** (injecter le défaut, voir le compteur monter).
Une mesure par chaîne doit **varier** par chaîne — jamais une constante partagée ni une rampe d'index.

## 9. AUCUN SUPPRESSEUR PAR DÉFAUT
Gel de calme, suspension d'anim, clamp de saut, sommeil, hystérésis : **absents au départ**. On en
rajoute un **seulement** si un défaut mesuré l'exige, et on rapporte **combien de mouvement il a
retiré** (pas sur combien de frames il tourne).

## 10. LIVRAISON
Substrat de preuve : device Redmi si connecté, sinon **x86** (autorisé par l'owner), avec la **dette
de preuve device déclarée**. Une exécution unique doit montrer, **par chaîne nommée de Keira** :
racine ancrée + pointe mobile + zéro pénétration de surface (contrôle positif tiré) + pas de saut
visible. Ensuite seulement : APK + pack sur jak-builds, et l'owner juge de ses yeux.
Toggle menu + niveaux de précision inchangés (OFF ≡ stock).

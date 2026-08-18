# CE QU'IL Y A À REGARDER SUR CE BUILD — la poitrine, et elle seule

Branche `physics-keira-clean`. (Le tag est lisible sur le device : `files/.custom_pack_stamp_jak1`.)
APK `9f75cbcc`, pack `324e9ebd`.

Rien d'autre sur Keira n'a été touché : cheveux, bretelles, lunettes, languettes, pantacourt
restent **gelés** par ton ordre du 14/08 — pas réparés, gelés, avec leur mesure au dossier.

---

## 1. LA PEAU SUIT ENFIN LE DEUXIÈME OS. C'EST LA RÉPONSE À « C'EST DU PUDDING ».

Tu avais raison, et la mesure te donnait raison : le deuxième os de chaque sein était bien posé
dans le squelette, mais **presque aucun morceau de chair ne le suivait**. L'organe restait une
pièce rigide pendue à une seule charnière — il *balançait* au lieu de *se déformer*.

Combien de la chair est maintenant pilotée en priorité par ce deuxième os :

| | il y a deux builds | build précédent | **ce build** |
|---|---|---|---|
| sein gauche | 0 % | 27,3 % | **43,5 %** |
| sein droit | 0 % | 22,7 % | **37,5 %** |

La barre que je m'étais fixée est 30 %. **Les deux la passent pour la première fois.**

Ce que ça devrait donner à l'œil : la poitrine **travaille** — la partie avant se déforme par
rapport à la partie arrière — au lieu de se déplacer d'un bloc.

## 2. CE QUE ÇA COÛTE, ET C'EST LA QUESTION QUE JE TE POSE

Le mouvement est **plus petit** qu'au build précédent, et je le mesure :

* amplitude de la pointe : **−13 %** à gauche, **−11 %** à droite ;
* affaissement quand elle se penche en avant (souder sur le Zoomer) : **−24 %** à gauche,
  **−52 %** à droite.

**LA QUESTION** : est-ce que ça rend mieux (ça se déforme, donc ça fait de la chair) ou moins bien
(ça bouge moins, donc ça fait mou/inerte) ? C'est le seul arbitrage que je ne peux pas faire à ta
place, et il décide si je garde ce placement ou si je le recule.

Aucun réglage n'a bougé : ni raideur, ni amortissement, ni masse, ni gravité. Les trois fréquences
propres sont **identiques** au build précédent et toutes dans leurs bandes.

---

## CE QUI N'EST TOUJOURS PAS RÉGLÉ, ET JE NE LE CACHE PAS

* **La poitrine traverse encore le buste sur les mouvements forts, et c'est PIRE que le build
  précédent** (mesuré 0,094 m à gauche contre 0,059 m). Mais j'ai enfin trouvé pourquoi, et ce
  n'est pas le solveur : **dans la pose debout d'origine, physique complètement éteinte, le nœud
  externe du sein est DÉJÀ 5,9 cm à l'intérieur du volume de collision épaule→torse.** Le solveur
  n'a donc nulle part où pousser — on lui demande de sortir d'un volume dont la pose d'auteur
  elle-même est à l'intérieur. C'est le volume qui est à refaire, pas la physique, et c'est le
  chantier suivant.
* **Le retour au calme est plus lent** : 1,48 s et 1,50 s (la cible est 1,0–1,5 s) contre 1,23 s
  et 1,43 s avant. C'est à la limite haute.

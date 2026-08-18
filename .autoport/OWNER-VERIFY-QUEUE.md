# CE QU'IL Y A À SAVOIR SUR CE CYCLE — rien de neuf à regarder à l'écran

Branche `physics-keira-clean`.

**LA PHYSIQUE N'A PAS BOUGÉ, ET C'EST VÉRIFIABLE.** Les trois ajouts au moteur sont des compteurs ;
aucun ne déplace un os. Un gros bloc de commentaires a été sorti du moteur vers son fichier de
notes : le code privé de ses commentaires est **bit-identique** avant et après. Tu ne verras donc
aucune différence à l'écran, et ce n'est pas un build retenu pour cause de qualité.

Ce cycle achète une CAUSE — celle du « pudding » — et elle est chiffrée deux fois.

---

## 1. J'AI TROUVÉ POURQUOI C'EST DU PUDDING, ET C'EST UN NOMBRE

Ta §22 fixe la limite : le centre de masse d'un sein ne doit pas s'écarter de plus de **0.40** fois
la longueur racine→pointe de l'organe (0.35 en régime normal).

Mesuré, sur la course complète (tes 5 pilotages × tes 31 animations) :

| | ta limite | mesuré | |
|---|---|---|---|
| sein gauche | 0.40 | **1.81** | **×4.5** |
| sein droit | 0.40 | **1.93** | **×4.8** |

Le centre de masse parcourt presque **deux fois** la longueur de l'organe. C'est ça, « du pudding » :
pas une mauvaise fréquence — tes fréquences, ton amortissement et ton temps de stabilisation sont
tous **dans tes bandes** — mais une amplitude quatre à cinq fois trop grande. Personne ne la
mesurait : le moteur applique ta limite de centre de masse à un autre canal, et ta limite d'apex à
un point du squelette qui n'est pas l'apex.

## 2. ET ÇA EXPLIQUE AUSSI QUE TES DEUX SEINS SE TRAVERSENT

L'écart entre les deux au repos vaut **0.63** longueur d'organe. Chacun en parcourt **1.8**. Aucun
solveur de collision ne peut rattraper ça : ce n'est pas que la collision ne pousse pas, c'est que
l'organe part beaucoup trop loin.

Deux chemins indépendants concordent : la géométrie du maillage dit qu'il faut 1077 u de
rapprochement pour produire la traversée déjà mesurée ; le compteur dit que le sein gauche à lui
seul en parcourt 1087. L'excursion d'un seul des deux suffit donc déjà. C'est ce qui me fait dire que cette fois la cause est solide et pas une hypothèse de plus.

**Je n'ai pas posé la limite, et ce n'est pas de la prudence : c'est la mesure qui l'interdit.**
J'ai mesuré la part du mouvement qu'une limite à 0.40 mordrait, et elle est énorme :

| | moyenne | instants au-dessus de 0.40 |
|---|---|---|
| sein gauche | 0.4743 | **54.6 %** |
| sein droit | 0.4605 | **52.1 %** |

La MOYENNE est déjà au-dessus de ta limite, et plus d'un instant sur deux la dépasse. Poser la
limite telle quelle la ferait mordre la moitié du temps — donc museler exactement le mouvement
subtil que tu juges « OK ». C'est le piège qui a déjà coûté deux cycles.

Et la corriger en raidissant ne marche pas non plus : tes fréquences (§24) et ton pilotage (§3)
fixent ensemble l'excursion — `excursion = accélération / (2π·f)²` — donc raidir sort tes
fréquences de leurs bandes. Avec tes propres chiffres, 2.30 Hz, la limite de 0.40 est atteinte dès
que le pilotage vaut **1,25 g** : autant dire tout le temps.

**Trois de tes sections ne peuvent donc pas être vraies en même temps avec le pilotage actuel.** Le
seul terme que personne n'a jamais vérifié est la FORCE de ce pilotage, et tes §14 à §20 sont les
seules lignes de ta spec qui relient un mouvement à une réponse attendue. C'est le prochain cycle.
Si ce terme est juste, alors la tension est dans ta spec et c'est toi qui trancheras.

## 3. TON DÉBARDEUR SOUTIENT TES SEINS — ET TA §35 DIT QU'IL NE DOIT PAS

Sur les 24 599 corrections de contact que subit le sein gauche, **40 % viennent des volumes de ses
bretelles** — `lTopStrap2` à lui seul en fait 20.7 %, c'est le **premier** constricteur, devant le
buste. À droite : 28.9 %. Pour comparaison, le contact sein↔sein que ta §33 décrit (« ils
s'entrechoquent ») pèse **1.8 %** et **2.2 %**.

Ta §35 est explicite : « The visible tank top is a non-supportive conforming layer. Support
contribution ≈ 0, Compression ≈ 0 ». Un volume qui pousse l'organe 5 083 fois n'est pas à zéro.

**C'EST UNE QUESTION QUI TE REVIENT, et je ne la tranche pas.** Ta §35 suppose que le vêtement SUIT
le sein ; ton ordre du 14 août a retiré toute physique aux bretelles, donc elles ne peuvent plus
suivre. Les deux issues sont opposées :
* **rendre la physique aux bretelles** — tu rouvres un organe que tu as gelé ;
* **retirer leur volume** — le sein traversera la bretelle, contre ta règle « rien ne traverse ».

## 4. DEUX DE MES MESURES ÉTAIENT FAUSSES, ET JE LES RETIRE

**(a) Mon tableau t'annonçait un défaut structurel qui n'existe pas.** Il écrivait que le premier
segment de chaque sein « ne tourne pas d'un degré » et que c'était structurel, pas un réglage. Le
compteur qui disait ça **ne pouvait pas être écrit** : sa condition d'écriture est vide pour tes
seins (ils n'ont volontairement pas d'ancrage rigide). Mesuré pour de vrai, ce segment tourne de
**26 à 147 degrés** selon le stimulus. Il n'y a rien à chercher de ce côté.

**(b) Deux de mes rouges t'étaient invisibles.** Mon validateur s'arrête à sa première porte —
celle qui attend TON verdict — donc les douze suivantes n'étaient jamais évaluées. En les passant
sur une copie : le moteur dépassait sa limite de taille (corrigé ce cycle, sans toucher au code),
et la traversée des seins est une **porte rouge**, pas seulement une ligne de rapport.

## 5. CE QUE J'AI CHERCHÉ ET QUI N'EST PAS LA CAUSE

J'avais posé que la contrainte qui empêche l'os de s'allonger confisquait aussi la direction dans
laquelle il faut écarter les deux seins. **Faux** : mesuré sur le maillage, elle n'en retire que
12 à 14 % ; 86 % de la poussée reste utilisable. Écrit avant la mesure, réfuté par elle.

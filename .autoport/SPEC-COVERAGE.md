# Couverture de SPEC-breast-softbody.md — registre de la poitrine de Keira

**À quoi ça sert.** L'owner demande depuis le 2026-08-13 une implémentation à 100 % de sa spec, et
jusqu'au 2026-08-20 je ne pouvais lui répondre qu'à l'impression : aucun document ne disait, section
par section, ce qui était tenu et ce qui ne l'était pas. Le voici.

**Règles de ce fichier.**
1. Un statut ne s'écrit **que** s'il s'appuie sur une mesure nommée. Sans mesure : `NON ÉTABLI`.
   « Le code a l'air de le faire » n'est pas un statut.
2. `TENUE` veut dire : la grandeur de la section est mesurée, dans sa bande, sur les deux seins.
   Une seule chaîne conforme = `PARTIELLE`.
3. `TENUE PAR CONSTRUCTION` veut dire : la section ne peut pas être violée dans ce moteur, et c'est
   **déclaré comme tel** — jamais compté comme une victoire.
4. Seul l'owner ferme la phase. Ce tableau ne ferme rien ; il dit où on en est.
5. Un statut qui régresse se réécrit. Ce fichier n'est pas un historique, c'est un état.

---

## AUCUNE LIGNE DE CE TABLEAU N'EST VALIDEE PAR L'OWNER

Le 2026-08-20 il le precise de lui-meme, avant meme que je puisse me tromper : « je n'ai rien validé
de ce qui a été fait donc rien de verrouillé par moi-même, j'ai juste dit que c'était cohérent par
rapport à ce que tu m'as demandé de vérifier ».

Donc : **`TENUE` ici veut dire « ma mesure est dans la bande de la spec », JAMAIS « l'owner a
approuve ».** Les deux sont independants, et le second n'existe pas encore — pas une seule fois, sur
aucune section. Aucun etat teste ne devient une reference ni un plancher. Sa consigne du meme
message : « implémenter la spec à 100 %, pas de raccourcis ».

## Périmètre

Seules `chestL` et `chestR` sont simulées (ordre de l'owner du 2026-08-14 07:30). Les sections qui
parlent d'autre chose que de la poitrine sont hors périmètre, pas « tenues ».

## Tableau

| §  | Ce que la section exige | Statut | Preuve / ce qui manque |
|----|-------------------------|--------|------------------------|
| 1  | Cible : sein non soutenu, réaliste | TENUE PAR CONSTRUCTION | Section descriptive, sans grandeur mesurable |
| 2  | « the **final settled** breast geometry shall reproduce the original authored standing model » (l.51-52) | PARTIELLE | **RETROGRADEE cycle 48, faux vert corrige.** Le TENUE ne s'appuyait que sur `ROOM-IDLE maxdev=0,0002`, qui mesure le repos SANS mouvement prealable. La clause dit « final **settled** » : `ROOM-SHFLOOR` mesure l'etat apres secousse et trouve un plancher NON NUL sur **9 axes sur 12** (jusqu'a 0,890 % de `a0`), le tableau ecrivant lui-meme « ca ne sonne plus, ca ne REVIENT pas ». Moitie tenue (repos), moitie non (retour) |
| 3  | Équilibre 1 g ; réponse à `(g_local − g_ref) − a_torso + a_angular` | **TENUE** | `gy` = 9,81 m/s² exact en unités moteur ; `gravity=1.00` livré depuis le 2026-08-19 ; repos inchangé |
| 4  | Morphologie de référence | TENUE PAR CONSTRUCTION | Descriptive |
| 5  | Volume 450–600 mL, densité 0,95, masse 0,50 kg | TENUE PAR CONSTRUCTION | La masse n'entre que dans `f = raideur/√masse` : jauge non observable. **Déclaré, pas gagné.** |
| 6  | `L0` `W0` `H0` `B0` `P0` ; bandes de contrôle L0 110-125, W0 130-150, H0 125-145, `B0` 115-125 mm ; « derive normalized dimensions **directly from the character mesh** » (l.122-123) | PARTIELLE | **`W0` EST MESURÉE POUR LA PREMIÈRE FOIS AU CYCLE 64, `L0` ET `H0` SONT DÉCLARÉES NON MESURABLES, ET JE RETIRE LA CONFIRMATION DE `B0` QUI ÉTAIT INSCRITE ICI.** Étendues du nuage de chair en pose de bind, dans le trièdre du torse (mesh LIVRÉ) : **`W0` = 776,1 u = 189,5 mm** sur les deux seins (extrêmes miroirs exacts — le rig est bilatéralement symétrique en bind). Elle passe le test de raffinement : **0,0 % d'écart** entre les frontières `w>0` et `w≥0,25`, 8,1 à 14,1 % sur quatre critères d'appartenance, et ses deux sommets extrêmes portent un poids de sein réel (0,34 et 0,59). **`H0` (901,2 u) et `L0` (638,4 u) ÉCHOUENT** : +31,7 % et +36,6 % entre deux frontières (barre de 30 % du `instrument-refinement-test`), parce que leurs extrêmes sont des sommets de FRANGE à `ws ≈ 0,04-0,07` qui disparaissent dès qu'on monte le seuil. Elles ne sont donc PAS publiées comme dimensions — un chiffre qui bouge d'un tiers selon un seuil ne mesure rien. **LA CONFIRMATION DE `B0` INSCRITE SUR CETTE LIGNE ÉTAIT PÉRIMÉE, ET C'EST MOI QUI L'AVAIS ÉCRITE** : elle disait « l'étendue du nuage sur l'axe anatomique vaut 597,9 / 598,3 u = 0,99 B0 (`probe_c48_com_identity.py`) ». Sur le mesh que le jeu reçoit aujourd'hui, **la même construction rend 701,8 / 718,6 u = 1,166 / 1,194 B0** (+17,4 % / +19,4 %) — le 597,9/598,3 décrit un mesh d'AVANT le reskin du cycle 57 (2026-08-20 06:58). `physics_c14_meshsamples.py:308` portait la même valeur périmée, corrigée au cycle 64. **`B0` est donc, à ce jour, un nombre SANS DÉFINITION ARBITRÉE** : sur les mêmes 94 sommets il vaut 602,2 u sur l'axe local `+Y` et 701,8 u sur l'axe anatomique de §31 (10,4 deg d'écart), et il varie de ×2,7 selon la frontière d'organe. `b0=602` N'EST PAS CHANGÉE — elle est le dénominateur de quinze sections et la déplacer sans course de contrôle appariée bougerait tous leurs verdicts d'un coup. C'est un défaut OUVERT, pas un correctif différé. **Rapports mesurés** : `W0/B0` = 1,289, dans la fourchette [1,04 ; 1,30] qu'impliquent les bandes de §6 — la FORME est cohérente, c'est l'ÉCHELLE qui est haute (+18 à +26 %). **`P0` est mesuré** (centroïde pondéré par maillon, espace bind) |
| 7 | « +X = character's outward lateral direction ; +Y = upward along torso ; +Z = forward from chest » ; « for the left and right breasts, outward **+X should be mirrored** so that the equations remain symmetrical » ; « all dynamic calculations shall occur **relative to the torso/root transform** rather than directly in world space » (l.126-134) | PARTIELLE | **REMONTEE DE `NON TENUE` AU CYCLE 63 : LA CLAUSE DU MIROIR EST CORRIGEE AU CODE ET MESUREE TENUE SUR LES DEUX CHAINES.** Le cycle 62 avait etabli le defaut (`a0` IDENTIQUE sur les deux seins, `angle(a0[chestL], -a0[chestR]) = 179,749 deg` la ou la clause exige 0) et sa cause structurelle : `*phys-fx* = cross(fy, fz)` dont LES DEUX ENTREES sont communes aux deux chaines, donc le lateral NE POUVAIT PAS differer. **LE CORRECTIF NE CALCULE RIEN DE NEUF** : le segment `sep` qui va du sein OPPOSE a celui-ci existe depuis le cycle 10 pour nommer la ligne laterale ; il n'etait garde que par ses PROJECTIONS (`*phys-axsep*`) et il l'est desormais en VECTEUR (`*phys-sepv*`). Le miroir tient en une ligne : `si dot(fx, sep) < 0 alors fx := -fx`, c'est-a-dire « +X sortant » au sens ou l'anatomie le definit, pas une convention de rig. **MESURE, ET LA PREDICTION A ETE POSEE AVANT LA COURSE** (`c63-predictions.txt`, P1/P2) : `ROOM-SPEC7-MIROIR 179,749 -> 0,251 deg -> MIROIR TENU` ; `ROOM-SPEC7-SENS det(chestL)=-0,99998 det(chestR)=+0,99998 -> SENS OPPOSES`, consequence geometrique exacte du miroir d'UN axe sur trois. **EXACTEMENT UNE CHAINE BASCULE, ET LAQUELLE ETAIT CALCULABLE A L'AVANCE** : `dot(fx, sep)` vaut -742,09 sur chestL et +742,09 sur chestR, donc chestL seule ; mesure : `PHYSTRI c=0 a=0` passe de (-0,98297 -0,18374 +0,00000) a (+0,98297 +0,18374 -0,00000) et **`c=1 a=0` est INCHANGE AU BIT**, comme `a=1` et `a=2` sur les deux chaines. Le test DISCRIMINE : un +X non mirore rend 180 deg, il ne peut pas rendre 0 par construction. Orthonormalite 7,77e-06 inchangee. **CORRECTION D'ETIQUETTE, ET ELLE EST DE MOI** : `PHYSTRI` etait publie « REPERE : le monde ». C'est faux, et la trace le refute seule — `a1` est le +Y « upward along torso » et vaut (+0,18290 **-0,97844** +0,09585) : un « haut » a y = -0,98 en MONDE sur un sujet debout est impossible. Ces cosinus sont dans la base de l'ANCRE (`gref` = g monde passe par `w2l = inverse(am)`, `fz` part du vecteur canonique de cette meme base). Le verdict de miroir n'en depend pas — les deux chaines partagent l'ancre `chest`, donc la comparaison se fait dans une base COMMUNE dans les deux lectures. **POURQUOI PARTIELLE ET PAS TENUE** : la 3e clause (« relative to the torso/root transform rather than world space ») porte sur le LIEU du calcul et **n'est toujours pas jugee** — aucune des grandeurs ci-dessus ne la teste. Le test qui la trancherait est nomme : un ECHELON DE LACET STATIQUE (rotation autour de l'axe de gravite, qui laisse `g_local` invariant), dont la reponse etablie doit etre INCHANGEE si le calcul est dans le repere du torse. Il n'existe pas dans la salle ; l'inventer le jour ou le miroir vient de tomber serait un cycle de plus sur une section deja mesuree **[POSE MESURÉE, cycle 67]** La pose de PH-SETTLE, où ce triède est relevé, était publiée sans que personne puisse dire laquelle. Elle est désormais enregistrée (`PHYSPOSETAG tag=settle`) et vaut **0,270 deg du miroir** — admissible au seuil dérivé de 1,3 deg. Le verdict de cette ligne porte donc enfin sa pose. **[SENS DE +Z, cycle 69 — RÉSERVE NOUVELLE ET MESURÉE]** La section écrit « +Z = forward from chest » (l.130). Le `+Z` que le moteur construit (`jak-hd-physics.gc:3532-3547`, `fz = +e[ia]` avec le signe **écrit en dur et aucune mesure**) pointe vers l'**ARRIÈRE**. Trois routes indépendantes concordent : l'os de racine de chaque sein porte une composante de **-0,14776 / -0,14794** sur cette ligne alors qu'un sein fait saillie vers l'avant ; sur le glb livré, en espace `chest`, la frange vaut -0,3135, les lunettes -0,2189 et la nuque +0,0618/+0,0990 sur l'axe 2 ; et la rotation commandée de la cellule prone compose avec la gravité monde pour donner le même sens. **LE CALCUL AVAL EST JUSTE** — `wbk = max(0,-gzc)` reçoit bien le triplet prone de §11 — donc deux erreurs de sens se compensent exactement et le défaut est **invisible en sortie**. Il reste que la convention livrée contredit la lettre de la section, et qu'un consommateur neuf qui lit `gz` comme « avant » inverserait §10 et §11. C'est arrivé : la docstring de `phys-shape` l'écrivait, [NOTE-67] et [NOTE-68] concluent l'inverse du rig livré. Docstrings corrigées au cycle 69, calcul NON touché (y toucher sans passe appariée casserait §10 et §11 ensemble). Voir [NOTE-408]. |
| 8  | « Normal movement: 98–101 % of neutral volume » ; « Conceptually `Sx·Sy·Sz ≈ 1`, **but the whole breast shall not be represented by one affine scale transformation** » (l.136-146) | **NON TENUE** | **SORT DE `NON ÉTABLI` AU CYCLE 53, ET C'EST UNE RÉTROGRADATION : la clause STRUCTURELLE est mesurée et elle est violée par le mécanisme même qui « conserve » le volume.** (a) La clause NUMÉRIQUE est **TAUTOLOGIQUE** : `jak-hd-physics.gc:3516-3519` calcule `det = sx0·sy0·sz0` puis `cvn = 1/det^(1/3)` par itération de Newton, et `:3558-3560` multiplie LES TROIS échelles par `cvn`. Le déterminant est donc forcé à 1 **par construction** — mesuré sur la course : **390 lectures, toutes dans [0,999900 ; 1,000000]**, une étendue de 1e-4. Publier « 98-101 % tenue » là-dessus serait le quatrième faux vert du dossier (§11, cycle 49) sous un autre costume : l'instrument republierait sa cible. (b) La clause STRUCTURELLE est **VIOLÉE** : `*phys-dfm*` est `(new 'global 'inline-array 'matrix PHYS-SC)` — **UNE matrice par chaîne**, donc le sein EST représenté par une seule transformation affine, exactement ce que la ligne interdit en gras. Et le volume est conservé PAR le rééchelonnement global que la même ligne prohibe. Ce que la section demande à la place (« root tissue moves little; intermediate tissue redistributes; distal tissue deforms most ») est la même exigence que §31, elle-même `NON TENUE` pour une cause de RIG (axe d'os à 78° de l'axe anatomique) **[MESURE, cycle 70 — LE MOTIF PASSE DU SOURCE A LA TRACE]** Ce statut reposait sur une lecture du SOURCE (« le determinant est force a 1 »), et la regle 0 du contrat dit qu'un commentaire n'est pas une preuve. Le tenseur 3x3 COMPLET est publie a chaque course sous `PHYSDFMA` (54 lignes, base de l'ancre) et **n'avait aucun lecteur** — deuxieme des trois flux muets nommes au cycle 69. Il en a un. MESURE : **18 cellules, determinant de 0,999997 a 0,999999, etendue 1,78e-06**. La bande 98-101 % est respectee, **et c'est precisement ce qui ne prouve rien** : neuf orientations, des poles a ±90 deg, deux chaines, et le determinant ne bouge pas de la sixieme decimale. Une grandeur physique de volume a une POPULATION ; celle-ci a une VALEUR. C'est une normalisation. La clause en gras (« shall NOT be represented by ONE affine scale transformation ») tombe sur deux faits mesures : `PHYSDFMA` porte un indice de CHAINE et de CELLULE et **aucun indice de MAILLON**, et la matrice est quasi symetrique (asymetrie 0,000000 a 0,024827), donc un etirement pur. **NON TENUE, motif desormais MESURE.** |
| 9  | Etat debout neutre = 1,00 sur tous les axes ; « Once settled, however, the original authored standing shape shall be **restored exactly**. » (l.160-161) | PARTIELLE | **RETROGRADEE cycle 48, meme cause que §2.** L'erreur statique est bien a 0,0001 — mais la clause « restored **exactly** » porte sur l'etat APRES mouvement, et `ROOM-SHFLOOR` y lit un plancher non nul sur 9 axes sur 12. Le `t01` de §27 est CENSURE par ce plancher meme, ce qui relie les deux lignes |
| 10 | « Forward projection −25 to −35%, `SupineProjectionScale = 0.70` » ; largeur ×1,23 ; hauteur ×1,09 ; « COM toward thorax: 18–28% B0 » ; « Outward COM migration per breast: 4–10% W0 » (l.165-169) | NON ÉTABLI | **LE CYCLE 64 LUI DONNE SA PROPRE GRANDEUR POUR LA PREMIÈRE FOIS, ET ELLE NE SUFFIT TOUJOURS PAS À TRANCHER — MOTIF ENTIÈREMENT RÉÉCRIT.** L'instrument qui lit §10 sur un **CENTRE DE MASSE** au lieu d'un APEX (`ROOM-ORICOM-MASS`, `d_COM = (W_0.d_0 + W_1.d_1)/N`) existait, et il était **SUSPENDU PAR SA PROPRE GARDE DE CONCORDANCE depuis le reskin du cycle 57 (2026-08-20 06:58)** : son instantané de masse datait du 18 août 18:51. Sept cycles ont tourné sans qu'aucun rapport ni aucune ligne d'ici ne le mentionne. La garde avait raison de refuser — les poids ont bougé de **+73 % sur `lBoob` et −31 % sur `lBooc`** — mais §10 restait lue sur une BORNE SUPÉRIEURE. Instantané régénéré, bloc rouvert. **CE QUE CHAQUE CLAUSE VAUT MAINTENANT, une par une.** (a) Les **trois clauses d'échelle sont TAUTOLOGIQUES et NON JUGÉES** — `jak-hd-physics.gc:3576-3581` mélange cinq triplets écrits en dur dont `1.230/1.090/0.700` EST §10, et l'attribution du rôle « supine » (`physics_room_table.py:542-563`) est un argmin-L1 contre ces mêmes constantes : elle ne peut pas échouer. Comparer une constante à elle-même n'est pas une mesure, et je ne la compte pas. (b) La clause **COM toward thorax 18-28 % B0 est encadrée, plus serrée qu'avant, et encore INDÉTERMINÉE** : borne INFÉRIEURE mesurée (squelettique) **0,1572 (chestR) / 0,1831 (chestL)** contre borne SUPÉRIEURE d'apex **0,2046 / 0,2291**. La bande commence à 0,18, **donc à l'intérieur de l'encadrement** — le verdict ne peut pas être prononcé dans un sens ni dans l'autre. L'encadrement passe néanmoins de ×2,76 (0,1317→0,3633, cycle 49) à **×1,30**. Le terme qui manque est NOMMÉ : le tenseur de déformation (`*phys-dfm*`) étire la peau sans déplacer un joint, donc aucune somme de déplacements de joints ne peut le voir. (c) **`chestL` EST SUSPENDUE À SON PROPRE CONTRÔLE** : le bloc compare deux accumulateurs indépendants (`\|sum ldb\|` contre `\|t\|`) et trouve **13,35 % d'écart, pire cellule à i=8, c'est-à-dire EXACTEMENT la fenêtre supine**, quand `chestR` s'accorde à 0,57 %. Le montage est en cause, pas la physique, et le bloc le déclare lui-même. (d) La clause **« 4-10 % W0 » a enfin un dénominateur** — `W0` = 776,1 u = 189,5 mm, mesurée et passant le test de raffinement au cycle 64 (voir §6) — mais **le canal de migration SORTANTE n'est pas construit** : `ROOM-ORICOM-MASS` ne publie que la NORME. Je ne le bâtis pas le jour où le montage vient de déclarer 13,35 % de désaccord sur une chaîne : construire un verdict neuf sur une base qui se contredit est la faute que ce registre existe pour interdire. **CHANTIER NOMMÉ POUR LE CYCLE SUIVANT** : comprendre le désaccord de `chestL`, puis projeter `d_COM` sur le latéral SORTANT (`PHYSORICOML dlat` × signe de `sja`) et rendre (b) et (d) déterminantes **CYCLE 64b — LE CONTRÔLE QUI SUSPENDAIT `chestL` ÉTAIT LUI-MÊME UN SCALAIRE À LA PLACE D'UN VECTEUR.** Il comparait deux NORMES ; en reordonnant `t` (trièdre §7) sur la base de l'ANCRE, les deux accumulateurs coïncident **composante par composante à moins de 0,6 deg sur 14 des 16 cellules chargées**, et les deux qui échouent le font à ~15 deg — dont **UNE que la norme laissait passer** (`chestR i=2` : 0,57 % en norme, **25,83 % en vecteur**). Corrigé en comparant les VECTEURS au MÊME seuil de 5 % (aucun seuil neuf ; critère strictement plus fort, séparation ×24 entre la pire cellule qui passe à 1,08 % et la pire prise à 25,83 %) et **par CELLULE au lieu de par chaîne** — suspendre une chaîne entière pour une orientation fautive jetait des lectures propres. **CONSÉQUENCE POUR §10** : `chestL i=8` reste suspendue, mais `chestR i=8` est **propre à 0,09 %**, donc sa lecture 0,1572 tient et l'encadrement publié ci-dessus est soutenu par un montage vérifié. **CAUSE DU DÉSACCORD : NON ÉTABLIE, deux suspects ÉLIMINÉS par la mesure** — (i) la composante radiale (l'ajouter en quadrature ne change rien, `rr` vaut 0,21 contre 138) ; (ii) une fenêtre non stabilisée (les deux cellules fautives ont les PLUS PETITS transitoires d'établissement de toutes, rangs 7/8 et 8/8). Signature mesurée : `t = l0 + k.l1` avec **k = 0,99-1,02 et résidu < 1,1 % sur les 14 cellules saines**, contre k = 2,156 (résidu 13,2 %) et k = 0,655 (résidu 3,5 %) sur les deux fautives — l'identité ne casse donc pas comme un simple ré-échelonnement du maillon distal. **CAUSE ÉTABLIE PAR ABLATION, ET ELLE EST DÉSORMAIS RE-DÉRIVÉE À CHAQUE COURSE** (le tableau recalcule l'écart sur les six passes du balayage de contrôle) : sur `chestL i=8`, **désarmer le MUR DE COLLISION (`k4`) ramène l'écart de 29,53 % à 0,22 %, soit 99 % retiré** — tandis que `k2` (côté) et `k5` (borne radiale §22) le laissent **identique au centième** (29,53 %). Sur `chestR i=2`, les deux sondes de collision réduisent aussi (`k3` rayon interpolé 25,83 → 5,00 %, 81 % ; `k4` → 11,92 %) sans le supprimer : mécanisme **DOMINANT, pas unique**. **C'EST LA COLLISION, et c'est cohérent physiquement** — les deux cellules fautives sont les poses de CONTACT (supine = pressée sur le dos ; pôle latéral = un sein comprimé contre le thorax), les cellules saines sont celles où le sein pend libre (prone). Même famille que le correctif du cycle 63b : la collision agit sur `q = joint + R(u).offset`, donc son effet sur l'APEX et son effet sur la chaîne de JOINTS ne s'attribuent pas de la même façon. **Et le suspect « fenêtre non stabilisée » est réfuté par un argument plus fort que celui que j'avais publié** : je l'avais écarté sur `PHYSORITR`, qui ne mesure que le transitoire RADIAL — argument incomplet. Ce qui le tue vraiment est que l'écart se reproduit **au centième sur trois passes indépendantes** (k0/k2/k5 : 29,53 / 29,53 / 29,53) ; un transitoire ne se reproduit pas à quatre décimales. |
| 11 | « Static COM displacement: 20–28% B0, nominal 24% B0 » ; « Root-to-apex length: +18 to +26%, `HangingLengthScale = 1.23` » ; transitoire ~+30% ; largeur ×0,90 ; épaisseur ×0,91 (l.178-182) | PARTIELLE | **RÉTROGRADÉE cycle 49 — FAUX VERT.** Le TENUE reposait sur `HangingLengthScale = 1.23` « portée par le tenseur ». Or `1.230 / 0.900 / 0.910` sont **écrits en dur** (`jak-hd-physics.gc:3513-3517`) comme le pôle « back » du mélange : le moteur COMMANDE la constante de la spec et `ROOM-ORI` la republie. Le tableau le disait lui-même en tête (« CE QUE CE N'EST PAS : la déformation VUE sur le mesh. C'est ce que le solveur COMMANDE ») — **c'est le registre qui a sur-lu le tableau.** La seule clause chiffrable indépendante, le COM 20-28 % B0, est **INDÉTERMINÉE** : borne inférieure 0,1290/0,1551 (SOUS), borne supérieure 0,4268/0,4106 (AU-DESSUS). Ce qui reste une vraie mesure est le transitoire — rapport 1,082/1,105 contre 1,057 exigé, et un RAPPORT est immunisé contre un facteur commun **CYCLE 64 — LA CLAUSE DE COM EST LUE SUR UN COM POUR LA PREMIÈRE FOIS** (`ROOM-ORICOM-MASS` rouvert, voir §10 pour la suspension de sept cycles) : fenêtre prone i=6, `d_COM` = **0,1275 (chestL) / 0,1468 (chestR) B0** contre une bande de 0,20-0,30, là où l'apex publiait 0,2377 / 0,2837. **CE N'EST PAS UNE VIOLATION DÉMONTRÉE, et le confondre serait un faux ROUGE** : `d_COM` est une borne INFÉRIEURE déclarée (la part tensorielle de la déformation ne passe par aucun joint et n'y est pas), donc une valeur sous la bande laisse la vraie valeur libre d'y être. Ce qu'elle établit, c'est que **la part SQUELETTIQUE seule ne suffit pas** à atteindre la bande : il manque 0,07 à 0,09 B0, et le terme manquant est nommé. **CYCLE 64b** : après correction du contrôle de pointe (comparaison EN VECTEUR, voir §10), les DEUX cellules prone sont propres — contrôle 0,06 % (chestL) et 0,22 % (chestR). Le manque de 0,07 à 0,09 B0 à la part squelettique repose donc sur un montage vérifié, pas seulement supposé. |
| 12 | « The breasts shall **not** behave identically » (l.189) ; « The **gravity-side** breast experiences stronger thoracic compression, while the opposite breast migrates across the chest » (l.189-190) ; « Global lateral COM response: 15-24% B0 » ; migration mediale 10-18 % W0 ; aplatissement -15 a -25 % (l.189-194) | PARTIELLE | **LE COTE ETAIT INVERSE, ET C'EST LE CYCLE 63 QUI LE MESURE — JE RETIRE UNE PARTIE DE MA PUBLICATION DU CYCLE 50.** Le cycle 50 avait corrige l'impossibilite mecanique (`(wlt (fabs gxc))` donnait le meme triplet aux deux seins) en composant `gxc` avec `signe(sja)`. L'ASYMETRIE etait reelle et elle tient toujours (ecart d'aplatissement 17-19 %, il s'inverse entre les deux poles, il survit a une pose epinglee symetrique). **MAIS LE SIGNE AVAIT ETE SUPPOSE, JAMAIS MESURE** : `fx` pointe le long de **-e_ja** (composante mesuree -0,98297), donc `gxc x signe(sja) = -(g . sortant)` et le poids d'aplatissement tombait sur le sein **OPPOSE** a la gravite, quand la section ecrit « the GRAVITY-SIDE breast ». C'est le piege `axis-sign-outlives-role-renaming` du registre : le bon INDICE de ligne, un signe hérité. **CE QUI L'A RENDU VISIBLE EST L'INSTRUMENT, PAS UN RAISONNEMENT** : `PHYSSYM6 gso` publie le cosinus entre la gravite locale et le segment sein-oppose -> ce sein — une grandeur d'ANATOMIE qui ne passe NI par `fx` NI par le melange de poles, donc elle ne peut pas republier le verdict qu'elle arbitre. `ROOM-SPEC12-COTE` : **0/4 cellules laterales avant (COTE INVERSE) -> 4/4 apres (COTE TENU)**, poses SYM et ASYM confondues. **LE CORRECTIF N'EST PAS DANS §12** : le miroir de §7 rend `gxc = g . sortant` par construction, donc `wlt = max(0, gxc)` suffit et le signe rapporte DISPARAIT du code. **C'EST UN ECHANGE, PAS UNE CREATION — prediction P4 posee avant la course :** pole +90 SYM `sx` 1,04062/0,87467 -> 0,87875/1,03774 ; pole -90 SYM 0,82152/0,97887 -> 0,97819/0,82209 ; les deux cellules ASYM s'echangent **a 1e-5 pres**. L'ECART EN POURCENT EST CONSERVE (+17,33/+17,48 -> +16,59/+17,34) : si la magnitude avait change, autre chose aurait bouge. **LE COUT, MESURE ET DECLARE** : mettre la compression du bon cote ENFONCE davantage le sein du cote gravite, ce que la section demande — `skinpen` chestL 0,0692 -> 0,0701, `ROOM-MEDIAL-PEN` chestL +0,0238 -> +0,0320 m, apex chestL max 0,9050 -> 0,9714 B0, et en sens inverse sur chestR (`meshpen` max 0,1424 -> 0,1288, `ROOM-STRETCH` 3,6736 -> 2,7829). **CE QUI RESTE OUVERT, INCHANGE** : (a) la clause COM 15-24 % B0 reste INDETERMINEE ; (b) « medial migration 10-18 % W0 » reste sans instrument, `W0` n'est mesure nulle part **CYCLE 64 — DEUX FAITS NEUFS, DONT UN QUE JE NE M'EXPLIQUE PAS.** (1) La clause de COM latéral (15-24 % B0) est lue sur un COM : `chestL` i=4 = **0,1869** et `chestR` i=2 = **0,1778** sont DANS la bande ; `chestL` i=2 = 0,1403 et `chestR` i=4 = **0,0582** sont sous. (2) **L'INVARIANCE MIROIR SE CASSE SUR UNE MOITIÉ SEULEMENT.** Les deux pôles échangent quel sein est du côté gravité (lu sur `gx`, le latéral SORTANT mirroré du cycle 63) : sur la condition **sein DU CÔTÉ GRAVITÉ** elles diffèrent d'un facteur **×2,41** (0,1403 vs 0,0582). **CORRECTION DU CYCLE 64b, CONTRE MOI-MÊME** : j'avais publié en regard « sur la condition sein OPPOSÉ les deux chaînes s'accordent à 5,1 % (0,1869 vs 0,1778) ». Ce 0,1778 est la cellule `chestR i=2`, que le contrôle de pointe **corrigé en VECTEUR** suspend (25,83 % d'écart, 14,88 deg, là où le contrôle en NORME ne voyait que 0,57 %). **Cette moitié est RETIRÉE** : il ne reste qu'UNE paire miroir comparable, et elle est celle qui DISAGRÉE d'un facteur 2,41. Les deux cellules qui la portent sont propres (contrôle de pointe 0,09 % et 0,26 %). Un rig symétrique à 0,005 deg en bind devrait rendre les deux paires égales. **RÉSERVE OBLIGATOIRE, et elle peut tout expliquer** : le balayage d'orientation impose le quaternion de racine mais **hérite la pose d'animation**, et le cycle 53 a mesuré que la pose tenue par la salle est à 43,4 deg du miroir parfait. Conformément à la règle du 2026-08-20 05:20, cette asymétrie **ne se déclare pas défaut du personnage** tant qu'elle n'est pas relevée dans une pose dont la symétrie est prouvée avant la course — ce que fait la phase PH-SYM, qui ne joue pas ces fenêtres-ci. **[POSE-C65/66]** Cette ligne publie un ecart gauche/droite tire de PH-REG, dont la pose est mesuree au cycle 65 a **43,8 / 48,0 deg du miroir** (`ROOM-REGPOSE`). Voir le bloc « Cycle 65 » plus bas : l'attribution de cette asymetrie au PERSONNAGE n'est pas soutenue. **[INSTRUMENT NOMMÉ, cycle 67]** Bonne nouvelle et mauvaise. Le geste est le BON : `physroom-lean` est bien un roulis, donc bien la « sideways gravity » de §12 — sous un nom qui dit le contraire. Mais l'INSTRUMENT ne peut pas porter la clause : `ROOM-GRAVSAG-MIRROR` publie un rapport gauche/droite dans une pose à **143,2 deg du miroir**, et le verrou d'asymétrie le refuse — à raison, car dans une pose roulée un écart L/R n'est pas attribuable au personnage. Or §12 EXIGE que les deux seins diffèrent : l'asymétrie EST le phénomène. L'instrument qui peut l'établir est une paire de stimuli MIROIR (rouler à +60 puis -60 et vérifier que la réponse se reflète), pas un rapport dans une seule pose. `ROOM-SYM` joue déjà des cellules à ±90 deg : c'est la bonne forme. |
| 13 | « shall **not** exist as unrelated hard-coded morph targets » ; « shall vary **continuously** with the local gravity direction » ; le comportement à 45° de lean, quatre descripteurs (l.202-207) | PARTIELLE | **RAISON CORRIGÉE cycle 49.** Le régime EST joué (les 4 orientations intermédiaires à ±45° sont dans le balayage). (a) Le moteur EST cinq morph targets codés en dur (`:3511-3517`) mais **mélangés** : « hard-coded » oui, « unrelated » non — la lettre est à moitié tenue et je ne tranche pas à ma convenance. (b) La continuité est vraie **par construction** (l'entrée est `gla` normalisée) et n'a jamais été testée comme telle. (c) La seule exigence CHIFFRABLE de §13 — les quatre descripteurs du lean à 45° — n'a **aucune ligne de verdict** dans le tableau **[CAUSE NOMMÉE, cycle 67]** Le régime n'est pas « jamais joué » : il est INJOUABLE avec les opérateurs actuels. Le seul opérateur d'inclinaison quasi-statique, `physroom-lean`, tourne autour du monde X — à 6,6 deg de l'axe avant/arrière du sujet — c'est donc un ROULIS, pas le « 45 deg forward lean » que §13 décrit. Preuve : une rotation autour de l'axe latéral laisse l'écart au miroir invariant par algèbre ; celle-ci le fait passer de 0,237 à **143,213 deg**. Il manque un opérateur qui incline autour de l'axe LATÉRAL du sujet. **CYCLE 69 — §13 N'A JAMAIS ÉTÉ INJOUABLE. ELLE ÉTAIT NON LUE, ET C'EST MOI QUI L'AI DÉCLARÉE INJOUABLE À TORT.** Le motif inscrit ci-dessus au cycle 67, et répété au cycle 68 (« le régime est INJOUABLE avec les opérateurs actuels ; il manque un opérateur qui incline autour de l'axe LATÉRAL du sujet »), est **RÉFUTÉ par la trace des courses de ces cycles-là**. `physroom-orient axis=1` tourne autour du monde Z, à **11,5 deg de l'axe latéral du sujet**, et tient la pose quasi-statiquement : c'est exactement l'opérateur déclaré manquant, et il tourne dans toutes les courses depuis que ce balayage existe. **CAUSE DE L'ERREUR, NOMMÉE :** le commentaire de `physroom-orient` étiquetait ses deux axes **à l'envers sur les deux**, deux cycles l'avaient constaté POUR `axis 0` et l'avaient écrit à DEUX SITES D'APPEL au lieu de le retirer du producteur — la note n'a jamais atteint `axis 1`. Et `PHYSORI4`, la gravité mesurée par cellule qui contredisait l'étiquette à chaque course, **n'avait AUCUN LECTEUR** (troisième occurrence de ce mode d'échec). **CE QUI EST MESURÉ MAINTENANT.** La cellule du penché AVANT de 45 deg est `i=5`, désignée par la gravité et par rien d'autre (`ROOM-ORIROLE`, écart 6,9 deg à la direction canonique, marge 32,7 deg). Trois des quatre descripteurs sont jugés et **tenus sur les deux seins**, encadrés par les pôles que la spec chiffre elle-même (§9 debout et §11 prone), sans un seul seuil de moi : migration COM **avant +133,66 u / bas +26,60 u** (chestL) et **avant +128,79 / bas +11,41** (chestR) — le sens `forward/downward` est tenu ; élongation racine-apex **1,1105 / 1,1071** strictement entre 1,0000 et le prone ; largeur **0,9415 / 0,9479** idem. Le quatrième (« redistribution toward the lower/distal pole ») est **NON JUGÉ** : il demande une répartition par maillon dont la garde de concordance suspend déjà des cellules. **ET LA CLAUSE DE CONTINUITÉ NE PASSE QUE SUR UN CANAL DES DEUX, C'EST LE DÉFAUT NEUF DE CE CYCLE.** La FORME interpole : **18 tests de position stricte sur 18**, poids de mélange 0,35 à 0,55, résidu de linéarité < 0,5 %. Le DÉPLACEMENT non : sur les 6 paires au montage sain, les rapports d(45 deg)/d(pôle) valent 0,806 · 0,816 · 0,887 · 0,957 · **1,294** · **1,345**, quand une loi continue en donnerait 0,50 (linéaire en angle) ou 0,707 (proportionnelle à la composante de gravité). **Deux paires ne sont même pas MONOTONES** : la cellule à 45 deg déplace PLUS que son propre pôle à 90 deg. La bande [0,35 ; 0,85] qui juge cette ligne est **DE MOI**, et la ligne le dit ; la non-monotonie, elle, ne dépend d'aucun seuil. **STATUT : `PARTIELLE`.** Le solveur n'a pas bougé d'une ligne ce cycle-ci — ce qui a changé, c'est qu'une mesure déjà produite a enfin un lecteur. |
| 14 | « COM lag: ordinary 15-25% B0, strong 25-32% B0 » ; « Apex displacement: ordinary 20-30% B0, strong 30-38% B0 » ; elongation +7 a +18 % (l.214-216) | **NON TENUE** | **REMESUREE AU CYCLE 57 SUR LE MESH RECUIT.** Le plafond d'ancrage qui bornait cette ligne est LEVE (§30 : l'apex passe de 43/41 % soude a 6/5 %), et les os n'ont PAS bouge — les mesures au niveau des JOINTS (`tipvar`, `rootdev`, `meshpen`, `jump`) sont IDENTIQUES AU BIT entre les deux courses, sur les cinq pilotages. Tout l'ecart ci-dessous est donc ce que la PEAU herite, attribue sans ambiguite. Gain mesure sur les 30 lectures de regime : mediane **x1,68** (x1,42-1,86), contre **x1,657 / x1,609** predits cote mesh. **Apex ordinaire** : chestL **0,2491 DANS** (etait 0,1492, SOUS x0,75) · chestR **0,4683 AU-DESSUS x1,56** (etait 0,2806, DANS). **Apex fort** : chestL **0,2987**, au plancher exact de la bande (SOUS x1,00 ; etait 0,1723) · chestR **0,3964 AU-DESSUS x1,04** (etait 0,2392). **LE DEFAUT A CHANGE DE SENS ET C'EST LE FAIT DU CYCLE** : chestL etait SOUS ses deux bandes et y entre ou les effleure ; chestR les DEPASSE desormais. Aucun regime n'a les deux seins dans la bande, donc la section reste rouge — mais pour la raison INVERSE de celle d'avant. DUREES EMPLOYEES, ET ELLES SONT DE MOI (cycle 49) : 15 frames / 0,25 s et 15 frames / 0,45 m. L'elongation reste NON MESUREE **[POSE-C65/66]** Cette ligne publie un ecart gauche/droite tire de PH-REG, dont la pose est mesuree au cycle 65 a **43,8 / 48,0 deg du miroir** (`ROOM-REGPOSE`). Voir le bloc « Cycle 65 » plus bas : l'attribution de cette asymetrie au PERSONNAGE n'est pas soutenue. **[POSE, cycle 67]** L'écart gauche/droite de cette ligne était lu à 7,5 deg du miroir (PH-REGS). Le seuil est passé à 1,3 deg (dérivé de §32 et de la sensibilité mesurée) : seule PH-REGT (0,594 deg) peut désormais porter une comparaison L/R. Rejouée là, la fenêtre rend R = 1,241 / 1,135 contre 1,387 / 1,204. **[AXE, cycle 70 — REMESUREE SUR L'AXE DU SUJET]** Les sauts partaient le long du MONDE Y, a **11,9 deg** de la verticale mesuree du sujet. Rejoues sur l'axe du sujet (phase appendue PH-REGB, meme pose epinglee, memes tables, une seule variable : l'axe), les deux fenetres bornees rendent **0,4574 / 0,4322** (detente ordinaire, bande 0,20-0,30, ×1,52 / ×1,44) et **0,4597 / 0,4615** (detente forte, bande 0,30-0,38, ×1,21 / ×1,21). **NON TENUE, mais pour la premiere fois les deux chaines rendent le MEME verdict avec le MEME facteur** — la detente forte les separe de 0,39 % la ou l'axe du monde en donnait 11,86. Le geste est NOMME par la mesure : deplacement d'ancre 917 a 2136 u sur la verticale contre 0,002 a 0,03 u sur les deux autres axes. **[LIMITEUR, cycle 71 — CE QUE VALAIT LA DEMANDE DU RESSORT DANS CES FENETRES-LA]** Le canal qui porte cet apex sature la §21 comme un MULTIPLICATEUR DE FORCE dont l'argument est plafonne (`jak-hd-physics.gc:2938-2943`) : identite stricte sous `kn = 0.42 B0`, raidissement en `x/(1-x)` jusqu'a `0.4992 B0`, puis **force de rappel CONSTANTE** (72.82 / 78.65 u/frame^2). `ROOM-REGLIM` publie desormais, SUR LA MEME LIGNE que chaque verdict de bande, l'etat du limiteur de SA PROPRE fenetre. PH-REGB (axes du sujet) : detente ordinaire r=1 **GENOU x1,12 / x1,07 kn**, detente forte r=4 **GELEE x1,36 / x1,33 kn**. Les quatre lectures sont AU-DESSUS de leur bande ET hors de la zone lineaire : **aucune des quatre ne peut etre lue comme un verdict sur le materiau**, et les deux de r=4 portent `(SATURE)`. La section reste NON TENUE ; ce qui change est qu'on sait maintenant que son depassement se mesure contre une force qui ne depend plus de l'ecart. |
| 15 | « shall **not use character speed alone** » ; « jump apex → breast may **cross neutral position** » (l.224-230) | PARTIELLE | **LA CLAUSE DE TRAVERSEE EST DEMONTREE, cycle 51 — elle ne l'était pas faute d'INSTRUMENT, pas faute de moteur.** `ROOM-SPEC15-CROSS` publie les DEUX extrêmes de la composante verticale du COM sur la fenêtre, là où le vecteur n'était relevé qu'à l'argmax de sa norme (UNE frame, qui ne peut ni établir ni exclure une traversée). Mesuré : **3 des 4 fenêtres de VOL traversent le neutre** (chestR r=2 cydn 0,0597 / cyup 0,0268 ; les deux chaînes sur r=5). Les deux extrêmes sont publiés EN POSITIF parce qu'un minimum initialisé à 0 par le reset de fenêtre ne peut pas remonter et lirait 0 sur une fenêtre entièrement d'un côté — un faux vert sur la seule clause que §15 rende vérifiable. Clause « pas piloté par la vitesse » : TENUE depuis le cycle 49. **Ce qui manque pour TENUE** : les quatre descripteurs de phase de l.227-230 ne sont pas vérifiés un par un, et chestL ne traverse pas sur r=2 |
| 16 | « Strong landing COM: 25-35% B0 » ; « Very hard: 35-40% B0 » ; « Strong landing apex: 30-42% B0 » ; « Very hard / exceptional: 42-50% B0 » (l.238-245) | **NON TENUE** | **REMESUREE AU CYCLE 57 SUR LE MESH RECUIT.** Le plafond d'ancrage qui bornait cette ligne est LEVE (§30 : l'apex passe de 43/41 % soude a 6/5 %), et les os n'ont PAS bouge — les mesures au niveau des JOINTS (`tipvar`, `rootdev`, `meshpen`, `jump`) sont IDENTIQUES AU BIT entre les deux courses, sur les cinq pilotages. Tout l'ecart ci-dessous est donc ce que la PEAU herite, attribue sans ambiguite. Gain mesure sur les 30 lectures de regime : mediane **x1,68** (x1,42-1,86), contre **x1,657 / x1,609** predits cote mesh. **Reception souple** : chestL **0,1398** (etait 0,0881) toujours SOUS x0,47 · chestR **0,3228 DANS** (etait 0,1733, SOUS x1,73) — **premiere lecture de §16 DANS sa bande en 57 cycles**. **Reception dure** : chestL **0,1574** SOUS x0,37 (etait 0,0996) · chestR **0,3270** SOUS x0,78 (etait 0,1994). **CE QUE CA TRANCHE, ET C'ETAIT LA QUESTION OUVERTE DU CYCLE 51** : le manque de chestR etait bien porte par l'ancrage — il disparait des qu'on le leve. Celui de chestL ne l'etait PAS : apres un gain de x1,59 il manque encore x2,15, donc **le solveur porte un deficit propre a chestL**, et l'ecart gauche/droite sur cette section (x2,3 sur la reception souple) n'est pas un artefact d'ancrage. DUREES DE MOI : 0,23 s et 0,15 s **[POSE-C65/66]** Cette ligne publie un ecart gauche/droite tire de PH-REG, dont la pose est mesuree au cycle 65 a **43,8 / 48,0 deg du miroir** (`ROOM-REGPOSE`). Voir le bloc « Cycle 65 » plus bas : l'attribution de cette asymetrie au PERSONNAGE n'est pas soutenue. **[POSE, cycle 67]** Même réserve que §14 : les écarts L/R lus à 7,5 deg ne sont plus publiables. À 0,594 deg la fenêtre rend R = 1,390 / 1,450 contre 1,338 / 1,773, et les quatre lectures d'amplitude restent SOUS leur bande — le déficit de §16 survit au resserrement de la pose. **[AXE, cycle 70 — LA SEULE LECTURE `DANS` DE CETTE SECTION ETAIT UN VERT D'AXE, ET ELLE TOMBE]** Le motif ci-dessus porte « chestR 0,3228 DANS — premiere lecture de §16 DANS sa bande en 57 cycles ». Cette lecture etait prise avec un stimulus le long du monde Y, a 11,9 deg de la verticale du sujet. Rejouee sur l'axe du sujet, la MEME fenetre rend **0,2021**, SOUS la bande d'un facteur 0,67 — exactement comme `chestL` (**0,1887**, ×0,63). La reception dure rend **0,2620 / 0,2431** contre 0,42-0,50, ×0,62 / ×0,58. **Les quatre lectures sont SOUS, et les deux chaines s'accordent** (6,63 % et 7,21 % d'ecart contre 28,08 % et 31,03 % sur l'axe du monde). Un vert retire vaut mieux qu'un vert garde : celui-la etait fabrique par l'axe. **[LIMITEUR, cycle 71 — CE QUE VALAIT LA DEMANDE DU RESSORT DANS CES FENETRES-LA]** Le canal qui porte cet apex sature la §21 comme un MULTIPLICATEUR DE FORCE dont l'argument est plafonne (`jak-hd-physics.gc:2938-2943`) : identite stricte sous `kn = 0.42 B0`, raidissement en `x/(1-x)` jusqu'a `0.4992 B0`, puis **force de rappel CONSTANTE** (72.82 / 78.65 u/frame^2). `ROOM-REGLIM` publie desormais, SUR LA MEME LIGNE que chaque verdict de bande, l'etat du limiteur de SA PROPRE fenetre. PH-REGB : reception souple r=3 **LINEAIRE x0,88 / x0,87 kn** — les DEUX seules cellules bornees de tout PH-REGB qui soient dans la zone lineaire — et reception dure r=6 **GENOU x1,07 / x1,06 kn**. **C'EST LE FAIT QUI COMPTE POUR CETTE SECTION** : les quatre lectures sont SOUS leur bande (x0,58 a x0,67) et **deux d'entre elles sont prises dans la zone ou le ressort est strictement lui-meme**. Le deficit de §16 n'est donc PAS un artefact du limiteur — il est produit par le solveur en regime lineaire. **Et la bande haute de §16, citee mot pour mot « Very hard / exceptional: 42-50% B0 », est EXACTEMENT l'intervalle [kn, cap] du limiteur** : la region que la section demande d'atteindre est celle que la barriere existe pour raidir. Ce n'est pas une contradiction de la spec — §22 autorise 50 % en exceptionnel — c'est une contrainte de notre IMPLEMENTATION, et elle est desormais ecrite. |
| 17 | « COM lag: moderate 10-18% B0, strong 18-27% B0 » ; « Apex displacement: strong 25-35% B0, upper transient ~40% B0 » (l.251-253) | PARTIELLE | **REMESUREE AU CYCLE 57 SUR LE MESH RECUIT.** Le plafond d'ancrage qui bornait cette ligne est LEVE (§30 : l'apex passe de 43/41 % soude a 6/5 %), et les os n'ont PAS bouge — les mesures au niveau des JOINTS (`tipvar`, `rootdev`, `meshpen`, `jump`) sont IDENTIQUES AU BIT entre les deux courses, sur les cinq pilotages. Tout l'ecart ci-dessous est donc ce que la PEAU herite, attribue sans ambiguite. Gain mesure sur les 30 lectures de regime : mediane **x1,68** (x1,42-1,86), contre **x1,657 / x1,609** predits cote mesh. **REMONTEE DE `NON TENUE`, ET ELLE PASSE A DEUX CENTIEMES DE LA BANDE.** Apex du FREINAGE (la seule bande d'apex de §17) : chestR **0,2698 DANS** (etait 0,1611, SOUS x0,64) · chestL **0,2445**, SOUS x0,98 — il manque **0,0055 B0**, soit 2 % du plancher de 0,25. Une chaine conforme, l'autre au bord : PARTIELLE au sens strict du registre, et c'est la section la plus proche d'un vert du dossier. §17 ne borne PAS l'apex du demarrage, et la ligne ne lui invente pas de bande : le demarrage rend 0,5743 / 0,5336 (etait 0,3377 / 0,3150), toujours la plus forte reponse des sept regimes. DUREES DE MOI : 36 frames / 18 frames **[POSE-C65/66]** Cette ligne publie un ecart gauche/droite tire de PH-REG, dont la pose est mesuree au cycle 65 a **43,8 / 48,0 deg du miroir** (`ROOM-REGPOSE`). Voir le bloc « Cycle 65 » plus bas : l'attribution de cette asymetrie au PERSONNAGE n'est pas soutenue. **[AXE + POSE, cycle 67]** Deux réserves nouvelles, toutes deux mesurées. (a) `physroom-run-z` accélère le long du monde Z, à **86,3 deg de l'axe avant/arrière du sujet** : la « course » de §17 est une embardée LATÉRALE. Le texte de §17 dit « horizontal » sans nommer de direction, donc la lecture reste admissible — mais la direction est NOTRE choix et elle est désormais déclarée, comme les durées le sont depuis le 2026-08-20. (b) La fenêtre de freinage est la PLUS SENSIBLE À LA POSE de tout le registre : son rapport gauche/droite bouge de **139,3 %** entre 7,5 deg et 0,594 deg d'écart au miroir, soit 20,3 %/deg, ce qui exigerait une pose à **0,099 deg** qu'aucune pose de ce rig n'atteint. Et le vert d'amplitude du cycle 66 (apex 0,2543 / 0,2927, les deux DANS la bande) ne survit pas : à 0,594 deg la même fenêtre rend **0,2367 / 0,6519**. Je n'ai pas de cause. **[AXE, cycle 70 — LA « COURSE » ETAIT UNE EMBARDEE LATERALE, ET C'EST CORRIGE]** La reserve (a) ci-dessus est levee : `physroom-run-z` accelerait le long du monde Z, a **86,3 deg** de l'axe avant/arriere mesure du sujet. La phase appendue PH-REGB rejoue les deux fenetres le long de cet axe, avec les DEUX SENS mesures et non choisis (le haut par la gravite, l'avant par la saillie du sein) et le geste NOMME par la mesure : deplacement d'ancre **4645 u et 8291 u** sur l'avant/arriere contre 0,009 a 0,03 u sur les deux autres. **BANDE : le freinage rend 0,4038 / 0,3966 contre 0,25-0,35, soit ×1,15 et ×1,13 — les DEUX chaines AU-DESSUS.** §17 s'eloigne donc du vert : le registre la disait « la section la plus proche d'un vert du dossier », elle ne l'est plus. **CE QU'ELLE GAGNE EN ECHANGE EST PLUS IMPORTANT** : sur l'axe du monde les deux chaines rendaient 0,2367 et 0,6519 — un facteur **2,75** et deux verdicts opposes (SOUS contre AU-DESSUS) sur un rig symetrique a 0,005 deg. Sur le bon axe elles sont a **1,78 %** l'une de l'autre. La reserve (b) sur l'extreme sensibilite a la pose de cette fenetre reste ouverte et non expliquee. **[LIMITEUR, cycle 71 — CE QUE VALAIT LA DEMANDE DU RESSORT DANS CES FENETRES-LA]** Le canal qui porte cet apex sature la §21 comme un MULTIPLICATEUR DE FORCE dont l'argument est plafonne (`jak-hd-physics.gc:2938-2943`) : identite stricte sous `kn = 0.42 B0`, raidissement en `x/(1-x)` jusqu'a `0.4992 B0`, puis **force de rappel CONSTANTE** (72.82 / 78.65 u/frame^2). `ROOM-REGLIM` publie desormais, SUR LA MEME LIGNE que chaque verdict de bande, l'etat du limiteur de SA PROPRE fenetre. PH-REGB : freinage r=8 **GELE x1,38 / x1,29 kn**, les deux chaines. Les deux lectures d'apex (0,4038 / 0,3966 contre 0,25-0,35) portent donc `(SATURE)` et **ne peuvent plus soutenir un `TENUE`**. Le demarrage r=7, que §17 ne borne pas, est GELE lui aussi. **UNE OBSERVATION QUI N'ETAIT PAS PREDITE ET QUE JE PUBLIE COMME TELLE** : sur les cinq fenetres bornees, le classement des apex suit celui de la demande SAUF pour r=8, qui porte la plus forte demande des cinq sur chestL (0,5807 B0) et rend pourtant un apex INFERIEUR a celui de r=1 (demande 0,4686). L'inversion est unique, elle est la meme sur les deux chaines, et elle tombe sur la cellule la plus gelee. Correlation, pas mecanisme demontre. |
| 18 | « COM displacement: moderate 10-17% B0, strong 17-24% B0 » ; « Apex displacement: strong 20-30% B0 » ; « Left and right trajectories shall differ **because their offsets from the torso rotational axis differ** » (l.259-266) | **NON TENUE** | **REMESUREE AU CYCLE 57 SUR LE MESH RECUIT** (ancrage d'apex leve, os INCHANGES AU BIT). Apex du lacet FORT, seule bande d'apex de §18 : chestL **0,1794** SOUS x0,90 (etait 0,1104, SOUS x0,55) · chestR **0,5022 AU-DESSUS x1,67** (etait 0,2791, DANS). Lacet modere : 0,0857 / 0,4965 (etait 0,0515 / 0,2756). **L'ECART GAUCHE/DROITE S'AGGRANDIT AU LIEU DE SE RESORBER : x5,79 sur le lacet modere et x2,80 sur le fort**, contre x5,4 et x2,5 avant. Le gain d'ancrage est pourtant quasi identique des deux cotes (x1,66 / x1,80 et x1,62 / x1,80), donc **ce n'est pas le repesage qui creuse l'ecart : il le REVELE a plus grande echelle.** La cause que §18 invoque elle-meme (« because their offsets from the torso rotational axis differ ») reste ABSENTE de ce rig — les deux racines sont a 548,1 u de l'axe de lacet a 5,2e-4 % pres, donc **§18 predit ICI la quasi-egalite**. **ET LA SECTION RESTE NON LISIBLE POUR TOUT CE QUI EST GAUCHE/DROITE** : les deux regimes de lacet tournent toujours dans la pose ASYMETRIQUE (123,4 deg du miroir), et le cycle 56 a etabli que le stimulus RECU y differe de x2,3-2,6 entre les jambes. Ni tenue, ni refutee sur cette clause. Ce qui est neuf et LISIBLE : chestR sort maintenant par le HAUT de sa bande, ce qui rejoint le constat global de §22 **[POSE-C65/66]** Cette ligne publie un ecart gauche/droite tire de PH-REG, dont la pose est mesuree au cycle 65 a **43,8 / 48,0 deg du miroir** (`ROOM-REGPOSE`). Voir le bloc « Cycle 65 » plus bas : l'attribution de cette asymetrie au PERSONNAGE n'est pas soutenue. **[POSE, cycle 67]** L'écart de x1,50 que le cycle 66 avait mesuré à 7,5 deg n'est plus publiable non plus : à 0,594 deg la même fenêtre rend **1,541 / 1,244**. Le sens ne s'inverse pas entre les deux poses, mais 3 fenêtres sur 11 le font ailleurs, donc « lequel des deux bouge le plus » n'est stable dans AUCUNE pose testée sauf la plus serrée. **[CYCLE 68]** Le lacet est le seul des trois axes que la salle avait juste (11,9 deg du vertical du sujet) ; PH-REGA le rejoue sur le vertical EXACT. Mesure : apex **0,43 a 0,58 sur chestL contre 0,10 a 0,15 sur chestR** — chestL AU-DESSUS de « 20-30% B0 » (l.262), chestR SOUS, sur les quatre lectures. Le rapport vaut 3,9 a 4,7. **Il n'est PAS publiable comme une propriete du personnage** : la pose de PH-REGA revalide a 2,09 deg, au-dessus du seuil derive de 1,3 deg, et le verrou le refuse. Ce qui reste lisible est le CONTRASTE a pose EGALE : le lacet rend 4,3 quand le tangage rend 1,00 dans la MEME pose. Un facteur 4 ne peut pas venir de 2 deg de pose quand 7,5 deg n'en deplacaient que 10 %, mais je n'ai pas de cause etablie et je ne la publie donc pas comme un verdict. A rejouer dans une pose sous 1,3 deg. **[LIMITEUR, cycle 71 — CE QUE VALAIT LA DEMANDE DU RESSORT DANS CES FENETRES-LA]** Le canal qui porte cet apex sature la §21 comme un MULTIPLICATEUR DE FORCE dont l'argument est plafonne (`jak-hd-physics.gc:2938-2943`) : identite stricte sous `kn = 0.42 B0`, raidissement en `x/(1-x)` jusqu'a `0.4992 B0`, puis **force de rappel CONSTANTE** (72.82 / 78.65 u/frame^2). `ROOM-REGLIM` publie desormais, SUR LA MEME LIGNE que chaque verdict de bande, l'etat du limiteur de SA PROPRE fenetre. PH-REG (pose HERITEE, donc aucune lecture gauche/droite n'en sort) : lacet fort r=10 **chestL LINEAIRE x0,32 kn** et **chestR GELE x1,33 kn**. Les deux chaines ne sont pas dans le meme regime de limiteur sur la meme fenetre, ce qui suffit a interdire d'en tirer un ecart L/R meme si la pose etait symetrique. |
| 19 | « Strong pitch motion may generate **30-40% B0 apex displacement** without requiring comparable local stretch » ; « the authored standing geometry is **crossed** » (l.271-279) | **NON TENUE** | **RETROGRADEE AU CYCLE 57, ET C'EST CE CYCLE QUI L'Y MET — JE LE DIS SANS L'ENROBER.** §19 etait le SEUL vert d'amplitude du dossier (quatre lectures dans [0,30 ; 0,40] au cycle 51). En levant le plafond d'ancrage de §30, les quatre lectures montent de x1,75 a x1,81 et sortent TOUTES par le haut : flexion **0,5965 / 0,6373** (AU-DESSUS x1,49 / x1,59), retour **0,5792 / 0,5896** (x1,45 / x1,47). **CE N'EST PAS UNE REGRESSION DU SOLVEUR — IL EST INCHANGE AU BIT** ; c'est la meme excursion, qui atteint enfin la peau au lieu d'etre divisee par 1,76 par la soudure au torse. **LE VERT PRECEDENT ETAIT DONC UN VERT DE COMPENSATION** : deux defauts opposes — un solveur trop energique et un maillage qui le bridait — se annulaient sur cette section. C'est exactement le mode de faux vert que ce dossier traque, et il aura tenu six cycles. La clause « crossed » reste tenue. LA DUREE EST DE MOI (0,40 s) et le verdict en depend **RÉTROGRADÉE DE `NON TENUE` À `NON ÉTABLI` AU CYCLE 67, ET LA CAUSE N'EST PAS UNE AMPLITUDE : CE N'EST PAS §19 QUI A ÉTÉ JOUÉE.** Les rotations sont commandées autour des axes du MONDE (`physroom-reg-pose`, littéralement `(1,0,0)/(0,1,0)/(0,0,1)`) alors que §19 est définie dans le repère du SUJET (« during a rapid **forward bend** »). L'axe latéral du sujet, mesuré à l'exécution, vaut (-0,081 ; +0,183 ; +0,980) : il est à **85,3 deg du monde X** que la salle emploie pour le « tangage ». Ce qui a été joué pendant six cycles est donc un **ROULIS à 70 deg**. CINQ PREUVES INDÉPENDANTES : (1) le rig livré — `lBoob` (+0,09) / `rBoob` (-0,09), séparation à 100 % sur un seul axe, 19 cm ; (2) `u_chestL - u_chestR` tombe à 0,240 deg de l'axe que le solveur nomme latéral, donc le nom est bon ; (3) une rotation autour du latéral laisse l'écart au miroir INVARIANT par algèbre, or `physroom-lean` (monde X) le fait passer de 0,237 à 143,213 deg ; (4) le « roulis » de §20 rend un rapport L/R de 1,002 (signature d'un tangage) et ce « tangage » 2,259 (signature d'un roulis) — **ce qui donne enfin sa cause à l'anomalie que le cycle 66 publiait sans en avoir** ; (5) rejouée autour de l'axe LATÉRAL (PH-REGA), la fenêtre rend un rapport L/R de **1,003 / 1,015** — la symétrie que la géométrie PRÉDIT, et qui n'apparaît que là. Le verdict `NON TENUE` du cycle 57 portait donc sur un geste qui n'est pas celui de cette section, et il est retiré. CE QUI MANQUE POUR LA MESURER : le SIGNE de l'axe. `PHYSREGAD`, bâti pour le trancher, rend la même constante sur les six fenêtres (il lit un axe figé à l'ancre) : instrument non discriminant, rejeté. **CYCLE 68 : LE GESTE DE CETTE SECTION A ENFIN ETE JOUE, ET IL SORT DE SA BANDE.** Le cycle 67 avait etabli que l'axe etait faux mais laissait le SIGNE indetermine — un axe mesure n'a pas de sens privilegie. PH-REGA joue desormais chaque fenetre DANS LES DEUX SENS et publie le DEPLACEMENT REEL DE L'ANCRE (l'instrument du cycle 67 lisait un axe fige et rendait une constante : rejete). Mesure : au signe +1 autour de l'axe LATERAL du sujet, l'ancre part de **875 u vers l'avant (21 cm) et 469 u vers le bas (11 cm), avec 0,1 u de lateral** — c'est la « rapid forward bend » de la section, pour la premiere fois. Regle de lecture MESUREE : l'os `chest -> lBoob` a +0,154 d'avant sur le mesh livre et -0,130 sur l'axe AP du solveur, donc cet axe pointe vers l'ARRIERE et `dap < 0` = vers l'avant. VERDICT SUR LA BANDE : apex **0,8199 / 0,8173** contre « 30-40% B0 » (l.278), soit **x2,05 et x2,04 AU-DESSUS** sur les deux seins. Le retour (r=12) rend 0,7943 / 0,8061, meme depassement, et son deplacement d'ancre net est **exactement 0,0000** sur les trois axes — la clause « the breast converges back to exactly 100% » est donc tenue au niveau de l'ANCRE. DUREE DE MOI : 24 frames (0,40 s). CONTROLE MIROIR AU PASSAGE : le signe -1 donne la flexion ARRIERE (dap +743, dver +663) et rend 0,6334 / 0,5526 — le solveur repond donc DIFFEREMMENT a l'avant et a l'arriere, ce qui n'etait pas mesurable avant. **CE QUE JE N'EXPLIQUE PAS** : la flexion AVANT est symetrique a 0,3 % (R = 1,003) comme la geometrie l'impose, mais la flexion ARRIERE rend R = 1,146. Une rotation autour du lateral doit etre symetrique dans les DEUX sens ; elle ne l'est pas. Je n'ai pas de cause. **[LIMITEUR, cycle 71 — CE QUE VALAIT LA DEMANDE DU RESSORT DANS CES FENETRES-LA]** Le canal qui porte cet apex sature la §21 comme un MULTIPLICATEUR DE FORCE dont l'argument est plafonne (`jak-hd-physics.gc:2938-2943`) : identite stricte sous `kn = 0.42 B0`, raidissement en `x/(1-x)` jusqu'a `0.4992 B0`, puis **force de rappel CONSTANTE** (72.82 / 78.65 u/frame^2). `ROOM-REGLIM` publie desormais, SUR LA MEME LIGNE que chaque verdict de bande, l'etat du limiteur de SA PROPRE fenetre. PH-REG : **les QUATRE cellules de §19 sont GELEES** — flexion r=11 x1,35 / x1,58 kn, retour r=12 x1,29 / x1,32 kn. §19 n'a qu'une clause chiffree, l'apex, et ses quatre lectures (0,4941 a 0,6423 contre 0,30-0,40) portent toutes `(SATURE)`. **C'est la section du registre dont le verdict est le plus entierement conditionne par le limiteur** : il n'y reste aucune lecture en zone lineaire. |
| 20 | « Typical strong roll: COM 15-22% B0, apex 20-30% B0, local stretch +5 to +12% » ; « must **not** be mechanically mirrored after contact » (l.283-286) | **NON TENUE** | **RETROGRADEE DE `PARTIELLE` AU CYCLE 57, meme cause que §19 et je l'assume de la meme facon.** Roulis simple **0,3625 / 0,5506** (AU-DESSUS x1,21 / x1,84 ; etait 0,2204 DANS / 0,3150) · bascule opposee **0,5179 / 0,6010** (x1,73 / x2,00 ; etait 0,2868 DANS / 0,3425). chestL tenait la bande sur les deux fenetres et n'y est plus : les quatre lectures sont maintenant AU-DESSUS. Le gain x1,64 a x1,81 est celui de l'ancrage leve, os inchanges au bit. Stretch local : NON ISOLE par regime. DUREE DE MOI : 0,55 s **[POSE-C65/66]** Cette ligne publie un ecart gauche/droite tire de PH-REG, dont la pose est mesuree au cycle 65 a **43,8 / 48,0 deg du miroir** (`ROOM-REGPOSE`). Voir le bloc « Cycle 65 » plus bas : l'attribution de cette asymetrie au PERSONNAGE n'est pas soutenue. **RÉTROGRADÉE DE `NON TENUE` À `NON ÉTABLI` AU CYCLE 67, MÊME CAUSE QUE §19 ET SYMÉTRIQUE DE LA SIENNE : CE N'EST PAS §20 QUI A ÉTÉ JOUÉE.** L'axe employé pour le « roulis » est le monde Z, à **11,5 deg de l'axe LATÉRAL du sujet** — c'est-à-dire l'axe d'un TANGAGE. Ce qui a été joué est donc une flexion avant/arrière à 35 deg, pas la « lateral torso motion » de la section. Les cinq preuves sont celles de §19. Signature mesurée : ce « roulis » rendait un rapport gauche/droite de **1,002 / 1,045** — quasi parfaitement symétrique, ce qu'un roulis ne peut pas être et ce qu'un tangage doit être ; sa propre clause « the gravity-side and opposite-side breasts must **not** be mechanically mirrored » était donc lue sur le geste qui la rend impossible. Rejouée autour de l'axe AVANT/ARRIÈRE (PH-REGA), elle rend 1,172 / 1,133 — asymétrique, comme un roulis doit l'être. LES AMPLITUDES TRAHISSENT L'INTENTION : 35 deg d'inclinaison LATÉRALE est plausible pour « typical strong roll », 70 deg de flexion AVANT l'est pour « rapid forward bend ». Les amplitudes avaient été choisies pour les gestes que les ÉTIQUETTES nomment ; seuls les AXES étaient faux. Même réserve que §19 sur le SIGNE de l'axe. **CYCLE 68 : LE GESTE A ETE JOUE, SA BANDE ECHOUE, ET SA SECONDE CLAUSE EST DEMONTREE POUR LA PREMIERE FOIS.** Joue autour de l'axe AVANT/ARRIERE du sujet, dans les deux sens : le deplacement d'ancre est **0,0 u d'avant/arriere, 386 u de bas, 421 u de lateral** au signe +1 et **-0,1 / -75 / -565** au signe -1 — deux inclinaisons LATERALES opposees, ce que §20 nomme. BANDE : apex 0,3770 / 0,4420 (sgn +1) et 0,5863 / 0,4553 (sgn -1) contre « apex 20-30% B0 » (l.283) — **les QUATRE lectures AU-DESSUS**, de x1,26 a x1,95. La bande echoue donc, et c'est ce qui fixe le statut. **MAIS SA CLAUSE DE NON-MIROIR EST TENUE, ET C'EST NEUF** : « the gravity-side and opposite-side breasts must **not** be mechanically mirrored » (l.285-286). Sur r=13 le sein le plus mobile est chestR au signe +1 (0,4420 > 0,3770) et chestL au signe -1 (0,5863 > 0,4553) ; sur r=14 l'inversion se produit aussi. **Le solveur distingue donc le cote de la gravite** — le controle a stimulus MIROIR que cette clause demandait n'existait pas avant ce cycle. DUREE DE MOI : 21 frames (0,35 s). **[LIMITEUR, cycle 71 — CE QUE VALAIT LA DEMANDE DU RESSORT DANS CES FENETRES-LA]** Le canal qui porte cet apex sature la §21 comme un MULTIPLICATEUR DE FORCE dont l'argument est plafonne (`jak-hd-physics.gc:2938-2943`) : identite stricte sous `kn = 0.42 B0`, raidissement en `x/(1-x)` jusqu'a `0.4992 B0`, puis **force de rappel CONSTANTE** (72.82 / 78.65 u/frame^2). `ROOM-REGLIM` publie desormais, SUR LA MEME LIGNE que chaque verdict de bande, l'etat du limiteur de SA PROPRE fenetre. PH-REG : roulis r=13 **GELE x1,24 kn (chestL) / GENOU x1,19 kn (chestR)**, bascule r=14 **GELEE x1,30 kn sur les deux**. Trois des quatre lectures portent `(SATURE)` ; les quatre sont AU-DESSUS de la bande. |
| 21 | « Linear and rotational displacement contributions shall combine vectorially. **They shall not be added without saturation.** » ; `D_combined = D_max · tanh( \|D_linear + D_angular\| / D_max )` (l.290-293, cité mot pour mot) | **NON TENUE** | **RETROGRADEE DE `PARTIELLE` AU CYCLE 71, ET LE MOTIF PRECEDENT NE DECRIVAIT QU'UNE DES DEUX SATURATIONS.** L'ancien motif (« facteur commun posé au cycle 46, il ne mord presque jamais ») parle de `phys-apex-scale` — le facteur COMMUN, qui en effet ne mord pas. **Il en existe une SECONDE sur le même canal, jamais déclarée ici, et elle mord en permanence** : `jak-hd-physics.gc:2938-2943` sature la §21 comme un **MULTIPLICATEUR DE FORCE** dont l'argument est plafonné par `fmin 0.99`. Trois régimes en découlent, tous lus dans le source et aucun choisi par moi : sous `kn = 0.42 B0` identité stricte ; entre `kn` et `kn + 0.99·cpp = 0.4992 B0` la barrière raidit en `x/(1−x)` ; **au-delà l'argument GÈLE et la force de rappel devient CONSTANTE** — 72.82 u/frame² (chestL) / 78.65 (chestR), calculées depuis les constantes livrées, soit **16.7× ce que le ressort linéaire rendrait à cette distance**, et la MÊME valeur à 5 021 u d'erreur qu'à 50 207 u. **Une force constante est un TAUX, pas une BORNE**, et c'est exactement le défaut que le cycle 34 a mesuré puis corrigé sur l'AUTRE canal (le point libre de §23) sans jamais le porter sur celui-ci. **MESURE, cycle 71** (`ROOM-REGLIM`, 132 fenêtres de régime, les cinq phases) : **36 LINEAIRE · 23 au GENOU · 73 GELEES, soit 55.3 %**. Le témoin r=0, qui ne reçoit aucun pilotage, est LINEAIRE sur les deux chaînes (0.0381 / 0.0241 B0) — donc les 130 autres cellules ont une échelle et ce qu'elles montrent au-delà du genou vient de leur pilotage. **POURQUOI `NON TENUE` ET NON `PARTIELLE`** : la section ne donne pas une bande mais une FORME, et la forme livrée n'est pas la forme prescrite — elle sature la FORCE là où le texte sature le DEPLACEMENT, et elle dégénère en constante sur plus de la moitié des fenêtres mesurées. **CE QUI N'EST PAS ETABLI, ET JE NE LE PRETENDS PAS** : que remplacer la forme améliore ce que l'owner voit. Le cycle 71 n'a touché aucun terme du solveur — il a donné un lecteur à une grandeur que le moteur calculait déjà. **CYCLE 72 — LE MUR DE FORCE EST DESORMAIS DESARMABLE (`*phys-fwall*`, [NOTE-330]) ET LA PAIRE APPARIEE EST FAITE.** Le registre exige d'ajouter l'interrupteur d'ablation AVANT de s'autoriser a corriger le mecanisme soupconne (`attribution-harness-outlives-its-defect`) : c'est fait, et la mesure existe maintenant. **TEMOIN D'INERTIE (jambe ARMEE)** : 43 386 lignes `PHYS`, **0 DIFFERENTE** de la course du cycle 71 — l'interrupteur arme est inerte au bit et la salle est deterministe dans ce build, donc l'autre jambe est attribuable. **JAMBE DESARMEE** : `stif_n` 50 397 -> **0 exactement** ; le filet de DEPLACEMENT mord **plus** (`sat_n` 40 484 -> 48 541, `sat_sum` 3 026 782 -> 3 561 160 u) ; le temoin sans pilotage ne bouge pas (`perr` 0,0381 -> 0,0388 et 0,0241 -> 0,0244 B0) ; `ROOM-IDLE` reste a 0,0002 ; le mouvement MONTE (`tipvar_max` +5,5 a +10,7 % sur 4 pilotages sur 5). **CE QUE JE NE LIVRE PAS, ET POURQUOI** : la jambe desarmee fait passer les cellules d'apex au-dessus du plafond EXCEPTIONNEL de §22 de **8/30 a 16/30** (max 0,6423 -> 0,7176 B0) et fait **ECHOUER le controle positif de §33/§34** (400 u injectes, 235 u restitues, bande exigee 75-125 %) — un compteur de penetration sans controle qui tire ne prouve rien. Livrer ce build echangerait une faute de FORME contre un doublement d'une borne violee ET un instrument sans controle. La correction ne peut pas se faire ici seule : voir §22, ou le cycle 72 etablit que la borne d'apex est posee sur la mauvaise GRANDEUR. Le mur de force reste donc ARME en livraison, et il est desormais desarmable en une constante. |
| 22 | « Breast COM: normal <=35% B0, hard transient <=40% B0 » (l.300) ; « Distal/apex displacement: normal <=42% B0, exceptional <=50% B0 » (l.301) ; elongation **locale** <=25 % | **NON TENUE** | **RETROGRADEE DE `PARTIELLE` AU CYCLE 57, ET C'EST LE RESULTAT LE PLUS IMPORTANT DU CYCLE.** Apex, plafonds DURS de la section : pic TYPIQUE de fenetre **0,6876 / 0,7003** contre <=0,42 -> **HORS x1,64 / x1,67** (etait 0,3984 / 0,4134, DANS) ; MAXIMUM de course **0,9249 / 0,9592** contre <=0,50 -> **HORS x1,85 / x1,92** (etait 0,5431 / 0,5553, HORS de +9 / +11 % seulement). **99,5 % et 98,9 % des fenetres** depassent 0,42 ; 98,9 % et 97,3 % depassent 0,50. **CE QUE CA ETABLIT, ET C'EST LE VRAI ACQUIS DU CYCLE 57 : LA SOUDURE AU TORSE MASQUAIT UN SOLVEUR TROP ENERGIQUE.** Elle divisait l'excursion d'apex par 1,76 / 1,68 AVANT qu'elle n'atteigne la peau, ce qui rendait des chiffres d'apparence conforme. Le solveur n'a PAS change — les mesures de JOINTS sont identiques au bit — donc cette amplitude existait deja et n'etait pas mesurable. **Le chantier bascule du MAILLAGE vers le SOLVEUR, et il est maintenant chiffre : il faut diviser l'excursion d'apex par ~1,85 sans retirer le mouvement que la §30 vient de rendre.** Corroboration independante dans la meme course : `ROOM-APEX-RATIO` donne apex/COM de mediane **x1,95** (x1,28-2,53) quand la bande implicite de la spec vaut x1,19 a x1,35 — l'apex sur-repond au COM d'un facteur ~1,5, ce qui est une sur-amplification STRUCTURELLE et non un depassement de bande. **Clause COM, relue sur une course POSTERIEURE a la correction de `comw=`** (l'ancienne valeur etait mesuree sur un mesh qui n'existe plus) : pic typique **0,3580 / 0,3353** contre <=0,35 -> chestL HORS de +2,3 %, chestR DANS ; transitoire dur **0,4758 / 0,4361** contre <=0,40 -> HORS de +19 % / +9 % (etait 0,4441 / 0,4086, +11 % / +2 %). **LE COM NE MONTE QUE DE +6,7 % ET +2,8 % LA OU L'APEX MONTE DE x1,68, ET C'EST EXACTEMENT CE QUE LA §30 DEMANDE** : le mouvement rendu est CONCENTRE sur l'apex (« Apex — minimal direct anchoring »), il ne gonfle pas l'organe en bloc. Les deux courses sont bit-reproductibles sur l'apex (30 lignes sur 30 identiques), donc cet ecart COM est attribuable au seul `comw=`. Elongation locale : deux instruments toujours en desaccord (0,124-0,157 contre 0,189-0,229) **CYCLE 58 — LE MECANISME DU DEPASSEMENT EST IDENTIFIE, ET UNE TENTATIVE EST REFUTEE PAR MESURE.** L'attribution par identite (residu 0,000170 B0 sur 372 fenetres) donne `maxima \|tp\| 0,5008 · \|rp\| 0,2313 · \|dp\| 0,4660` B0. **Le maximum de `tp` EST le plafond dur de la section au centieme pres (0,5008 contre 0,5000)** : la borne mord, et elle mord parfaitement — mais sur UN SEUL des trois termes. `dp` (le tenseur de deformation multiplie par un bras de chair de 1,0817 B0) ajoute jusqu'a 0,4660 B0 par-dessus, et **aucun des cinq sites qui appliquent 0,42/0,50 x B0 ne le voit** : les cinq lisent un JOINT (`:2744`, `:3024`, `:2816`, `phys-apex-scale :1293`, `:3648`), alors que la section nomme « Distal/apex displacement ». **TENTATIVE, MESUREE, RETIREE :** faire lire a `phys-apex-scale` le point d'apex pondere (`ax`, deja charge depuis `physics_mesh.txt`) rend la borne **DEUX FOIS PLUS FAIBLE** — `bendcut` 7245/5360 -> 2266/2214 (-69 % / -59 %), `\|tp\|` max **0,5008 -> 0,7127 B0** (le joint passe au travers de son propre plafond, x1,43), `ROOM-APEX` **0,9249/0,9592 -> 0,9664/0,9616** et `ROOM-COM` **0,4758/0,4361 -> 0,5006/0,4561** : la section visee EMPIRE sur ses DEUX clauses. Trois causes arithmetiques : les poids `ax` somment a 0,9402/0,9549 ; la somme est VECTORIELLE sur deux maillons dont les contributions se compensent ; et surtout **`dp` n'existe pas encore** au point ou la borne s'applique (le tenseur est bati a la section 5bis, APRES la boucle de contraintes). **Le joint de pointe etait donc un majorant PLUS STRICT que l'apex prive du tenseur.** Retire par `git checkout`, recompile (551 cibles) et **retrait VERIFIE par une course de controle**. REGLE : remplacer un proxy par la grandeur que la spec nomme n'est un progres que si cette grandeur est COMPLETE au point ou la borne s'applique. **§22 n'est pas bornable depuis la boucle de contraintes** ; le chantier est de la borner APRES la construction du tenseur, ou de reduire `dp` a la source. **[LIMITEUR, cycle 71 — SES DEUX SEUILS SONT DEVENUS UN GENOU ET UN MUR, ET LE MUR NE BORNE PAS]** Les deux nombres de cette section — `normal <=42% B0` et `exceptional <=50% B0` — sont EXACTEMENT `kn` et `cap` du limiteur du ressort principal (`kn = 0.42 B0`, `cap = 0.50 B0`, `jak-hd-physics.gc:2859-2860` et `phys-apex-scale:1205`). Le moteur les implemente comme une barriere de FORCE dont l'argument est plafonne par `fmin 0.99` : au-dela de `0.4992 B0` la force de rappel est **CONSTANTE** a 72,82 (chestL) / 78,65 (chestR) u/frame^2 — elle vaut la meme chose a 5 021 u d'erreur qu'a 50 207 u. **Une force constante est un taux, pas une borne**, et c'est precisement coherent avec le depassement deja inscrit ci-dessus (apex maximum de course 0,9249 / 0,9592 B0 contre un plafond de 0,50) : le plafond ne tient pas parce que sa mise en oeuvre ne peut pas tenir. Mesure du cycle 71 : **73 des 132 fenetres de regime (55,3 %) sont au-dela du gel**, temoin sans pilotage LINEAIRE sur les deux chaines. Voir §21, dont le statut change pour cette raison. **CYCLE 72 — LA BORNE DE §22 EST POSEE SUR UNE GRANDEUR QUI N'EST PAS L'APEX, ET AUCUN REGLAGE NE PEUT LES ACCORDER.** Verifie dans le source et dans la donnee LIVREE, sans aucune course neuve. (1) L'apex publie est `ap = \|SUM_l w_l ((bm_l . o_l + p_l) - (pre_l . o_l + pre_l.trans))\| / B0` (`jak-hd-physics.gc:3902-3908` accumule, `:4026-4034` publie l'emplacement 53, `phys-pt-exc!` `:115-120`), ou `pre` est la pose d'AUTEUR de la meme frame (`:3835-3836`) et `bm` la matrice REELLEMENT livree au rendu. Il porte donc DEUX termes : la TRANSLATION du maillon (`p_l - pre_l.trans`) **et** la ROTATION de `bm` appliquee a un levier `o_l`. (2) Ce levier est mesure dans `recharged_assets/physics_mesh.txt` (`ax`) : **739,5 / 728,0 / 743,2 u, soit 1,228 / 1,209 / 1,235 B0** — le point de chair de l'apex est a plus d'un `B0` de son joint. Poids : 0,9402 (chestL) / 0,9549 (chestR). (3) La borne qui pretend tenir §22 (`jak-hd-physics.gc:3120-3141`, genou 0,42 B0, tanh de Pade, asymptote 0,50 B0) agit sur `*phys-px*` SEUL — la translation. **Son asymptote consomme donc a elle seule LA TOTALITE du plafond exceptionnel de la section, et il ne reste ZERO budget pour la rotation d'un levier de 1,23 B0.** A titre d'echelle : une rotation de **10 deg** deplace deja l'apex de **0,213 B0** a translation nulle, et **24,3 deg** suffisent a atteindre 0,50 B0 sans que le maillon se soit translate d'une seule unite. (4) La mesure le confirme dans les DEUX jambes du cycle 72 : apex max **0,6423 B0** mur de force arme, **0,7176** desarme, et **8/30 puis 16/30** cellules de regime au-dessus de 0,50 B0. Le mur de FORCE ne bornait pas l'apex ; il rapetissait toute la reponse, ce qui le masquait. **CONSEQUENCE, ET C'EST LE CHANTIER NOMME** : §22 ne peut pas etre tenue en reglant la borne existante — il faut que la grandeur bornee soit celle que la section nomme, c'est-a-dire l'excursion du POINT DE CHAIR, rotation comprise. Le meme piege que le 2026-08-20 07:20 (« un axe de mesure qui n'est pas celui que la spec DEFINIT est un axe faux »), deplace de l'AXE vers la GRANDEUR. **CYCLE 73 — LA BORNE DE §22 NE FUIT PAS UN PEU : ELLE EST DEFAITE APRES COUP, ET C'EST MESURE SUR LA TRACE DEJA LIVREE.** Le filet de deplacement de `jak-hd-physics.gc:3120-3141` est **algebriquement incapable** de laisser le maillon RACINE au-dessus de `kn + cp = 0,50 B0` a l'instant ou il s'applique (`ds = kn + cp*tanh(...) < kn + cp`, puis `p := t + d*ds/dd`). Or `jt = \|p_l - pose_auteur_l\| / B0` (emplacement 39+l, publie par `PHYSCOMWL`) vaut, mesure a la FIN de la frame sur les **372 fenetres** de la course livree : **maillon 0 max 0,6670 B0 contre 0,50 -> +33,4 %, 15 fenetres au-dessus** ; maillon 1 (somme telescopique, plafond 0,5675) max 0,6317 -> +11,3 %, 4 fenetres. **CE QUI SEPARE LES DEUX INSTANTS, CE SONT QUINZE ITERATIONS DE CONTRAINTES** — `(dotimes (it 8) phys-length-chain phys-collide-chain)`, `phys-bend-chain`, `(dotimes (it 3) ...)`, `(dotimes (it 4) ...)`, `phys-skin-chain` — qui reecrivent toutes `*phys-px*` APRES que la borne a mordu. La borne est posee sur un ETAT INTERMEDIAIRE, pas sur la valeur livree : c'est exactement ce que [NOTE-84] interdit pour le canal radial (« la borne est appelee sur la valeur LIVREE, jamais sur l'etat ») et que personne n'avait applique a celui-ci. **DEUX RAISONS DE LIRE CE CHIFFRE COMME UN MINORANT.** (1) `jt` est latche a l'argmax de `ee` (l'excursion de chair du maillon), pas au sien propre : le vrai maximum de `\|p - pose_auteur\|` est donc >= celui-la. (2) Le `tp` de `PHYSCOMD`, qui est une PROJECTION sur la direction d'excursion et donc <= la norme, depasse deja de +25,9 % sur les memes fenetres, sur les deux chaines et sur 4 pilotages sur 5. **CONSEQUENCE POUR LE CHANTIER, ET ELLE PASSE DEVANT LE RESTE** : poser une borne d'apex en section 6 pendant que la borne de translation est defaite en aval ne servirait a rien — toute borne placee en amont de la boucle de contraintes subit le meme sort. Il faut d'abord que la borne de §22 SURVIVE a la frame. **CE QUI N'EST PAS ETABLI, ET JE NE L'INVENTE PAS** : LAQUELLE des quatre contraintes la defait. Les trois interrupteurs d'ablation existent deja (`*phys-len-off*`, `*phys-col-off*`, `*phys-bend-off*`) : c'est une course d'attribution, pas une deduction. |
| 23 | « Un seul ressort à l'apex est INSUFFISANT » | **NON TENUE** | **RETROGRADEE AU CYCLE 59, SUR LA GRANDEUR QUE LE MOTEUR LIT.** Deux articulations sont bien simulées, mais les enregistrements `ax` du mesh LIVRÉ (lus par `pc-physics-chain-link-apex-mi`, jak-hd-physics.gc:797) donnent la part d'apex pilotée par le maillon DISTAL : **`ax chestL 1 = 0.0818`** et **`ax chestR 1 = 0.0000`**. À l'apex — la seule chose que cette ligne de la spec nomme — les deux chaînes sont donc des chaînes à UN ressort, à 8,2 % près à gauche et exactement à droite. La présence de l'articulation ne vaut pas sa participation : c'est le mode d'échec du 2026-08-18 08:55 (« la preuve est la RÉPARTITION, jamais la présence »), lu cette fois sur l'apex et non sur la possession de sommets. CIBLE CHIFFRÉE : `ax <chain> 1 >= 0.30` des deux côtés, sans faire sortir les cinq bandes de §30 sur l'axe anatomique. La chair simulée couvre par ailleurs 19 % de l'organe |
| 24 | 2,30 / 2,50 / 2,65 Hz par axe | PARTIELLE | Raideur dérivée pour 2,30 Hz. Le maillon distal est **sous la bande** |
| 25 | ζ = 0,35 (0,32–0,42) | PARTIELLE | Recalibrée le 2026-08-19 : l'ancien réglage l'était sur un signal saturé |
| 26 | Rebond ≈ 31 % (`FirstBounceRatio = 0.31`) | PARTIELLE | **SORT DE `NON ÉTABLI` AU CYCLE 52, ET SA RAISON ÉTAIT PÉRIMÉE, PAS SA MESURE.** Le motif inscrit (« le signal était saturé, jamais remesuré ») ne tenait plus : la colonne `rebond` de `ROOM-RINGFIT` est calculée par `_rebound()` à partir des EXTREMA BRUTS de `PHYSRINGA` — vérifié, la fonction ne prend que la série et le `zeta` ajusté n'y entre pas, donc elle **n'est pas tautologique**. Mesuré : chestL ap **0,314** / lat **0,322** ; chestR ap **0,313** / lat **0,318** — quatre lectures, LES DEUX seins, à **+0,9 % à +3,9 %** de sa cible. **Pourquoi PAS `TENUE`** : les deux canaux VERTICAUX sont NON LISIBLES (résidu d'ajustement 0,184 / 0,104 ; ils rendent 0,545 contre 0,309 selon la chaîne, donc leur série n'est pas un mode unique) — et le vertical est justement le mode que sa §24 nomme principal |
| 27 | « dominant visible response 0.3-0.6 s; secondary movement 0.6-1.2 s; mostly settled ~1.0-1.5 s; **essentially stationary ~1.3-1.7 s** » (l.350-351) | PARTIELLE | **RETROGRADEE cycle 48 — C'ETAIT UN FAUX VERT, ET SUR UNE ERREUR DE COLONNE.** §27 pose QUATRE seuils ; le TENUE lisait `t1`=1,38 s (chestR) comme « essentially stationary » alors que `t1` est le seuil a 1 %. La colonne qui repond a la clause est `t01`, et elle vaut **`>2,47` s sur LES DEUX chaines** (`ROOM-SETTLE` l.427/430) ; `t05` vaut `>2,47` sur chestL. Cause mesuree et commune avec §2/§9 : le plancher de `ROOM-SHFLOOR` **censure** `t01` sur 9 axes sur 12 |
| 28 | `k = m(2πf)²`, `c = 2ζ√(km)` | TENUE PAR CONSTRUCTION | Le moteur calcule `ω = 2π·raideur/√masse` : la relation est la forme même du code |
| 29 | Anisotropie 1,00 / 0,90 / 0,82 / torsion 0,72 | PARTIELLE | Compliance latérale mesurée 1,0294 / 0,9180 pour une cible de 0,820 |
| 30 | « **28-35% of the rear breast volume** should behave as strongly attached tissue, nominal **30%** » (l.375) ; le profil en cinq bandes (l.378-382) ; « Apex — **minimal direct anchoring** » (l.382) ; « **There shall be no hard attachment boundary.** » (l.384) | PARTIELLE | **REMONTEE DE `NON TENUE` AU CYCLE 57, ET LA CAUSE ETAIT DANS NOTRE OPERATEUR, PAS DANS LE MAILLAGE — JE RETIRE MA PROPRE PUBLICATION DU CYCLE 51.** Le registre portait « 41-43 % de l'apex est soude au torse » et un plafond de **x1.76 / x1.68 hors d'atteinte de TOUTE physique**, qui BORNAIT les verdicts de six sections. **C'ETAIT FAUX, et voici pourquoi, mesure.** L'operateur `anchor30` (`physics_c7_reskin.py:436-444`) calculait son abscisse sur `pts[-1]-pts[0]`, l'axe d'**OS** de la chaine — a **77,82 deg (chestL) / 78,15 deg (chestR)** de l'axe que la §31 DEFINIT mot pour mot (« r = 0 at chest attachment and r = 1 at distal/apex region »), et correle **NEGATIVEMENT** a lui (-0,116 / -0,292). Le MEME champ de poids rendait alors **5 bandes sur 5 DANS** lu sur l'axe d'os et **1 sur 5** lu sur celui de la spec. **PREUVE QUE L'OPERATEUR EST L'AUTEUR ET PAS UN SUSPECT** : son profil impose `0,95*(1-s)^p` avec p=1,285 PREDIT **0,4314** d'ancrage sur le decile apex anatomique de chestL contre **0,4324 MESURE** — 0,001 d'ecart. **CORRECTIF** : `axis=anat` ne change QUE la direction de l'abscisse d'ANCRAGE ; la PARTITION entre maillons reste sur l'axe de la chaine, parce que la geometrie l'impose (le maillon distal est 34,4 u / 77,5 u PLUS PRES du torse le long de l'axe anatomique). **RESULTAT, mesure sur le mesh RECUIT** : les cinq bandes passent de **1/5 a 5/5 DANS sur LES DEUX seins** (Deep 0,904/0,906 · Rear 0,747/0,735 · Mid 0,523/0,517 · Dist 0,281/0,275 · Apex 0,094/0,082). L'ancrage de l'apex tombe de **0,4324/0,4064 a 0,0598/0,0451** — DANS « minimal direct anchoring » — et le plafond d'apex, **statistique `apex_region` IDENTIQUE a celle qui avait publie 0,5676/0,5936**, monte a **0,9402 / 0,9549**. **CONTROLE A REPERE GELE** (l'axe d'`apex_region` est bati sur un centroide PONDERE, donc il se DEPLACE quand on repese, et un avant/apres naif comparerait deux populations) : sur l'axe et la region calcules sur l'ANCIEN mesh, **0,9352 / 0,9470** — le gain n'est donc PAS un artefact de deplacement d'axe. Banc hors cuisson et cuisson s'accordent au chiffre. **POURQUOI PAS `TENUE`, ET C'EST PUBLIE COMME UN COUT** : (a) `StrongRootFraction` depend du REPERE et les DEUX lectures sont publiees — **0,224 / 0,275 SOUS** la bande sur le nuage de la regle, **0,298 DANS et 0,356 au-dessus** sur le nuage de l'organe (contre 0,362 / 0,389 tous deux HORS avant, donc la clause S'AMELIORE mais chestR reste hors bande) ; (b) « no hard attachment boundary » : les aretes cassees tombent de **15 -> 5** et **22 -> 7** et se relocalisent de tout l'organe (mediane s=0,59) a la RACINE seule (mediane 0,00), ou la §30 veut justement de l'ancrage — mais ce n'est pas zero. **CETTE BAISSE N'ETAIT PAS PREDITE et je la publie comme non predite.** Les deux reperes sont MUTUELLEMENT EXCLUSIFS : sur le mesh recuit l'axe d'os rend 1/5 et l'axe anatomique 5/5, image miroir de l'etat d'avant **CYCLE 59 — LA « BARRE DES 30 % » DU CONTRAT DU 2026-08-18 N'EST PAS CETTE SECTION.** La directive du 08:55 exige « au moins 30 % des sommets de la chaîne ont le NOUVEL os pour joint majoritaire (w > 0.5), **conformément à `StrongRootFraction = 0.30` de sa §30** ». Le texte exact de §30 dit « 28-35% of the **rear breast volume** should behave as **strongly attached tissue** » : c'est la part de chair ANCRÉE AU BUSTE, pas la part de sommets possédés par l'os DISTAL — et les deux vont en sens CONTRAIRE (plus le distal possède, moins il reste d'ancre). Mesuré sur le mesh livré : `lBooc` 27/85 = **31,8 %** (au-dessus), `rBooc` 18/80 = **22,5 %** (sous). Le repesage n'est PAS fait, et la raison est mesurée : le seul balayage qui dérive cette barre (`probe_c24_distal_ownership.py`, cycle 24) calcule son `StrongRootFraction` sur l'AXE D'OS — l'axe que la directive du 2026-08-20 07:20 déclare FAUX — et prédit `rBoob=0` sommet majoritaire, c'est-à-dire un os de racine qui ne pilote plus rien. Le défaut que la barre désignait est réel et il est reporté sur la grandeur qui le nomme, à §23 (`ax <chain> 1` = 0,0818 / 0,0000). |
| 31 | « little deformation at the root; progressively increasing mobility; **largest displacement in distal tissue** » ; `w(r) = r^1.6...2.0` (l.389-390) | PARTIELLE | **REMONTEE DE `NON TENUE` AU CYCLE 57, ET JE RETIRE LA CAUSE QUE J'AVAIS INSCRITE.** Le registre affirmait : « Un gradient racine->pointe n'est donc pas exprimable par cette chaine, **quel que soit le reglage** » — declarant la section structurellement impossible a cause des 77,83/78,05 deg entre l'axe d'os et l'axe anatomique. **C'ETAIT FAUX** : le gradient ne vit pas dans la direction des OS, il vit dans les POIDS DE PEAU, et ceux-ci peuvent le porter le long de n'importe quelle direction. Mesure sur le mesh recuit, mobilite (poids porte par la chaine) par bande de la racine vers l'apex : **0,096 · 0,253 · 0,477 · 0,719 · 0,906** (chestL) et **0,094 · 0,265 · 0,483 · 0,725 · 0,918** (chestR) — **strictement CROISSANTE sur les cinq bandes, sur les deux seins**. La clause DESCRIPTIVE des trois membres de l.389 est donc TENUE, et elle etait declaree hors d'atteinte. **CE QUI RESTE HORS BANDE** : l'exposant. Ajuste par moindres carres sur `w(r) = r^n` contre le r anatomique, **n = 1,158 (rms 0,035) et n = 1,118 (rms 0,029)**, contre la bande 1,6-2,0 de la section. **ET LA CAUSE EST UNE TENSION ENTRE DEUX SECTIONS DE SA SPEC, PAS UN REGLAGE** : les trois bandes interieures de la §30 n'autorisent l'exposant d'ancrage que dans [0,831 ; 1,900], la derivation le fixe au PLANCHER 0,831, et un ancrage en `(1-r)^0,831` donne mecaniquement une mobilite en `r^~1,16`. **Tenir la §30 dans ses bandes INTERDIT l'exposant de la §31.** C'est une question ouverte sur sa spec, remontee comme telle et non tranchee a ma convenance. **AUTRE FAIT PUBLIE** : le parametre `grad` (le `RootDeformationExponent` de la §38) est **INERTE sur toute sa bande** — 1,60 / 1,80 / 2,00 rendent des comptes de sommets majoritaires IDENTIQUES. Et l'apex est desormais pilote par le maillon **PROXIMAL** (poids 0,8584/0,0818 sur chestL, **0,9549/0,0000** sur chestR) : le maillon distal ne porte RIEN de l'apex anatomique, ce que le cycle 57 avait predit d'avance (P7) et que corriger un axe d'ancrage ne pouvait pas deplacer |
| 32 | Indépendance gauche/droite ; masse ±2–4 %, raideur ±3–5 % | PARTIELLE | Les écarts de paramètres sont dans les bandes, mais bouger un sein déplace l'autre de 32 à 321 % (mesure de COUPLAGE, non touchée par le cycle 55). **CE QUE LE CYCLE 55 CORRIGE, ET C'EST MA PROPRE PUBLICATION** : l'écart gauche/droite de **×3,41** sur l'apex vertical publié au cycle 52 comme un dépassement de cette section était un **ARTEFACT DE POSE**. Épinglée à une pose bilatéralement symétrique (6,7° du miroir parfait au lieu de 43,4°), la même mesure rend **×1,06 / ×1,17**. **CORRECTION DE RÉDACTION, CYCLE 56 — CES DEUX CHIFFRES NE SONT PAS « PETITS », ILS SONT SOUS LA RÉSOLUTION.** Le tableau de la salle n'avait pas été régénéré depuis le cycle 53 ; régénéré sur la course que le cycle 55 a **réellement livrée**, il donne un plancher de répétabilité `ROOM-SIGN-REPEAT` de **2,882 %** (contre 0,462 % au cycle 53) et une dispersion de rang `ROOM-SIGN-RANK` de **5,10 %**, au-dessus du critère de 5 % que l'analyseur porte lui-même (**P6 y passe de TENUE à REFUTEE**, et personne ne l'avait lu). Un rapport de ×1,06 est donc DANS le bruit de son propre instrument, et ×1,17 à peine au-dessus. **La conclusion du cycle 55 n'en est pas affaiblie — elle en est renforcée** : l'écart ne « tombe pas à 6 % », il tombe à l'IRRÉSOLVABLE. C'est sa rédaction qui était fautive, pas sa mesure. La raison est géométrique et mesurée : les deux os y font le même angle avec le pilotage (22,3° / 21,8° au lieu de 2,03° / 41,77°), et l'écart de CONFISCATION tombe à 0,039 / 0,176. **Les autres écarts gauche/droite du dossier (§18 ×2,5 sur l'apex, §12) tournent dans des phases qui tiennent TOUJOURS la pose asymétrique : ils sont NON LISIBLES, ni tenus ni réfutés** **[LE SEUIL DE POSE EN DÉRIVE, cycle 67]** C'est la ligne « mass ±2-4%, stiffness ±3-5%, damping ±3-5% » de cette section qui fixe la plus petite différence gauche/droite que l'instrument doit résoudre — **2 %**. Croisée avec la sensibilité mesurée du rapport L/R à la pose (1,53 % par degré, cycle 67), elle donne le seuil d'écart au miroir au-delà duquel aucune comparaison gauche/droite n'est publiable : **1,3 deg**. §32 ne sert donc plus seulement de cible, elle calibre le verrou. |
| 33 | « Medial surfaces shall collide or repel **before visible interpenetration** » (l.400) ; restitution 0,00-0,15, nominal 0,06 | **NON TENUE** | **CYCLE 62 — LA SECTION EST MESUREE POUR LA PREMIERE FOIS, ET SON CONTROLE TIRE SUR LA FENETRE QUI PORTE LE VERDICT.** **1. LE DOMAINE N'EST PLUS VIDE.** Jusqu'ici `physics_c14_meshsamples.py` excluait les os de chaine de `bs`, donc le sein OPPOSE n'etait dans AUCUN jeu que le moteur lit et §33 avait un domaine **vide par construction** — aucune valeur ne pouvait rien en dire, ni rouge ni verte. La surface opposee est desormais chargee comme une population PAR CHAINE (`*phys-bslo*` / `*phys-bscn*`), et l'exclusion de SOI est STRUCTURELLE (`phys-other-surf-chain`) : une chaine n'interroge jamais ses propres ensembles, et la donnee ne porte aucun drapeau. **2. LE CONTROLE POSITIF EST DEVENU EVALUABLE, ET C'EST LE CORRECTIF DE CE CYCLE.** Il injectait **200 u FIXES** (0,0488 m) : sur la fenetre de COURSE l'approche vaut 47 et 50 u, donc le point injecte TRAVERSAIT la surface et le controle sortait `NON EVALUABLE` — c'est-a-dire **precisement sur la fenetre qui porte le verdict**. Il ne tirait qu'au repos, ou le domaine est VIDE : **il tirait la ou il n'y a rien a mesurer et manquait la ou on mesure.** L'injection est maintenant une **FRACTION** (0,50) de l'approche : le point ne peut plus traverser, et la prediction `gapi = (1 - f) x gap` est bien posee sur toute fenetre. MESURE : **les quatre cellules (2 chaines x 2 fenetres) tirent, ecart 0,0-0,1 %**, sur des baisses predites de **0,0057 a 0,0705 m** — un facteur **12,4**, donc l'instrument SUIT SON ENTREE au lieu de republier une constante. **3. LE VERDICT, ET IL EST ROUGE :** sur la fenetre de course la physique enfonce la peau du sein dans la surface du sein OPPOSE de **+0,0238 m (chestL)** et **+0,0106 m (chestR)** au-dela de la pose d'auteur. **Les DEUX chaines depassent** : NON TENUE, pas PARTIELLE (regle 2). Ce rouge-ci se tient la ou celui du cycle 60 a ete retire, parce que son estimateur est celui du cycle 61 (moyenne ponderee des 8 plans, continue, rayon adapte) **et que son controle tire sur la fenetre du verdict**. **4. TROIS RESERVES, ET ELLES SONT CONTRE MOI.** (a) **LE DOMAINE EST MINCE** : 67 et 6 lectures EN PORTEE sur 66 960 — le verdict est ETROIT et se lit comme tel. (b) **LES POINTS SONDES NE SONT PAS CHOISIS POUR LA MEDIALITE** : `process_link` retient le sommet le plus PERPENDICULAIREMENT ELOIGNE de chacun des 4 QUADRANTS autour de l'axe d'OS, plafonne a 5, sur une base de quadrants ARBITRAIRE. Rien ne garantit qu'un sommet de la face INTERNE — la ou §33 vit — soit retenu. La mesure est donc une **BORNE INFERIEURE** de la frequence du contact, pas son compte, et c'est le chantier suivant. (c) **LA BASE D'AUTEUR DE chestL EST ENTRAINEE, PAS LUE EN PORTEE** : son approche d'auteur (0,1317 m) ne descend jamais sous le rayon de support (0,0236 m), donc sa penetration nulle est ENTRAINEE par la distance, non lue sur une lecture en portee ; chestR descend a 0,0165 m sous un support de 0,0424 m, sa base EST une lecture. Les deux natures sont publiees separement. **5. AUCUNE MECANIQUE NE REPOUSSE : §33 est MESUREE, elle n'est pas APPLIQUEE.** La fenetre mediale n'est posee que dans le bloc de MESURE (`jak-hd-physics.gc:2367-2412`) ; `phys-skin-chain`, la seule contrainte de non-traversee, lit toujours la population de CORPS. Sa clause « shall collide or repel » n'a donc **aucun mecanisme**, et sa clause de RESTITUTION (0,00-0,15, nominal 0,06) reste **NON ETABLIE** faute d'un contact resolu a mesurer. **6. AU REPOS LE DOMAINE EST VIDE** (0/480 lectures en portee, surfaces a 0,1326 / 0,1410 m) et c'est desormais publie comme tel. Le cycle precedent en tirait **`TENUE`** — un verdict sur un domaine vide, exactement le faux vert que la regle 2 interdit : la garde de vacuite portait sur `n` (TOUTES les lectures) au lieu du domaine EN PORTEE, donc `n = 480 > 0` la laissait passer et la ligne sortait `domaine=0/480 -> TENUE`. Corrige ce cycle. **CYCLE 63 — LES DEUX CHAINES BOUGENT, EN SENS OPPOSES, ET JE REFUSE L'UPGRADE QUE LA LETTRE DE LA REGLE 2 M'AUTORISERAIT.** Le correctif de cote de §12 (voir §7 et §12) deplace la compression sur le sein du cote gravite ; mesure sur la meme fenetre `run` : chestL **+0,0238 -> +0,0320 m** (DEPASSEE, +34 %) et chestR **+0,0106 -> +0,0000 m** (TENUE). Une chaine conforme sur deux ferait `PARTIELLE` au sens mecanique de la regle 2 — **je ne l'ecris pas** : le zero de chestR repose sur **6 lectures en portee sur 66 960**, c'est-a-dire sur un domaine si mince qu'il ne distingue pas « ne penetre plus » de « n'a pas regarde ». Monter un statut sur un domaine qui se retrecit est la forme meme du faux vert que la garde de vacuite du cycle 62 vient d'interdire. La section reste ROUGE, et la reserve (c) du cycle 62 — les points sondes ne sont pas choisis pour la MEDIALITE — tient. |
| 34 | « Chest restitution 0.00-0.05, nominal **0.02** » (l.408) ; « Collision energy should primarily become deformation... **not bounce** » (l.410) | **PARTIELLE** | **CYCLE 61, SECOND TEMPS — LA GATE PASSE SUR LES DEUX CHAINES.** `ROOM-SKINPEN` 0,0692 / 0,0868 m contre un plancher d'AUTEUR pris sur la MEME fenetre, les memes frames, les memes maillons et la meme fonction (0,0612 / 0,0883 m). C'est la premiere fois que la question « la physique enfonce-t-elle la peau au-dela de la pose d'auteur » reçoit une reponse dont les deux termes viennent de la meme population — le plancher precedent etait le maximum d'une fenetre de 120 frames compare a une course de 16 740, et il faisait **echouer la gate meme avec la physique entierement desarmee**. Restitution 0,0215 sur 26 contacts, dans sa bande. **PARTIELLE ET PAS TENUE** : chestL depasse son propre plancher de +0,0079 m (regle 2 : une seule chaine conforme = PARTIELLE), et `reste` — la pire violation qui survit aux six passes de correction, mesuree par une 7e qui ne corrige pas — vaut encore 0,0347 m : la contrainte ne ferme pas partout et le dit elle-meme. `meshpen` monte sur chestR (0,1019 -> 0,1424) et c'est ATTENDU : c'est un DEPLACEMENT invariant au rayon, pas une profondeur, et la contrainte deplace le joint. **CYCLE 63 :** `ROOM-SKINPEN-VERDICT` chestL **0,0692 -> 0,0701** (plancher d'auteur 0,0612 inchange, donc `physique` +0,0079 -> **+0,0088 m**, toujours DEPASSEE) ; chestR **inchangee au bit** (0,0868 contre 0,0883, TENUE). La hausse de chestL est le COUT DECLARE du correctif de cote de §12 : la compression thoracique tombe desormais sur le sein du cote gravite, ce que §12 exige, et un sein comprime contre le thorax entre plus profond dans la surface. Reste PARTIELLE. **LE CONTROLE POSITIF DE CETTE LIGNE EST TOMBE PUIS A ETE REPARE DANS LE MEME CYCLE** : `ROOM-POSCONTROL` etait passe a **69,2 %** de restitution (contre 86,9 % avant), hors de la bande 75-125 %. Cause etablie au code : l'injection deplace le JOINT alors que la mesure sonde `q = joint + R(u).offset` avec un offset de 467 a 651 u — deplacer le joint FAIT TOURNER cet offset, donc le point mesure ne se deplace pas de ce qu'on injecte (meme famille que `apex-bound-reads-a-joint-not-the-apex`). Corrige en GELANT l'offset pendant la seule relecture armee : **88,4 %**, le controle tire et §33/§34 sont soutenues. **RESERVE PUBLIEE CONTRE MOI** : le mecanisme corrige predit 100 % et la mesure rend 88,4 % — 11,6 points restent inexpliques, donc l'instrument est utilisable mais pas compris. |
| 35 | « The visible tank top is a **non-supportive conforming layer** » ; support ≈ 0, compression ≈ 0, amortissement ≈ 0, retard de tissu ≈ 0 ; « the garment **follows the underlying breast surface essentially one-to-one** » (l.412-424) | TENUE PAR CONSTRUCTION | **SORT DE `NON ETABLI` AU CYCLE 64, ET LE MOTIF QUI Y ETAIT INSCRIT ETAIT FAUX.** Le registre portait « le vêtement ne suit pas le sein : 0 sommet majoritaire ». Le NOMBRE est reproductible, la PHRASE ne l'est pas : il vient de `c38_garment_overlap.py:167-183`, qui compte les sommets contenus dans la **sphère de collision `lTopStrap2`** — la BRETELLE D'ÉPAULE, rayon 157 u = 38,3 mm, centrée à **428 u = 104,6 mm de `lBoob`**, sur le flanc (x=786, z=436) quand l'apex du sein est à z≈1114. Le rapport C38E1 l'écrivait lui-même : `intersecte=non`. **DOMAINE VIDE**, même famille que le faux vert de §33 corrigé au cycle 62 — un compteur qui n'a rien regardé. **CE QUE MESURE LA MESURE NEUVE, sur le mesh LIVRE** (`keira-hd-lod0.glb`, pas le donor pré-reskin qui rend 0 par construction) : sur les **28 primitives, UNE SEULE** porte le moindre poids de sein — `prim 15`, texture **`keira-shirt`**, 389 sommets (63 majoritaires chestL, 55 chestR). **LE DÉBARDEUR EST LA SURFACE DU SEIN** : il n'existe aucune peau dessous, aucune seconde coque, aucun sommet d'indice partagé, et le maillage n'a qu'un couple `(JOINTS_0, WEIGHTS_0)` — un sommet ne peut pas porter deux pesées. Dans la région, la masse de peau va à `chest` + `lBoob` + `lBooc` et **les 13 os de vêtement (`*Strap*`) pèsent W = 0,000000**, tandis que `physics_chains.txt:89` gèle `topstrapL/R`, `botstrapL/R` : aucune chaîne de vêtement n'est simulée. Les quatre termes sont donc nuls **par IDENTITÉ DE SOMMETS**, pas par réglage, et le « one-to-one » est exact au sens le plus fort — c'est le même point. **CE QUE CETTE LIGNE NE PROUVE PAS, et je le dis plutôt que de le laisser croire** : la preuve est en pose de BIND, aucune frame n'a été jouée ; elle tomberait le jour où un solveur de tissu existerait. **ET ELLE N'EST PAS UNE VICTOIRE** (règle du 2026-08-20 00:10 : `TENUE PAR CONSTRUCTION` ne se compte jamais comme une section gagnée) |
| 36 | Ballotement secondaire 2–7 %, ~5,2 Hz, ζ 0,55–0,75 | PARTIELLE | Canal présent, bandes jamais vérifiées |
| 37 | ≥120 Hz, ≥2 sous-pas ; les transformations artificielles ne créent pas d'impulsion | **TENUE** | Sous-pas en place ; rebase des deux moitiés (rotation **et** translation) corrigé. **PRÉCISION AJOUTÉE AU CYCLE 52, et elle ne rétrograde rien** : `ns` vaut **4 en permanence** (`axo` = 1 sur les deux chaînes rend le premier membre du `or` toujours vrai à `:2757`), soit 240 Hz — donc ≥120 Hz et ≥2 sont satisfaits TOUJOURS, et 3-4 est dans la fourchette. Mais **l'ADAPTATIVITÉ que sa ligne décrit n'existe pas** : le second membre du `or`, le vrai test d'impact, est du code qui ne peut jamais changer le résultat. Écrit ici pour qu'un futur « correctif » de ce test ne croie pas agir sur un mécanisme actif |
| 38 | Preset complet recommandé — Keira Hagai (l.446-555) | PARTIELLE | **CONFRONTÉ LIGNE À LIGNE AU CYCLE 52 : le trou est comblé.** Le preset compte **74** paramètres (compte vérifié, pas estimé). Répartition : **MESURE 55** — dont **13 TAUTOLOGIQUES**, où la trace republie la constante visée (les 6 pôles de forme SUPINE/HANGING sont écrits en dur à `jak-hd-physics.gc:3509-3514` et `PHYSORI2` les relit ; les deux bandes de volume sont forcées par la normalisation en racine cubique `cvn`, donc `det` vaut 1 par construction) — **CODE-VIVANT 4**, **CODE-MORT 3**, **ABSENT 12**. Mesures réellement discriminantes : **42/74 = 56,8 %**. **LES TROIS CODE-MORT, vérifiés dans le source** : (a) `RootDeformationExponent` — `*phys-rootgr*` n'a qu'un lecteur fonctionnel, `(rlk (if (> rgr 0.0) 0 rlk0))` à `:2388`, où il sert de BOOLÉEN ; il n'est **jamais** un exposant ; (b) `MinimumSubstepsAt60FPS` — `substeps=2` est livré et parsé, aucun appelant GOAL ne le lit ; (c) `HardImpactSubsteps` — `ns = (if (or (nonzero? axo) …) 4 2)` à `:2757-2761` et `axo` vaut 1 en permanence, donc le test d'impact ne peut jamais changer le résultat. **Pourquoi PARTIELLE et pas TENUE** : 19 paramètres sur 74 (25,7 %) sans effet observable, bloc ATTACHMENT mort ou hors bande 6/6, bloc SECONDARY rouge 3/4, les deux plafonds durs de déplacement dépassés sur les deux seins |

## Cycle 66 — LES SEPT REGIMES SONT REJOUES DANS LA POSE EPINGLEE : §18 PASSE DE x5,58 A x1,50 ET CHANGE DE SENS

**AUCUN STATUT NE BOUGE ENCORE.** Ce que ce cycle apporte est la PAIRE qui manquait : les memes
quinze fenetres, dans la MEME course, avec pour seule variable declaree le nom de l'animation
epinglee. PH-REG reste intacte au bit ; PH-REGS est APPENDUE.

    pose HERITEE (PH-REG)    48,0 deg du miroir      pose EPINGLEE (PH-REGS)   7,5 deg
    `PHYSREGSPOSE ai=12 src=name` — l'epingle a pris, et elle est REVALIDEE a l'execution.

### 1. §18 — l'ecart etait la POSE, et deux montages independants le disent

    r=9  lacet modere   heritee  0,0833 / 0,4648  R = 5,580  (chestR le plus grand)
                        epinglee 0,3631 / 0,2420  R = 1,500  (chestL le plus grand)
    r=10 lacet fort     heritee  0,1679 / 0,5057  R = 3,012  (chestR)
                        epinglee 0,6224 / 0,4102  R = 1,517  (chestL)

Le cycle 65 avait obtenu la MEME conclusion par `ROOM-SYM` (R = 1,649 et 1,432, chestL le plus
grand) sur un montage entierement different. **Deux instruments, meme sens, meme ordre de
grandeur.** L'ecart de x5,79 que ce registre portait depuis le cycle 57 n'est pas une propriete du
personnage.

**ET CE QUE LA MESURE PROPRE DIT EST CE QUE CE RIG PREDIT.** Ce tableau ecrit depuis le cycle 51
que les deux racines sont a 548,078 et 548,081 u de l'axe de lacet — 5,2e-4 % d'ecart. §18 fonde
sa clause de differenciation sur « because their offsets from the torso rotational axis differ » :
**cette cause n'existe pas dans ce rig**, donc §18 y predit la quasi-egalite, et c'est ce qu'on
mesure des que la pose cesse de contaminer. La clause ne peut pas etre tenue sans DEPLACER une
racine, c'est-a-dire sans changer le RIG.

### 2. §20 devient quasi parfaitement symetrique — et reste hors bande

    r=13 roulis    heritee 0,3738 / 0,5468  R = 1,463   epinglee 0,6491 / 0,6503  R = 1,002
    r=14 bascule   heritee 0,3914 / 0,5112  R = 1,306   epinglee 0,6496 / 0,6787  R = 1,045

L'asymetrie de §20 etait de la pose. **L'AMPLITUDE, ELLE, NE L'EST PAS** : les quatre lectures
restent AU-DESSUS de la bande 0,20-0,30, et elles y montent (x2,16 a x2,26 contre x1,25 a x1,82).
§20 reste `NON TENUE`, et son defaut est desormais isole : c'est une amplitude, pas une asymetrie.

### 3. §16 : son deficit SURVIT au controle de pose — c'est un vrai defaut

    r=3 reception souple  heritee 0,1304 / 0,3215   epinglee 0,1960 / 0,2622   bande 0,30-0,42
    r=6 reception dure    heritee 0,1414 / 0,3367   epinglee 0,1812 / 0,3213   bande 0,42-0,50

Le rapport gauche/droite se resserre (x2,465 -> x1,338 et x2,381 -> x1,773), donc **la moitie
« ecart gauche/droite » de la ligne de §16 etait bien portee par la pose** — le cycle 65 avait
raison de retirer l'attribution « le solveur porte un deficit propre a chestL ». Mais les QUATRE
lectures restent SOUS leur bande dans la pose propre. **Le deficit d'amplitude de §16 est reel.**
Son COM aussi : 0,1170 / 0,1445 contre 0,25-0,35, et 0,0848 / 0,1679 contre 0,35-0,40.

### 4. §17 — L'APEX EST DANS LA BANDE SUR LES DEUX SEINS POUR LA PREMIERE FOIS, ET §17 RESTE PARTIELLE

    apex freinage fort  0,2543 / 0,2927   bande « strong 25-35% B0 » (l.252)   LES DEUX DANS
    COM  lag            0,1590 / 0,1617   bande « strong 18-27% B0 » (l.251)   SOUS x0,88 / x0,90

C'est la premiere fois qu'une clause d'amplitude de ce dossier est tenue sur LES DEUX chaines dans
une pose dont la symetrie est prouvee. **Elle ne fait pas passer §17**, et la regle 2 de ce fichier
l'interdit : la section porte DEUX clauses chiffrees et la seconde manque de 10 a 12 % sur les deux
seins. §17 reste `PARTIELLE`, et ce qui lui manque est desormais NOMME et CHIFFRE au lieu d'etre
« il manque 0,0055 B0 sur chestL ».

### 5. §14 — meme forme, moitie inverse

    COM ordinaire  0,1823 / 0,2306   bande « ordinary 15-25% B0 » (l.214)   LES DEUX DANS
    apex ordinaire 0,3209 / 0,4452   bande « ordinary 20-30% B0 » (l.215)   AU-DESSUS x1,07 / x1,48

§14 reste `NON TENUE` : son COM entre dans la bande sur les deux seins, son apex en sort sur les
deux. Une section a deux clauses ne se declare pas sur la meilleure.

### 6. §19 EST LA SEULE QUE LA POSE PROPRE AGGRAVE, ET JE LE PUBLIE

    r=12 retour   heritee 0,6423 / 0,4941  R = 1,300   epinglee 0,3086 / 0,6970  R = 2,259

chestL tombe DANS la bande (0,3086 dans 0,30-0,40) pendant que chestR monte a x1,74. C'est la
seule des onze fenetres bornees ou l'ecart gauche/droite S'ELARGIT franchement dans la pose propre.
Je n'ai pas de cause. Sur les onze : **9 se resserrent, 2 s'elargissent, 5 changent de sens.**

### 7. Ce que ce bloc n'etablit pas

Les deux passes partagent le solveur, les tables, l'operateur de pilotage et les emplacements de
lecture — mais PAS leur place dans la course. PH-REGS est APPENDUE, donc elle herite d'un autre
historique de chaine. **La pose est la seule variable DECLAREE ; elle n'est pas la seule qui
bouge.** Ce bloc autorise a REFUSER une attribution au personnage quand le sens s'inverse ; il
n'autorise pas a donner a §18 un chiffre neuf. La ligne de base de la passe epinglee, elle, est
saine et mesuree : temoin r=0 a 0,0331 / 0,0273 B0, sous le seuil de 0,10.

---

## Cycle 65 — LA POSE DE §14 A §20 EST MESUREE POUR LA PREMIERE FOIS, ET LA LIGNE DE BASE DE `ROOM-SYM` N'EN ETAIT PAS UNE

**AUCUN STATUT NE BOUGE DANS CE CYCLE.** Ce qui bouge est la QUALITE DE LA PREUVE sous six lignes,
et dans le sens qui les affaiblit. Une section ne devient pas tenue parce qu'on a mieux mesure.

### 1. `ROOM-REGPOSE` : les sept regimes sont joues a 43,8 / 48,0 deg du miroir

PH-SGN (cycle 55) et PH-SYM (cycle 56) EPINGLENT leur pose par son nom et la REVALIDENT a
l'execution. **PH-REG — la phase qui joue §14 a §20 — ne fait ni l'un ni l'autre** : elle tient la
pose que la phase precedente lui laisse, c'est-a-dire la queue de la derniere animation de la
liste, choisie par personne, et l'animation n'avance plus ensuite. L'ecart au miroir de cette
pose-la n'avait jamais ete releve.

Il l'est : `PHYSREGB`, emis au meme point de protocole que `PHYSSGNB`, sujet droit, immobile et a
`home` — et lu avec la MEME formule de reflexion que `PHYSSYMB`, pour que les trois soient
comparables.

    pose de bind (cycle 53)          0,005 deg
    pose EPINGLEE de PH-SYM          6,4 a 6,8 deg
    POSE HERITEE DE PH-REG           43,8 deg (maillon 0) · 48,0 deg (maillon 1)

Le 43,8 retombe sur les **43,4 deg** que le cycle 53 avait mesures par un tout autre chemin : deux
constructions independantes, meme nombre a 0,4 deg pres.

**CE QUE CA COUTE, ET C'EST LA REGLE DE L'OWNER DU 2026-08-20 05:20 QUI LE DIT** : « toute mesure
d'ASYMETRIE se releve dans une pose dont la symetrie est **prouvee avant la course**. Une pose
heritee n'est pas une pose choisie. » §14, §16, §17, §18 et §20 publient toutes un ecart
gauche/droite tire de ces fenetres — jusqu'a x5,79 sur §18 — et **aucune ne le declarait**. §18
etait la seule a porter la reserve ; elle vaut pour les cinq.

Le cas le plus genant est **§16**, dont la ligne conclut « le solveur porte un deficit propre a
chestL ». C'est une attribution au PERSONNAGE, prononcee sur une course dont la pose est a 44 deg
du miroir. Elle n'est pas refutee — elle n'est pas soutenue, ce qui n'est pas la meme chose et
doit se lire tel quel.

### 2. `ROOM-SYM` : sa « queue de calme » commencait par un saut de 90 a 150 deg en UNE frame

`ROOM-SYM` (cycle 56) existe pour trancher exactement la question ci-dessus. Il rendait **`NON
RESOLU` sur 8 cellules sur 8** — ce qui se lisait comme un resultat sur le personnage alors que
c'etait une propriete du montage.

La cause, etablie sur la trace du cycle 63b et dans le code, SANS RIEN RELANCER : la fenetre qui
lui sert de plancher s'ouvrait sur `physroom-hold`, donc sur `quaternion-identity!`, donc sur le
retour de l'orientation pilotee (90 deg, 150 deg, +/-90 deg) a la verticale **en une frame**.

**LA REGLE ETAIT DEJA ECRITE DANS CE DEPOT**, dans `physroom-reg-drive` : « Y ramener le sujet
D'UN COUP serait une impulsion artificielle de plusieurs milliers d'unites — precisement ce que sa
§37 interdit de generer ». PH-REG l'applique depuis le cycle 49 ; PH-SYM, ecrit sept cycles plus
tard, ne l'appliquait pas. Le ring-down n'explique rien ici : les 45 frames de `post` sont DANS la
fenetre de pilotage par construction, donc le pic sous-amorti est deja dans `apex`.

Correctif : PH-SYM recoit le meme retour doux, retrace par l'operateur de pilotage de sa PROPRE
cellule. Aucune constante neuve, aucun seuil neuf.

    cellule i=0 (lacet 90, pose SYM)   ligne de base   0,5889 / 0,5332  ->  0,0655 / 0,0285
    cellule i=3 (lacet 150, pose SYM)                  0,6444 / 0,5191  ->  0,0795 / 0,0315
    cellules en pose ASYM                              0,5449 a 0,9286  ->  0,4133 a 0,7617

**LE PLANCHER TOMBE SUR LA POSE SYMETRIQUE ET PAS SUR L'AUTRE**, et je ne me l'explique pas
entierement. Sur les cellules ASYM il reste 0,41 a 0,76 B0 d'excursion sans aucun stimulus. Une
cause plausible existe et n'est PAS etablie : dans une pose d'auteur fortement inclinee, `g_local
- g_ref` n'est pas nul, donc l'equilibre est LEGITIMEMENT deplace de la pose d'auteur — c'est ce
que §10 a §13 decrivent. Je la nomme, je ne la conclus pas.

### 3. `ROOM-SYM` peut enfin resoudre deux cellules, et elles RETOURNENT le sens de §18

Le plancher se prend desormais sur la CELLULE et non sur la PAIRE — un plancher tire a travers la
POSE est tire a travers la variable meme que ce bloc teste. **Les deux colonnes sont publiees**
(`res` de la construction du cycle 56, `resc` de la cellule) : rien n'est remplace en silence, et
je dis que j'ai change cette construction APRES avoir lu la course, pour une raison qui elle ne
depend pas de la course.

    i=0  lacet 90   pose SYM   apexL 0,36708  apexR 0,22266   R = 1,649   RESOLU
    i=3  lacet 150  pose SYM   apexL 0,61343  apexR 0,42825   R = 1,432   RESOLU

**DANS LA POSE EPINGLEE SYMETRIQUE, C'EST chestL QUI BOUGE LE PLUS (x1,65 et x1,43). DANS LA POSE
HERITEE DE PH-REG, C'EST chestR (x5,79 et x2,80).** Meme operateur de pilotage, meme profil, meme
longueur de fenetre : **la seule variable est la pose, et elle RETOURNE LE SENS de l'asymetrie.**

C'est la premiere lecture RESOLUE de la question du cycle 56, et elle suffit a interdire toute
attribution de l'asymetrie de §18 au personnage. Elle ne suffit PAS a donner a §18 sa valeur : les
deux montages different aussi par leur rampe d'entree et par le chainage des fenetres, et les
amplitudes absolues ne se recouvrent pas (0,367 contre 0,086).

### 4. §12 reste sans reponse, et cette fois la raison est nommee

Les quatre cellules laterales rendent 3 `NON RESOLU` et 1 `PLANCHER NON CALME`. La cause est
structurelle et n'est pas un defaut de reglage : **a un pole lateral de +/-90 deg, l'equilibre
sous gravite est legitimement deplace de la pose d'auteur** — c'est le contenu meme de §12. Une
ligne de base qui mesure la distance A LA POSE D'AUTEUR ne peut donc pas y servir de plancher de
bruit. §12 a besoin d'une ligne de base prise sur son propre equilibre incline, et elle n'existe
pas.

### 5. Ce que ce cycle n'a pas fait

  - **PH-REG n'est PAS rejoue dans la pose epinglee.** Ce serait le cycle suivant, et c'est ce qui
    donnerait a §14, §16, §17, §18 et §20 des chiffres gauche/droite attribuables. Je ne l'ai pas
    fait dans le meme cycle que la mesure qui le motive : la course qui etablit le defaut et la
    course qui le corrige ne sont pas la meme, et les melanger rendrait les deux inattribuables.
  - **Le residu de 0,41 a 0,76 B0 des cellules ASYM n'a pas de cause etablie.**
  - **Aucun statut de section n'a bouge.** 2 TENUE, 5 par construction, 20 PARTIELLE, 9 NON TENUE,
    2 NON ETABLI — inchange.

---

## Compte au 2026-08-21, cycle 70

Dérivé du tableau ci-dessus, ligne par ligne, jamais recopié du bloc précédent.

- **TENUE** : **2** (§3, §37)   ·   **TENUE PAR CONSTRUCTION** : **5** (§1, §4, §5, §28, §35)
- **PARTIELLE** : **21**   ·   **NON TENUE** : **9**   ·   **NON ÉTABLI** : **1** (§10)

Total 2 + 5 + 21 + 9 + 1 = 38, aucune section omise.

**AUCUN STATUT NE CHANGE, ET C'EST LE RÉSULTAT DU CYCLE.** Ce qui change est la QUALITÉ de la
preuve sous quatre sections. §14, §16 et §17 étaient mesurées avec un stimulus commandé le long des
axes du MONDE : à **11,9 deg** de la verticale du sujet pour les sauts, à **86,3 deg** de son axe
avant/arrière pour la course — la « Horizontal Acceleration and Braking » de §17 était jouée comme
une **embardée latérale**. La phase appendue PH-REGB les rejoue sur les axes mesurés du sujet.

**LE TEST QUI DÉCIDE NE COÛTE AUCUN SEUIL.** Le rig est bilatéralement symétrique à **0,005 deg**
en pose de bind. Dans une pose prouvée symétrique (PH-REGB revalide à **0,4 deg** du miroir), un
stimulus qui tombe sur le bon axe doit rendre les deux seins égaux. Mesure : **8 fenêtres sur 8**
rendent une réponse plus symétrique sur l'axe du sujet — jusqu'à **63,69 % → 1,78 %** sur le
freinage. Ce test n'était PAS pré-enregistré ; il se lit comme une observation, pas comme une
prédiction vérifiée.

**ET IL COÛTE DEUX VERTS, CE QUI EST UN GAIN.** §16 perd son unique lecture `DANS` en 57 cycles
(elle était un vert d'AXE) et §17 cesse d'être « la section la plus proche d'un vert du dossier ».
En échange, **sur les cinq fenêtres bornées les deux chaînes rendent enfin le MÊME verdict** — sur
l'axe du monde elles se contredisaient sur deux des cinq. §14, §16 et §17 peuvent donc se juger
comme une propriété du personnage et non comme un accident par chaîne.

**§8 CHANGE DE NATURE DE PREUVE SANS CHANGER DE STATUT** : son motif reposait sur une lecture du
source ; il repose désormais sur le tenseur 3×3 complet, lu pour la première fois.

**LE SOLVEUR N'A PAS BOUGÉ D'UNE LIGNE**, et c'est vérifié : les 43 254 lignes `PHYS` des phases
antérieures sont identiques au bit à celles du cycle 69, sur onze préfixes vérifiés un par un.

---

## Compte au 2026-08-21, cycle 69

Dérivé du tableau ci-dessus, ligne par ligne, jamais recopié du bloc précédent.

- **TENUE**, mesurée et dans sa bande sur les deux seins : **2** (§3, §37)
- **TENUE PAR CONSTRUCTION**, déclarée sans être comptée comme une victoire : **5** (§1, §4, §5, §28, §35)
- **PARTIELLE** : **21**
- **NON TENUE**, mesurée et rouge : **9**
- **NON ÉTABLI** : **1** (§10)

Total 2 + 5 + 21 + 9 + 1 = 38, aucune section omise.

**UN SEUL MOUVEMENT, ET IL NE VIENT PAS DU SOLVEUR.** §13 quitte `NON ÉTABLI` pour `PARTIELLE`.
Aucun terme du moteur n'a bougé ce cycle-ci ; la trace de la course est **identique au bit** à celle
du cycle précédent sur les 54 075 lignes `PHYS`. Ce qui a changé est qu'une mesure produite à chaque
course depuis des dizaines de cycles — `PHYSORI4`, la gravité par cellule dans la base de l'ancre —
**a enfin un lecteur**.

**ET IL FAUT DIRE CE QUE ÇA CORRIGE CHEZ MOI, PAS SEULEMENT CE QUE ÇA GAGNE.** J'ai écrit au cycle
67, et répété au cycle 68, que §13 était « INJOUABLE avec les opérateurs actuels ». C'était faux :
l'opérateur existait, il tournait, et sa gravité était publiée. Je l'ai cru parce que j'ai lu une
**étiquette** — le commentaire de `physroom-orient` — au lieu de la mesure qui la contredisait. Un
faux rouge coûte autant qu'un faux vert : celui-là a tenu §13 hors du registre pendant douze cycles
et a envoyé le chantier chercher un opérateur qui n'a jamais manqué.

**CE QUE LE CYCLE APPORTE SANS CHANGER UN AUTRE STATUT :**
- **§10 et §11 gagnent leur première confrontation NON TAUTOLOGIQUE.** Leur rôle était attribué par
  un argmin contre les triplets que le moteur écrit en dur — un test qui ne peut pas échouer, et le
  registre le porte comme tel depuis le cycle 64. La gravité mesurée ne passe ni par les morphs ni
  par ces constantes, et elle **désigne les mêmes cellules** (prone `i=6`, supine `i=8`) sur les
  deux chaînes. Ça ne rend aucune clause tenue ; ça retire une tautologie du dossier.
- **§7 reçoit une réserve mesurée** sur le sens de `+Z` (voir sa ligne).
- **Deux étiquettes écrites en dur sont CONTREDITES par la mesure et corrigées** :
  `ROOM-ORICTL-DIAG` publiait « supine i=6 · prone i=8 », l'inverse exact du rôle que
  `ROOM-ORICOM-ROLE` publiait **dans le même tableau**. Les chiffres étaient justes, les noms
  mentaient. Le verrou `ROOM-ORIROLE-VERROU` confronte désormais chaque affirmation de rôle écrite
  en dur au rôle mesuré, et publie les désaccords.

**UNE CRÉANCE DE CE REGISTRE À VÉRIFIER AU PROCHAIN CYCLE, ET JE LA SIGNALE PLUTÔT QUE DE LA
LAISSER DORMIR.** Le bloc du cycle 64 ci-dessous écrit que « `W0` existe (776,1 u = 189,5 mm) là où
elle n'avait aucun instrument ». `W0` n'apparaît **nulle part** dans `physics_room_table.py` ni dans
le tableau livré ; la seule occurrence du dépôt est un script hors-ligne, `c41e2_verdict.py`, qu'aucune
course ne rejoue. Les deux clauses en `% W0` (§10 migration sortante, §12 migration médiale) sont
donc, en l'état, **sans dénominateur reproductible**. À reconstruire ou à retirer du registre.

---

## Compte au 2026-08-20, cycle 64

Dérivé du tableau ci-dessus, ligne par ligne, jamais recopié du bloc précédent.

- **TENUE**, mesurée et dans sa bande sur les deux seins : **2** (§3, §37)
- **TENUE PAR CONSTRUCTION**, déclarée sans être comptée comme une victoire : **5** (§1, §4, §5, §28, §35)
- **PARTIELLE** : **20**
- **NON TENUE**, mesurée et rouge : **9**
- **NON ÉTABLI** : **2** (§10, §13)

Total 2 + 5 + 20 + 9 + 2 = 38, aucune section omise.

**UN SEUL MOUVEMENT, ET IL EST HONNÊTE PLUTÔT QUE FLATTEUR.** §35 quitte `NON ÉTABLI` pour
`TENUE PAR CONSTRUCTION` — le débardeur et le sein sont **les mêmes 389 sommets** (`prim 15`,
texture `keira-shirt`), donc les quatre termes de la section sont nuls par identité, pas par
réglage. Ce n'est pas une victoire et le registre l'interdit explicitement de l'être. Ce qui compte
davantage, c'est que **le motif inscrit ici était faux** : il extrapolait « le vêtement ne suit pas
le sein » depuis un compteur posé sur la sphère de collision de la BRETELLE D'ÉPAULE, à 104,6 mm du
sein, qui ne l'a jamais touché. **Domaine vide**, exactement la faute corrigée sur §33 au cycle 62.

**§10 RESTE `NON ÉTABLI`, ET C'EST DÉLIBÉRÉ.** Le cycle lui a pourtant donné sa propre grandeur
pour la première fois : l'instrument qui la lit sur un CENTRE DE MASSE au lieu d'un APEX était
**suspendu par sa propre garde depuis le reskin du cycle 57**, sept cycles sans que rien le dise.
Rouvert, il resserre l'encadrement de ×2,76 à ×1,30 — et la bande commence **à l'intérieur** de cet
encadrement, donc aucun verdict ne peut être prononcé. La classer `PARTIELLE` parce qu'une mesure
existe désormais serait confondre « j'ai mesuré » avec « c'est tenu » : aucune de ses cinq clauses
n'est tenue, trois sont tautologiques, une est indéterminée, une n'a pas de canal.

**CE QUE LE CYCLE A CHANGÉ SANS CHANGER UN STATUT**, et qui vaut plus que les statuts : §11 et §12
sont lues sur un COM au lieu d'un apex, `W0` existe (776,1 u = 189,5 mm) là où elle n'avait aucun
instrument, `L0` et `H0` sont déclarées NON MESURABLES avec les chiffres qui le disent (+31,7 % et
+36,6 % au test de raffinement), et **la confirmation indépendante de `B0` inscrite en §6 est
retirée : elle décrivait un mesh d'avant le reskin du cycle 57**.

## Compte au 2026-08-20, cycle 62

**CE BLOC ÉTAIT FAUX ET IL EST RECOMPTÉ.** Il datait du cycle 52 et n'avait pas suivi dix cycles de
réécritures de lignes : il annonçait §19 `TENUE` (elle est rouge depuis le cycle 49) et rangeait
§17, §30 et §31 dans le mauvais seau. Le compte ci-dessous est **dérivé du tableau lui-même**, ligne
par ligne, et les 38 sections sont présentes une fois chacune — vérifié, pas affirmé. Il concorde
avec le décompte que les DIRECTIVES portent depuis le 2026-08-20 02:50 (« 2 TENUES sur 38 »).

- **TENUE**, mesurée et dans sa bande sur les deux seins : **2** (§3, §37)
- **TENUE PAR CONSTRUCTION**, déclarée sans être comptée comme une victoire : **4** (§1, §4, §5, §28)
- **PARTIELLE** : **20** (§2, §6, §7, §9, §11, §12, §15, §17, §21, §24, §25, §26, §27, §29, §30,
  §31, §32, §34, §36, §38)
- **NON TENUE**, mesurée et rouge : **9** (§8, §14, §16, §18, §19, §20, §22, §23, §33)
- **NON ÉTABLI** : **3** (§10, §13, §35)

**CYCLE 63 — UN SEUL MOUVEMENT, ET C'EST LE PREMIER DEPUIS LE CYCLE 57 QUI VA VERS LE VERT.**
§7 `NON TENUE` -> `PARTIELLE` : la clause du miroir est corrigée au code et mesurée tenue sur les
deux chaînes (179,749 deg -> 0,251 deg), la 3e clause reste non jugée. §12 ne change PAS de statut
et c'est délibéré — sa clause structurante passe de **violée** (l'aplatissement tombait sur le sein
OPPOSÉ à la gravité) à **tenue et mesurée** (4/4 cellules latérales), mais ses deux clauses
chiffrées restent l'une indéterminée et l'autre sans dénominateur. **Un correctif réel qui ne fait
pas bouger un statut se dit quand même** : le taire donnerait l'impression que le cycle n'a rien
produit, et l'écrire vert donnerait l'impression que §12 est finie.

**ET UN ROUGE APPARU PUIS REFERMÉ DANS LE MÊME CYCLE, QUI N'EST PAS DANS CE TABLEAU PARCE QU'IL
N'EST PAS UNE SECTION :** le contrôle positif `ROOM-POSCONTROL` est tombé à 69,2 % de restitution
(bande 75-125 %) parce qu'il déplaçait le JOINT pendant que la mesure sonde `joint + R(u).offset`.
Corrigé en gelant l'offset sur la seule relecture armée : **88,4 %**, il tire de nouveau et §33/§34
sont soutenues. Le mécanisme corrigé prédit 100 % : **11,6 points restent inexpliqués**, et c'est
écrit sur la ligne de §34 plutôt que tu : l'instrument est utilisable, il n'est pas compris.

Total 2 + 4 + 19 + 10 + 3 = 38. **DEUX mouvements ce cycle, et tous deux vers le ROUGE — ce sont
des trous de MESURE qui se ferment, pas de la physique qui se dégrade** (le solveur est resté
bit-identique, cf. §33). §33 `PARTIELLE` -> `NON TENUE` : elle n'était `PARTIELLE` que par emprunt à
`skinpen` (le THORAX, §34) faute d'avoir un domaine à elle ; elle en a un, et il est rouge sur les
deux chaînes. §7 `NON ÉTABLI` -> `NON TENUE` : son repère n'avait jamais été mesuré parce que le
seul de ses trois axes qui porte une clause chiffrable — le latéral sortant — n'était pas publié ;
publié, il montre **le même vecteur sur les deux seins** là où §7 exige qu'il soit miroir. Le reste
de l'écart avec l'ancien bloc n'est pas un mouvement : c'est une erreur de comptage qui se corrige.

**LES DEUX ROUGES DE CE CYCLE ONT LA MÊME FORME, ET ELLE MÉRITE D'ÊTRE NOMMÉE :** dans les deux cas
la grandeur qui aurait dénoncé le défaut existait dans le moteur et n'était pas PUBLIÉE — l'axe 0 du
trièdre pour §7, la surface du sein opposé pour §33. Ce qui les a masqués n'est pas un solveur
fautif mais un instrument muet, et dans les deux cas un SCALAIRE tenait lieu du vecteur (`sja` pour
§7, le joint pour §33) en donnant l'apparence d'une mesure.

Total 3 + 4 + 20 + 7 + 4 = 38 sections, aucune omise.

**CYCLE 61 — LES DEUX SECTIONS SONT PASSÉES PAR `NON ÉTABLI` AVANT DE REVENIR À `PARTIELLE`, ET LE
DÉTOUR EST LE TRAVAIL.** Premier temps : §33 quitte `NON TENUE` et §34 quitte `PARTIELLE` pour
`NON ÉTABLI`. Les deux portaient un
rouge chiffré (« la physique enfonce la peau de 7 à 9 cm ») tiré d'un estimateur dont ce cycle
démontre, par deux voies indépendantes, qu'il ne mesure pas ce que son nom dit : `|sd| <= |p-q|`
place le maximum des DEUX colonnes à plus de 12 cm du moindre échantillon de peau, et un
raffinement du maillage à densité triplée déplace ce même maximum de 30 % sans qu'un bit du solveur
bouge. **Retirer un rouge non soutenu coûte autant que retirer un vert non soutenu** : les deux
envoient le chantier suivant au mauvais endroit.

Second temps, le même cycle : l'estimateur est **refait** (moyenne pondérée des 8 plus proches
plans, noyau nul au K-ième — continu, robuste, rayon adapté à la densité locale), ce qui rend la
grandeur lisible pour la première fois ; puis `phys-skin-chain` est **armée en livraison** sous un
plafond de déplacement qui la rend inerte au repos par algèbre. Les deux sections reviennent à
`PARTIELLE`, la gate COLLIDE passe sur les deux chaînes, **et le coût mesuré est nul** (`tipvar`
-0,2 % / +2,4 %). Elles ne montent PAS à `TENUE` : chestL dépasse encore son propre plancher de
+0,0079 m.

**CYCLE 62 — §33 ET §34 SE SÉPARENT, ET ELLES NE PORTENT PLUS LE MÊME VERDICT.** Le domaine de §33
(contact sein↔sein) n'est plus vide : la surface du sein OPPOSÉ est chargée comme une population par
chaîne, l'exclusion de soi est structurelle, et la section est **mesurée pour la première fois**.
Elle sort donc de l'ombre de §34 — dont le verdict repose sur `skinpen` contre le THORAX — et prend
le sien : **§33 `NON TENUE`** (les deux chaînes enfoncent la peau dans le sein opposé de +0,0238 et
+0,0106 m au-delà de la pose d'auteur), **§34 `PARTIELLE`** (inchangée, `skinpen` identique au
chiffre près). Deux sections, deux verdicts, jamais fondues sur une ligne commune.

**ET DEUX FAUX VERDICTS SONT RETIRÉS, UN DE CHAQUE SIGNE.** (a) Au repos, §33 publiait `TENUE` sur
un domaine de **0 lecture en portée** — la garde de vacuité testait `n` (toutes les lectures) au lieu
du domaine EN PORTÉE, seul capable d'écrire une pénétration. Un zéro tiré d'un domaine vide est le
faux vert le plus facile à produire. (b) Sur la course, le verdict `DEPASSEE` était publié alors que
le contrôle positif y était `NON EVALUABLE` par construction (injection de 200 u fixes contre une
approche de 47 u) : le contrôle tirait au repos, là où il n'y a rien à mesurer, et manquait sur la
course, là où on mesure. L'injection est passée en **fraction** de l'approche, et les quatre cellules
tirent maintenant à 0,0-0,1 % sur une plage de 12,4x.

**DEUX MOUVEMENTS CE CYCLE, ET AUCUN N'EST UN GAIN DE PHYSIQUE — ce sont deux trous d'INSTRUMENT
et de DOSSIER qui se ferment.** §26 `NON ÉTABLI` -> `PARTIELLE` (sa mesure existait, son motif de
classement était périmé) et §38 `NON ÉTABLI` -> `PARTIELLE` (74 paramètres confrontés un par un
pour la première fois). Les `NON ÉTABLI` tombent de 7 à 5. **Le solveur n'a pas bougé d'un bit ce
cycle : 37 995 lignes de mesure identiques, une seule ligne différente, et c'est le garde-fou de
numéro de phase.**

## Cycle 60 — LE PERIMETRE A CHANGE EN COURS DE CYCLE, ET LES TROIS LIGNES QUE LA NOUVELLE GATE EXIGE SONT CONSTRUITES

**Ce qui s'est passe.** `.autoport/DIRECTIVES.md` et le validateur ont ete REECRITS par le
superviseur a 13:19, pendant que la premiere course tournait. La version acceptee et le
`SCOPE-SERIAL` sont inchanges (`v3fee554599`, serial 8) — la tentative n'est donc pas invalidee,
c'est le CHANTIER qui change. **`meshpen` ne porte plus aucun verdict** ; §33/§34 se jugent
desormais sur `skinpen` contre sa **ligne de base au repos**, et « NON ETABLI FAIT ECHOUER ». Le
controle positif passe d'un RATIO a une **prediction quantitative** : injecter X doit faire monter
la mesure de X, a 25 % pres, l'exces comme le defaut etant un echec.

**Consequence immediate, appliquee : j'ai arrete par PID exact le correctif de solveur que j'avais
prepare** (mettre la collision en derniere operation de la frame, [NOTE-153]) **avant qu'il tourne**
— il visait `meshpen`, qui ne decide plus rien, et il aurait deplace le solveur pendant que je
construis des instruments. La note reste au dossier pour le cycle qui voudra la reprendre.

### Ce qui est livre, et pourquoi chaque piece existe

**1. La ligne de base au repos ([NOTE-154]).** `ROOM-SKINPEN-REST` = la profondeur sous la peau du
point que **l'auteur** a dessine — « physique desarmee » au sens exact, puisque la pose d'auteur EST
la pose sans physique. Elle est prise **a la meme frame, sur la meme surface, pour le meme lien**,
et pas dans une fenetre de repos separee : comparer le maximum d'une fenetre au maximum d'une AUTRE
est le piege `ratio-of-two-statistics`. L'offset anatomique — l'os de poitrine est interieur de 0,13
a 0,16 m par construction du rig — se retranche donc exactement.

**2. Le controle d'integrite qui decide si cette ligne est lisible.** `skinout` compte les lectures
qui placent le point d'AUTEUR **dehors**, ce qui est anatomiquement impossible. **Si ce compte est
non nul, le tableau REFUSE de publier `ROOM-SKINPEN-REST` sous le nom que la gate lit** : elle reste
NON ETABLI et elle echoue. Je ne fais pas verdir une gate sur un instrument dont j'ai mesure qu'il
se trompe de cote. Le soupcon vient d'une mesure, pas d'une intuition : la premiere course rend
`skinadd` = 1052,0 / 938,9 u la ou la plus grande deviation de joint jamais mesuree au dossier vaut
**301 u** (`|tp|` = 0,5008 B0), alors que `skinadd <= |A - S|` SERAIT une identite si `phys-surf-sd`
etait lipschitzienne. Elle ne l'est pas : c'est une SDF de **nuage de points** filtree par une phase
large (`|p - os| < bsr + 512`), donc deux points distants de 0,2 m peuvent etre notes contre des
ensembles d'os differents.

**3. Le controle positif, reecrit sur DEUX defauts mesures ([NOTE-155]).**
  - **il contaminait l'etat** : l'injection etait posee EN PLACE dans `*phys-px*`, qui est la
    position PORTEE d'une frame a l'autre (Verlet), pas une variable de frame. Les deux branches ne
    comparaient donc pas deux mesures mais deux TRAJECTOIRES, sur deux fenetres d'animation
    differentes de surcroit. La sonde est desormais **appariee** : meme frame, mesure sans puis
    avec, position **restauree au bit** entre les deux ;
  - **elle n'injectait pas le defaut mesure** : elle poussait vers l'ANCRE, direction sans rapport
    avec le gradient de profondeur — **110,85 u rendus pour 400 u injectes, soit 27,7 %**. Elle
    pousse maintenant le long de la normale RENTRANTE du volume ou le lien est deja le plus
    enfonce, c'est-a-dire exactement « de la profondeur inadmissible ».

**4. Un cliquet corrige en chemin.** `*phys-skinpen*` n'etait remis a zero **qu'une fois** : les huit
tags emis apres `run` publiaient tous le meme maximum courant — **644,2134 / 638,9550 a l'identique**
sur self-*, side-*, cone-* et prox-*. Huit fenetres, deux nombres. **Portee honnete : aucun verdict
ne lisait ces huit tags**, donc corriger ne change aucune conclusion existante ; c'etait un
instrument faux qui publiait dans le vide, pas un faux vert.

**5. Ce que la gate qui echoue toujours cachait — troisieme occurrence, et c'est une bonne
nouvelle.** `ROOM-POSCONTROL` sort par `die`, donc IDLE, ANIM et DISCRIMINANT n'avaient jamais ete
evaluees. Evaluees a la main sur la trace livree : **IDLE maxdev 0,0002** (plafond 1,0), **ANIM 2/2
respectees, perchain=yes**, **DISCRIMINANT 41 % / 43 %** (plancher 25 %). Les trois passent. Les
seules gates rouges sont les deux verdicts de COLLIDE et `OPEN-DEFECTS`.

### Les deux resultats, mesures

**Le controle positif est REPARE : 80,0 % de restitution contre 27,7 %.** `PHYSPC injections=321
armed=623,77 disarmed=303,84 inject=400,00` — hausse mesuree **319,93 u pour 400 u injectes**, dans
la bande 75-125 % que l'arbitrage pose. `ROOM-POSCONTROL` etait rouge depuis le cycle 15 ; il ne
l'est plus, et le critere qui le declare vert est **plus dur** que le ratio qu'il remplace.

**La ligne de base est REFUTEE par son propre controle d'integrite, et je la retiens.** `skinout`
= **41 842** lectures placent le point d'AUTEUR dehors. Preuve sans aucun taux, sur la frame du
maximum : `skinadd` = 1052,01 u et `-sd(simule) <= skinpen max` = 556,15 u, donc
**`sd(auteur) >= 495,87 u DEHORS`** alors que `skinrest` le mesure a **411,38 u SOUS** la peau —
erreur de signe de **0,221 m**. Le tableau publie la valeur sous `ROOM-SKINPEN-REST-NON-ETABLIE`
(0,1004 / 0,1039 m) et **pas** sous le nom que la gate lit. §33/§34 restent donc **NON ETABLI**, ce
qui les fait ECHOUER.

**Le solveur n'a pas bouge la ou ca compte** : 14 444 lignes de trace avant les fenetres de
controle, ZERO differente ; les 310 lignes `PHYSROW` (meshpen, tipvar, rootdev, jump) identiques ;
`worstres` 456,7879 / `worstci` 39 identiques. Les 207 lignes qui different sont TOUTES des
compteurs CUMULES traversant la fenetre armee — consequence directe et attendue du fait que
l'injection a CESSE de contaminer cette fenetre. Ma prediction P3 disait « zero ligne differente » :
elle est **REFUTEE telle qu'ecrite**, et je ne la reinterprete pas.

### Et la suite du cycle : la ligne de base que la gate exige n'est PAS CALCULABLE sur cette donnee

Trois courses de plus, trois hypotheses posees et **les trois refutees par la mesure suivante** :
  1. « le point d'AUTEUR est le mauvais point de reference » — non : construite sur la fenetre de
     REPOS (`physroom-hold`, desarmement CHIFFRE par `PHYSIDLE dev` = 0,4721 / 1,0232 u), la mesure
     rend `chestL skinpen = 0,0000` et `chestR = 417,23 u`. Le point SIMULE a le meme defaut ;
  2. « la phase large ecarte l'ensemble le plus proche » — non : passee en branch-and-bound EXACT
     (la marge inventee de 512,0 disparait), `skinmiss = 0` sur les deux chaines et `chestL` lit
     toujours 0,0000 ;
  3. « la peau est tronquee » — la trace disait `sets=64/92`, donc **28 ensembles de surface sur 92
     etaient jetes** ; releve a 96, `sets=92/92`… et les valeurs sont **identiques**.

**LA CAUSE EST DANS LE MODELE DE DONNEES, ET ELLE EST DELIBEREE.**
`physics_c14_meshsamples.py:563` exclut de la surface-obstacle tout os qui est un MAILLON DE
CHAINE (« ceux-la ont des `ms`, pas des `bs` »). Les seins sont les seules chaines simulees :
**leur propre peau ne peut donc jamais apparaitre dans la surface que `phys-surf-sd` lit.** Le
fichier livre le confirme — 84 des 92 ensembles portent **12** echantillons, et aucun ne s'appelle
`lBoob`, `rBoob`, `lBooc` ni `rBooc`. Le point de peau le plus proche d'un joint de poitrine est
l'un des 12 echantillons de `chest`, repartis sur tout le buste ; que `chestR` lise « dedans » et
`chestL` « dehors » est un accident de lequel de ces 12 points est le plus proche.

**CONSEQUENCE, ET C'EST UNE DECISION DE SUPERVISEUR.** La lecture de `chestL` se contredit
elle-meme entre deux fenetres — 0,0000 m au repos, 0,1358 m en course, soit 0,136 m d'ecart que le
deplacement du joint (borne a 301 u = 0,073 m) ne peut pas produire. Le tableau REFUSE donc de
publier `ROOM-SKINPEN-REST`, et §33/§34 restent **NON ETABLI**, donc rouges. Je ne publie pas un
plancher dont je viens de mesurer qu'il est faux — ni pour faire passer la gate, ni pour la faire
echouer proprement. Trois garde-fous le tiennent, chacun avec sa mesure : `skinmiss > 0`,
`sets < declared`, et l'incoherence repos/course.

**CE QUI DEBLOQUERAIT LA SECTION** : que la surface lue par le moteur CONTIENNE la peau des seins —
soit en changeant ce que `bs` represente, soit en portant la mesure sur les `ms`, qui existent
deja. Les deux touchent un jeu de donnees que d'autres sections lisent (§18 en particulier), donc
je ne le change pas de ma propre initiative en fin de cycle.

### JAMBE 6 — §33/§34 DEVIENT MESURABLE, ET LA MESURE EST ROUGE

Le trou etait **cote GOAL seul** (correction : le C++ expose `msample` depuis le cycle 14, je
l'avais nie a tort en cherchant `msurf`). Le GOAL les charge, et `skinpen` porte desormais sur la
PEAU de la chaine — ses sommets extremaux — au lieu du JOINT, qui est interieur par construction et
ne peut pas repondre a une question de surface.

    chaine    repos (physique desarmee)   course     ajoute par la PHYSIQUE
    chestL          0,0351 m              0,1052 m         **+0,0701 m**
    chestR          0,0498 m              0,1398 m         **+0,0900 m**

**L'instrument est coherent avec lui-meme** : au repos, lecture SIMULEE et lecture d'AUTEUR
coincident a **0,13 u / 0,37 u** pour des profondeurs de 144 et 204 u. La contradiction de la
version « joint » (chestL DEHORS au repos, 556 u DEDANS en course) a disparu. `skinmiss = 0`,
`sets = 92/92`.

**§33 reste NON TENUE, mais pour la premiere fois avec la bonne grandeur** : la physique enfonce la
peau des seins de **7 a 9 cm** sous la surface du corps au-dela de la pose d'auteur, ce que sa §33
interdit mot pour mot. Ce n'est plus un `NON ETABLI` — la gate juge.

**Statut de §33 et §34 : inchange** — `NON TENUE` et `PARTIELLE`, sur la meme penetration declaree a
chaque cycle. Ce cycle ne fait pas bouger la physique d'un bit ; il rend le verdict **mesurable**,
ce qui etait le blocage nomme par l'arbitrage.

## Cycle 56 — LE MONTAGE APPARIÉ N'A PAS DE CONTRASTE. §18 RESTE NON LISIBLE. §12 SURVIT.

Une phase neuve (`PHYSROOM-PH-SYM`, 33) joue les mêmes stimuli dans **deux poses épinglées par
leur nom, dans la même course**, ordre des jambes équilibré. Les deux épingles prennent et sont
revalidées à l'exécution : **6,7 / 6,8°** du miroir (symétrique) contre **123,4°** (asymétrique),
identiques à 0,1° près sur les quatre cellules de chaque jambe.

**CE QUI ÉCHOUE, ET C'ÉTAIT ÉCRIT AVANT LA COURSE.** La jambe asymétrique rend un écart
gauche/droite d'apex de **×1,027** et **×1,019** — aucun contraste. Le montage n'a rien à séparer :
**ce cycle NE DIT RIEN de §18**, et je ne lis pas la jambe symétrique seule. C'est la branche (b)
de ma prédiction P3. **Et je dis ce qui va contre moi** : la pose à 123° rend ×1,02 quand celle à
6,7° rend ×1,39–1,97, soit l'ordre INVERSE de l'hypothèse « la pose porte l'écart ».

**TROIS RAISONS, TOUTES MESURÉES PAR MES PROPRES ÉMETTEURS, ET LA PREMIÈRE TUE LA PRÉMISSE :**
1. **les deux jambes n'ont pas reçu le même stimulus** (×2,3 et ×2,6 — `stim` 8,20/6,80 contre
   17,27/18,85, et 20,94/18,15 contre 49,01/53,40). Cause : le **bras de levier de rotation diffère
   d'un facteur 59** entre les deux poses (`cex` = −13895,6 contre −234,4 u, soit 3,39 m contre
   0,06 m). Pour un lacet, **le levier EST le stimulus**. Épingler une autre animation ne change pas
   que la symétrie : ça déplace le squelette dans l'espace de l'acteur ;
2. **la jambe la plus excitée travaille là où le plafond mord** (apex 0,370–0,420 B0 contre le
   plafond 0,42/0,50 de §22) : une réponse proche de son plafond aplatit tout rapport vers 1 ;
3. **rien n'est résolu** — voir le point suivant.

**P6 EST DÉCLARÉE VIDE, PAS GAGNÉE.** La queue de calme s'ouvre par un retour à l'identité **en une
frame** depuis une rotation de 90–150° : elle mesure ce retour de manivelle, pas le plancher de
l'instrument. Mesuré, `res` = 0,348 à 0,646 B0 pour des apex pilotés de 0,110 à 0,437 — **le
plancher est plus grand que le signal**, donc les huit rapports sont « NON RESOLU » par
construction. Le test de vacuité était dans l'adjudicateur **avant** que la course produise une
seule ligne (commit `49e35370ff`).

**TROIS DÉFAUTS DE CONCEPTION DE MA PROPRE PHASE**, tous trouvés par ses instruments : le plancher
ci-dessus ; les cellules de §12 qui mesurent le transitoire au lieu de l'équilibre (`sx` n'est pas
touché, c'est pourquoi §12 reste lisible) ; et le levier qui suit la pose.

**P2 EST ROUGE ET LE TEST FAUTIF EST LE MIEN, DEUX FOIS** : il comparait des lignes de log
horodatées qui ne peuvent jamais coïncider, et j'ai annoncé « 8 lignes ajoutées sous un tag
existant » alors que `physroom-set-anim` en émet **24 sous trois tags** (`PHYSANIMLEN`,
`PHYSREMAP`, `PHYSREMAPORPHAN`). Le cycle 55 écrivait « ma liste d'exclusions était courte d'un
tag » — **j'en avais deux de moins, en ayant lu son rapport.** La substance, publiée comme un
contrôle SÉPARÉ et non comme un sauvetage : sur les lignes de mesure, **une seule** a changé de
valeur (`PHYSROOM-PHASEGUARD maxwork=32→33`, changée exprès) et **zéro valeur de mesure** n'a bougé.

**ÉTAT DU VALIDATEUR, VU POUR LA PREMIÈRE FOIS DERRIÈRE LA PORTE HUMAINE** (sonde en lecture seule,
le validateur n'est pas touché) : SYNC, CLEAN, SCOPE, TUNING, MOVE, ROOM, IDLE, ANIM, DISCRIMINANT
**toutes vertes** — quatre d'entre elles n'avaient **jamais** été évaluées, masquées par `COLLIDE`,
lui-même masqué par `OPEN-DEFECTS`. **Il reste UN seul rouge technique dans tout le validateur : la
pénétration de la poitrine, 0,1115 m contre un plafond de 0,0005 (§33/§34).** Le prochain chantier
n'a plus à être deviné.

**DÉFAUTS DE DOSSIER CORRIGÉS** : le tableau de la salle était périmé de **deux courses** (empreinte
du log du cycle 53 alors que 54 et 55 avaient livré) — corrigé **au point de production**, le
runner dérive maintenant le tableau et vérifie l'empreinte DANS le fichier écrit ; le ×1,06 du
cycle 55 requalifié **sous la résolution** ; le « §32 prescrit 2–5 % » retiré de §18 (ce sont des
bandes de **paramètres**) ; et `OWNER-VERIFY-QUEUE.md` purgé des deux chiffres retirés le 19/08
(l'organe « de 73 cm », et la ligne « §22 voudrait 21-25 % » qui n'existe pas).

## Cycle 55 — L'ÉCART GAUCHE/DROITE ÉTAIT UN ARTEFACT DE POSE : ×3,41 -> ×1,06

La pose des fenêtres de PH-SGN est **épinglée** à `assistant-village2-idle-hut-breath`, retrouvée
PAR SON NOM et **revalidée à l'exécution** : 6,7° du miroir parfait (contre 43,4° avant).

    écart gauche/droite, apex vertical, k=0 :  ×1,06 (s=+1)  ×1,17 (s=−1)   — il valait ×3,41

**Et la raison est géométrique, pas une coïncidence.** Les deux os font désormais le même angle
avec le pilotage (**22,3° / 21,8°** au lieu de 2,03° / 41,77°), donc les deux chaînes sont
confisquées pareil : écart de confiscation **0,039 / 0,176** (critère ≤ 0,30). Le mécanisme
prédit dans les DEUX poses : mesuré ×2,05–2,73 contre ×2,64/×2,70 prédits, témoins négatifs
×0,95–1,19 contre ×1,00–1,08 prédits.

**ET ÇA EXPLIQUE LE RÉSIDU DU CYCLE 53** : la sur-prédiction d'un facteur ~6 sur chestL arrivait
à **2,03°**, où `sin θ = 0,035` et `1/sin` explose — le modèle était évalué au bord de sa
singularité. À 22°, il tombe juste à 20 % près. Il n'était pas faux, il était lu là où il ne vaut
rien.

**CONTRÔLE** : zéro ligne de mesure changée ; une ligne AJOUTÉE (`PHYSANIMLEN a=12`), émise par
l'épingle elle-même — ma liste d'exclusions était courte d'un tag et je le dis plutôt que
d'élargir le filtre après coup.

## Cycle 54 — UNE POSE SYMÉTRIQUE EXISTE, ET CELLE QU'ON TIENT EST LA 3e PIRE SUR 31

Les 31 animations de Keira sont échantillonnées au **même point de protocole**, donc le classement
est comparable. Écart au miroir parfait, os de racine : **min 4,0° · médiane 34,3° · max 125,5° ;
5 poses sur 31 sont sous 10°**. La meilleure, `assistant-village2-idle-hut-breath`, est symétrique
sur LES DEUX maillons (4,0 / 5,4°). **Celle que la salle laisse en place —
`assistant-firecanyon-idle-down` — est à 124,1°, rang 29 sur 31.**

**MAIS L'ASYMÉTRIE EST UNE PROPRIÉTÉ DE LA FRAME, PAS DE L'ANIMATION**, et ça va contre la
facilité : la MÊME animation rend 124,1° à la frame échantillonnée ici et **43,4°** à la frame que
la salle fige ensuite (cycle 53). « Choisir une meilleure animation » ne suffit donc pas — il faut
ÉPINGLER une paire (animation, frame) et vérifier sa symétrie avec l'émetteur ajouté ici.

**CE QUI RESTE NON LISIBLE, ET CE N'EST NI TENU NI RÉFUTÉ** : §32, §18, §12 et l'écart
gauche/droite que j'ai publié au cycle 52 sont tous mesurés dans cette pose. Les rejouer dans une
pose épinglée symétrique DÉPENSERA le contrôle d'identité au bit — c'est exactement ce pour quoi
il faut le dépenser. **CONTRÔLE : zéro ligne différente** sur 38 575 (émetteur purement additif).

## Cycle 53 — LE MÉCANISME EST QUANTIFIÉ, ET LA POSE TENUE PAR LA SALLE N'EST PAS SYMÉTRIQUE

**LE MÉCANISME.** `phys-length-chain` est une projection d'ÉGALITÉ sur la sphère : elle retire la
composante ALIGNÉE avec l'os, donc la part qui survit vaut `sin(theta)`. Mesuré (nouvel émetteur
`PHYSSGNB`, relevé sujet droit et immobile) : l'os de racine de chestL est à **2,03°** de l'axe
vertical poussé et à **88,10° / 89,30°** des deux autres.

                              prédit par 1/sin      MESURÉ
    chestL VERTICAL               ×28,22            ×3,79 / ×4,99
    chestR VERTICAL               ×1,50             ×1,58 / ×1,30
    chestL avant-arrière          ×1,00             ×0,99 / ×1,00
    chestL latéral                ×1,00             ×1,04 / ×0,92

Sur chestR et sur **les deux témoins négatifs**, le modèle tombe juste à 8 % près : l'attribution
du cycle 52 devient un mécanisme qui PRÉDIT. Sur chestL il **sur-prédit d'un facteur ~6**, et ce
n'est pas expliqué (le canal radial de §23 en rend ×1,59, pas le reste).

**ET CE QUI CONTREDIT LE CYCLE 52.** Le rig est bilatéralement symétrique à **0,005°** en pose de
bind (mesuré sur le mesh livré). **La pose que la salle TIENT ne l'est pas : 43,4° d'écart au
miroir parfait.** C'est un repos de Fire Canyon (`assistant-firecanyon-idle-down`) laissé par la
phase d'animation, et toutes les phases suivantes le tiennent. L'écart gauche/droite ×3,41 publié
au cycle 52 est donc, pour une part non chiffrée, un artefact de LA POSE — pas du personnage.
**Cela vaut aussi pour §32, §18 et §12, toutes mesurées dans cette pose.** Rien n'est invalidé ;
rien ne peut plus être lu comme une propriété du personnage avant une course en pose symétrique.

**CONTRÔLE : ZÉRO ligne différente** sur 37 995 lignes de mesure, `PHYSBONE` compris — le seul
changement de moteur est un paramètre ajouté à un accesseur, appelé avec `comp = -1` par son
unique appelant existant. Moteur à 4800 lignes exactement, le plafond.

**LES DEUX DÉFAUTS D'INSTRUMENT DU CYCLE 52 SONT CORRIGÉS ET VÉRIFIÉS.** Rampe d'entrée : `stim`
de la première fenêtre passe de 1255,82 (×74) à **17,00**, la médiane exacte. Double passe à ordre
inversé : le RANG déplace la lecture de **2,58 % au pire, 0,16 % en médiane** — les asymétries de
sens de 11 à 30 % du cycle 52 ne sont donc pas des artefacts de rang, et sa section 5 tient.

## Cycle 52 — LA RÉPONSE PAR SENS : LA CONTRAINTE DE LONGUEUR EST NOMMÉE, LE MUR EST EXONÉRÉ

**CE QUE LE CYCLE 51 AVAIT LAISSÉ OUVERT.** Il avait mesuré que la réponse dépend du SENS du
stimulus, refusé de nommer la cause faute de l'avoir mesurée, et désigné la grandeur à
instrumenter. Une phase neuve (`PHYSROOM-PH-SGN`) joue 36 fenêtres — 6 ablations × 3 axes × 2 sens
— à amplitude STRICTEMENT identique au signe près, sur axe isolé.

**CE QUI REND LA MESURE DÉCIDABLE SANS SEUIL CHOISI.** Pour un système linéaire, et pour toute
non-linéarité SYMÉTRIQUE (le `tanh` de §21, une borne sur une NORME, une raideur cubique), la
réponse à `-u` est exactement l'opposée de la réponse à `+u`. Les deux écarts publiés valent donc
zéro par PROPRIÉTÉ, pas par convention.

**LE RÉSULTAT PRINCIPAL, ET CE N'EST PAS CELUI QUE JE CHERCHAIS.**

    chestL, axe VERTICAL, contrainte de longueur EN PLACE : 0.0462 B0
    chestL, axe VERTICAL, contrainte de longueur LEVÉE    : 0.2311 B0   -> ×5.01
    LA MÊME ablation, LA MÊME chaîne : avant-arrière ×0.98, latéral ×0.92

Le contrôle négatif est DANS le tableau : une ablation qui ne déplace QU'UN axe ne « retire pas la
seule restriction, donc tout grandit » — le piège que le cycle 28 avait eu raison de refuser. Le
plancher est donné par la course elle-même : k=2 est inerte ici et reproduit k=0 à **0,356 %** près
sur 10 cellules séparées de douze fenêtres.

**LE MUR DE COLLISION EST EXONÉRÉ, ET C'ÉTAIT MA MISE ÉCRITE AVANT LA COURSE.** Le désarmer déplace
la réponse de **0,1 % en médiane**, et de **×1,00 exactement** sur l'axe vertical des deux chaînes.
C'était le seul terme unilatéral PAR NATURE du solveur. Il ne porte pas ce défaut.

**L'ÉCART GAUCHE/DROITE, contre les 2-5 % de §32** : vertical ×3.41 tel que livré, ×1.13 quand la
contrainte de longueur est levée — c'est donc elle qui le porte. **Et ce n'est pas une affaire de
longueur d'os** : `PHYSBONE` donne 1040.50/140.42 (chestL) contre 1039.03/144.23 (chestR), soit
0,14 % et 2,7 % d'écart. La cause du ×5.01 contre ×1.30 n'est PAS établie ; l'instrument qui
manque est la direction MONDE de l'os par chaîne.

**CE QUE L'INSTRUMENT A TROUVÉ CONTRE LUI-MÊME.** Le contrôle de stimulus (P6) a attrapé que la
PREMIÈRE fenêtre de la phase reçoit ×74 le stimulus des autres — `PH-SGN` succède à `PH-REG` sans
rampe d'ENTRÉE. Cette cellule portait le plus gros chiffre du tableau ; le premier jet du lecteur
publiait `P3 TENUE` et `P7 TENUE` dessus, et c'est corrigé avant publication. **P3 et P7 sont donc
INDÉCIDABLES et ne sont comptées ni tenues ni réfutées.** La ligne de base prévue (P5) est elle
aussi réfutée, et pour une faute de conception : la rampe de RETOUR est une impulsion de même
amplitude et le calme la suit immédiatement.

**CE QUE CE CYCLE NE CONTREDIT PAS.** Le cycle 51 avait déclaré réfutée la thèse « la contrainte de
longueur confisque le vertical ». Il testait une PART DE DIRECTION sur des régimes non appariés ;
sa réfutation tient. Ce cycle mesure une AMPLITUDE à stimulus égal sur axe isolé. Une réponse peut
être à la fois faible en amplitude et peu verticale en direction : les deux mesures répondent à des
questions différentes.

## Cycle 51 — LE CANAL D'APEX EST OUVERT : SEPT SECTIONS LE BORNENT, RIEN NE LE PUBLIAIT

**CE QUE C'ETAIT, ET POURQUOI CA BLOQUAIT SIX SECTIONS.** §14, §16, §17, §18, §19, §20 et §22
bornent toutes un « apex displacement » en % B0. Aucun canal de la salle n'en publiait un. §19
n'a **que** cette clause : son COM était mesuré et ne répondait à aucune de ses lignes. Le
registre du cycle 49 le désignait comme « le plus gros trou d'instrument » ; il est comblé.

**LE CONTROLE EST TOTAL, ET C'EST LUI QUI AUTORISE A LIRE LE RESTE.** Les **37 191 lignes de
mesure** de la course sont IDENTIQUES à celles du cycle 50 — même md5, zéro ligne différente. Le
solveur n'a pas bougé d'un bit : tout ce qui change ici est de l'INSTRUMENT. Le bloc `lc` de
l'écriture n'a délibérément PAS été refactorisé pour appeler la nouvelle fonction, alors que
cela aurait économisé 21 lignes sous un plafond qu'il a fallu payer autrement — déplacer une
expression flottante qui alimente `comex`, `ee`, `jt` et le COM aurait mis CE contrôle en jeu
contre rien.

**CE QUE LE CANAL APPREND, ET C'EST UN SEUL FAIT STRUCTUREL PLUS TROIS VERDICTS.**

1. **§19 SORT DE `NON ETABLI` ET ELLE EST TENUE** — les quatre lectures dans [0,30 ; 0,40] sur
   les deux seins, plus la traversée du neutre qu'elle exige. Première section gagnée depuis le
   cycle 37. **Le verdict dépend d'une DUREE que j'ai choisie (0,40 s) et sa spec n'en donne
   aucune : c'est déclaré sur sa ligne, pas en note de bas de page.**

2. **§30 EST RETROGRADEE EN `NON TENUE` SUR UNE CLAUSE QUE RIEN NE MESURAIT.** Sa spec écrit
   « Apex — minimal direct anchoring ». Le mesh livré met **41 à 43 % de la masse de la région
   distale sur `chest`**, qui n'est pas simulé. L'apex est donc plafonné à 0,5676 / 0,5936 de ce
   que ses maillons produisent, **quelle que soit la physique**.

3. **ET CE PLAFOND SEPARE, POUR LA PREMIERE FOIS, LE DEFAUT DE MAILLAGE DU DEFAUT DE DYNAMIQUE.**
   Sur §14, §17 et une lecture de §18, le manque à la bande est INFERIEUR au plafond d'ancrage :
   la repesée seule pourrait les fermer. Sur **§16 la réception, le manque vaut ×1,73 à ×4,22
   contre un plafond de ×1,76** : sur trois des quatre lectures **l'ancrage NE SUFFIT PAS**, et
   il reste un facteur 1,9 à 2,4 que seul le solveur porte. C'est le premier chiffre du dossier
   qui dise où la repesée s'arrête et où la dynamique commence.

4. **§22 : le plafond GLOBAL d'apex est dépassé (+9 % / +11 %) alors que SIX des sept bandes de
   régime sont tenues ou SOUS.** Ce qui sature n'est donc aucun geste de sa spec, mais les
   balayages longs `jerk`/`accel` — la leçon du cycle 49 (« la réponse est gouvernée par la DURÉE
   du geste ») confirmée sur une grandeur indépendante.

5. **§15 : la clause de traversée du neutre est DEMONTREE** (3 des 4 fenêtres de vol). Elle était
   `NON DEMONTREE` par défaut d'INSTRUMENT, pas de moteur : le vecteur du COM n'était relevé qu'à
   l'argmax de sa norme, une seule frame, qui ne peut ni l'établir ni l'exclure.

**LE CONTROLE DE L'INSTRUMENT LUI-MEME, ET IL N'EST PAS UNE TAUTOLOGIE.** Les bandes de sa propre
spec impliquent un rapport apex/COM de ×1,19 à ×1,35 (§14 30/25, §16 30/25, §17 25/18, §18 20/17,
§20 20/15). Mesuré sur les 30 fenêtres de régime : **médiane ×1,154, étendue ×0,899 à ×1,396** —
et l'unique lecture sous 1,0 est la fenêtre TEMOIN, où les deux grandeurs valent 0,02 et où un
rapport ne veut rien dire. Deux sources indépendantes — la géométrie du mesh livré passée dans le
solveur d'un côté, la table de bandes écrite par l'owner de l'autre — s'accordent sur ce rapport.
C'est ce qui distingue ce canal d'un instrument qui republierait sa cible (le quatrième faux vert
du cycle 49, §11).

**CE QUE CE CYCLE NE PRETEND PAS.** L'élongation directionnelle de §14, §16, §17, §18 et §20
reste NON MESUREE : aucun canal ne la publie par régime. §17 et §18 ne donnent PAS de bande
d'apex pour leur régime modéré — les lignes le disent au lieu d'inventer une bande. Et rien de ce
cycle n'est visible à l'écran : le comportement livré est identique au bit.

## Cycle 50 — §12 : LE PREMIER CORRECTIF DE SOLVEUR DE LA SERIE, ET IL EST MESURE AVANT/APRES

Le cycle 49 était de l'INSTRUMENT et le prouvait au bit. Le cycle 50 touche le SOLVEUR, donc ce
contrôle est **dépensé**, et l'avant/après se publie au lieu d'être revendiqué :

- **`row` de la salle : 257 lignes sur 310 bougent.** Écart médian sur `tipvar` **0,88 %**,
  p95 13,0 %, max 94,4 % (une fenêtre). Par pilotage : `updown` 0,08 %, `leftright` 0,86 %,
  `tilt` 1,21 %, `accel` 1,83 %, `jerk` 3,51 %. La propagation vient de l'ÉTAT : les fenêtres
  s'enchaînent sans retour complet au repos, donc une fenêtre `tilt` modifiée décale la suite.
- **`meshpen` monte de 0,1061 / 0,0898 à 0,1115 / 0,1019 m** (+5,1 % / +13,5 %), sous le plafond
  de 20 % que la prédiction P4 s'était fixé — mais **elle monte, et c'est un coût, pas un détail.**
  `tipvar` monte aussi, de 0,1720 / 0,1738 à 0,1756 / 0,1775 (+2,1 %).
- **La prédiction P1 est RÉFUTÉE** : j'avais annoncé les neuf fenêtres de régime à quaternion
  identité IDENTIQUES AU BIT, en raisonnant sur l'application instantanée (`gxc` = 0 debout, donc
  mélange inchangé). **J'avais oublié l'ÉTAT** : la phase de régime s'exécute APRÈS le balayage
  d'orientation, que le correctif modifie légitimement. Résidu mesuré : chestL inchangée à quatre
  décimales sur 8 fenêtres sur 9, chestR de 0,05 % à 1,35 %. Le raisonnement était juste sur la
  fonction et faux sur l'historique.

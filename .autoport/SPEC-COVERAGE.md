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
| 6  | `L0` `W0` `H0` `B0` `P0` ; `B0` ≈ 115–125 mm ; « derive normalized dimensions directly from the character mesh » (l.122-123) | PARTIELLE | `b0=602 u` = 14,7 cm livre, **confirme independamment au cycle 48** : l'etendue du nuage de chair sur l'axe anatomique vaut 597,9 / 598,3 u = 0,99 B0 (`probe_c48_com_identity.py`). **`P0` est desormais mesure** (centroide pondere par maillon, en espace bind). `L0`/`W0`/`H0` toujours non mesures, et `B0` reste +17,6 % au-dessus de la bande de controle 115-125 mm |
| 7  | Repère local | NON ÉTABLI | Aucune mesure du repère lui-même |
| 8  | « Normal movement: 98–101 % of neutral volume » ; « Conceptually `Sx·Sy·Sz ≈ 1`, **but the whole breast shall not be represented by one affine scale transformation** » (l.136-146) | **NON TENUE** | **SORT DE `NON ÉTABLI` AU CYCLE 53, ET C'EST UNE RÉTROGRADATION : la clause STRUCTURELLE est mesurée et elle est violée par le mécanisme même qui « conserve » le volume.** (a) La clause NUMÉRIQUE est **TAUTOLOGIQUE** : `jak-hd-physics.gc:3516-3519` calcule `det = sx0·sy0·sz0` puis `cvn = 1/det^(1/3)` par itération de Newton, et `:3558-3560` multiplie LES TROIS échelles par `cvn`. Le déterminant est donc forcé à 1 **par construction** — mesuré sur la course : **390 lectures, toutes dans [0,999900 ; 1,000000]**, une étendue de 1e-4. Publier « 98-101 % tenue » là-dessus serait le quatrième faux vert du dossier (§11, cycle 49) sous un autre costume : l'instrument republierait sa cible. (b) La clause STRUCTURELLE est **VIOLÉE** : `*phys-dfm*` est `(new 'global 'inline-array 'matrix PHYS-SC)` — **UNE matrice par chaîne**, donc le sein EST représenté par une seule transformation affine, exactement ce que la ligne interdit en gras. Et le volume est conservé PAR le rééchelonnement global que la même ligne prohibe. Ce que la section demande à la place (« root tissue moves little; intermediate tissue redistributes; distal tissue deforms most ») est la même exigence que §31, elle-même `NON TENUE` pour une cause de RIG (axe d'os à 78° de l'axe anatomique) |
| 9  | Etat debout neutre = 1,00 sur tous les axes ; « Once settled, however, the original authored standing shape shall be **restored exactly**. » (l.160-161) | PARTIELLE | **RETROGRADEE cycle 48, meme cause que §2.** L'erreur statique est bien a 0,0001 — mais la clause « restored **exactly** » porte sur l'etat APRES mouvement, et `ROOM-SHFLOOR` y lit un plancher non nul sur 9 axes sur 12. Le `t01` de §27 est CENSURE par ce plancher meme, ce qui relie les deux lignes |
| 10 | « Forward projection −25 to −35%, `SupineProjectionScale = 0.70` » ; largeur ×1,23 ; hauteur ×1,09 ; « COM toward thorax: 18–28% B0 » ; « Outward COM migration per breast: 4–10% W0 » (l.165-169) | NON ÉTABLI | **RAISON CORRIGÉE cycle 49 — l'ancienne était fausse, et ce qui la remplace est pire.** Le régime EST joué (`PHYSROOM-PH-ORI`, 9 orientations dont ±90° en tangage ET en roulis, 18 lignes `ROOM-ORI` mesurées). Mais les trois échelles que §10 borne **ne sont pas une mesure** : `jak-hd-physics.gc:3511-3517` mélange barycentriquement CINQ triplets ÉCRITS EN DUR, dont `1.230/1.090/0.700` qui EST §10. Comparer `ROOM-ORI` à sa bande, c'est comparer une constante à elle-même — reconstruit à la main depuis `gx/gy/gz`, l'écart au publié est de **1e-4**. L'attribution du rôle « supine » (`physics_room_table.py:508-534`) est un argmin-L1 contre ces mêmes constantes : **elle ne peut pas échouer**. La clause COM est **INDÉTERMINÉE** — borne inférieure squelettique 0,1317/0,1243 (SOUS), borne supérieure d'apex 0,3633/0,3291 (AU-DESSUS), la bande 0,18-0,28 est entre les deux. `W0` n'a **aucun** instrument (0 occurrence dans le tableau) : la clause en % W0 n'a pas de dénominateur |
| 11 | « Static COM displacement: 20–28% B0, nominal 24% B0 » ; « Root-to-apex length: +18 to +26%, `HangingLengthScale = 1.23` » ; transitoire ~+30% ; largeur ×0,90 ; épaisseur ×0,91 (l.178-182) | PARTIELLE | **RÉTROGRADÉE cycle 49 — FAUX VERT.** Le TENUE reposait sur `HangingLengthScale = 1.23` « portée par le tenseur ». Or `1.230 / 0.900 / 0.910` sont **écrits en dur** (`jak-hd-physics.gc:3513-3517`) comme le pôle « back » du mélange : le moteur COMMANDE la constante de la spec et `ROOM-ORI` la republie. Le tableau le disait lui-même en tête (« CE QUE CE N'EST PAS : la déformation VUE sur le mesh. C'est ce que le solveur COMMANDE ») — **c'est le registre qui a sur-lu le tableau.** La seule clause chiffrable indépendante, le COM 20-28 % B0, est **INDÉTERMINÉE** : borne inférieure 0,1290/0,1551 (SOUS), borne supérieure 0,4268/0,4106 (AU-DESSUS). Ce qui reste une vraie mesure est le transitoire — rapport 1,082/1,105 contre 1,057 exigé, et un RAPPORT est immunisé contre un facteur commun |
| 12 | « The breasts shall **not** behave identically » (l.189) ; « Global lateral COM response: 15–24% B0 » ; migration médiale 10–18 % W0 ; aplatissement −15 à −25 % (l.189-194) | PARTIELLE | **CORRIGÉE AU CODE, cycle 50 — la clause structurante est désormais SATISFAITE.** Elle était mécaniquement impossible : `(wlt (fabs gxc))` donnait le même triplet aux deux seins. **Et retirer le `fabs` n'aurait pas suffi** — `PHYSAXW` et `PHYSTRI` sont IDENTIQUES sur les deux chaînes (même ancre `chest`), donc `gxc` est le MÊME nombre pour les deux : un poids signé aurait distingué les deux POSES en continuant à donner le même triplet aux deux SEINS. Ce qui discrimine les chaînes est `PHYSAXNAME sja` = **+754,9434 / −754,9434** (même module, signe opposé), et l'engin nomme sa ligne latérale par la direction où les deux seins sont SÉPARÉS — rapport |sja|/|sjb| = 84 000:1, un invariant anatomique. Le correctif applique l'aplatissement AU SEUL côté gravité (`wlt = max(0, gxc·signe(sja))`), le côté opposé recevant le pôle NEUTRE déjà livré. **Aucun chiffre n'est inventé** : §12 ne donne d'échelle qu'au côté gravité et donne au côté opposé une MIGRATION que la dynamique produit déjà. MESURÉ : l'écart gauche/droite sur `sx` passe de **0,34 % à 18,98 %** (pôle i=2) et de 0,29 % à **19,14 %** (pôle i=4), **et il s'inverse entre les deux pôles** — exactement un sein s'aplatit, et c'est celui du côté gravité. Repos inchangé (i=0 : 1,000 sur les deux chaînes). **CE QUI RESTE OUVERT** : (a) la clause COM 15–24 % B0 est INCHANGÉE et toujours indéterminée, parce que le triplet pilote le tenseur de déformation (la PEAU) et ne déplace aucun joint — `ROOM-ORICOM-MASS` est identique au chiffre près ; (b) « medial migration 10–18 % W0 » reste sans instrument, `W0` n'est mesuré nulle part ; (c) ~~quelle pose physique charge la ligne « latérale » du solveur est une question OUVERTE~~ → **FERMÉE AU CYCLE 56, PAR UNE MESURE.** `physroom-orient` sur l'**axe 0 à ±90°** met la gravité à **|gx| = 0,9713** dans le trièdre de sa §7 (`PHYSSYM5`, publié par cellule). Le commentaire du code (`physroom-orient` : « axis 0 = tangage ») est **FAUX** ; le `lat = (2, 4)` codé en dur de l'analyseur est juste, et l'est désormais pour une raison mesurée. **ET LE MÉCANISME DE §12 SURVIT À UNE POSE ÉPINGLÉE SYMÉTRIQUE** (6,7° du miroir, revalidée à l'exécution) : l'écart d'aplatissement `sx` vaut **+17,10 %** au pôle +90 et **+17,48 %** au pôle −90, **et il s'inverse** (chestL 1,041 > chestR 0,877 à +90 ; 0,822 < 0,979 à −90), pendant que la gravité lue s'inverse exactement (∓0,9713). L'asymétrie de §12 n'est donc **PAS un artefact de pose** : elle est armée par `sign(sja)`, un invariant de RIG — **l'attribution du correctif du cycle 50 TIENT**, et c'était la prédiction qui devait me la faire rouvrir si elle tombait. Contre-épreuve dans la MÊME course : en pose asymétrique le même écart ne vaut que 7,76 / 7,36 % pour |gx| = 0,5814 — le mécanisme SUIT SON ENTRÉE. **RÉSERVE, ET ELLE EST DE MOI** : les cellules de §12 du cycle 56 ouvrent leur fenêtre AVANT l'échelon d'orientation, donc leur `apex` couvre le transitoire et n'est **pas** la grandeur d'équilibre de `PH-ORI` ; `sx`, lu instantanément en fin de fenêtre, est après établissement et n'est pas touché — c'est pourquoi lui seul est publié ici |
| 13 | « shall **not** exist as unrelated hard-coded morph targets » ; « shall vary **continuously** with the local gravity direction » ; le comportement à 45° de lean, quatre descripteurs (l.202-207) | NON ÉTABLI | **RAISON CORRIGÉE cycle 49.** Le régime EST joué (les 4 orientations intermédiaires à ±45° sont dans le balayage). (a) Le moteur EST cinq morph targets codés en dur (`:3511-3517`) mais **mélangés** : « hard-coded » oui, « unrelated » non — la lettre est à moitié tenue et je ne tranche pas à ma convenance. (b) La continuité est vraie **par construction** (l'entrée est `gla` normalisée) et n'a jamais été testée comme telle. (c) La seule exigence CHIFFRABLE de §13 — les quatre descripteurs du lean à 45° — n'a **aucune ligne de verdict** dans le tableau |
| 14 | « COM lag: ordinary 15-25% B0, strong 25-32% B0 » ; « Apex displacement: ordinary 20-30% B0, strong 30-38% B0 » ; elongation +7 a +18 % (l.214-216) | **NON TENUE** | **REMESUREE AU CYCLE 57 SUR LE MESH RECUIT.** Le plafond d'ancrage qui bornait cette ligne est LEVE (§30 : l'apex passe de 43/41 % soude a 6/5 %), et les os n'ont PAS bouge — les mesures au niveau des JOINTS (`tipvar`, `rootdev`, `meshpen`, `jump`) sont IDENTIQUES AU BIT entre les deux courses, sur les cinq pilotages. Tout l'ecart ci-dessous est donc ce que la PEAU herite, attribue sans ambiguite. Gain mesure sur les 30 lectures de regime : mediane **x1,68** (x1,42-1,86), contre **x1,657 / x1,609** predits cote mesh. **Apex ordinaire** : chestL **0,2491 DANS** (etait 0,1492, SOUS x0,75) · chestR **0,4683 AU-DESSUS x1,56** (etait 0,2806, DANS). **Apex fort** : chestL **0,2987**, au plancher exact de la bande (SOUS x1,00 ; etait 0,1723) · chestR **0,3964 AU-DESSUS x1,04** (etait 0,2392). **LE DEFAUT A CHANGE DE SENS ET C'EST LE FAIT DU CYCLE** : chestL etait SOUS ses deux bandes et y entre ou les effleure ; chestR les DEPASSE desormais. Aucun regime n'a les deux seins dans la bande, donc la section reste rouge — mais pour la raison INVERSE de celle d'avant. DUREES EMPLOYEES, ET ELLES SONT DE MOI (cycle 49) : 15 frames / 0,25 s et 15 frames / 0,45 m. L'elongation reste NON MESUREE |
| 15 | « shall **not use character speed alone** » ; « jump apex → breast may **cross neutral position** » (l.224-230) | PARTIELLE | **LA CLAUSE DE TRAVERSEE EST DEMONTREE, cycle 51 — elle ne l'était pas faute d'INSTRUMENT, pas faute de moteur.** `ROOM-SPEC15-CROSS` publie les DEUX extrêmes de la composante verticale du COM sur la fenêtre, là où le vecteur n'était relevé qu'à l'argmax de sa norme (UNE frame, qui ne peut ni établir ni exclure une traversée). Mesuré : **3 des 4 fenêtres de VOL traversent le neutre** (chestR r=2 cydn 0,0597 / cyup 0,0268 ; les deux chaînes sur r=5). Les deux extrêmes sont publiés EN POSITIF parce qu'un minimum initialisé à 0 par le reset de fenêtre ne peut pas remonter et lirait 0 sur une fenêtre entièrement d'un côté — un faux vert sur la seule clause que §15 rende vérifiable. Clause « pas piloté par la vitesse » : TENUE depuis le cycle 49. **Ce qui manque pour TENUE** : les quatre descripteurs de phase de l.227-230 ne sont pas vérifiés un par un, et chestL ne traverse pas sur r=2 |
| 16 | « Strong landing COM: 25-35% B0 » ; « Very hard: 35-40% B0 » ; « Strong landing apex: 30-42% B0 » ; « Very hard / exceptional: 42-50% B0 » (l.238-245) | **NON TENUE** | **REMESUREE AU CYCLE 57 SUR LE MESH RECUIT.** Le plafond d'ancrage qui bornait cette ligne est LEVE (§30 : l'apex passe de 43/41 % soude a 6/5 %), et les os n'ont PAS bouge — les mesures au niveau des JOINTS (`tipvar`, `rootdev`, `meshpen`, `jump`) sont IDENTIQUES AU BIT entre les deux courses, sur les cinq pilotages. Tout l'ecart ci-dessous est donc ce que la PEAU herite, attribue sans ambiguite. Gain mesure sur les 30 lectures de regime : mediane **x1,68** (x1,42-1,86), contre **x1,657 / x1,609** predits cote mesh. **Reception souple** : chestL **0,1398** (etait 0,0881) toujours SOUS x0,47 · chestR **0,3228 DANS** (etait 0,1733, SOUS x1,73) — **premiere lecture de §16 DANS sa bande en 57 cycles**. **Reception dure** : chestL **0,1574** SOUS x0,37 (etait 0,0996) · chestR **0,3270** SOUS x0,78 (etait 0,1994). **CE QUE CA TRANCHE, ET C'ETAIT LA QUESTION OUVERTE DU CYCLE 51** : le manque de chestR etait bien porte par l'ancrage — il disparait des qu'on le leve. Celui de chestL ne l'etait PAS : apres un gain de x1,59 il manque encore x2,15, donc **le solveur porte un deficit propre a chestL**, et l'ecart gauche/droite sur cette section (x2,3 sur la reception souple) n'est pas un artefact d'ancrage. DUREES DE MOI : 0,23 s et 0,15 s |
| 17 | « COM lag: moderate 10-18% B0, strong 18-27% B0 » ; « Apex displacement: strong 25-35% B0, upper transient ~40% B0 » (l.251-253) | PARTIELLE | **REMESUREE AU CYCLE 57 SUR LE MESH RECUIT.** Le plafond d'ancrage qui bornait cette ligne est LEVE (§30 : l'apex passe de 43/41 % soude a 6/5 %), et les os n'ont PAS bouge — les mesures au niveau des JOINTS (`tipvar`, `rootdev`, `meshpen`, `jump`) sont IDENTIQUES AU BIT entre les deux courses, sur les cinq pilotages. Tout l'ecart ci-dessous est donc ce que la PEAU herite, attribue sans ambiguite. Gain mesure sur les 30 lectures de regime : mediane **x1,68** (x1,42-1,86), contre **x1,657 / x1,609** predits cote mesh. **REMONTEE DE `NON TENUE`, ET ELLE PASSE A DEUX CENTIEMES DE LA BANDE.** Apex du FREINAGE (la seule bande d'apex de §17) : chestR **0,2698 DANS** (etait 0,1611, SOUS x0,64) · chestL **0,2445**, SOUS x0,98 — il manque **0,0055 B0**, soit 2 % du plancher de 0,25. Une chaine conforme, l'autre au bord : PARTIELLE au sens strict du registre, et c'est la section la plus proche d'un vert du dossier. §17 ne borne PAS l'apex du demarrage, et la ligne ne lui invente pas de bande : le demarrage rend 0,5743 / 0,5336 (etait 0,3377 / 0,3150), toujours la plus forte reponse des sept regimes. DUREES DE MOI : 36 frames / 18 frames |
| 18 | « COM displacement: moderate 10-17% B0, strong 17-24% B0 » ; « Apex displacement: strong 20-30% B0 » ; « Left and right trajectories shall differ **because their offsets from the torso rotational axis differ** » (l.259-266) | **NON TENUE** | **REMESUREE AU CYCLE 57 SUR LE MESH RECUIT** (ancrage d'apex leve, os INCHANGES AU BIT). Apex du lacet FORT, seule bande d'apex de §18 : chestL **0,1794** SOUS x0,90 (etait 0,1104, SOUS x0,55) · chestR **0,5022 AU-DESSUS x1,67** (etait 0,2791, DANS). Lacet modere : 0,0857 / 0,4965 (etait 0,0515 / 0,2756). **L'ECART GAUCHE/DROITE S'AGGRANDIT AU LIEU DE SE RESORBER : x5,79 sur le lacet modere et x2,80 sur le fort**, contre x5,4 et x2,5 avant. Le gain d'ancrage est pourtant quasi identique des deux cotes (x1,66 / x1,80 et x1,62 / x1,80), donc **ce n'est pas le repesage qui creuse l'ecart : il le REVELE a plus grande echelle.** La cause que §18 invoque elle-meme (« because their offsets from the torso rotational axis differ ») reste ABSENTE de ce rig — les deux racines sont a 548,1 u de l'axe de lacet a 5,2e-4 % pres, donc **§18 predit ICI la quasi-egalite**. **ET LA SECTION RESTE NON LISIBLE POUR TOUT CE QUI EST GAUCHE/DROITE** : les deux regimes de lacet tournent toujours dans la pose ASYMETRIQUE (123,4 deg du miroir), et le cycle 56 a etabli que le stimulus RECU y differe de x2,3-2,6 entre les jambes. Ni tenue, ni refutee sur cette clause. Ce qui est neuf et LISIBLE : chestR sort maintenant par le HAUT de sa bande, ce qui rejoint le constat global de §22 |
| 19 | « Strong pitch motion may generate **30-40% B0 apex displacement** without requiring comparable local stretch » ; « the authored standing geometry is **crossed** » (l.271-279) | **NON TENUE** | **RETROGRADEE AU CYCLE 57, ET C'EST CE CYCLE QUI L'Y MET — JE LE DIS SANS L'ENROBER.** §19 etait le SEUL vert d'amplitude du dossier (quatre lectures dans [0,30 ; 0,40] au cycle 51). En levant le plafond d'ancrage de §30, les quatre lectures montent de x1,75 a x1,81 et sortent TOUTES par le haut : flexion **0,5965 / 0,6373** (AU-DESSUS x1,49 / x1,59), retour **0,5792 / 0,5896** (x1,45 / x1,47). **CE N'EST PAS UNE REGRESSION DU SOLVEUR — IL EST INCHANGE AU BIT** ; c'est la meme excursion, qui atteint enfin la peau au lieu d'etre divisee par 1,76 par la soudure au torse. **LE VERT PRECEDENT ETAIT DONC UN VERT DE COMPENSATION** : deux defauts opposes — un solveur trop energique et un maillage qui le bridait — se annulaient sur cette section. C'est exactement le mode de faux vert que ce dossier traque, et il aura tenu six cycles. La clause « crossed » reste tenue. LA DUREE EST DE MOI (0,40 s) et le verdict en depend |
| 20 | « Typical strong roll: COM 15-22% B0, apex 20-30% B0, local stretch +5 to +12% » ; « must **not** be mechanically mirrored after contact » (l.283-286) | **NON TENUE** | **RETROGRADEE DE `PARTIELLE` AU CYCLE 57, meme cause que §19 et je l'assume de la meme facon.** Roulis simple **0,3625 / 0,5506** (AU-DESSUS x1,21 / x1,84 ; etait 0,2204 DANS / 0,3150) · bascule opposee **0,5179 / 0,6010** (x1,73 / x2,00 ; etait 0,2868 DANS / 0,3425). chestL tenait la bande sur les deux fenetres et n'y est plus : les quatre lectures sont maintenant AU-DESSUS. Le gain x1,64 a x1,81 est celui de l'ancrage leve, os inchanges au bit. Stretch local : NON ISOLE par regime. DUREE DE MOI : 0,55 s |
| 21 | Saturation sur la **combinaison** `D_max·tanh(...)` | PARTIELLE | Facteur commun posé au cycle 46, mais **il ne mord presque jamais** (prouvé : trace identique au bit près) |
| 22 | « Breast COM: normal <=35% B0, hard transient <=40% B0 » (l.300) ; « Distal/apex displacement: normal <=42% B0, exceptional <=50% B0 » (l.301) ; elongation **locale** <=25 % | **NON TENUE** | **RETROGRADEE DE `PARTIELLE` AU CYCLE 57, ET C'EST LE RESULTAT LE PLUS IMPORTANT DU CYCLE.** Apex, plafonds DURS de la section : pic TYPIQUE de fenetre **0,6876 / 0,7003** contre <=0,42 -> **HORS x1,64 / x1,67** (etait 0,3984 / 0,4134, DANS) ; MAXIMUM de course **0,9249 / 0,9592** contre <=0,50 -> **HORS x1,85 / x1,92** (etait 0,5431 / 0,5553, HORS de +9 / +11 % seulement). **99,5 % et 98,9 % des fenetres** depassent 0,42 ; 98,9 % et 97,3 % depassent 0,50. **CE QUE CA ETABLIT, ET C'EST LE VRAI ACQUIS DU CYCLE 57 : LA SOUDURE AU TORSE MASQUAIT UN SOLVEUR TROP ENERGIQUE.** Elle divisait l'excursion d'apex par 1,76 / 1,68 AVANT qu'elle n'atteigne la peau, ce qui rendait des chiffres d'apparence conforme. Le solveur n'a PAS change — les mesures de JOINTS sont identiques au bit — donc cette amplitude existait deja et n'etait pas mesurable. **Le chantier bascule du MAILLAGE vers le SOLVEUR, et il est maintenant chiffre : il faut diviser l'excursion d'apex par ~1,85 sans retirer le mouvement que la §30 vient de rendre.** Corroboration independante dans la meme course : `ROOM-APEX-RATIO` donne apex/COM de mediane **x1,95** (x1,28-2,53) quand la bande implicite de la spec vaut x1,19 a x1,35 — l'apex sur-repond au COM d'un facteur ~1,5, ce qui est une sur-amplification STRUCTURELLE et non un depassement de bande. **Clause COM, relue sur une course POSTERIEURE a la correction de `comw=`** (l'ancienne valeur etait mesuree sur un mesh qui n'existe plus) : pic typique **0,3580 / 0,3353** contre <=0,35 -> chestL HORS de +2,3 %, chestR DANS ; transitoire dur **0,4758 / 0,4361** contre <=0,40 -> HORS de +19 % / +9 % (etait 0,4441 / 0,4086, +11 % / +2 %). **LE COM NE MONTE QUE DE +6,7 % ET +2,8 % LA OU L'APEX MONTE DE x1,68, ET C'EST EXACTEMENT CE QUE LA §30 DEMANDE** : le mouvement rendu est CONCENTRE sur l'apex (« Apex — minimal direct anchoring »), il ne gonfle pas l'organe en bloc. Les deux courses sont bit-reproductibles sur l'apex (30 lignes sur 30 identiques), donc cet ecart COM est attribuable au seul `comw=`. Elongation locale : deux instruments toujours en desaccord (0,124-0,157 contre 0,189-0,229) **CYCLE 58 — LE MECANISME DU DEPASSEMENT EST IDENTIFIE, ET UNE TENTATIVE EST REFUTEE PAR MESURE.** L'attribution par identite (residu 0,000170 B0 sur 372 fenetres) donne `maxima \|tp\| 0,5008 · \|rp\| 0,2313 · \|dp\| 0,4660` B0. **Le maximum de `tp` EST le plafond dur de la section au centieme pres (0,5008 contre 0,5000)** : la borne mord, et elle mord parfaitement — mais sur UN SEUL des trois termes. `dp` (le tenseur de deformation multiplie par un bras de chair de 1,0817 B0) ajoute jusqu'a 0,4660 B0 par-dessus, et **aucun des cinq sites qui appliquent 0,42/0,50 x B0 ne le voit** : les cinq lisent un JOINT (`:2744`, `:3024`, `:2816`, `phys-apex-scale :1293`, `:3648`), alors que la section nomme « Distal/apex displacement ». **TENTATIVE, MESUREE, RETIREE :** faire lire a `phys-apex-scale` le point d'apex pondere (`ax`, deja charge depuis `physics_mesh.txt`) rend la borne **DEUX FOIS PLUS FAIBLE** — `bendcut` 7245/5360 -> 2266/2214 (-69 % / -59 %), `\|tp\|` max **0,5008 -> 0,7127 B0** (le joint passe au travers de son propre plafond, x1,43), `ROOM-APEX` **0,9249/0,9592 -> 0,9664/0,9616** et `ROOM-COM` **0,4758/0,4361 -> 0,5006/0,4561** : la section visee EMPIRE sur ses DEUX clauses. Trois causes arithmetiques : les poids `ax` somment a 0,9402/0,9549 ; la somme est VECTORIELLE sur deux maillons dont les contributions se compensent ; et surtout **`dp` n'existe pas encore** au point ou la borne s'applique (le tenseur est bati a la section 5bis, APRES la boucle de contraintes). **Le joint de pointe etait donc un majorant PLUS STRICT que l'apex prive du tenseur.** Retire par `git checkout`, recompile (551 cibles) et **retrait VERIFIE par une course de controle**. REGLE : remplacer un proxy par la grandeur que la spec nomme n'est un progres que si cette grandeur est COMPLETE au point ou la borne s'applique. **§22 n'est pas bornable depuis la boucle de contraintes** ; le chantier est de la borner APRES la construction du tenseur, ou de reduire `dp` a la source. |
| 23 | « Un seul ressort à l'apex est INSUFFISANT » | **NON TENUE** | **RETROGRADEE AU CYCLE 59, SUR LA GRANDEUR QUE LE MOTEUR LIT.** Deux articulations sont bien simulées, mais les enregistrements `ax` du mesh LIVRÉ (lus par `pc-physics-chain-link-apex-mi`, jak-hd-physics.gc:797) donnent la part d'apex pilotée par le maillon DISTAL : **`ax chestL 1 = 0.0818`** et **`ax chestR 1 = 0.0000`**. À l'apex — la seule chose que cette ligne de la spec nomme — les deux chaînes sont donc des chaînes à UN ressort, à 8,2 % près à gauche et exactement à droite. La présence de l'articulation ne vaut pas sa participation : c'est le mode d'échec du 2026-08-18 08:55 (« la preuve est la RÉPARTITION, jamais la présence »), lu cette fois sur l'apex et non sur la possession de sommets. CIBLE CHIFFRÉE : `ax <chain> 1 >= 0.30` des deux côtés, sans faire sortir les cinq bandes de §30 sur l'axe anatomique. La chair simulée couvre par ailleurs 19 % de l'organe |
| 24 | 2,30 / 2,50 / 2,65 Hz par axe | PARTIELLE | Raideur dérivée pour 2,30 Hz. Le maillon distal est **sous la bande** |
| 25 | ζ = 0,35 (0,32–0,42) | PARTIELLE | Recalibrée le 2026-08-19 : l'ancien réglage l'était sur un signal saturé |
| 26 | Rebond ≈ 31 % (`FirstBounceRatio = 0.31`) | PARTIELLE | **SORT DE `NON ÉTABLI` AU CYCLE 52, ET SA RAISON ÉTAIT PÉRIMÉE, PAS SA MESURE.** Le motif inscrit (« le signal était saturé, jamais remesuré ») ne tenait plus : la colonne `rebond` de `ROOM-RINGFIT` est calculée par `_rebound()` à partir des EXTREMA BRUTS de `PHYSRINGA` — vérifié, la fonction ne prend que la série et le `zeta` ajusté n'y entre pas, donc elle **n'est pas tautologique**. Mesuré : chestL ap **0,314** / lat **0,322** ; chestR ap **0,313** / lat **0,318** — quatre lectures, LES DEUX seins, à **+0,9 % à +3,9 %** de sa cible. **Pourquoi PAS `TENUE`** : les deux canaux VERTICAUX sont NON LISIBLES (résidu d'ajustement 0,184 / 0,104 ; ils rendent 0,545 contre 0,309 selon la chaîne, donc leur série n'est pas un mode unique) — et le vertical est justement le mode que sa §24 nomme principal |
| 27 | « dominant visible response 0.3-0.6 s; secondary movement 0.6-1.2 s; mostly settled ~1.0-1.5 s; **essentially stationary ~1.3-1.7 s** » (l.350-351) | PARTIELLE | **RETROGRADEE cycle 48 — C'ETAIT UN FAUX VERT, ET SUR UNE ERREUR DE COLONNE.** §27 pose QUATRE seuils ; le TENUE lisait `t1`=1,38 s (chestR) comme « essentially stationary » alors que `t1` est le seuil a 1 %. La colonne qui repond a la clause est `t01`, et elle vaut **`>2,47` s sur LES DEUX chaines** (`ROOM-SETTLE` l.427/430) ; `t05` vaut `>2,47` sur chestL. Cause mesuree et commune avec §2/§9 : le plancher de `ROOM-SHFLOOR` **censure** `t01` sur 9 axes sur 12 |
| 28 | `k = m(2πf)²`, `c = 2ζ√(km)` | TENUE PAR CONSTRUCTION | Le moteur calcule `ω = 2π·raideur/√masse` : la relation est la forme même du code |
| 29 | Anisotropie 1,00 / 0,90 / 0,82 / torsion 0,72 | PARTIELLE | Compliance latérale mesurée 1,0294 / 0,9180 pour une cible de 0,820 |
| 30 | « **28-35% of the rear breast volume** should behave as strongly attached tissue, nominal **30%** » (l.375) ; le profil en cinq bandes (l.378-382) ; « Apex — **minimal direct anchoring** » (l.382) ; « **There shall be no hard attachment boundary.** » (l.384) | PARTIELLE | **REMONTEE DE `NON TENUE` AU CYCLE 57, ET LA CAUSE ETAIT DANS NOTRE OPERATEUR, PAS DANS LE MAILLAGE — JE RETIRE MA PROPRE PUBLICATION DU CYCLE 51.** Le registre portait « 41-43 % de l'apex est soude au torse » et un plafond de **x1.76 / x1.68 hors d'atteinte de TOUTE physique**, qui BORNAIT les verdicts de six sections. **C'ETAIT FAUX, et voici pourquoi, mesure.** L'operateur `anchor30` (`physics_c7_reskin.py:436-444`) calculait son abscisse sur `pts[-1]-pts[0]`, l'axe d'**OS** de la chaine — a **77,82 deg (chestL) / 78,15 deg (chestR)** de l'axe que la §31 DEFINIT mot pour mot (« r = 0 at chest attachment and r = 1 at distal/apex region »), et correle **NEGATIVEMENT** a lui (-0,116 / -0,292). Le MEME champ de poids rendait alors **5 bandes sur 5 DANS** lu sur l'axe d'os et **1 sur 5** lu sur celui de la spec. **PREUVE QUE L'OPERATEUR EST L'AUTEUR ET PAS UN SUSPECT** : son profil impose `0,95*(1-s)^p` avec p=1,285 PREDIT **0,4314** d'ancrage sur le decile apex anatomique de chestL contre **0,4324 MESURE** — 0,001 d'ecart. **CORRECTIF** : `axis=anat` ne change QUE la direction de l'abscisse d'ANCRAGE ; la PARTITION entre maillons reste sur l'axe de la chaine, parce que la geometrie l'impose (le maillon distal est 34,4 u / 77,5 u PLUS PRES du torse le long de l'axe anatomique). **RESULTAT, mesure sur le mesh RECUIT** : les cinq bandes passent de **1/5 a 5/5 DANS sur LES DEUX seins** (Deep 0,904/0,906 · Rear 0,747/0,735 · Mid 0,523/0,517 · Dist 0,281/0,275 · Apex 0,094/0,082). L'ancrage de l'apex tombe de **0,4324/0,4064 a 0,0598/0,0451** — DANS « minimal direct anchoring » — et le plafond d'apex, **statistique `apex_region` IDENTIQUE a celle qui avait publie 0,5676/0,5936**, monte a **0,9402 / 0,9549**. **CONTROLE A REPERE GELE** (l'axe d'`apex_region` est bati sur un centroide PONDERE, donc il se DEPLACE quand on repese, et un avant/apres naif comparerait deux populations) : sur l'axe et la region calcules sur l'ANCIEN mesh, **0,9352 / 0,9470** — le gain n'est donc PAS un artefact de deplacement d'axe. Banc hors cuisson et cuisson s'accordent au chiffre. **POURQUOI PAS `TENUE`, ET C'EST PUBLIE COMME UN COUT** : (a) `StrongRootFraction` depend du REPERE et les DEUX lectures sont publiees — **0,224 / 0,275 SOUS** la bande sur le nuage de la regle, **0,298 DANS et 0,356 au-dessus** sur le nuage de l'organe (contre 0,362 / 0,389 tous deux HORS avant, donc la clause S'AMELIORE mais chestR reste hors bande) ; (b) « no hard attachment boundary » : les aretes cassees tombent de **15 -> 5** et **22 -> 7** et se relocalisent de tout l'organe (mediane s=0,59) a la RACINE seule (mediane 0,00), ou la §30 veut justement de l'ancrage — mais ce n'est pas zero. **CETTE BAISSE N'ETAIT PAS PREDITE et je la publie comme non predite.** Les deux reperes sont MUTUELLEMENT EXCLUSIFS : sur le mesh recuit l'axe d'os rend 1/5 et l'axe anatomique 5/5, image miroir de l'etat d'avant **CYCLE 59 — LA « BARRE DES 30 % » DU CONTRAT DU 2026-08-18 N'EST PAS CETTE SECTION.** La directive du 08:55 exige « au moins 30 % des sommets de la chaîne ont le NOUVEL os pour joint majoritaire (w > 0.5), **conformément à `StrongRootFraction = 0.30` de sa §30** ». Le texte exact de §30 dit « 28-35% of the **rear breast volume** should behave as **strongly attached tissue** » : c'est la part de chair ANCRÉE AU BUSTE, pas la part de sommets possédés par l'os DISTAL — et les deux vont en sens CONTRAIRE (plus le distal possède, moins il reste d'ancre). Mesuré sur le mesh livré : `lBooc` 27/85 = **31,8 %** (au-dessus), `rBooc` 18/80 = **22,5 %** (sous). Le repesage n'est PAS fait, et la raison est mesurée : le seul balayage qui dérive cette barre (`probe_c24_distal_ownership.py`, cycle 24) calcule son `StrongRootFraction` sur l'AXE D'OS — l'axe que la directive du 2026-08-20 07:20 déclare FAUX — et prédit `rBoob=0` sommet majoritaire, c'est-à-dire un os de racine qui ne pilote plus rien. Le défaut que la barre désignait est réel et il est reporté sur la grandeur qui le nomme, à §23 (`ax <chain> 1` = 0,0818 / 0,0000). |
| 31 | « little deformation at the root; progressively increasing mobility; **largest displacement in distal tissue** » ; `w(r) = r^1.6...2.0` (l.389-390) | PARTIELLE | **REMONTEE DE `NON TENUE` AU CYCLE 57, ET JE RETIRE LA CAUSE QUE J'AVAIS INSCRITE.** Le registre affirmait : « Un gradient racine->pointe n'est donc pas exprimable par cette chaine, **quel que soit le reglage** » — declarant la section structurellement impossible a cause des 77,83/78,05 deg entre l'axe d'os et l'axe anatomique. **C'ETAIT FAUX** : le gradient ne vit pas dans la direction des OS, il vit dans les POIDS DE PEAU, et ceux-ci peuvent le porter le long de n'importe quelle direction. Mesure sur le mesh recuit, mobilite (poids porte par la chaine) par bande de la racine vers l'apex : **0,096 · 0,253 · 0,477 · 0,719 · 0,906** (chestL) et **0,094 · 0,265 · 0,483 · 0,725 · 0,918** (chestR) — **strictement CROISSANTE sur les cinq bandes, sur les deux seins**. La clause DESCRIPTIVE des trois membres de l.389 est donc TENUE, et elle etait declaree hors d'atteinte. **CE QUI RESTE HORS BANDE** : l'exposant. Ajuste par moindres carres sur `w(r) = r^n` contre le r anatomique, **n = 1,158 (rms 0,035) et n = 1,118 (rms 0,029)**, contre la bande 1,6-2,0 de la section. **ET LA CAUSE EST UNE TENSION ENTRE DEUX SECTIONS DE SA SPEC, PAS UN REGLAGE** : les trois bandes interieures de la §30 n'autorisent l'exposant d'ancrage que dans [0,831 ; 1,900], la derivation le fixe au PLANCHER 0,831, et un ancrage en `(1-r)^0,831` donne mecaniquement une mobilite en `r^~1,16`. **Tenir la §30 dans ses bandes INTERDIT l'exposant de la §31.** C'est une question ouverte sur sa spec, remontee comme telle et non tranchee a ma convenance. **AUTRE FAIT PUBLIE** : le parametre `grad` (le `RootDeformationExponent` de la §38) est **INERTE sur toute sa bande** — 1,60 / 1,80 / 2,00 rendent des comptes de sommets majoritaires IDENTIQUES. Et l'apex est desormais pilote par le maillon **PROXIMAL** (poids 0,8584/0,0818 sur chestL, **0,9549/0,0000** sur chestR) : le maillon distal ne porte RIEN de l'apex anatomique, ce que le cycle 57 avait predit d'avance (P7) et que corriger un axe d'ancrage ne pouvait pas deplacer |
| 32 | Indépendance gauche/droite ; masse ±2–4 %, raideur ±3–5 % | PARTIELLE | Les écarts de paramètres sont dans les bandes, mais bouger un sein déplace l'autre de 32 à 321 % (mesure de COUPLAGE, non touchée par le cycle 55). **CE QUE LE CYCLE 55 CORRIGE, ET C'EST MA PROPRE PUBLICATION** : l'écart gauche/droite de **×3,41** sur l'apex vertical publié au cycle 52 comme un dépassement de cette section était un **ARTEFACT DE POSE**. Épinglée à une pose bilatéralement symétrique (6,7° du miroir parfait au lieu de 43,4°), la même mesure rend **×1,06 / ×1,17**. **CORRECTION DE RÉDACTION, CYCLE 56 — CES DEUX CHIFFRES NE SONT PAS « PETITS », ILS SONT SOUS LA RÉSOLUTION.** Le tableau de la salle n'avait pas été régénéré depuis le cycle 53 ; régénéré sur la course que le cycle 55 a **réellement livrée**, il donne un plancher de répétabilité `ROOM-SIGN-REPEAT` de **2,882 %** (contre 0,462 % au cycle 53) et une dispersion de rang `ROOM-SIGN-RANK` de **5,10 %**, au-dessus du critère de 5 % que l'analyseur porte lui-même (**P6 y passe de TENUE à REFUTEE**, et personne ne l'avait lu). Un rapport de ×1,06 est donc DANS le bruit de son propre instrument, et ×1,17 à peine au-dessus. **La conclusion du cycle 55 n'en est pas affaiblie — elle en est renforcée** : l'écart ne « tombe pas à 6 % », il tombe à l'IRRÉSOLVABLE. C'est sa rédaction qui était fautive, pas sa mesure. La raison est géométrique et mesurée : les deux os y font le même angle avec le pilotage (22,3° / 21,8° au lieu de 2,03° / 41,77°), et l'écart de CONFISCATION tombe à 0,039 / 0,176. **Les autres écarts gauche/droite du dossier (§18 ×2,5 sur l'apex, §12) tournent dans des phases qui tiennent TOUJOURS la pose asymétrique : ils sont NON LISIBLES, ni tenus ni réfutés** |
| 33 | « Medial surfaces shall collide or repel **before visible interpenetration** » (l.400) ; restitution 0,00-0,15, nominal 0,06 | **NON TENUE** | `meshpen` **0,1115 / 0,1019 m** contre un plafond épinglé de **0,0005 m** — facteur **223 / 204**, INCHANGÉ par le cycle 59 et vérifié au bit (310 lignes `row` identiques, `worstres` 456.7879 / 417.4324 identiques). **LE DOMAINE N'EST PLUS VIDE ET IL EST ATTRIBUÉ** : le nouveau `PHYSCVOL max=` (cycle 59) donne, sur le maillon distal, `ci=39 rBoob` à **456.79 u** pour chestL et `ci=37 lBoob` à **366.40 u** pour chestR — le contact sein↔sein a bien un domaine, contrairement au « 0 contact sur 2978 » du cycle 7. **DEUX FAMILLES DE CORRECTIFS SONT CLOSES CE CYCLE, PAR MESURE ET PAR IDENTITÉ** : (a) « corriger le volume fautif » — le résidu est un PLATEAU, 8 volumes (chestL) et 10 (chestR) à ≥ 50 % du maximum, sur trois familles sans rapport (sein opposé, capsules de buste, sphères de vêtement) ; retirer l'argmax fait passer 0,1115 → 0,1064 m, soit **−4,6 %** ; (b) « redimensionner un volume » — `probe_c59_resize_identity.py` mesure une invariance **EXACTE** (0,0000000000 u sur 229 560 couples propres, 56 volumes livrés) de `res` par le rayon du lien ET par tout gonflement uniforme du volume, avec un contrôle négatif qui tire jusqu'à 158,93 u. `res` est la variation de la DISTANCE SIGNÉE À LA SURFACE : une grandeur de MOUVEMENT, et la borne de Lipschitz du cycle 58 est ATTEINTE (0,999999). Restitution mesurée 0,0225 |
| 34 | « Chest restitution 0.00-0.05, nominal **0.02** » (l.408) ; « Collision energy should primarily become deformation... **not bounce** » (l.410) | PARTIELLE | **La restitution EST dans sa bande : `e_moy = 0,0215`** sur 26 contacts, avec un contrôle positif qui a tiré (×12,14). Ce qui n'est pas tenu est la MÊME pénétration que §33, déclarée à chaque cycle par la ligne `BREAST-PENETRATION:` du rapport. **NEUF AU CYCLE 59** : le résidu du maillon PROXIMAL (78,87 u à gauche, 122,27 u à droite, soit ×39 et ×60 le plafond) est le seul dont le domaine admissible est PROUVÉ NON VIDE — son parent est l'ancre `chest`, qui n'est pas simulée, donc la pose d'auteur est exactement atteignable à longueur exacte et satisfait tous les volumes. Sur ce maillon-là c'est un déficit de SOLVEUR et non la géométrie. Publiée par COURSE et non par chaîne, donc « les deux seins » reste indémontré |
| 35 | Couplage vêtement (tous les termes ≈ 0 pour Keira) | NON ÉTABLI | Le vêtement ne suit pas le sein : 0 sommet majoritaire |
| 36 | Ballotement secondaire 2–7 %, ~5,2 Hz, ζ 0,55–0,75 | PARTIELLE | Canal présent, bandes jamais vérifiées |
| 37 | ≥120 Hz, ≥2 sous-pas ; les transformations artificielles ne créent pas d'impulsion | **TENUE** | Sous-pas en place ; rebase des deux moitiés (rotation **et** translation) corrigé. **PRÉCISION AJOUTÉE AU CYCLE 52, et elle ne rétrograde rien** : `ns` vaut **4 en permanence** (`axo` = 1 sur les deux chaînes rend le premier membre du `or` toujours vrai à `:2757`), soit 240 Hz — donc ≥120 Hz et ≥2 sont satisfaits TOUJOURS, et 3-4 est dans la fourchette. Mais **l'ADAPTATIVITÉ que sa ligne décrit n'existe pas** : le second membre du `or`, le vrai test d'impact, est du code qui ne peut jamais changer le résultat. Écrit ici pour qu'un futur « correctif » de ce test ne croie pas agir sur un mécanisme actif |
| 38 | Preset complet recommandé — Keira Hagai (l.446-555) | PARTIELLE | **CONFRONTÉ LIGNE À LIGNE AU CYCLE 52 : le trou est comblé.** Le preset compte **74** paramètres (compte vérifié, pas estimé). Répartition : **MESURE 55** — dont **13 TAUTOLOGIQUES**, où la trace republie la constante visée (les 6 pôles de forme SUPINE/HANGING sont écrits en dur à `jak-hd-physics.gc:3509-3514` et `PHYSORI2` les relit ; les deux bandes de volume sont forcées par la normalisation en racine cubique `cvn`, donc `det` vaut 1 par construction) — **CODE-VIVANT 4**, **CODE-MORT 3**, **ABSENT 12**. Mesures réellement discriminantes : **42/74 = 56,8 %**. **LES TROIS CODE-MORT, vérifiés dans le source** : (a) `RootDeformationExponent` — `*phys-rootgr*` n'a qu'un lecteur fonctionnel, `(rlk (if (> rgr 0.0) 0 rlk0))` à `:2388`, où il sert de BOOLÉEN ; il n'est **jamais** un exposant ; (b) `MinimumSubstepsAt60FPS` — `substeps=2` est livré et parsé, aucun appelant GOAL ne le lit ; (c) `HardImpactSubsteps` — `ns = (if (or (nonzero? axo) …) 4 2)` à `:2757-2761` et `axo` vaut 1 en permanence, donc le test d'impact ne peut jamais changer le résultat. **Pourquoi PARTIELLE et pas TENUE** : 19 paramètres sur 74 (25,7 %) sans effet observable, bloc ATTACHMENT mort ou hors bande 6/6, bloc SECONDARY rouge 3/4, les deux plafonds durs de déplacement dépassés sur les deux seins |

## Compte au 2026-08-20, cycle 52

- **TENUE**, mesurée et dans sa bande sur les deux seins : **3** (§3, §19, §37)
- **TENUE PAR CONSTRUCTION**, déclarée sans être comptée comme une victoire : **4** (§1, §4, §5, §28)
- **PARTIELLE** : **19** (§2, §6, §9, §11, §12, §15, §20, §21, §22, §23, §24, §25, §26, §27, §29,
  §32, §34, §36, §38)
- **NON TENUE**, mesurée et rouge : **8** (§8, §14, §16, §17, §18, §30, §31, §33)
- **NON ÉTABLI** : **4** (§7, §10, §13, §35)

Total 3 + 4 + 19 + 8 + 4 = 38 sections, aucune omise.

**DEUX MOUVEMENTS CE CYCLE, ET AUCUN N'EST UN GAIN DE PHYSIQUE — ce sont deux trous d'INSTRUMENT
et de DOSSIER qui se ferment.** §26 `NON ÉTABLI` -> `PARTIELLE` (sa mesure existait, son motif de
classement était périmé) et §38 `NON ÉTABLI` -> `PARTIELLE` (74 paramètres confrontés un par un
pour la première fois). Les `NON ÉTABLI` tombent de 7 à 5. **Le solveur n'a pas bougé d'un bit ce
cycle : 37 995 lignes de mesure identiques, une seule ligne différente, et c'est le garde-fou de
numéro de phase.**

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

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
| 8  | Volume 98–101 % (96–102 % en transitoire) | NON ÉTABLI | Canal de déformation présent depuis le cycle ~30, jamais mesuré contre cette bande |
| 9  | Etat debout neutre = 1,00 sur tous les axes ; « Once settled, however, the original authored standing shape shall be **restored exactly**. » (l.160-161) | PARTIELLE | **RETROGRADEE cycle 48, meme cause que §2.** L'erreur statique est bien a 0,0001 — mais la clause « restored **exactly** » porte sur l'etat APRES mouvement, et `ROOM-SHFLOOR` y lit un plancher non nul sur 9 axes sur 12. Le `t01` de §27 est CENSURE par ce plancher meme, ce qui relie les deux lignes |
| 10 | « Forward projection −25 to −35%, `SupineProjectionScale = 0.70` » ; largeur ×1,23 ; hauteur ×1,09 ; « COM toward thorax: 18–28% B0 » ; « Outward COM migration per breast: 4–10% W0 » (l.165-169) | NON ÉTABLI | **RAISON CORRIGÉE cycle 49 — l'ancienne était fausse, et ce qui la remplace est pire.** Le régime EST joué (`PHYSROOM-PH-ORI`, 9 orientations dont ±90° en tangage ET en roulis, 18 lignes `ROOM-ORI` mesurées). Mais les trois échelles que §10 borne **ne sont pas une mesure** : `jak-hd-physics.gc:3511-3517` mélange barycentriquement CINQ triplets ÉCRITS EN DUR, dont `1.230/1.090/0.700` qui EST §10. Comparer `ROOM-ORI` à sa bande, c'est comparer une constante à elle-même — reconstruit à la main depuis `gx/gy/gz`, l'écart au publié est de **1e-4**. L'attribution du rôle « supine » (`physics_room_table.py:508-534`) est un argmin-L1 contre ces mêmes constantes : **elle ne peut pas échouer**. La clause COM est **INDÉTERMINÉE** — borne inférieure squelettique 0,1317/0,1243 (SOUS), borne supérieure d'apex 0,3633/0,3291 (AU-DESSUS), la bande 0,18-0,28 est entre les deux. `W0` n'a **aucun** instrument (0 occurrence dans le tableau) : la clause en % W0 n'a pas de dénominateur |
| 11 | « Static COM displacement: 20–28% B0, nominal 24% B0 » ; « Root-to-apex length: +18 to +26%, `HangingLengthScale = 1.23` » ; transitoire ~+30% ; largeur ×0,90 ; épaisseur ×0,91 (l.178-182) | PARTIELLE | **RÉTROGRADÉE cycle 49 — FAUX VERT.** Le TENUE reposait sur `HangingLengthScale = 1.23` « portée par le tenseur ». Or `1.230 / 0.900 / 0.910` sont **écrits en dur** (`jak-hd-physics.gc:3513-3517`) comme le pôle « back » du mélange : le moteur COMMANDE la constante de la spec et `ROOM-ORI` la republie. Le tableau le disait lui-même en tête (« CE QUE CE N'EST PAS : la déformation VUE sur le mesh. C'est ce que le solveur COMMANDE ») — **c'est le registre qui a sur-lu le tableau.** La seule clause chiffrable indépendante, le COM 20-28 % B0, est **INDÉTERMINÉE** : borne inférieure 0,1290/0,1551 (SOUS), borne supérieure 0,4268/0,4106 (AU-DESSUS). Ce qui reste une vraie mesure est le transitoire — rapport 1,082/1,105 contre 1,057 exigé, et un RAPPORT est immunisé contre un facteur commun |
| 12 | « The breasts shall **not** behave identically » (l.189) ; « Global lateral COM response: 15–24% B0 » ; migration médiale 10–18 % W0 ; aplatissement −15 à −25 % (l.189-194) | **NON TENUE** | **RÉFUTÉE AU CODE, cycle 49.** Sa clause structurante est rendue **mécaniquement impossible** par `(wlt (fabs gxc))` — `jak-hd-physics.gc:3508`. La valeur absolue donne le MÊME triplet aux deux signes de gravité latérale ET aux deux seins. Mesuré : `sx` = 0,8240 / 0,8212, soit **0,34 % d'écart** là où sa spec EXIGE une différence. Clause COM : chestL 0,1283 (SOUS) / 0,1639 (DANS) ; le bloc chestR est **suspendu par son propre contrôle** (désaccord 9,73 %). Correctif désigné et chiffré : retirer le `fabs`, UNE ligne, et remesurer — non fait ce cycle pour ne pas détruire le contrôle bit-à-bit qui rend le reste lisible |
| 13 | « shall **not** exist as unrelated hard-coded morph targets » ; « shall vary **continuously** with the local gravity direction » ; le comportement à 45° de lean, quatre descripteurs (l.202-207) | NON ÉTABLI | **RAISON CORRIGÉE cycle 49.** Le régime EST joué (les 4 orientations intermédiaires à ±45° sont dans le balayage). (a) Le moteur EST cinq morph targets codés en dur (`:3511-3517`) mais **mélangés** : « hard-coded » oui, « unrelated » non — la lettre est à moitié tenue et je ne tranche pas à ma convenance. (b) La continuité est vraie **par construction** (l'entrée est `gla` normalisée) et n'a jamais été testée comme telle. (c) La seule exigence CHIFFRABLE de §13 — les quatre descripteurs du lean à 45° — n'a **aucune ligne de verdict** dans le tableau |
| 14 | « COM lag: ordinary 15–25% B0, strong 25–32% B0 » ; apex 20–38 % ; élongation +7 à +18 % (l.214-216) | **NON TENUE** | **RÉGIME JOUÉ POUR LA PREMIÈRE FOIS, cycle 49** (`ROOM-REGIME` r=1 détente ordinaire 1,18 g / r=4 détente forte 1,90 g, profils dérivés de la biomécanique, stimulus VÉRIFIÉ à l'exécution par `amax`). Ordinaire : **0,1389 SOUS ×1,08 / 0,2404 DANS**. Forte : **0,1526 SOUS ×1,64 / 0,2087 SOUS ×1,20**. Aucune des deux bandes n'est tenue sur les DEUX chaînes. Les clauses d'**apex** et d'**élongation** restent NON MESURÉES : aucun canal de la salle ne publie un apex rapporté à B0 |
| 15 | « shall **not use character speed alone** » ; « jump apex → breast may **cross neutral position** » (l.224-230) | PARTIELLE | **RÉGIME JOUÉ, cycle 49 — vol BALISTIQUE réel, l'ancre tombe à −g.** Clause « pas piloté par la vitesse » : **TENUE et discriminante** — à l'apex la vitesse du torse est nulle et l'accélération vaut −g ; un modèle piloté par la vitesse rendrait ≈ 0. Mesuré : le vol rend **0,56 à 1,32 fois** la réponse de la détente sur les quatre fenêtres (r=2/r=1, r=5/r=4), jamais un silence. Clause « traverse le neutre » : **NON DÉMONTRÉE, et mon instrument ne peut pas la démontrer** — le vecteur du COM est relevé à l'ARGMAX de sa norme, une seule frame ; il y reste négatif, ce qui n'établit ni la présence ni l'absence d'une traversée. Il faut le MAX et le MIN de la composante verticale signée sur la fenêtre : deux emplacements, un cycle |
| 16 | « Strong landing COM: 25–35% B0 » ; « Very hard: 35–40% B0 » ; apex 30–50 % ; élongation +10 à +25 % (l.238-245) | **NON TENUE** | **RÉGIME JOUÉ, cycle 49 — et c'est le plus gros rouge des sept.** Réception souple (1,51 g, 0,23 s) : **0,0836 SOUS ×2,99 / 0,1426 SOUS ×1,75**. Réception DURE (3,11 g, 0,15 s) : **0,0964 SOUS ×3,63 / 0,1746 SOUS ×2,00**. Le solveur SOUS-répond d'un facteur 1,75 à 3,63 à l'impulsion la plus violente de toute la spec. Apex et élongation : NON MESURÉS, pas de canal |
| 17 | « COM lag: moderate 10–18% B0, strong 18–27% B0 » ; apex 25–40 % ; élongation +5 à +18 % (l.251-253) | **NON TENUE** | **RÉGIME JOUÉ, cycle 49 — et cette paire EXPOSE LE MÉCANISME.** Démarrage (0,76 g **soutenu 36 frames**) : **0,2923 AU-DESSUS ×1,62 / 0,2610 ×1,45**. Freinage (1,53 g, **18 frames**) : **0,1475 SOUS ×1,22 / 0,1387 SOUS ×1,30**. Le stimulus le plus FAIBLE mais le plus LONG dépasse sa bande ; le plus FORT mais le plus COURT reste dessous. La réponse est gouvernée par la DURÉE rapportée à la période propre (26,1 frames à 2,30 Hz), pas par l'amplitude — et la spec ne donne aucune durée, donc mes durées biomécaniques portent le verdict et je le déclare |
| 18 | « COM displacement: moderate 10–17% B0, strong 17–24% B0 » ; « Left and right trajectories shall differ **because their offsets from the torso rotational axis differ** » (l.259-266) | **NON TENUE** | **RÉGIME JOUÉ, cycle 49, bras de levier VÉRIFIÉ à ×1,00** (`r_eff` 238,9 / 239,4 u contre 239,8 anatomiques). Modéré : **0,0511 SOUS ×1,96 / 0,2016 AU-DESSUS ×1,19**. Fort : **0,1019 SOUS ×1,67 / 0,2040 DANS**. Les deux chaînes diffèrent d'un facteur **3,9 et 2,0** — or sur le rig LIVRÉ leurs distances à l'axe de lacet sont ÉGALES (548,1 u chacune) : la cause que la spec invoque N'EXISTE PAS dans ce rig, et l'écart mesuré est 40 à 80 fois l'asymétrie de paramètres que sa §32 prescrit (2–5 %) |
| 19 | « Strong pitch motion may generate **30–40% B0 apex displacement** without requiring comparable local stretch » ; « the authored standing geometry is **crossed** » (l.271-279) | NON ÉTABLI | **RÉGIME JOUÉ, cycle 49** (buste en avant 70° en 0,40 s puis retour, bras de levier vérifié à ×1,01 et ×1,00). COM mesuré : flexion **0,2888 / 0,2477**, retour **0,2493 / 0,2259**. Mais **§19 ne borne QUE l'apex**, et il n'existe aucun canal d'apex : le COM ne répond pas à cette clause. La direction de la réponse TOURNE entre la flexion (dominée par l'avant-arrière, `cz` = −0,2828) et le retour (dominée par la verticale, `cy` = −0,2485), ce qui est compatible avec la traversée qu'exige la section — compatible, pas démontré |
| 20 | « Typical strong roll: COM 15–22% B0, apex 20–30% B0, local stretch +5 to +12% » ; « must **not** be mechanically mirrored after contact » (l.283-286) | PARTIELLE | **RÉGIME JOUÉ, cycle 49, bras vérifié à ×1,00 / ×0,99.** Roulis simple : **0,1917 DANS / 0,2549 AU-DESSUS ×1,16**. Bascule côté opposé : **0,2407 ×1,09 / 0,2543 ×1,16**. Une seule des quatre lectures est dans la bande. La clause de non-symétrie est **tenue** au sens littéral (les deux chaînes diffèrent de 33 % puis 6 %), mais elle porte sur le comportement APRÈS contact et rien ne sépare ici le contact du reste. Apex et stretch : NON MESURÉS |
| 21 | Saturation sur la **combinaison** `D_max·tanh(...)` | PARTIELLE | Facteur commun posé au cycle 46, mais **il ne mord presque jamais** (prouvé : trace identique au bit près) |
| 22 | « Breast COM: normal <=35% B0, hard transient <=40% B0 » (l.300) ; apex <=42/50 % ; elongation **locale** <=25 % | PARTIELLE | **MESURE EXACTEMENT POUR LA PREMIERE FOIS, cycle 48** (`ROOM-COM`, moyenne ponderee par la masse, identite du skinning lineaire verifiee a 2e-05 %). Bande **normale** lue sur le pic typique de fenetre : **0,3393 / 0,3278 B0 -> DANS** (<=0,35). Plafond **transitoire dur** lu sur le maximum de course : **0,4725 / 0,4169 -> HORS de +18 % / +4 %**, sur **0,32 % / 0,08 % des frames**. L'ancien chiffre (`comex` 0,8865 / 0,8506, « HORS BANDE x2,22 ») etait un MAXIMUM SUR 2 CENTROIDES : il surestimait de **1,88x / 2,04x**. Elongation locale : deux instruments en desaccord (0,124-0,157 vs 0,189-0,229), a trancher. Apex non isole |
| 23 | « Un seul ressort à l'apex est INSUFFISANT » | PARTIELLE | Deux articulations simulées ; la chair simulée couvre 19 % de l'organe |
| 24 | 2,30 / 2,50 / 2,65 Hz par axe | PARTIELLE | Raideur dérivée pour 2,30 Hz. Le maillon distal est **sous la bande** |
| 25 | ζ = 0,35 (0,32–0,42) | PARTIELLE | Recalibrée le 2026-08-19 : l'ancien réglage l'était sur un signal saturé |
| 26 | Rebond ≈ 31 % | NON ÉTABLI | Même cause : le signal était saturé, jamais remesuré depuis |
| 27 | « dominant visible response 0.3-0.6 s; secondary movement 0.6-1.2 s; mostly settled ~1.0-1.5 s; **essentially stationary ~1.3-1.7 s** » (l.350-351) | PARTIELLE | **RETROGRADEE cycle 48 — C'ETAIT UN FAUX VERT, ET SUR UNE ERREUR DE COLONNE.** §27 pose QUATRE seuils ; le TENUE lisait `t1`=1,38 s (chestR) comme « essentially stationary » alors que `t1` est le seuil a 1 %. La colonne qui repond a la clause est `t01`, et elle vaut **`>2,47` s sur LES DEUX chaines** (`ROOM-SETTLE` l.427/430) ; `t05` vaut `>2,47` sur chestL. Cause mesuree et commune avec §2/§9 : le plancher de `ROOM-SHFLOOR` **censure** `t01` sur 9 axes sur 12 |
| 28 | `k = m(2πf)²`, `c = 2ζ√(km)` | TENUE PAR CONSTRUCTION | Le moteur calcule `ω = 2π·raideur/√masse` : la relation est la forme même du code |
| 29 | Anisotropie 1,00 / 0,90 / 0,82 / torsion 0,72 | PARTIELLE | Compliance latérale mesurée 1,0294 / 0,9180 pour une cible de 0,820 |
| 30 | « **28-35% of the rear breast volume** should behave as strongly attached tissue, nominal **30%** » (l.375) ; « **There shall be no hard attachment boundary.** » (l.384) | PARTIELLE | Ancre mesure **45,85 % / 46,06 %** (`probe_c48_com_identity.py`, frontiere `w>0`), soit **+31 % / +32 % au-dessus du haut de bande**. Sensibilite declaree : a `w>=0,25` la part tombe a 34,52 / 34,90 %, donc **DANS** la bande — la frontiere decide, et c'est ca la mesure. Reserve : la grandeur lue est un poids de PEAU, pas un volume ARRIERE |
| 31 | « little deformation at the root; progressively increasing mobility; **largest displacement in distal tissue** » ; `w(r) = r^1.6...2.0` (l.389-390) | **NON TENUE** | **CAUSE REMPLACEE AU CYCLE 48, ET ELLE EST STRUCTURELLE, PAS UN REGLAGE.** L'axe d'os `lBoob->lBooc` est a **77,83 deg / 78,05 deg** de l'axe anatomique racine->apex, et LE LONG de cet axe le maillon distal est **34,4 u / 77,5 u PLUS PRES du torse** que le proximal. Un gradient racine->pointe n'est donc pas exprimable par cette chaine, quel que soit le reglage. L'exposant 1,6-2,0 n'est ajuste nulle part (commentaire seul) |
| 32 | Indépendance gauche/droite ; masse ±2–4 %, raideur ±3–5 % | PARTIELLE | Les écarts de paramètres sont dans les bandes, mais bouger un sein déplace l'autre de 32 à 321 % |
| 33 | « Medial surfaces shall collide or repel **before visible interpenetration** » (l.400) ; restitution 0,00-0,15, nominal 0,06 | **NON TENUE** | **CHIFFRE PERIME CORRIGE AU CYCLE 48** : le registre annoncait 0,049 m ; la course lit `meshpen` **0,1061 / 0,0898 m** et `skinpen` **0,1416 / 0,1426 m** contre un plafond de 0,0005 — soit **2x pire** que ce qui etait ecrit. Restitution mesuree 0,0225 (melange sein↔sein et sein↔thorax, jamais separee) |
| 34 | « Chest restitution 0.00-0.05, nominal **0.02** » (l.408) ; « Collision energy should primarily become deformation... **not bounce** » (l.410) | PARTIELLE | **La restitution EST dans sa bande : `e_moy = 0,0215`** sur 26 contacts, avec un controle positif qui a tire (x12,14). Ce qui n'est pas tenu est la MEME penetration que §33 (0,1061 / 0,0898 m). Publiee par COURSE et non par chaine, donc « les deux seins » reste indemontre |
| 35 | Couplage vêtement (tous les termes ≈ 0 pour Keira) | NON ÉTABLI | Le vêtement ne suit pas le sein : 0 sommet majoritaire |
| 36 | Ballotement secondaire 2–7 %, ~5,2 Hz, ζ 0,55–0,75 | PARTIELLE | Canal présent, bandes jamais vérifiées |
| 37 | ≥120 Hz, ≥2 sous-pas ; les transformations artificielles ne créent pas d'impulsion | **TENUE** | Sous-pas en place ; rebase des deux moitiés (rotation **et** translation) corrigé |
| 38 | Preset complet recommandé | NON ÉTABLI | Jamais confronté ligne à ligne au fichier livré |

## Compte au 2026-08-20, cycle 49

- **TENUE**, mesurée et dans sa bande sur les deux seins : **2** (§3, §37)
- **TENUE PAR CONSTRUCTION**, déclarée sans être comptée comme une victoire : **4** (§1, §4, §5, §28)
- **PARTIELLE** : **17** (§2, §6, §9, §11, §15, §20, §21, §22, §23, §24, §25, §27, §29, §30, §32, §34, §36)
- **NON TENUE**, mesurée et rouge : **7** (§12, §14, §16, §17, §18, §31, §33)
- **NON ÉTABLI** : **8** (§7, §8, §10, §13, §19, §26, §35, §38)

**CE QUE LE CYCLE 49 CHANGE — SEPT SECTIONS SORTENT DE `NON ÉTABLI`, ET SIX EN SORTENT ROUGES.**
Le trou de MESURE que les DIRECTIVES du 00:10 désignaient comme le chantier prioritaire est
comblé sur sa partie dynamique : les régimes de §14 à §20 sont JOUÉS, avec des stimuli dérivés de
la biomécanique et **vérifiés à l'exécution**, pas affirmés. `NON ÉTABLI` passe de 15 à 8.

**LE CONTRÔLE EST TOTAL, ET C'EST LUI QUI AUTORISE À LIRE LE RESTE.** 37 082 lignes de mesure de
la course sont IDENTIQUES à celles du cycle 48 ; la seule différence est la ligne de garde de
phase, que j'ai changée exprès. Le solveur n'a pas bougé d'un bit : tout ce qui change ici est de
l'INSTRUMENT.

**LE COMPTE DE TENUES BAISSE DE 3 À 2, ET C'EST LE QUATRIÈME FAUX VERT DU DOSSIER.** §11 était
comptée TENUE sur `HangingLengthScale = 1.23` — une constante que le moteur ÉCRIT (`:3513-3517`)
et que l'instrument REPUBLIE. Un chiffre juste et sans contenu. Le tableau le déclarait lui-même
en tête ; c'est le registre qui l'avait sur-lu.

**CE QUE LES SEPT RÉGIMES APPRENNENT, ET C'EST UN SEUL FAIT, PAS SEPT.** La réponse est gouvernée
par la DURÉE du geste rapportée à la période propre (26,1 frames à 2,30 Hz), pas par son
amplitude. Le démarrage de course — le stimulus le plus FAIBLE des sept (0,76 g) mais soutenu
36 frames — **dépasse** sa bande de ×1,45 à ×1,62. La réception dure — le plus FORT (3,11 g) mais
long de 9 frames — reste **sous** la sienne d'un facteur 2,00 à 3,63. Le solveur sur-répond au
soutenu et sous-répond à l'impulsif. Aucune bande de sa spec ne se juge donc sans la DURÉE du
geste, et sa spec n'en donne aucune : mes durées biomécaniques portent le verdict, et je le dis.

**UNE PISTE MESURÉE, PAS UNE HYPOTHÈSE DE PLUS.** Une poussée PUREMENT VERTICALE produit une
réponse dont la part verticale ne vaut que **12,2 % sur chestL** (0,0170 sur 0,1389) et 52,5 % sur
chestR. L'axe d'os est à 95,4 % / 97,9 % vertical (`ROOM-ORICOM`, ligne 1790 du tableau) et la
contrainte de longueur est DURE : elle confisque la composante du pilotage le long de l'os. La
salle porte déjà l'ablation qui le testerait (`phys-len-off-set!`, passe k=1 de PH-ORI). C'est le
contrôle positif à tirer, pas un raisonnement à publier.

**CE QUI RESTE LE PLUS GROS TROU D'INSTRUMENT : L'APEX.** §14, §16, §17, §18, §19 et §20 bornent
toutes un « apex displacement » en % B0, et **aucun canal de la salle ne publie un apex**. §19 n'a
même que ça : son COM est désormais mesuré (0,226 à 0,289 B0) et ne répond à aucune de ses
clauses. Six sections ne peuvent pas être fermées tant que ce canal n'existe pas.


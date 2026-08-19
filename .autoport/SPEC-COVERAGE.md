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
| 10 | Couché sur le dos : projection ×0,70, largeur ×1,23 | NON ÉTABLI | Régime jamais joué dans la salle de test |
| 11 | À plat ventre : longueur ×1,23, largeur ×0,90 | **TENUE** | Fermée au cycle 27, portée par le tenseur de déformation |
| 12 | Gravité latérale : asymétrie des deux seins | NON ÉTABLI | Régime jamais joué |
| 13 | Orientations intermédiaires : variation continue | NON ÉTABLI | Régime jamais joué |
| 14 | Décollage de saut : COM 15–32 % B0 | NON ÉTABLI | Régime non instrumenté séparément |
| 15 | Apex et chute | NON ÉTABLI | idem |
| 16 | Atterrissage : COM 25–40 % B0 | NON ÉTABLI | idem |
| 17 | Accélération/freinage horizontal | NON ÉTABLI | idem |
| 18 | Rotation en lacet | NON ÉTABLI | idem |
| 19 | Rotation en tangage | NON ÉTABLI | idem |
| 20 | Roulis latéral | NON ÉTABLI | idem |
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

## Compte au 2026-08-20, cycle 48

- **TENUE**, mesuree et dans sa bande sur les deux seins : **3** (3, 11, 37)
- **TENUE PAR CONSTRUCTION**, declaree sans etre comptee comme une victoire : **4** (1, 4, 5, 28)
- **PARTIELLE** : **16** (2, 6, 9, 21, 22, 23, 24, 25, 27, 29, 30, 32, 34, 36)  + (7, 26 a re-mesurer)
- **NON TENUE**, mesuree et rouge : **3** (31, 33) et l'enfoncement partage par 34
- **NON ETABLI** : les onze regimes de mouvement **§10 et §12 a §20**, plus §7, §8, §26, §35, §38

**CE QUE LE CYCLE 48 A CHANGE, ET TROIS DES QUATRE SONT DES RETROGRADATIONS.**
Le compte de TENUES passe de **6 a 3**. Ce n'est pas une regression de la physique — rien n'a bouge
dans le solveur, c'est prouve au bit pres. C'est la correction de trois statuts qui n'etaient pas
soutenus par la mesure qu'ils citaient :

  * **§27 etait un FAUX VERT sur une erreur de colonne.** Sa clause « essentially stationary » se lit
    sur `t01`, qui vaut `>2,47 s` sur les deux chaines ; le statut lisait `t1`=1,38 s.
  * **§2 et §9 lisaient le repos SANS mouvement prealable** alors que leurs deux clauses disent
    « final **settled** » et « restored **exactly** ». Apres secousse, 9 axes sur 12 ne reviennent pas.
  * **§22, a l'inverse, s'AMELIORE et c'est le resultat du cycle** : mesuree comme la grandeur que la
    spec nomme (une moyenne ponderee par la masse, pas un maximum sur deux centroides), la bande
    NORMALE est **DANS** (0,3393 / 0,3278 contre 0,35) et seul le plafond transitoire est depasse, de
    +18 % / +4 %, sur 0,32 % / 0,08 % des frames. Le rouge publie valait **1,88x / 2,04x** trop.
  * **§31 garde son rouge mais change de CAUSE** : ce n'est pas un correctif rate, c'est le rig —
    l'axe de la chaine est a 78 deg de l'axe anatomique.

**LE PLUS GROS TROU RESTE UN TROU DE MESURE, ET IL N'A PAS BOUGE.** Onze sections (§10, §12 a §20)
decrivent le comportement au saut, a l'atterrissage, au freinage, en rotation, allongee — **aucune
n'a jamais ete jouee dans la salle**. Tant qu'elles ne le sont pas, « 100 % » est indemontrable
quelle que soit la qualite du solveur. C'est le chantier designe par les DIRECTIVES du 00:10, et le
cycle 48 ne l'entame pas : il a ferme les deux questions de mesure (Q-A, Q-B) que le cycle 47 posait
comme prealables obligatoires.

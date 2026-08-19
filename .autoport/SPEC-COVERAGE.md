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

## Périmètre

Seules `chestL` et `chestR` sont simulées (ordre de l'owner du 2026-08-14 07:30). Les sections qui
parlent d'autre chose que de la poitrine sont hors périmètre, pas « tenues ».

## Tableau

| §  | Ce que la section exige | Statut | Preuve / ce qui manque |
|----|-------------------------|--------|------------------------|
| 1  | Cible : sein non soutenu, réaliste | TENUE PAR CONSTRUCTION | Section descriptive, sans grandeur mesurable |
| 2  | Le modèle debout EST la référence 100 % ; `Additional Procedural Sag = 0%` | **TENUE** | Écart max au modèle au repos = 0,0002 (gate IDLE) |
| 3  | Équilibre 1 g ; réponse à `(g_local − g_ref) − a_torso + a_angular` | **TENUE** | `gy` = 9,81 m/s² exact en unités moteur ; `gravity=1.00` livré depuis le 2026-08-19 ; repos inchangé |
| 4  | Morphologie de référence | TENUE PAR CONSTRUCTION | Descriptive |
| 5  | Volume 450–600 mL, densité 0,95, masse 0,50 kg | TENUE PAR CONSTRUCTION | La masse n'entre que dans `f = raideur/√masse` : jauge non observable. **Déclaré, pas gagné.** |
| 6  | `L0` `W0` `H0` `B0` `P0` ; `B0` ≈ 115–125 mm | PARTIELLE | `b0=602 u` = 14,7 cm livré. `L0`/`W0`/`H0`/`P0` non mesurés |
| 7  | Repère local | NON ÉTABLI | Aucune mesure du repère lui-même |
| 8  | Volume 98–101 % (96–102 % en transitoire) | NON ÉTABLI | Canal de déformation présent depuis le cycle ~30, jamais mesuré contre cette bande |
| 9  | État debout neutre = 1,00 sur tous les axes | **TENUE** | Erreur §9 ramenée de 0,2077 à 0,0001 (correction de `g_ref` : pose debout d'auteur, pas bind-pose) |
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
| 22 | COM ≤35/40 % B0 ; apex ≤42/50 % ; élongation locale ≤25 % | PARTIELLE | Élongation locale 23,6/23,3 % **dans** la bande. COM dépassé de +18 %/+7 % sur une borne supérieure (chiffre corrigé le 2026-08-19, l'instrument publiait ×2,22 à tort). Apex non isolé |
| 23 | « Un seul ressort à l'apex est INSUFFISANT » | PARTIELLE | Deux articulations simulées ; la chair simulée couvre 19 % de l'organe |
| 24 | 2,30 / 2,50 / 2,65 Hz par axe | PARTIELLE | Raideur dérivée pour 2,30 Hz. Le maillon distal est **sous la bande** |
| 25 | ζ = 0,35 (0,32–0,42) | PARTIELLE | Recalibrée le 2026-08-19 : l'ancien réglage l'était sur un signal saturé |
| 26 | Rebond ≈ 31 % | NON ÉTABLI | Même cause : le signal était saturé, jamais remesuré depuis |
| 27 | Stabilisation 1,0–1,5 s | **TENUE** | Passée de PARTIELLE à TENUE sur les deux chaînes après le cycle 46 |
| 28 | `k = m(2πf)²`, `c = 2ζ√(km)` | TENUE PAR CONSTRUCTION | Le moteur calcule `ω = 2π·raideur/√masse` : la relation est la forme même du code |
| 29 | Anisotropie 1,00 / 0,90 / 0,82 / torsion 0,72 | PARTIELLE | Compliance latérale mesurée 1,0294 / 0,9180 pour une cible de 0,820 |
| 30 | 28–35 % du volume arrière fortement ancré | PARTIELLE | 45,9 %/46,1 % de la chair mesurée comme ancrée — **au-dessus** de la bande |
| 31 | Gradient `w(r) = r^1.6…2.0`, monotone | **NON TENUE** | La contrainte de monotonie a été essayée le 2026-08-19 et **aggrave** l'enfoncement. Retirée sur mesure |
| 32 | Indépendance gauche/droite ; masse ±2–4 %, raideur ±3–5 % | PARTIELLE | Les écarts de paramètres sont dans les bandes, mais bouger un sein déplace l'autre de 32 à 321 % |
| 33 | Sein↔sein : collision **avant** interpénétration visible, restitution 0,06 | **NON TENUE** | Pénétration mesurée 0,049 m contre un plafond de 0,0005 (gate COLLIDE rouge) |
| 34 | Sein↔thorax, restitution 0,02 | **NON TENUE** | Même mesure |
| 35 | Couplage vêtement (tous les termes ≈ 0 pour Keira) | NON ÉTABLI | Le vêtement ne suit pas le sein : 0 sommet majoritaire |
| 36 | Ballotement secondaire 2–7 %, ~5,2 Hz, ζ 0,55–0,75 | PARTIELLE | Canal présent, bandes jamais vérifiées |
| 37 | ≥120 Hz, ≥2 sous-pas ; les transformations artificielles ne créent pas d'impulsion | **TENUE** | Sous-pas en place ; rebase des deux moitiés (rotation **et** translation) corrigé |
| 38 | Preset complet recommandé | NON ÉTABLI | Jamais confronté ligne à ligne au fichier livré |

## Compte au 2026-08-20 00:10

- **TENUE**, mesurée et dans sa bande sur les deux seins : **6** (2, 3, 9, 11, 27, 37)
- **TENUE PAR CONSTRUCTION**, déclarée sans être comptée comme une victoire : **4** (1, 4, 5, 28)
- **PARTIELLE** : **10** (6, 21, 22, 23, 24, 25, 29, 30, 32, 36)
- **NON TENUE**, mesurée et rouge : 3 (31, 33, 34)
- **NON ÉTABLI** : 15 — dont **les onze régimes de mouvement §10 et §12 à §20**, qui ne sont
  jamais joués dans la salle de test.

**Le plus gros trou n'est pas un défaut de physique, c'est un trou de MESURE.** Onze sections
décrivent ce que la poitrine doit faire au saut, à l'atterrissage, au freinage, en rotation, allongée
— et aucune n'a jamais été jouée. Tant qu'elles ne le sont pas, « 100 % » est indémontrable, quelle
que soit la qualité du solveur.

# ARRÊT — ÉTAPE 1 BLOQUANTE : LA SALLE DE TEST (SPEC §11)

Le validateur échoue MAINTENANT, en tout premier, sur la gate `ROOM`. Aucune autre gate n'est
même évaluée. Tant que la salle de test n'existe pas et n'a pas produit son tableau, il n'y a
rien à mesurer, rien à régler, rien à livrer. **Ne touche à aucun autre sujet** — ni C19, ni
remplissage de paramètres, ni gates existantes.

Ce qu'il faut, et rien d'autre :
1. Une facilité **`phys-room`** dans `goal_src/jak1/pc/*.gc` : spawn de l'acteur **par nom**
   (`keira-hd`) dans une zone vide devant la caméra ; le piloter (translations, **arrêts nets**,
   **accélérations/décélérations brutales**, changements de direction) ; **cycler toutes les
   animations de son art-group** ; **changer son inclinaison** (la pencher, tête en bas — c'est
   la seule façon d'exercer l'exception de gravité de la famille A, jamais testée) ; relire ses
   chaînes à chaud.
2. Le tableau, écrit dans
   `.autoport/reports/Grecharged-secondary-motion/keira-room-table.txt`, format exact :
   ```
   drive=hardstop ...            (une ligne par mode : hardstop, accel, tilt)
   row chain=<nom> anim=<nom-anim> tipvar=<f> rootdev=<f> meshpen=<f> jump=<f>
   worst chain=<nom> anim=<nom-anim> ...        (le NOM de l'anim au pire cas)
   ROOM-POSCONTROL: fired <valeur non nulle>    (le défaut injecté a bien fait monter le compteur)
   ```
   Minimums vérifiés par la gate : ≥120 lignes `row`, ≥20 chaînes distinctes sur les 47,
   ≥12 animations distinctes, les trois modes de pilotage présents, ≥10 attributions `worst`,
   et chaque colonne doit **varier** (une colonne constante = colonne synthétisée, rejetée).
3. **Substrat x86, tout de suite.** Le Redmi est de retour, mais il sert à CONFIRMER, pas à
   découvrir. Itère sur x86 (REPL, secondes), device ensuite.

C'est ce tableau, et lui seul, qui autorise à dire « Keira est prête à être jugée ».

---

# PHYSIQUE DE KEIRA — DÉPART PROPRE (owner 2026-08-10 : « on part propre, la physique de Keira aux
# petits oignons, et on voit à partir de là »)

LE CONTRAT EST `.autoport/prompts/SPEC-keira-physique.md`. Lis-le en entier, c'est la seule source
d'exigences. Il tient en 10 sections et il est écrit pour être suivi, pas pour être archéologué.

PÉRIMÈTRE : **KEIRA SEULE**, code ET données. On ne touche pas aux 59 autres modèles. Le fichier de
chaînes peut ne contenir qu'elle. On étend seulement quand l'owner l'a validée de ses yeux.

CE QU'ON NE FAIT PLUS :
  * pas de rustine sur `physics_chains.txt` — ses chaînes sont GÉNÉRÉES depuis son rig + les règles ;
  * pas de nouveau gate — le jeu de gates est GELÉ ; un critère manquant remplace un gate réfuté ;
  * pas de suppresseur de mouvement par défaut ;
  * pas de mesure qui ne descende pas de la position ÉCRITE du joint ;
  * pas de zéro sans contrôle positif qui a tiré.

HISTORIQUE (à ne PAS reprendre comme plan de travail, seulement pour comprendre ce qui a échoué) :
`.autoport/prompts/archive/SPEC-physique-secondaire-ARCHIVE.md` (22 sections, 7 faux verts
documentés) et `.../phase-Grecharged-secondary-motion-JOURNAL.md` (14 cycles).

ORDRE DE TRAVAIL — quatre étapes, rien d'autre :
  1. générer les chaînes de Keira depuis son rig et les règles de la spec ;
  2. jambe de preuve (device si connecté, sinon x86 avec la dette déclarée) ;
  3. verdict PAR CHAÎNE NOMMÉE : racine ancrée + pointe mobile + zéro pénétration de surface avec
     contrôle positif + pas de saut visible ;
  4. build + rapport, puis l'owner juge.

### PÉRIMÈTRE APPLIQUÉ PAR LE SUPERVISEUR (2026-08-10 19:45)
Le worker a passé 1h28 à retravailler les 349 chaînes des 43 modèles au lieu de se limiter à Keira,
et le rapport est resté figé 2h. J'ai donc RÉDUIT le fichier moi-même :
`recharged_assets/physics_chains.txt` ne contient plus QUE les blocs de Keira (+ les sections
globales `[levels]`/`[eyescale]`). Le cast complet est archivé dans
`recharged_assets/physics_chains.FULL-CAST.bak` — il sera RÉGÉNÉRÉ (pas restauré) une fois Keira
validée par l'owner.
CONSÉQUENCE : les 59 autres modèles n'ont plus de physique pour l'instant. C'EST VOULU et l'owner
l'a autorisé. Ne pas les réintroduire. Travailler uniquement sur Keira, avec un fichier assez petit
pour être poussé à chaud sur device en quelques secondes.

### ÉTAPE 1 BLOQUANTE : LA SALLE DE TEST (SPEC §11) — x86, MAINTENANT
Ne pas chercher à valider Keira en jouant. Construire d'abord la salle de test décrite en SPEC §11 :
spawn par nom, pilotage (accélérations/arrêts brutaux), cycle de TOUTES ses animations avec le nom
attaché aux pires chiffres, changement d'INCLINAISON (l'exception de gravité famille A n'a jamais été
testée), et rechargement à chaud des 32 chaînes.
Substrat : **x86**, immédiatement — le device absent n'est PAS une raison d'attendre.

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

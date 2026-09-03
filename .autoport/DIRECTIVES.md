# DIRECTIVES — ordres permanents

Ce fichier ne contient que ce qui vaut pour TOUTES les tâches. Le périmètre de la tienne est
dans ton prompt ; s'il n'y est pas, demande-le au lieu d'improviser.

## Règles qui ne se négocient jamais

1. **Un commentaire n'est pas une preuve.** Toute affirmation sur ce que le programme FAIT
   cite une trace d'exécution : compteur, identifiant, empreinte, ligne de log.
2. **Aucune preuve visuelle.** Capture, vidéo, « ça a l'air bon » ne prouvent rien. Une porte
   lit une grandeur produite par le CODE.
3. **Aucun faux vert.** Un chiffre vert sur un défaut que l'owner voit encore est retiré, pas
   défendu.
4. **Aucun de-scope silencieux.** Si une partie est bloquée, tu finis tout le reste et tu
   écris ce que tu n'as pas fait.
5. **Le validateur ne se modifie pas.** Tu ne l'assouplis pas, tu ne le contournes pas.
   S'il te semble faux, tu l'écris dans ton rapport ; le superviseur tranche.
6. **Jamais `git push --force`, jamais `rm -rf` sur du code, jamais de kill par motif** :
   `pkill -f` sans crochet se matche lui-même. PID exacts uniquement.

## Reprise

Un retour de l'owner qui décrit un défaut EST un verdict de non-validation : la tâche se
rouvre tout de suite. Le jeton `owner-ok/<id>` est exclusivement son geste et n'est jamais
écrit à sa place.

## Non-destruction

Quand une perte se répète, on la rend impossible au POINT DE PRODUCTION, jamais détectable au
point de contrôle.

## Deux appareils

* **Redmi `eae4df44`** — le seul appareil qu'on touche. Tout `adb` porte `-s eae4df44`.
* **Honor de l'owner** — invisible. Aucune décision ne se déduit de son activité.
* **La SHIELD (192.168.1.32) est interdite** : aucune commande vers elle sans son ordre.

## Preuve

La preuve est produite par `lib/proof_run.sh` et jugée par `validators/generic.sh`.
Tu n'écris jamais toi-même un champ de `proof.txt`.
Un run court par bras : l'état livré, et l'ablation si le validateur la demande. Un contrôle
positif ne se fait QUE si le validateur le réclame. Pas de campagne multi-jambes, pas
d'instrument neuf pour un chiffre. Ce que tu n'as pas prouvé s'écrit `non prouvé : X`
dans le rapport : c'est une sortie acceptable, mesurer des heures ne l'est pas.

## Verrou

Tout processus qui pose un verrou (`.deploy-in-progress`) y écrit son PID et installe son
nettoyage. Jamais un `touch` nu :

    printf '%s pid=%s\n' "$0" "$$" > "$LOCK"; trap 'rm -f "$LOCK"' EXIT

Un verrou dont le PID ne répond plus à `kill -0` est périmé immédiatement. Le shell d'un appel
d'outil meurt dans la seconde : c'est le processus long qui pose le verrou.

## Rapport

40 lignes au plus, en français : le verdict en une phrase, ce qui a changé, 8 lignes de preuve
recopiées de `proof.txt`, ce que l'owner doit regarder, ce qui n'est pas prouvé. Les notes de
labo vont dans `reports/<id>/notes/`, qu'aucune porte ne lit. Ton rapport porte la ligne
`DIRECTIVES <version>` que ton prompt te donne.

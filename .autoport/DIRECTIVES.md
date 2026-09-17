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

## Refonte

Owner, 17/09 : « On parle de refonte hein ! Retordre l'existant en espérant atteindre le niveau
de la refonte ça va pas fonctionner. » Un item d'une campagne de refonte (eau, herbe, lumière,
surfaces meubles) se juge contre la CIBLE de sa SPEC, jamais seulement contre la non-régression
de l'existant : sa porte porte une grandeur de la cible, et une brique qui change ce qui se voit
ne régresse pas sur le build précédent (ça se mesure, ça entre dans la porte). Une brique
intermédiaire qui n'a rien à montrer le dit (`where` : « rien à voir ») au lieu d'envoyer l'owner
tester ce qui n'existe pas encore.

## Reprise

Un retour de l'owner qui décrit un défaut EST un verdict de non-validation : la tâche se
rouvre tout de suite. Le jeton `owner-ok/<id>` est exclusivement son geste et n'est jamais
écrit à sa place.

## Non-destruction

Quand une perte se répète, on la rend impossible au POINT DE PRODUCTION, jamais détectable au
point de contrôle.

## Deux appareils

* L'appareil de preuve est celui branché en USB, Honor compris (owner du 6 septembre).
  `lib/pick_device.sh` le choisit à l'exécution ; la preuve consigne son identité.
* La SHIELD et tout appareil joint par une adresse réseau sont interdits.

## Preuve

La preuve est produite par `lib/proof_run.sh` et jugée par `validators/generic.sh`.
Tu n'écris jamais toi-même un champ de `proof.txt`.
Un run court par bras : l'état livré, et l'ablation si le validateur la demande. Un contrôle
positif ne se fait QUE si le validateur le réclame, sauf campagne explicitement demandée
par l'owner et inscrite dans `proof_plan` du backlog/périmètre de l'item. Hors cette
autorisation, pas de campagne multi-jambes ni d'instrument neuf pour un chiffre. Ce que tu n'as pas prouvé s'écrit `non prouvé : X`
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

## Signalements

Tout ce que tu vois de cassé et que tu ne corriges PAS — hors périmètre, défaut latent, coût non
mesuré, code mort — va dans `reports/<id>/FINDINGS.txt`, une ligne par trouvaille :

    <fichier:ligne ou zone> | <ce qui cloche, une phrase> | <ce que ça coûte de le laisser>

Écris le fichier même vide (`AUCUN`). Une trouvaille laissée dans ta prose est une dette
invisible : personne ne relit un rapport fermé, et on la retrouve par hasard des mois plus tard.
La porte de fermeture lit ce fichier ; le superviseur en fait des chantiers ou les écarte devant
l'owner.

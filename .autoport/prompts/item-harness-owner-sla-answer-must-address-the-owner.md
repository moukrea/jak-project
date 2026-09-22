# Un retour de l'owner ne compte comme « repondu » que si la reponse lui est adressee, pas si un verdict automatique passe apres

## Defaut cite
- 2026-09-23 : « Je pense qu'ils les faut tous... à prioriser of course mais tout est pertinent il semblerait, go »

## Cause connue
Signale par le worker de harness-supervisor-death-is-an-alarm (reports/harness-supervisor-death-is-an-alarm/FINDINGS.txt, ligne 5), non corrige ; l'owner a dit d'ouvrir tous ces chantiers le 23/09.
`.autoport/lib/owner_sla.py:collect` : « repondu » = n'importe quel commentaire du harnais poste APRES le retour sur le meme ticket. Un verdict d'essai poste automatiquement eteint le compteur alors que l'owner n'a recu aucune reponse a SA question : le cout reel est sous-estime et l'owner peut croire avoir ete entendu.

## Livrable
1. Recensement AVANT : sur 7 jours, combien de retours sont « repondus » UNIQUEMENT par un commentaire automatique (verdict, changement d'etat).
2. Une reponse compte si elle vient du superviseur et vise ce retour (marqueur de reponse ou citation), jamais si c'est un message automatique.
3. `owner_sla_auto_answered` = retours eteints par un message automatique ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut semé rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`owner_sla_auto_answered == 0` dans `reports/harness-owner-sla-answer-must-address-the-owner/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-owner-sla-answer-must-address-the-owner x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

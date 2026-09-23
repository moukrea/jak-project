# Quand un worker repond a un retour de l'owner, sa reponse est postee dans le fil de ce retour et compte comme une reponse

## Defaut cite
- 2026-09-23 : « oui ouvre »

## Cause connue
Signale par les workers de harness-linear-auto-archive-when-space-runs-out / harness-owner-sla-matches-every-owner-comment / harness-owner-sla-answer-must-address-the-owner (reports/<id>/FINDINGS.txt), non corrige ; l'owner a dit « oui ouvre » le 23/09.
`.autoport/DIRECTIVES.md:86` : la consigne de commentaire des workers ne mentionne pas `--reply-to` ; depuis 2026-09-23T00:30Z, une reponse d'agent postee hors fil n'eteint plus le compteur. Le worker n'a PAS modifie DIRECTIVES (ordre de l'owner : pas de regle en prose). Faire passer la reponse dans le fil par l'OUTIL (ex. `--comment` qui repond par defaut au dernier retour owner ouvert du ticket), pas par une phrase de plus.

## Livrable
1. L'outil de commentaire rattache la reponse au dernier retour owner ouvert du ticket quand il y en a un.
2. `worker_replies_off_thread` = reponses d'agents a un retour owner postees hors fil sur 7 jours ; doit valoir 0 apres correctif.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`worker_replies_off_thread == 0` dans `reports/harness-workers-reply-in-the-owner-thread/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-workers-reply-in-the-owner-thread x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

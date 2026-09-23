# Un pouce de l'owner sur le dernier message du harnais clot la discussion du ticket : plus aucune etiquette « A traiter », « A lire » ni « En discussion » n'y reste

## Defaut cite
- 2026-09-23 : « Pourquoi les labels subsistent, j'ai mis le pouce sur le dernier message »

## Cause connue
JAK-176 (hud-eco-gauge), constate par le superviseur le 23/09 : l'owner a mis 👍 sur le dernier message du harnais (« → Terminé », automatique, 22/09 21:25) apres son retour de 21:23. Les etiquettes sont restees : (1) le pouce ne retire que « A lire » (linear_sync.py:pull_labeled_unmapped et son equivalent pour les tickets du backlog) ; (2) depuis harness-owner-sla-answer-must-address-the-owner (23/09), un message automatique ne compte plus comme reponse, donc son retour restait ouvert et « A traiter » aussi. Les deux regles se contredisent : le pouce de l'owner est sa facon de dire « lu, rien a ajouter » (owner 17/09 : « si j'ai rien à ajouter à ta réponse ça reste en discussion indéfiniment »). Etiquettes retirees a la main sur JAK-176.

## Livrable
1. Un pouce (ou ✅) de l'owner sur le DERNIER message du harnais, poste APRES son dernier retour ou non, clot la discussion : retire « A traiter », « A lire » et « En discussion », et marque ses retours precedents du ticket comme repondus pour owner_sla (source : reaction owner).
2. Meme regle pour les tickets du backlog ET hors backlog (une seule fonction).
3. Un nouveau commentaire de l'owner APRES le pouce rouvre normalement.
4. `thumbed_tickets_still_labeled` = tickets dont le dernier message du harnais porte un pouce de l'owner et qui gardent une de ces etiquettes ; doit valoir 0. Recenser l'existant AVANT.
CONTROLE POSITIF (pouce sur un message automatique apres un retour owner -> tout retire) + CONTROLE NEGATIF (pouce sur un message ANCIEN, pas le dernier -> rien ne change).

## Preuve exigee
`thumbed_tickets_still_labeled == 0` dans `reports/harness-owner-thumbs-up-closes-the-thread/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-owner-thumbs-up-closes-the-thread x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

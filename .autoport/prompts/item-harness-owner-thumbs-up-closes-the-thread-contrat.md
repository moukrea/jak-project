# Un pouce de l'owner sur le dernier message du harnais clot la discussion du ticket : plus aucune etiquette « A traiter », « A lire » ni « En discussion » n'y reste — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

JAK-176 (hud-eco-gauge), constate par le superviseur le 23/09 : l'owner a mis 👍 sur le dernier message du harnais (« → Terminé », automatique, 22/09 21:25) apres son retour de 21:23. Les etiquettes sont restees : (1) le pouce ne retire que « A lire » (linear_sync.py:pull_labeled_unmapped et son equivalent pour les tickets du backlog) ; (2) depuis harness-owner-sla-answer-must-address-the-owner (23/09), un message automatique ne compte plus comme reponse, donc son retour restait ouvert et « A traiter » aussi. Les deux regles se contredisent : le pouce de l'owner est sa facon de dire « lu, rien a ajouter » (owner 17/09 : « si j'ai rien à ajouter à ta réponse ça reste en discussion indéfiniment »). Etiquettes retirees a la main sur JAK-176.

RECHUTE LE 25/09 (JAK-50, JAK-277, JAK-77, tous Done) : l'owner a mis 👍 sur le message automatique « → Terminé » (commentaire racine du harnais), mais le superviseur avait poste une reponse DANS LE FIL une minute apres. La regle ne regarde que le DERNIER message du harnais (la reponse de fil, sans pouce) : « En discussion » et « À traiter » sont restes des heures. Owner : « faudrait plus que ça de reproduise et c'est pas la première fois que je te le dis ».

## Livrable — le contrat, en entier

1. Un pouce (ou ✅) de l'owner sur le DERNIER message du harnais, poste APRES son dernier retour ou non, clot la discussion : retire « A traiter », « A lire » et « En discussion », et marque ses retours precedents du ticket comme repondus pour owner_sla (source : reaction owner).
2. Meme regle pour les tickets du backlog ET hors backlog (une seule fonction).
3. Un nouveau commentaire de l'owner APRES le pouce rouvre normalement.
4. `thumbed_tickets_still_labeled` = tickets dont le dernier message du harnais porte un pouce de l'owner et qui gardent une de ces etiquettes ; doit valoir 0. Recenser l'existant AVANT.
CONTROLE POSITIF (pouce sur un message automatique apres un retour owner -> tout retire) + CONTROLE NEGATIF (pouce sur un message ANCIEN, pas le dernier -> rien ne change).

AJOUT DU 25/09 : (a) un pouce de l'owner sur N'IMPORTE QUEL message du harnais poste APRES son dernier commentaire clot la discussion (racine ou fil, peu importe l'ordre) ; (b) un ticket passe en Done ou Canceled perd automatiquement « À lire », « À traiter » et « En discussion » sauf si l'owner a ecrit APRES le passage en Done ; (c) rejouer les 3 tickets du 25/09 comme controle positif.

## Hors perimetre

(non precise)

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-23
> Pourquoi les labels subsistent, j'ai mis le pouce sur le dernier message

### 2026-09-25
> Ils sont en done, j'ai mis la réaction du pouce..  et le label réponse du harnais et discussion active sont toujours là des heures après… faudrait plus que ça de reproduise et c'est pas la première fois que je te le dis

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


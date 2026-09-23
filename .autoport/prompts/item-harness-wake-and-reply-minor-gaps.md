# Petits defauts du reveil et des reponses : reveil inutile apres une reponse en retard, libelle de delai faux, retours du terminal sans fil, cible de --reply-to

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »
- 2026-09-23 : « Vas-y traite comme tu l'entends »

## Cause connue
Signale par les workers de harness-linear-relink-keeps-owner-comments / harness-linear-stale-map-never-fakes-an-owner-move / harness-wake-unanswered-list-carries-its-age / harness-workers-reply-in-the-owner-thread (reports/<id>/FINDINGS.txt). Owner 23/09 : « Ok tu peux traiter le tout du coup, comme tu l'entends » (pose sur JAK-235, applique aussi a la question JAK-237 posee juste avant).
(1) `wake_gate.py:empreinte_retours` : repondre a un retour EN RETARD change la signature, le reveil suivant passe au lieu d'etre refuse. (2) `wake_gate.py:cran_retour` : « PLUS D'UN JOUR » faux si AUTOPORT_OWNER_SLA_S > 12 h. (3) `owner_sla.py:EXCLUDED_SOURCES` : un retour relaye du terminal n'a pas de fil, aucune mesure ne dit s'il a ete repondu. (4) `linear_sync.py:reply_target` : `--reply-to last` vise le dernier recopie meme deja repondu ; `wake_gate.py:310` conseille encore `--reply-to last`.

## Livrable
1. Corriger les quatre ; le reveil conseille la commande sans option (dernier retour OUVERT).
2. `wake_reply_minor_gaps` = somme ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`wake_reply_minor_gaps == 0` dans `reports/harness-wake-and-reply-minor-gaps/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-wake-and-reply-minor-gaps x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

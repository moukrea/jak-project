# Chaque retour de l'owner recopie de Linear se retrouve sur son ticket : le compteur « sans reponse » ne perd plus ses messages

## Defaut cite
- 2026-09-23 : « oui ouvre le chantier »

## Cause connue
Signale par le worker de harness-supervisor-death-is-an-alarm (reports/.../FINDINGS.txt, lignes 2 et 10), non corrige : `.autoport/lib/owner_sla.py:_match_owner_comment` ne retrouve pas sur son ticket Linear le commentaire de l'owner que le backlog a recopie. 20 retours sur 145 a l'essai 3, 28 sur 153 a l'essai 4 : leur delai n'est pas mesure, et un retour non apparie peut passer pour traite. L'appariement se fait sur un prefixe normalise de 60 caracteres ; la cause PROBABLE (non prouvee) est la reecriture du texte a la recopie par `save_owner_images` (liens d'images remplaces), qui change le debut du texte.

## Livrable
1. Recensement AVANT : lister les retours non apparies de la fenetre de 7 jours, et pour chacun la CAUSE nommee (reecriture d'image, troncature, espaces, auteur, autre). Publier le compte par cause.
2. Corriger l'appariement a la racine (garder l'identifiant du commentaire Linear au moment de la recopie plutot que re-deviner par le texte, si c'est faisable), sans jamais apparier un commentaire du harnais qui CITE l'owner.
3. `owner_sla_unmatched` = nombre de retours owner de la fenetre non retrouves sur leur ticket ; doit valoir 0. Publier aussi le denominateur (retours de la fenetre).
4. CONTROLE POSITIF : un retour dont le texte a ete reecrit a la recopie (image) est retrouve. CONTROLE NEGATIF : un commentaire du harnais qui cite mot pour mot l'owner n'est PAS pris pour lui.

## Preuve exigee
`owner_sla_unmatched == 0` dans `reports/harness-owner-sla-matches-every-owner-comment/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-owner-sla-matches-every-owner-comment x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

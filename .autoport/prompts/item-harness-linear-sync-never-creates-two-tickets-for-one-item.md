# La synchro Linear ne cree jamais deux tickets pour un meme chantier, et ne prend jamais son propre ticket pour un ticket de l'owner

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Constate par le superviseur le 23/09 : pour l'item harness-owner-sla-matches-every-owner-comment, la synchro a cree JAK-195 (pulled_at 22:19:49Z) ET JAK-196 (22:19:47Z), puis a relu JAK-195 comme un « NOUVEAU TICKET OWNER » (logs/linear_sync.txt:22524) et fabrique l'item fantome owner-chaque-retour-de-l-owner-recopie-de-linear-se-re, signale ensuite en boucle « À TRAITER ... retour owner sans reponse ». Double consequence : un faux retour de l'owner, et un bruit qui noie les vrais.
Piste NON prouvee : `linear_sync.py:1255-1261` ecrit la correspondance item->ticket en memoire apres `issueCreate` ; si une deuxieme execution (veille linear_watch.sh toutes les 30 s, `--comment` ou `--only` lances par le superviseur) lit linear_map.json avant que la premiere l'ait sauve, ou l'ecrase ensuite, l'item repart sans ticket et en recoit un second. Verifier aussi si `--comment` prend le verrou .linear_sync.lock.
Un ticket cree par le harnais ne doit JAMAIS etre relu comme ticket de l'owner : le fantome a ete archive a la main (JAK-195 -> Canceled).

## Livrable
1. Reproduire : deux executions concurrentes sur un item neuf -> compter les tickets crees.
2. Une creation est idempotente (cle de l'item dans le ticket, recherche avant creation, ou map sauvee sous verrou immediatement apres issueCreate) ; toutes les voies d'entree (veille, --comment, --only, --check) prennent le meme verrou.
3. Le pull ne transforme jamais en « ticket owner » un ticket dont le harnais est l'auteur ou qui porte une cle d'item.
4. `linear_duplicate_tickets` = items du backlog lies a plus d'un ticket Linear + items owner-* nes d'un ticket cree par le harnais ; doit valoir 0. Recenser AUSSI l'historique (combien de fantomes deja crees).
CONTROLE POSITIF fabrique (deux executions concurrentes rendent 2 sans le correctif) + CONTROLE NEGATIF.

## Preuve exigee
`linear_duplicate_tickets == 0` dans `reports/harness-linear-sync-never-creates-two-tickets-for-one-item/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-sync-never-creates-two-tickets-for-one-item x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

> LIS D'ABORD `prompts/item-harness-owner-test-requires-a-capture-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un chantier visible ne part au test de l'owner que si son ticket porte une capture de la zone : la règle devient une porte, plus une consigne

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Cree le 21/09 00:55 par le superviseur. FAITS : DIRECTIVES (Ticket Linear, 18/09) exige une capture jointe quand un chantier visible part au test de l'owner ; l'item hud-eco-gauge portait en plus « CAPTURE COTE A COTE OBLIGATOIRE » dans sa consigne ; l'essai 11 est passe en test le 21/09 00:46 sans aucune piece jointe ni image dans le commentaire de l'agent (0 appel `--attach` dans attempt-011.jsonl ; 0 attachment sur JAK-176). Meme manque sur grass-blade-variants essai 7 et grass-interaction-direction essai 3 (owner 19/09 : « t'aurais pu joindre un screen ca aurait accelere les choses »). Une consigne que trois agents sur trois ignorent n'est pas une regle : c'est une porte qui manque. CIBLE : dans la porte de fermeture de l'orchestrateur, pour un item `owner_test: true` dont le `where` n'est pas « rien a installer/rien a regarder en jeu », le passage a `to-test` est REFUSE (l'item rest […suite dans le contrat]

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`owner_test_capture_defects == 0` dans `reports/harness-owner-test-requires-a-capture/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-owner-test-requires-a-capture x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder en jeu : preuve machine. La porte compte un defaut quand un chantier visuel part au test sans capture ET sans build livre a l'owner ; une capture impossible suivie d'une livraison n'est PAS un defaut..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

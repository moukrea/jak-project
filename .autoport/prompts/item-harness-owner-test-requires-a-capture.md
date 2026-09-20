# Un chantier visible ne part au test de l'owner que si son ticket porte une capture de la zone : la règle devient une porte, plus une consigne

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Cree le 21/09 00:55 par le superviseur. FAITS : DIRECTIVES (Ticket Linear, 18/09) exige une capture jointe quand un chantier visible part au test de l'owner ; l'item hud-eco-gauge portait en plus « CAPTURE COTE A COTE OBLIGATOIRE » dans sa consigne ; l'essai 11 est passe en test le 21/09 00:46 sans aucune piece jointe ni image dans le commentaire de l'agent (0 appel `--attach` dans attempt-011.jsonl ; 0 attachment sur JAK-176). Meme manque sur grass-blade-variants essai 7 et grass-interaction-direction essai 3 (owner 19/09 : « t'aurais pu joindre un screen ca aurait accelere les choses »). Une consigne que trois agents sur trois ignorent n'est pas une regle : c'est une porte qui manque. CIBLE : dans la porte de fermeture de l'orchestrateur, pour un item `owner_test: true` dont le `where` n'est pas « rien a installer/rien a regarder en jeu », le passage a `to-test` est REFUSE (l'item reste in-progress, le worker est renvoye poster) tant qu'aucun commentaire du harnais poste PENDANT cet essai sur le ticket ne porte une image (attachment ou `![`) ; le refus est nomme dans le journal et le handoff. La capture n'est pas une preuve (regle 2) : la porte de mesure reste la meme, seule la SORTIE vers l'owner est conditionnee. PORTE : (1) test : un item visible dont l'essai n'a poste aucune image -> fermeture refusee avec la raison ; le meme avec une image postee -> passe ; un item `where`=« rien a installer » -> passe sans image (controle) ; (2) le releve des 7 derniers jours : combien de passages en test visibles sans image (attendu >= 3, les cas nommes ci-dessus) ; (3) DIRECTIVES cite la porte. Un terme non mesure compte 1.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`owner_test_capture_defects == 0` dans `reports/harness-owner-test-requires-a-capture/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-owner-test-requires-a-capture x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder en jeu : preuve machine..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.

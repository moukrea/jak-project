# Un chantier visible ne part au test de l'owner que si son ticket porte une capture de la zone : la règle devient une porte, plus une consigne — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Cree le 21/09 00:55 par le superviseur. FAITS : DIRECTIVES (Ticket Linear, 18/09) exige une capture jointe quand un chantier visible part au test de l'owner ; l'item hud-eco-gauge portait en plus « CAPTURE COTE A COTE OBLIGATOIRE » dans sa consigne ; l'essai 11 est passe en test le 21/09 00:46 sans aucune piece jointe ni image dans le commentaire de l'agent (0 appel `--attach` dans attempt-011.jsonl ; 0 attachment sur JAK-176). Meme manque sur grass-blade-variants essai 7 et grass-interaction-direction essai 3 (owner 19/09 : « t'aurais pu joindre un screen ca aurait accelere les choses »). Une consigne que trois agents sur trois ignorent n'est pas une regle : c'est une porte qui manque. CIBLE : dans la porte de fermeture de l'orchestrateur, pour un item `owner_test: true` dont le `where` n'est pas « rien a installer/rien a regarder en jeu », le passage a `to-test` est REFUSE (l'item reste in-progress, le worker est renvoye poster) tant qu'aucun commentaire du harnais poste PENDANT cet essai sur le ticket ne porte une image (attachment ou `![`) ; le refus est nomme dans le journal et le handoff. La capture n'est pas une preuve (regle 2) : la porte de mesure reste la meme, seule la SORTIE vers l'owner est conditionnee. PORTE : (1) test : un item visible dont l'essai n'a poste aucune image -> fermeture refusee avec la raison ; le meme avec une image postee -> passe ; un item `where`=« rien a installer » -> passe sans image (controle) ; (2) le releve des 7 derniers jours : combien de passages en test visibles sans image (attendu >= 3, les cas nommes ci-dessus) ; (3) DIRECTIVES cite la porte. Un terme non mesure compte 1.

AMENDEMENT OWNER DU 22/09 (perimetre, pas un commentaire) : « Attention si t'arrives pas a capturer et que c'est visuel vaut quand meme mieux me donner de quoi tester moi-meme que faire des mesures qui menent a rien (echecs ou faux verts parce que tu mesures tout ce qui est visuel comme une merde) ». La porte ne doit donc JAMAIS transformer une capture impossible en essai rouge, ni pousser a fabriquer une mesure de substitution. Trois issues, et trois seulement : (a) capture jointe -> defaut=0 ; (b) capture impossible MAIS un build est livre a l'owner (APK publie, tag inscrit dans .published_build_info.txt, commentaire de ticket qui dit quoi regarder et que la capture a echoue) -> defaut=0 ; (c) capture impossible ET rien a tester pour l'owner -> defaut=1. Une mesure visuelle inventee pour remplacer la capture compte comme (c).

## Livrable — le contrat, en entier

(aucun)

## Hors perimetre

(non precise)

## Ou l'owner regardera

Rien a regarder en jeu : preuve machine. La porte compte un defaut quand un chantier visuel part au test sans capture ET sans build livre a l'owner ; une capture impossible suivie d'une livraison n'est PAS un defaut.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


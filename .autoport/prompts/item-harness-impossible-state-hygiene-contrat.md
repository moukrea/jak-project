# L'etat « preuve impossible » se purge, et se lit sous le nom que la course a vraiment ecrit — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

TROIS SIGNALEMENTS DU 12/09 (reports/harness-proof-impossible-must-be-read/FINDINGS.txt), sur le mecanisme livre la nuit meme.
1. RIEN NE PURGE un `proof-impossible.txt` debout. `proof_run.sh` ne l'efface qu'a sa propre relance, sur le MEME item et le MEME bras. Un item abandonne en cours de route garde donc son etat, et `autoport status` continue d'annoncer une impossibilite perimee — a l'owner.
2. NOM DE FICHIER DIVERGENT, deja mesure : `proof_run.sh:766` ecrit `proof$SUF-wait.txt`, donc `proof-off-wait.txt` pour le bras d'ablation. Le recensement de `harness-attempt-not-burned-by-foreign-cause` lit un `proof-wait.txt` code EN DUR. L'attente du bras d'ablation n'est donc lue par personne, dans une porte qui vient de passer au vert.
3. Le validateur ecrit encore « proof.txt absent ou vide » EN PREMIER quand la preuve etait impossible ; c'est le verdict de la porte, appose plus loin dans le meme journal, qui requalifie. Qui lit le journal de haut en bas lit d'abord le mauvais diagnostic.

## Livrable — le contrat, en entier

`impossible_hygiene_defects` = 0, somme de termes publies SEPAREMENT.
1. Un etat d'impossibilite est PURGE des qu'il ne decrit plus le present : changement d'item, changement de bras, ou course ulterieure aboutie. Publier le compte d'etats purges et le compte d'etats encore debout, separement. Un zero d'etats debout se lit « rien en cours », jamais « rien verifie ».
2. Preuve a deux bras sur un etat SEME : un etat perime doit disparaitre du texte de statut dans le bras d'APRES et y figurer dans celui d'AVANT. C'est le texte RENDU qui est juge, pas une intention.
3. Les noms de fichiers d'attente sont derives du MEME endroit par l'ecrivain et par le lecteur. Publier, par bras, le nom ecrit et le nom lu : l'egalite est le verdict. Le bras d'ablation est inclus, c'est lui qui etait aveugle.
4. Le journal ne commence plus par un diagnostic que la porte va contredire : quand la preuve etait impossible, la premiere ligne le dit. Publier le compte de journaux ou les deux lignes se contredisaient.

## Hors perimetre

Ne touche a aucun code du jeu. Ne change pas la detection de l'impossibilite elle-meme.

## Ou l'owner regardera

Invisible. C'est ce que le harnais raconte quand il n'a pas pu mesurer.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.


# Le controle des particules et le nettoyage des shaders verifient des resultats reels — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Diagnostic superviseur 14/09 apres handoff et validator-002 : les deux termes existants sont a zero, mais le contrat demandait empreintes liees avant/apres et miroir POM d un programme deja supprime. Ordre owner 11/09 dans lighting-legacy-purge : « bah non faut supprimer le code ! On en veut plus, ca va etre refait, mieux, donc ca degage pour eviter de polluer ! » ; suppression c65c9a71bd, validee par l owner le 12/09. Ces exigences historiques sont donc remplacees explicitement par la conservation octet pour octet des artefacts des shaders courants, et non par un vert sur indisponible. Correctif 17fe0f99fa conserve : hdr_batches controle particle_steps et preprocess.py purge les sorties orphelines. Le census actuel rend t1+t2+penalty, sans mesurer la conservation des sorties vivantes. La reprise porte sur cette lacune du harnais ; aucune restauration POM, aucune campagne de rendu.

## Livrable — le contrat, en entier

`dead_literals_r3_defects` = 0, somme de TROIS termes publies SEPAREMENT et des penalites d infrastructure.
1. ASSERTION REELLE : conserver le banc avant/apres du vrai lecteur hdr_batches, reference cc00f44ca828075acb873078b41b8dd6b6436b13. Un compteur de particules fabrique incoherent est accepte AVANT et refuse APRES ; cadence correcte acceptee, melanges/valeurs manquantes traites explicitement, aucune relaxation des controles existants. Publier populations non vides et t1_defects.
2. NETTOYAGE EFFECTIF : le shader historique et ses producteurs POM sont supprimes par c65c9a71bd, sur ordre owner de purge. Conserver la provenance de la suppression et le zero gain revendique par cet item. Le vrai preprocesseur AVANT conserve un residu seme, APRES le retire ; les artefacts vivants et les fichiers etrangers survivent. Conserver les controles non vides sur sorties, blob et bibliotheque quand elle est presente. Publier t2_defects. Les empreintes liees et cles POM du programme supprime sont SANS OBJET, avec motif et commit de suppression publies, jamais des zeros de mesure ni une exigence de resurrection du vieux rendu.
3. LES SHADERS VIVANTS SONT CONSERVES : executer les preprocesseurs avant/apres sur les MEMES sources courantes epinglees et comparer octet par octet chaque sortie vivante (shaders, chunks et blob). Publier compte de fichiers/bytes compares non nul, liste/empreinte d inventaire et nombre de divergences nul ; fichiers courants omis ou illisibles = defaut. Verifier sur banc isole qu une sortie vivante alteree ou absente fait rougir ce terme, et que le seul retrait d un residu mort ne le fait pas. Publier t3_defects et le sommer dans dead_literals_r3_defects ; un terme manquant/indisponible ne peut pas rendre vert.
Cette equivalence porte sur les artefacts generes du rendu ACTUEL, pas sur des pixels observes ni un programme ancien supprime. Ne pas annoncer une identite visuelle ou un gain de performance. Renouveler la preuve par proof_run seulement APRES adaptation du census et tests pertinents ; aucune repetition de la preuve essai 2 inchangee.

## Hors perimetre

Reprise limitee au harnais (.autoport/lib/census/dead-literals-round-3.sh et bancs associes). Ne pas modifier le moteur, le preprocesseur de production ni la loi des particules. Executer les versions du preprocesseur dans des dossiers isoles hors /tmp. Aucun appareil, aucun build/deploiement reel, aucune campagne supplementaire, aucun changement de generic.sh. Les autres signalements restent hors perimetre.

## Ou l'owner regardera

Controle automatique des particules et de la generation des shaders ; aucun test visuel a demander.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-14
> Reprise superviseur requise pour : dead-literals-round-3. Ces priorités sont bloquées. Lis leurs derniers handoffs et journaux de validation, identifie la cause, corrige le harnais ou le périmètre nécessaire et reprends le travail autorisé sous Codex. Ne te limite pas à annoncer l'arrêt ; ne valide rien et ne relance pas le même essai sans diagnostic.

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

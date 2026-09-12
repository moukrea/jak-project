# Un essai TUE par le lanceur ne compte pas comme un essai rate — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

RECENSEMENT DU 12/09 SUR LES JOURNAUX. Le CLI attend 600 s les taches de fond d'un worker qui a rendu la main, puis les TERMINE : « Background tasks still running after 600s; terminating ». Le worker n'a rien conclu, mais l'orchestrateur enchaine sur le validateur, qui juge un arbre incoherent — source moteur plus recente que la preuve, sha du binaire different de celui du disque, preuve x86 sur un item qui exige l'appareil — et l'essai est COMPTE dans `max_retries`.
QUATRE ESSAIS DETRUITS AINSI : Grecharged-mesh-browser essai 6, refset-replay-stable essai 2, lighting-hdr essai 7, et lighting-legacy-purge essai 8 le 12/09 a 02:2x. Ce dernier a epuise le budget d'un item que l'owner avait mis en PRIORITE 17 (« vire les dessuite avant qu'ils nous embetent »), et l'item est maintenant BLOQUE sur « max_retries (6) epuise ». Les sept essais precedents de cet item avaient tourne sans consigne utilisable : le seul essai equitable est celui qui a ete coupe.
ATTENUATION DEJA POSEE, INSUFFISANTE : `launch.sh` exporte `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` a 45 minutes depuis le 12/09. Ca ne prend effet qu'au prochain demarrage de l'orchestrateur, et ca ne fait que reculer la borne : un build plus long brulerait encore un essai.

## Livrable — le contrat, en entier

`aborted_attempt_defects` = 0, somme de termes publies SEPAREMENT.
1. L'orchestrateur RECONNAIT un essai tue par le lanceur : la ligne « Background tasks still running after ...; terminating » dans la sortie du worker est lue, et l'essai est marque ABORTE. Publier le compte d'essais abortes reconnus.
2. Un essai aborte N'INCREMENTE PAS `max_retries`. Preuve a deux bras sur un etat jetable : le bras d'AVANT compte l'essai, le bras d'APRES ne le compte pas, meme entree.
3. Un essai aborte ne passe PAS au validateur : juger un arbre que le worker n'a pas fini de poser produit des constats qui ne decrivent aucun defaut du travail. Publier le compte de validations evitees.
4. Le journal le DIT en toutes lettres, avec la duree atteinte et la borne en vigueur : un essai qui disparait sans un mot est ce qui a coute quatre essais sans que personne le voie.

## Hors perimetre

Ne touche a aucun code du jeu. Ne debloque et ne reouvre aucun item au passage : rendre ses essais a lighting-legacy-purge est une decision de l'owner, pas de ce chantier.

## Ou l'owner regardera

Invisible. C'est la comptabilite des essais du harnais.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

